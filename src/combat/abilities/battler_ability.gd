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

## What this lands on whoever it reaches. Instant for a hit or a heal, timed for
## anything that lingers.
@export var payload: GameplayEffect = null
#endregion


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
	if payload == null:
		return
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for battler: Battler in targets:
		if battler != null and battler.asc != null:
			data.append_node(battler.asc)
	apply_effect_to_targets(payload, data)


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

	var out_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	out_tween.tween_property(caster, "position", origin + offset, out_time)
	await out_tween.finished

	_land()

	var back_tween: Tween = caster.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	back_tween.tween_property(caster, "position", origin, back_time)
	await back_tween.finished


## Which way the first target lies, as -1 or 1. Zero targets is not a case here:
## `_activate_ability()` refuses before any of this runs.
func _facing() -> float:
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null or targets.is_empty():
		return 1.0
	return signf(targets[0].position.x - caster.position.x)
#endregion
