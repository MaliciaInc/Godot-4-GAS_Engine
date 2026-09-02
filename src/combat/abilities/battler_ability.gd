## What a battler can do on its turn.
##
## Every combat ability has the same skeleton - pay for it, move, land something
## on the targets, come home - and differs only in how it moves and what it
## lands. Subclasses fill in those two; nothing else needs restating.
##
## The part worth understanding is what an ability does *not* do. It does not
## subtract energy: it commits, and the engine refuses the whole activation if
## the pool cannot cover the cost, so an ability that cannot be paid for never
## half-happens. It does not write damage onto a target either: it applies a
## GameplayEffect, and the target's own attribute set decides what that means
## after its defences, clamps and active buffs have had their say.
##
## @meta_license: MIT
@abstract
class_name BattlerAbility extends GameplayAbility

## Who this ability may be aimed at, which is a question about the ability, not
## about whoever is holding the cursor.
enum Scope {
	SELF,   ## Only the caster.
	SINGLE, ## One battler.
	ALL,    ## Every battler the sides below allow.
}

#region Authoring
@export var display_name: String = "Action"
@export_multiline var description: String = "A combat action."
@export var icon: Texture2D = null

@export_group("Targets")
@export var scope: BattlerAbility.Scope = Scope.SINGLE
@export var targets_allies: bool = false
@export var targets_enemies: bool = true
@export_group("")

## The ability's own accuracy, before the caster's `hit_chance` is applied.
## A hundred means the ability never misses of its own accord.
@export_range(0.0, 100.0) var accuracy: float = 100.0

## Energy this costs to use. Zero is free.
@export_range(0.0, 10.0) var energy_cost: float = 0.0

@export_group("Pacing")
## Beat before the caster moves, so a turn beginning is something the eye
## catches rather than something it misses.
@export var windup: float = 0.15

## Beat held at the moment of impact, before anything moves again.
##
## This is the one the damage number is read in. Without it the hit and the
## recovery are the same instant, and the number is gone before it is seen -
## which is exactly how the rewrite first felt.
@export var impact_hold: float = 0.35

## Beat after the caster is home, so one turn ends before the next begins.
@export var recovery: float = 0.2
@export_group("")
#endregion


## Declare the cost so the engine can refuse an activation nobody can pay for.
##
## Built from the number above rather than authored beside it, for the reason
## `_payload()` is: two ways to say what an ability costs is two places to look
## when a battler pays the wrong amount.
##
## The engine holds the refusal. Nothing here checks whether the caster can
## afford this - `commit_ability()` does, before any animation runs, which is
## what makes an unaffordable action not happen rather than happen on credit.
func _ready() -> void:
	if energy_cost <= 0.0:
		return
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = energy_cost

	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = BattlerAttributes.ENERGY
	cost.amount = amount
	costs = [cost] as Array[GameplayAbilityCost]


## Filled by the arena before activation. An ability never goes looking for its
## own targets: choosing them is the arena's job, and an ability that picked its
## own could not be aimed by a player.
var targets: Array[Battler] = []


func _activate_ability() -> bool:
	if targets.is_empty():
		return false

	# Paid first. Nothing has moved yet, so a refusal here costs nothing to undo.
	var commit: AbilityCommitResult = commit_ability()
	if not commit.is_ok():
		return false

	# `_perform()` lands the payload itself, at whatever point in its own
	# choreography the hit is supposed to read as connecting. Landing it here
	# too would apply every effect twice.
	await _perform()
	return true


## The choreography, and the moment inside it when the ability connects.
##
## A subclass moves the caster however this ability looks and calls `_land()`
## once, at the beat where the hit reads as landing - which is not the same beat
## for a lunge as for a thrown projectile.
@abstract
func _perform() -> void


## Apply the payload to everyone this ability reached.
##
## The effect carries the numbers; this only says who. Which is why a subclass
## that changes how an ability *looks* never has to touch what it *does*.
func _land() -> void:
	var effect: GameplayEffect = _payload()
	if effect == null:
		return
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for battler: Battler in targets:
		if battler == null or battler.asc == null:
			continue
		if not _connects_with(battler):
			# Told, not merely skipped: a miss the player cannot see reads as
			# the ability doing nothing at all.
			battler.evaded.emit()
			continue
		data.append_node(battler.asc)
	if not data.get_target_nodes().is_empty():
		apply_effect_to_targets(effect, data)


## What this ability lands on whoever it reaches.
##
## Built from the ability's own declared numbers, and only from those. There is
## deliberately no authored-resource alternative sitting beside it: two ways to
## say what an ability does is two places to look when it does the wrong thing,
## and the one that would have been hand-written in a .tres is the one nothing
## can check.
##
## Null for an ability whose whole job is its choreography.
func _payload() -> GameplayEffect:
	return null


## Whether this ability connects with one particular target.
##
## Rolled per target, not once for the whole swing: an area attack that hits
## three enemies is three chances to be dodged, which is what makes evasion
## worth having. Read live from both components, so a debuff to the caster's
## aim or a buff to the target's footwork is felt on this swing.
func _connects_with(target: Battler) -> bool:
	if accuracy >= 100.0 and target.attribute(BattlerAttributes.EVASION) <= 0.0:
		return true
	var caster_aim: float = owner_asc.get_attribute_current(BattlerAttributes.HIT_CHANCE)
	var chance: float = accuracy * (caster_aim / 100.0) - target.attribute(BattlerAttributes.EVASION)
	return randf() * 100.0 < chance


## Everyone this ability could legally be aimed at right now.
##
## One implementation, asked by both the opponent picking at random and the
## player's targeting cursor. Two would be two chances for the cursor to offer
## a target the AI considers illegal, or the reverse.
func possible_targets(roster: BattlerRoster) -> Array[Battler]:
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null:
		return []
	if scope == BattlerAbility.Scope.SELF:
		return [caster] as Array[Battler]

	var found: Array[Battler] = []
	if targets_allies:
		found.append_array(
			roster.get_player_battlers() if caster.is_player else roster.get_enemy_battlers()
		)
	if targets_enemies:
		found.append_array(
			roster.get_enemy_battlers() if caster.is_player else roster.get_player_battlers()
		)
	return found.filter(func _targetable(b: Battler) -> bool: return b.is_targetable())


## Whether this ability takes everyone it can reach rather than one of them.
func takes_everyone() -> bool:
	return scope == BattlerAbility.Scope.ALL


#region Choreography helpers
## Step out to `offset` from where the caster stands, and come back.
##
## Shared because three of the four abilities are this move with different
## numbers, and because a battler that fails to come home stays wherever the
## animation left it for the rest of the fight.
func _lunge(offset: Vector2, out_time: float, back_time: float) -> void:
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null:
		return
	var origin: Vector2 = caster.position

	await _pause(windup)
	if not is_instance_valid(caster):
		return

	var out_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	out_tween.tween_property(caster, "position", origin + offset, out_time)
	await out_tween.finished

	# Two awaits, and a battle can end across either. A caster freed with the
	# arena while its own swing is still in the air would be asked to tween
	# home, which is a crash rather than a missing animation.
	if not is_instance_valid(caster):
		return

	_land()
	await _pause(impact_hold)
	if not is_instance_valid(caster):
		return

	var back_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	back_tween.tween_property(caster, "position", origin, back_time)
	await back_tween.finished
	await _pause(recovery)


## A deliberate beat.
##
## The rewrite dropped these and the fight read as hurried: every phase ran
## straight into the next with nothing between them. Exported rather than
## sprinkled as bare numbers, so a hit can be retimed without reading the
## choreography, and named for what each is for rather than how long it lasts.
func _pause(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var tree: SceneTree = owner_asc.get_tree() if owner_asc != null else null
	if tree == null:
		return
	await tree.create_timer(seconds).timeout


## Which way the first target lies, as -1 or 1. Zero targets is not a case here:
## `_activate_ability()` refuses before any of this runs.
func _facing() -> float:
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null or targets.is_empty():
		return 1.0
	return signf(targets[0].position.x - caster.position.x)
#endregion
