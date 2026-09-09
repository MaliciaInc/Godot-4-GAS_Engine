## Whatever a ray from the caster strikes.
##
## The line a bolt travels. Aimed along the caster's own forward direction,
## because a preset runs where there is no cursor - a game that aims by cursor
## uses a provider, which is the thing that exists for aims a person moves.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingSelectTrace extends GameplayTargetingTask

@export var length: float = 10.0

## Where the ray starts, relative to the caster.
@export var offset: Vector3 = Vector3.ZERO

@export var collision_mask: int = 0xFFFFFFFF

## Whether the place the ray struck is kept as well as whatever it struck.
##
## For a bolt that leaves a scorch mark where it landed: the actor is what takes
## the damage and the spot is where the mark goes, and an aim can carry both.
@export var keep_impact_point: bool = true


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

	var request: GameplayRaycastRequest3D = GameplayRaycastRequest3D.new()
	request.from = body.global_position + offset
	# Godot's -Z is forward, which is the direction a Node3D is facing.
	request.to = request.from + (-body.global_basis.z.normalized() * length)
	request.collision_mask = collision_mask

	var found: GameplayAbilityTargetData = GameplayTargetingService.raycast_3d(
		source_asc, world, request
	)
	for hit: GameplayTargetHit in found.get_all_hits():
		if hit.collider != null:
			input.append_node(hit.collider)
		if keep_impact_point and hit.has_position:
			input.append_location(hit.position_3d, hit.normal_3d)
	return input
