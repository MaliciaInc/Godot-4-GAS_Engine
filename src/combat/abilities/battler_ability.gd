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
##
## Declared through the setter rather than in `_ready()`, and that is not a
## style choice. Granting an ability snapshots its definition straight after
## `instantiate()` - `GameplayAbilityDefinitionSnapshot` copies `costs` there and
## its own header warns that mutating the instance afterwards changes nothing.
## `_ready()` runs later, when the instance is added to the tree, so a cost built
## there never reaches the engine: the ability reads as free, the action menu
## never greys it, and `commit_ability()` has nothing to refuse. A setter runs
## while the scene is being instantiated, which is before the snapshot is taken.
@export_range(0.0, 10.0) var energy_cost: float = 0.0:
	set(value):
		energy_cost = value
		costs = _build_costs()

## The tag that marks this ability as cooling down.
##
## The tag IS the cooldown: the engine refuses an activation by asking
## whether the caster carries it, not by consulting a timer of its own. So
## two abilities given the same tag deliberately share one cooldown, and two
## given none share nothing.
@export var cooldown_tag: StringName = &"":
	set(value):
		cooldown_tag = value
		cooldown_effect = _build_cooldown()

## Turns this ability is unusable for after it is used. Zero is no cooldown.
##
## Built in a setter for the reason `energy_cost` is, and rebuilt in both
## setters rather than one: a scene assigns its properties in file order and
## neither setter can know whether it ran last. Whichever runs second builds
## the effect that survives, and both build the same one.
##
## Nothing here advances the clock. `Combat` does, once per round - which is
## what `TURN_BASED` means: the engine ages the effect when a turn manager
## says a turn passed, and this game is the turn manager.
@export_range(0, 9) var cooldown_turns: int = 0:
	set(value):
		cooldown_turns = value
		cooldown_effect = _build_cooldown()

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


## The cooldown the engine refuses a second activation over.
##
## Legal by the engine's own contract, which is stricter than it looks: no
## modifiers (a cooldown is not a debuff), at least one granted tag (without
## one nothing could observe it and it would expire unnoticed), and a
## duration above zero. Null when either half is unset, because half a
## cooldown is a cooldown that never lifts.
func _build_cooldown() -> GameplayEffect:
	if cooldown_turns <= 0 or cooldown_tag == &"":
		return null

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.TURN_BASED
	effect.duration_turns = cooldown_turns

	var marker: GameplayEffectTargetTagsComponent = (
		GameplayEffectTargetTagsComponent.new()
	)
	marker.granted_tags = [cooldown_tag] as Array[StringName]
	effect.components.append(marker)
	return effect


## The cost the engine refuses an activation over.
##
## Built from the number above rather than authored beside it, for the reason
## `_payload()` is: two ways to say what an ability costs is two places to look
## when a battler pays the wrong amount.
##
## Nothing here checks whether the caster can afford it. `commit_ability()`
## does, before any animation runs, and the action menu asks the same question
## to decide what a player may press - which is what makes an unaffordable
## action not happen rather than happen on credit.
func _build_costs() -> Array[GameplayAbilityCost]:
	if energy_cost <= 0.0:
		return [] as Array[GameplayAbilityCost]

	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = energy_cost

	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = BattlerAttributes.ENERGY
	cost.amount = amount
	return [cost] as Array[GameplayAbilityCost]


## Filled by the arena before activation. An ability never goes looking for its
## own targets: choosing them is the arena's job, and an ability that picked its
## own could not be aimed by a player.
var targets: Array[Battler] = []


## Refuse a target that has gone down, through the engine's own gate.
##
## `possible_targets()` keeps corpses out of the menu, and that used to be the
## whole story. It is only half: intentions are declared for the whole round and
## resolved in speed order, so a target chosen at the start can be downed by
## someone faster before this ability ever runs. The game then spent a turn
## swinging at a corpse and applying an effect to it.
##
## `accepts_target()` is what the engine checks, and `apply_effect_to_targets()`
## is what its own doc calls the sole enforcement route - which `_land()` already
## goes through. The gate was there the whole time with nothing written on it.
##
## Built in `_init()` rather than `_ready()`: the engine freezes an ability's
## definition when it is granted, and `_ready()` runs after that, so the value
## would be reported as drift and never read. The ability scenes store no
## override for this property, so what is set here survives instantiation.
func _init() -> void:
	var downed: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	downed.operator = GameplayTagQueryExpression.Operator.ANY
	downed.tags = [Battler.DOWNED] as Array[StringName]
	target_blocked_query = GameplayTagQuery.new()
	target_blocked_query.root = downed


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

	var winding: bool = await _pause(windup)
	if not winding or not is_instance_valid(caster):
		return

	var out_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	out_tween.tween_property(caster, "position", origin + offset, out_time)
	await out_tween.finished

	# Two awaits, and a battle can end across either. A caster freed with the
	# arena while its own swing is still in the air would be asked to tween
	# home, which is a crash rather than a missing animation.
	#
	# `is_active` for the other ending: a tween finishes on its own clock, so
	# an ability cancelled mid-swing wakes up here and would land its payload
	# into a fight whose turn is already over.
	if not is_active or not is_instance_valid(caster):
		return

	_land()
	var holding: bool = await _pause(impact_hold)
	if not holding or not is_instance_valid(caster):
		return

	var back_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	back_tween.tween_property(caster, "position", origin, back_time)
	await back_tween.finished
	if not is_active or not is_instance_valid(caster):
		return
	await _pause(recovery)


## A deliberate beat, counted on the engine's clock.
##
## The rewrite dropped these and the fight read as hurried: every phase ran
## straight into the next with nothing between them. Exported rather than
## sprinkled as bare numbers, so a hit can be retimed without reading the
## choreography, and named for what each is for rather than how long it lasts.
##
## Through the ability's own `wait_delay()`, not a SceneTreeTimer - which is
## what this used, and what AbilityTaskWaitDelay was written to refuse. A tree
## timer keeps its own clock: it goes on counting after the ability that owns
## the beat has been cancelled, and the swing wakes up to land its payload into
## a fight that already moved on. The engine's task is cancelled with the
## ability and answers to the same clock the effect scheduler does.
##
## Returns whether the beat was served or cut short.
func _pause(seconds: float) -> bool:
	if seconds <= 0.0:
		return is_active
	var task: AbilityTaskWaitDelay = wait_delay(seconds)
	if task == null:
		return false
	await task.completed()
	return task.state == GameplayAbilityTask.State.SUCCEEDED


## Which way the first target lies, as -1 or 1. Zero targets is not a case here:
## `_activate_ability()` refuses before any of this runs.
func _facing() -> float:
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null or targets.is_empty():
		return 1.0
	return signf(targets[0].position.x - caster.position.x)
#endregion
