## Everything standing in a circle takes it.
##
## The ability finds its own targets instead of asking the player for them: the
## targeting service answers "what is in here" against real physics, and the
## answer is target data exactly like the kind a player hands back.
##
## Written against 2D. The 3D twin is the same six lines with `overlap_3d` and a
## Vector3, because Godot keeps the two physics servers apart and an engine that
## supports both has to mirror them.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends GameplayAbility

@export var damage: GameplayEffect

## In world units, around the caster.
@export var radius: float = 96.0


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	var caster: Node2D = owner_asc.get_effect_target() as Node2D
	if caster == null:
		return false

	var sweep: GameplayOverlapRequest2D = GameplayOverlapRequest2D.new()
	sweep.center = caster.global_position
	sweep.radius = radius

	var found: GameplayAbilityTargetData = GameplayTargetingService.overlap_2d(
		owner_asc, caster.get_world_2d(), sweep
	)
	apply_effect_to_targets(damage, found)
	end_ability()
	return true
