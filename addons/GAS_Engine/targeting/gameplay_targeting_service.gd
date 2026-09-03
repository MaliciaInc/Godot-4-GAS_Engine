## The only place in the addon that talks to the physics server.
##
## Godot answers a query with an untyped Dictionary. That dictionary stops here:
## it is converted at the boundary and never stored in a field, handed to a
## signal, or put in target data. Everything downstream sees typed hits, so a
## renamed physics key breaks one file loudly instead of every consumer quietly.
##
## The service is given world coordinates and a world. It does not read the
## mouse, the camera, the viewport or the input map: working out where the
## player pointed belongs to whatever owns the camera, and an ability system
## that read input could not be tested without one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetingService extends RefCounted

## Borrowed from the type that owns it, not respelled here.
const COLLIDER_KEY: StringName = GameplayTargetHit.COLLIDER_KEY


#region Traces
static func raycast_2d(
	source_asc: AbilitySystemComponent, world: World2D, request: GameplayRaycastRequest2D
) -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	if world == null or request == null:
		return found

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		request.from, request.to, request.collision_mask
	)
	query.collide_with_bodies = request.collide_with_bodies
	query.collide_with_areas = request.collide_with_areas

	_take_hit(found, world.direct_space_state.intersect_ray(query), source_asc, request.filter)
	return found


static func raycast_3d(
	source_asc: AbilitySystemComponent, world: World3D, request: GameplayRaycastRequest3D
) -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	if world == null or request == null:
		return found

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		request.from, request.to, request.collision_mask
	)
	query.collide_with_bodies = request.collide_with_bodies
	query.collide_with_areas = request.collide_with_areas

	_take_hit(found, world.direct_space_state.intersect_ray(query), source_asc, request.filter)
	return found
#endregion


#region Sweeps
static func overlap_2d(
	source_asc: AbilitySystemComponent, world: World2D, request: GameplayOverlapRequest2D
) -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	if world == null or request == null:
		return found

	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = maxf(request.radius, 0.0)

	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, request.center)
	query.collision_mask = request.collision_mask
	query.collide_with_bodies = request.collide_with_bodies
	query.collide_with_areas = request.collide_with_areas

	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(
		query, maxi(request.max_results, 1)
	)
	_take_sweep(found, hits, source_asc, request.filter)
	return found


static func overlap_3d(
	source_asc: AbilitySystemComponent, world: World3D, request: GameplayOverlapRequest3D
) -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	if world == null or request == null:
		return found

	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = maxf(request.radius, 0.0)

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), request.center)
	query.collision_mask = request.collision_mask
	query.collide_with_bodies = request.collide_with_bodies
	query.collide_with_areas = request.collide_with_areas

	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(
		query, maxi(request.max_results, 1)
	)
	_take_sweep(found, hits, source_asc, request.filter)
	return found
#endregion


#region The boundary
## Take one trace result, if anything wants it.
##
## The dictionary is handed to the typed converter whole rather than picked
## apart here: a trace reports where it struck and which way the surface faced,
## and a cue wants both.
static func _take_hit(
	found: GameplayAbilityTargetData,
	hit: Dictionary,
	source_asc: AbilitySystemComponent,
	filter: GameplayTargetFilter
) -> void:
	var raw: Variant = hit.get(COLLIDER_KEY)
	if not raw is Node:
		return
	var collider: Node = raw
	if filter != null and not filter.accepts(source_asc, collider):
		return
	found.append_physics_hit(hit)


## Take what a sweep found, in the order physics reported it.
##
## Only the collider is read. `intersect_shape` reports no impact point and no
## normal, and inventing them would put numbers nothing measured into a cue, so
## these arrive as nodes rather than as hits.
##
## Not sorted by distance. Physics decides the order; a service that quietly
## reordered would make "the first target" mean something different here than
## everywhere else, and a caller that wants nearest-first can say so.
static func _take_sweep(
	found: GameplayAbilityTargetData,
	results: Array[Dictionary],
	source_asc: AbilitySystemComponent,
	filter: GameplayTargetFilter
) -> void:
	var limit: int = filter.max_targets if filter != null else 0
	var reached: Array[int] = []

	for entry: Dictionary in results:
		if limit > 0 and reached.size() >= limit:
			return

		var raw: Variant = entry.get(COLLIDER_KEY)
		if not raw is Node:
			continue
		var collider: Node = raw
		if filter != null and not filter.accepts(source_asc, collider):
			continue

		# Two shapes on one actor are one target. A sweep across a character with
		# a torso and a head collider must not count it twice.
		var target_asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(collider)
		if target_asc == null or reached.has(target_asc.get_instance_id()):
			continue
		reached.append(target_asc.get_instance_id())
		found.append_node(collider)
#endregion
