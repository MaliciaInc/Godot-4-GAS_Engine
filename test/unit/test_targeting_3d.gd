## 3D targeting against the real physics server.
##
## The 3D half of the same contract, asked separately because it runs on a
## different server with different types. The 2D suite passing says nothing
## about whether a sphere sweep reports what a circle sweep does, and the two
## Godot APIs are similar enough that a mistake in one would read past easily.
##
## Nothing is mocked here either. Bodies need a physics frame before the server
## knows about them, so every test that queries awaits one first.
##
## @meta_license: MIT
extends GutTest

const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")

const SIZE: float = 1.0
const LAYER_ONE: int = 1
const LAYER_TWO: int = 2
const EVERY_LAYER: int = 0xFFFFFFFF
const ORIGIN: Vector3 = Vector3.ZERO
const NEAR: Vector3 = Vector3(6.0, 0.0, 0.0)
const FAR: Vector3 = Vector3(18.0, 0.0, 0.0)
const BEYOND: Vector3 = Vector3(60.0, 0.0, 0.0)
const ASIDE: Vector3 = Vector3(0.0, 40.0, 0.0)
const REACH: float = 25.0
const ALLY: StringName = &"Team.Ally"


## One way of writing a tag rule, and which actor it should leave standing.
class TagCase extends RefCounted:
	var blocks: bool = false

	func _init(by_blocking: bool) -> void:
		blocks = by_blocking


#region Scenes
func _component() -> AbilitySystemComponent:
	var component: AbilitySystemComponent = AbilitySystemComponent.new()
	component.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	component.attribute_sets = [AttributeSetScript.new()]
	component.share_attributes = true
	return component


func _shape() -> CollisionShape3D:
	var holder: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SIZE
	holder.shape = sphere
	return holder


## Put a physics object where it belongs and give it what makes it an actor.
func _place(body: CollisionObject3D, actor_name: String, at: Vector3, layer: int) -> void:
	body.name = actor_name
	body.position = at
	body.collision_layer = layer
	body.add_child(_shape())
	add_child_autofree(body)


func _actor(actor_name: String, at: Vector3, layer: int) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.add_child(_component())
	_place(body, actor_name, at, layer)
	return body


func _area_actor(actor_name: String, at: Vector3, layer: int) -> Area3D:
	var area: Area3D = Area3D.new()
	area.add_child(_component())
	_place(area, actor_name, at, layer)
	return area


## Something physics can find that nothing can receive an effect on.
func _scenery(actor_name: String, at: Vector3, layer: int) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	_place(body, actor_name, at, layer)
	return body


func _asc_of(node: Node) -> AbilitySystemComponent:
	return AbilitySystemLocator.find_for_node(node)
#endregion


#region Queries
func _world() -> World3D:
	return get_tree().root.world_3d


## Let the physics server see the bodies that were just added.
func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _trace(mask: int = EVERY_LAYER, areas: bool = false) -> GameplayAbilityTargetData:
	var request: GameplayRaycastRequest3D = GameplayRaycastRequest3D.new()
	request.from = ORIGIN
	request.to = BEYOND
	request.collision_mask = mask
	request.collide_with_areas = areas
	return GameplayTargetingService.raycast_3d(null, _world(), request)


func _sweep(
	filter: GameplayTargetFilter = null, caster: AbilitySystemComponent = null
) -> GameplayAbilityTargetData:
	var request: GameplayOverlapRequest3D = GameplayOverlapRequest3D.new()
	request.center = ORIGIN
	request.radius = REACH
	request.filter = filter
	return GameplayTargetingService.overlap_3d(caster, _world(), request)
#endregion


#region Tracing
func test_a_trace_finds_the_body_in_its_way() -> void:
	_actor("Target", NEAR, LAYER_ONE)
	await _settle()
	assert_eq(_trace().get_target_nodes().size(), 1, "the body on the line was found")


func test_a_trace_that_meets_nothing_finds_nothing() -> void:
	_actor("Elsewhere", ASIDE, LAYER_ONE)
	await _settle()
	assert_false(_trace().has_targets(), "nothing was on the line")


func test_a_mask_that_excludes_the_layer_finds_nothing() -> void:
	_actor("Target", NEAR, LAYER_TWO)
	await _settle()
	assert_false(_trace(LAYER_ONE).has_targets(), "the mask kept it out")


## An area is a trigger volume, so a trace ignores one unless asked not to.
func test_an_area_is_met_only_when_the_request_asks_for_it() -> void:
	_area_actor("Trigger", NEAR, LAYER_ONE)
	await _settle()

	assert_false(_trace().has_targets(), "by default a trace passes through it")
	assert_eq(_trace(EVERY_LAYER, true).get_target_nodes().size(), 1, "and meets it when told to")


## A trace knows where it struck and which way the surface faced.
func test_a_trace_keeps_the_point_and_the_normal_physics_gave_it() -> void:
	_actor("Target", NEAR, LAYER_ONE)
	await _settle()
	var hits: Array[GameplayTargetHit] = _trace().get_all_hits()

	assert_eq(hits.size(), 1, "one hit was recorded")
	assert_eq(hits[0].space_kind, GameplayTargetHit.SpaceKind.THREE_D, "in its own space")
	assert_gt(hits[0].position_3d.x, 0.0, "with a real impact point")
	assert_lt(hits[0].normal_3d.x, 0.0, "and a normal facing back along the trace")
#endregion


#region Sweeping
func test_a_sweep_finds_everything_inside_it() -> void:
	_actor("Near", NEAR, LAYER_ONE)
	_actor("Far", FAR, LAYER_ONE)
	await _settle()
	assert_eq(_sweep().get_target_nodes().size(), 2, "both were inside the sphere")


## Two shapes on one actor are one target.
func test_one_actor_with_two_shapes_arrives_once() -> void:
	var body: StaticBody3D = _actor("TwoShapes", NEAR, LAYER_ONE)
	body.add_child(_shape())
	await _settle()
	assert_eq(_sweep().get_target_nodes().size(), 1, "one actor, however many shapes it wears")


func test_a_sweep_stops_at_the_limit_it_was_given() -> void:
	_actor("Near", NEAR, LAYER_ONE)
	_actor("Far", FAR, LAYER_ONE)
	await _settle()
	var filter: GameplayTargetFilter = GameplayTargetFilter.new()
	filter.max_targets = 1

	assert_eq(_sweep(filter).get_target_nodes().size(), 1, "it kept only as many as allowed")
#endregion


#region Filtering
func _tag_cases() -> Array[TagCase]:
	return [TagCase.new(false), TagCase.new(true)] as Array[TagCase]


## A tag rule keeps out whoever does not qualify, read from either end.
##
## Required and blocked are one rule seen from opposite sides, so they are asked
## together: the tagged actor is the only one kept when the tag is required, and
## the only one dropped when it is blocked.
func test_a_tag_rule_keeps_out_whoever_does_not_qualify(
	scenario: TagCase = use_parameters(_tag_cases())
) -> void:
	var tagged: StaticBody3D = _actor("Tagged", NEAR, LAYER_ONE)
	var plain: StaticBody3D = _actor("Plain", FAR, LAYER_ONE)
	_asc_of(tagged).add_tag(ALLY)
	await _settle()

	var filter: GameplayTargetFilter = GameplayTargetFilter.new()
	if scenario.blocks:
		filter.blocked_tags = [ALLY]
	else:
		filter.required_tags = [ALLY]

	var survivor: Node = plain if scenario.blocks else tagged
	assert_eq(
		_sweep(filter).get_target_nodes(),
		[survivor] as Array[Node],
		"only whoever the rule leaves standing"
	)


## "Around me" almost never means "and me".
func test_the_caster_is_left_out_of_its_own_sweep() -> void:
	var caster: StaticBody3D = _actor("Caster", ORIGIN, LAYER_ONE)
	var other: StaticBody3D = _actor("Other", NEAR, LAYER_ONE)
	await _settle()

	var found: GameplayAbilityTargetData = _sweep(GameplayTargetFilter.new(), _asc_of(caster))
	assert_eq(found.get_target_nodes(), [other] as Array[Node], "everyone but the caster")


func test_something_with_no_ability_system_is_not_a_target() -> void:
	_scenery("Wall", NEAR, LAYER_ONE)
	await _settle()

	var found: GameplayAbilityTargetData = _sweep(GameplayTargetFilter.new())
	assert_false(found.has_targets(), "physics found it, but nothing there can receive an effect")
#endregion
