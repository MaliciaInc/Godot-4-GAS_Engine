## Everything inside a circle around the caster.
##
## Through GameplayTargetingService like every other sweep in the addon, so the
## filter, the actor-per-collider collapsing and the result limit are the ones
## every other sweep gets rather than a second set written here.
##
## The centre is the caster's own position plus an offset, because a preset is
## authored before anybody has cast anything: there is no cursor to read, and a
## step that wanted one would be a step that cannot run on a server.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingSelectAoe extends GameplayTargetingTask

@export var radius: float = 5.0

## Moved by this much from the caster, in world space.
@export var offset: Vector3 = Vector3.ZERO

@export var collision_mask: int = 0xFFFFFFFF

## On for a sweep more often than for a trace, and still the author's decision.
@export var collide_with_areas: bool = false


func execute(
	input: GameplayAbilityTargetData, source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	if source_asc == null:
		return input
	var body: Node3D = source_asc.get_effect_target() as Node3D
	if body == null:
		return input
	var world: World3D = body.get_world_3d()
	if world == null:
		return input

	var request: GameplayOverlapRequest3D = GameplayOverlapRequest3D.new()
	request.center = body.global_position + offset
	request.radius = radius
	request.collision_mask = collision_mask
	request.collide_with_areas = collide_with_areas

	var found: GameplayAbilityTargetData = GameplayTargetingService.overlap_3d(
		source_asc, world, request
	)
	for node: Node in found.get_target_nodes():
		input.append_node(node)
	return input
