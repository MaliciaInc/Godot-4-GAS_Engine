## The physics boundary: raw dictionaries in, typed hits out or nothing.
##
## A dynamic boundary converts immediately to semantic types. This is that
## boundary, and it is the one place allowed to read a raw physics result. The
## value of
## converting once is that no consumer downstream ever calls `hit.get("collider")`
## and guesses; the value of refusing is that a half-understood hit never
## reaches them looking valid.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ORIGIN_2D: Vector2 = Vector2(3.0, 4.0)
const NORMAL_2D: Vector2 = Vector2(0.0, 1.0)
const ORIGIN_3D: Vector3 = Vector3(1.0, 2.0, 3.0)
const NORMAL_3D: Vector3 = Vector3(0.0, 1.0, 0.0)

var data: GameplayAbilityTargetData = null
var collider: Node = null


func before_each() -> void:
	data = GameplayAbilityTargetData.new()
	collider = Node.new()
	collider.name = "Collider"
	add_child_autofree(collider)


func after_each() -> void:
	data = null
	collider = null


func _physics_hit(position: Variant, normal: Variant) -> Dictionary:
	return {"collider": collider, "position": position, "normal": normal}


#region Converting a raw hit
## One space, and the fields a hit in it should carry.
##
## Shared by both parameterised tests below: the conversion is meant to treat
## the two spaces identically and differ only in which pair of fields it fills,
## so testing them as one procedure is what the design claims.
class SpaceCase extends RefCounted:
	var label: String = ""
	var two_d: bool = false


func _space_cases() -> Array[SpaceCase]:
	var flat: SpaceCase = SpaceCase.new()
	flat.label = "2D"
	flat.two_d = true

	var spatial: SpaceCase = SpaceCase.new()
	spatial.label = "3D"

	return [flat, spatial] as Array[SpaceCase]


func _expected_kind(scenario: SpaceCase) -> GameplayTargetHit.SpaceKind:
	if scenario.two_d:
		return GameplayTargetHit.SpaceKind.TWO_D
	return GameplayTargetHit.SpaceKind.THREE_D


## A well-formed hit in either space converts, keeping its own fields.
func test_a_hit_becomes_a_typed_hit_of_its_own_space(
	scenario: SpaceCase = use_parameters(_space_cases())
) -> void:
	var raw: Dictionary = (
		_physics_hit(ORIGIN_2D, NORMAL_2D) if scenario.two_d
		else _physics_hit(ORIGIN_3D, NORMAL_3D)
	)
	var hit: GameplayTargetHit = GameplayTargetHit.try_from_physics_hit(raw)

	assert_not_null(hit, scenario.label + ": converted")
	assert_eq(hit.space_kind, _expected_kind(scenario), scenario.label + ": space")
	assert_eq(hit.collider, collider, scenario.label + ": collider")
	if scenario.two_d:
		assert_eq(hit.position_2d, ORIGIN_2D)
		assert_eq(hit.normal_2d, NORMAL_2D)
	else:
		assert_eq(hit.position_3d, ORIGIN_3D)
		assert_eq(hit.normal_3d, NORMAL_3D)


## The dimension comes from the fields agreeing, not from whichever is non-zero.
func test_a_mixed_dimension_hit_is_refused_rather_than_half_converted() -> void:
	assert_null(
		GameplayTargetHit.try_from_physics_hit(_physics_hit(ORIGIN_2D, NORMAL_3D)),
		"a 2D position with a 3D normal is not a hit anyone can use"
	)
	assert_null(GameplayTargetHit.try_from_physics_hit(_physics_hit(ORIGIN_3D, NORMAL_2D)))


func test_a_hit_without_a_collider_node_is_refused() -> void:
	assert_null(GameplayTargetHit.try_from_physics_hit({}), "an empty dictionary")
	assert_null(
		GameplayTargetHit.try_from_physics_hit(
			{"collider": null, "position": ORIGIN_3D, "normal": NORMAL_3D}
		),
		"a null collider"
	)
	# Godot hands back a RID for a body with no node. Storing that as a target
	# would make every consumer test for a Node it might not have.
	assert_null(
		GameplayTargetHit.try_from_physics_hit(
			{"collider": RID(), "position": ORIGIN_3D, "normal": NORMAL_3D}
		),
		"a collider that is not a Node"
	)


func test_a_hit_missing_its_geometry_is_refused() -> void:
	assert_null(
		GameplayTargetHit.try_from_physics_hit({"collider": collider}),
		"a collider alone is not a hit; append_node is the entry point for that"
	)
#endregion


#region Appending
func test_a_refused_hit_adds_nothing_at_all() -> void:
	assert_false(data.append_physics_hit({}), "reported as refused")
	assert_eq(data.get_all_hits().size(), 0, "and nothing was recorded")
	assert_false(data.has_targets())


## A node's space comes from its own type, never from an untyped argument, so a
## 2D node can never be recorded as a 3D hit.
func test_appending_a_node_reads_the_space_from_the_node(
	scenario: SpaceCase = use_parameters(_space_cases())
) -> void:
	var node: Node = null
	if scenario.two_d:
		var flat: Node2D = Node2D.new()
		flat.position = ORIGIN_2D
		node = flat
	else:
		var spatial: Node3D = Node3D.new()
		spatial.position = ORIGIN_3D
		node = spatial
	add_child_autofree(node)

	assert_true(data.append_node(node), scenario.label + ": accepted")
	var hit: GameplayTargetHit = data.get_all_hits()[0]
	assert_eq(hit.space_kind, _expected_kind(scenario), scenario.label + ": from the node's type")
	if scenario.two_d:
		assert_eq(hit.position_2d, ORIGIN_2D)
	else:
		assert_eq(hit.position_3d, ORIGIN_3D)


## A UI element or a pure data node is a legitimate target with no position.
func test_appending_a_node_with_no_space_is_accepted_without_inventing_one() -> void:
	assert_true(data.append_node(collider))
	assert_eq(data.get_all_hits()[0].position_3d, Vector3.ZERO)
	assert_true(data.has_targets())


func test_appending_nothing_is_refused() -> void:
	assert_false(data.append_node(null))
	assert_false(data.has_targets())


func test_an_overlap_reports_how_many_it_accepted() -> void:
	var second: Node = Node.new()
	add_child_autofree(second)
	assert_eq(data.append_overlap([collider, second] as Array[Node]), 2)
	assert_eq(data.get_target_nodes().size(), 2)
#endregion


#region One node, several hits
## A shotgun hits one target more than once. The node is unique; the hits are not.
func test_a_node_hit_twice_is_one_target_and_two_hits() -> void:
	data.append_physics_hit(_physics_hit(ORIGIN_3D, NORMAL_3D))
	data.append_physics_hit(_physics_hit(Vector3.ZERO, NORMAL_3D))

	assert_eq(data.get_target_nodes().size(), 1, "one target")
	assert_eq(data.get_all_hits().size(), 2, "two hits")
	assert_eq(data.get_hits_for_node(collider).size(), 2, "both belong to it")


func test_hits_for_an_unknown_node_are_none() -> void:
	data.append_physics_hit(_physics_hit(ORIGIN_3D, NORMAL_3D))
	var stranger: Node = Node.new()
	add_child_autofree(stranger)
	assert_eq(data.get_hits_for_node(stranger).size(), 0)


## An aura drops a target that walked out, and every hit that belonged to it.
func test_removing_a_target_removes_its_hits_too() -> void:
	var second: Node = Node.new()
	add_child_autofree(second)
	data.append_physics_hit(_physics_hit(ORIGIN_3D, NORMAL_3D))
	data.append_physics_hit(_physics_hit(Vector3.ZERO, NORMAL_3D))
	data.append_node(second)

	data.force_remove_target(collider)
	assert_eq(data.get_target_nodes().size(), 1, "only the one that stayed")
	assert_eq(data.get_all_hits().size(), 1, "and no hit left behind pointing at the gone one")
	assert_eq(data.get_hits_for_node(collider).size(), 0)
#endregion


#region What is handed out
## The collector validates at the append boundary, so what it hands back must
## not be the array it validated into.
func test_mutating_what_was_handed_out_does_not_reach_the_collector() -> void:
	data.append_node(collider)

	data.get_target_nodes().clear()
	data.get_all_hits().clear()

	assert_eq(data.get_target_nodes().size(), 1, "the target is still there")
	assert_eq(data.get_all_hits().size(), 1, "and so is its hit")
#endregion
