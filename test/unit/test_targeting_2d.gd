## 2D targeting against the real physics server.
##
## Nothing here is mocked. A faked space state would prove that the service
## calls the functions this test expects it to call, which restates the
## implementation rather than checking it; the questions worth asking - does a
## mask exclude, does an area count as a body, does one actor with two shapes
## arrive twice - are answered by physics or not at all.
##
## Bodies need a physics frame before the server knows about them, so every test
## that queries awaits one first.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")

const SIZE: float = 16.0
const LAYER_ONE: int = 1
const LAYER_TWO: int = 2
const EVERY_LAYER: int = 0xFFFFFFFF
const ORIGIN: Vector2 = Vector2.ZERO
const NEAR: Vector2 = Vector2(100.0, 0.0)
const FAR: Vector2 = Vector2(300.0, 0.0)
const BEYOND: Vector2 = Vector2(1000.0, 0.0)
const ASIDE: Vector2 = Vector2(0.0, 500.0)
const REACH: float = 400.0
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


func _shape() -> CollisionShape2D:
	var holder: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = SIZE
	holder.shape = circle
	return holder


## Put a physics object where it belongs and give it what makes it an actor.
func _place(body: CollisionObject2D, actor_name: String, at: Vector2, layer: int) -> void:
	body.name = actor_name
	body.position = at
	body.collision_layer = layer
	body.add_child(_shape())
	add_child_autofree(body)


func _actor(actor_name: String, at: Vector2, layer: int) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.add_child(_component())
	_place(body, actor_name, at, layer)
	return body


func _area_actor(actor_name: String, at: Vector2, layer: int) -> Area2D:
	var area: Area2D = Area2D.new()
	area.add_child(_component())
	_place(area, actor_name, at, layer)
	return area


## Something physics can find that nothing can receive an effect on.
func _scenery(actor_name: String, at: Vector2, layer: int) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	_place(body, actor_name, at, layer)
	return body


func _asc_of(node: Node) -> AbilitySystemComponent:
	return AbilitySystemLocator.find_for_node(node)
#endregion


#region Queries
func _world() -> World2D:
	return get_tree().root.world_2d


## Let the physics server see the bodies that were just added.
func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _trace(mask: int = EVERY_LAYER, areas: bool = false) -> GameplayAbilityTargetData:
	var request: GameplayRaycastRequest2D = GameplayRaycastRequest2D.new()
	request.from = ORIGIN
	request.to = BEYOND
	request.collision_mask = mask
	request.collide_with_areas = areas
	return GameplayTargetingService.raycast_2d(null, _world(), request)


func _sweep(
	filter: GameplayTargetFilter = null, caster: AbilitySystemComponent = null
) -> GameplayAbilityTargetData:
	var request: GameplayOverlapRequest2D = GameplayOverlapRequest2D.new()
	request.center = ORIGIN
	request.radius = REACH
	request.filter = filter
	return GameplayTargetingService.overlap_2d(caster, _world(), request)
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


## A trace knows where it struck and which way the surface faced, so the target
## data carries both rather than only naming what was hit.
func test_a_trace_keeps_the_point_and_the_normal_physics_gave_it() -> void:
	_actor("Target", NEAR, LAYER_ONE)
	await _settle()
	var hits: Array[GameplayTargetHit] = _trace().get_all_hits()

	assert_eq(hits.size(), 1, "one hit was recorded")
	assert_eq(hits[0].space_kind, GameplayTargetHit.SpaceKind.TWO_D, "in its own space")
	assert_gt(hits[0].position_2d.x, 0.0, "with a real impact point")
	assert_lt(hits[0].normal_2d.x, 0.0, "and a normal facing back along the trace")
#endregion


#region Sweeping
func test_a_sweep_finds_everything_inside_it() -> void:
	_actor("Near", NEAR, LAYER_ONE)
	_actor("Far", FAR, LAYER_ONE)
	await _settle()
	assert_eq(_sweep().get_target_nodes().size(), 2, "both were inside the circle")


## Two shapes on one actor are one target.
func test_one_actor_with_two_shapes_arrives_once() -> void:
	var body: StaticBody2D = _actor("TwoShapes", NEAR, LAYER_ONE)
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
	var tagged: StaticBody2D = _actor("Tagged", NEAR, LAYER_ONE)
	var plain: StaticBody2D = _actor("Plain", FAR, LAYER_ONE)
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
	var caster: StaticBody2D = _actor("Caster", ORIGIN, LAYER_ONE)
	var other: StaticBody2D = _actor("Other", NEAR, LAYER_ONE)
	await _settle()

	var found: GameplayAbilityTargetData = _sweep(GameplayTargetFilter.new(), _asc_of(caster))
	assert_eq(found.get_target_nodes(), [other] as Array[Node], "everyone but the caster")


## A sweep with no filter is not a trace with no filter.
##
## A trace reports whatever it struck; a sweep answers by actor, and the actor
## is whoever the ability system belongs to, so scenery stays out either way.
## The caster does not: leaving it out is the filter's job, and there is no
## filter to ask. Both were true and only one of them was written down.
func test_a_sweep_with_no_filter_still_answers_by_actor() -> void:
	var caster: StaticBody2D = _actor("Caster", ORIGIN, LAYER_ONE)
	_scenery("Wall", NEAR, LAYER_ONE)
	await _settle()

	var found: Array[Node] = _sweep(null, _asc_of(caster)).get_target_nodes()
	assert_eq(found, [caster] as Array[Node], "the wall is not a target, the caster is")


func test_something_with_no_ability_system_is_not_a_target() -> void:
	_scenery("Wall", NEAR, LAYER_ONE)
	await _settle()

	var found: GameplayAbilityTargetData = _sweep(GameplayTargetFilter.new())
	assert_false(found.has_targets(), "physics found it, but nothing there can receive an effect")
#endregion


## Godot intersect_shape answers 32 colliders by default and says nothing when
## it stops there - a ceiling nobody wrote, applied before the sweep has even
## worked out who is a target.
func test_a_sweep_is_not_capped_by_the_ceiling_nobody_wrote() -> void:
	var crowd: int = 40
	for index: int in crowd:
		_actor("Crowd%d" % index, ORIGIN + Vector2(float(index) * 4.0, 0.0), LAYER_ONE)
	await _settle()

	assert_eq(
		_sweep().get_target_nodes().size(), crowd,
		"every actor in reach was found, not the first thirty-two"
	)
