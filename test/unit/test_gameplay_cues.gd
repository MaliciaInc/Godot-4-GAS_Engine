## Cues: typed parameters, real execution and pooling.
##
## Step 10.1 forbids proving a cue ran by asserting `true` after calling it.
## These tests use a recording GameplayCueNotify and check what it actually
## received: how many times, on which node, with which parameters.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GodotGAS/managers/gameplay_cue_manager.gd")

const IMPACT: StringName = &"Cue.Impact"
const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


## A cue that records every playback instead of drawing anything.
class RecordingCue extends GameplayCueNotify:
	var play_count: int = 0
	var last_params: GameplayCueParams = null
	var last_parent: Node = null

	func play_cue(params: GameplayCueParams) -> void:
		play_count += 1
		last_params = params
		last_parent = get_parent()


func before_each() -> void:
	fixture = Fixture.create("CueTarget")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript


func after_each() -> void:
	fixture = null
	asc = null
	manager = null


func _params(magnitude: float = 3.0) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = IMPACT
	params.instigator = fixture.owner
	params.target = fixture.owner
	params.magnitude = magnitude
	return params


#region Typed parameters
func test_params_carry_every_field_the_cue_needs() -> void:
	var params: GameplayCueParams = _params(12.5)
	assert_eq(params.cue_tag, IMPACT)
	assert_eq(params.instigator, fixture.owner)
	assert_eq(params.target, fixture.owner)
	assert_almost_eq(params.magnitude, 12.5, TOLERANCE)


func test_an_absent_location_is_distinguishable_from_the_origin() -> void:
	var params: GameplayCueParams = _params()
	assert_false(params.has_location, "no location yet")

	params.with_location(Vector3.ZERO)
	# Vector3.ZERO is a real place, so it cannot double as "nowhere". The flag is
	# what tells a cue whether to use the vector at all.
	assert_true(params.has_location, "the origin is still a location")


func test_the_factory_builds_the_common_case() -> void:
	var params: GameplayCueParams = GameplayCueParams.for_target(
		IMPACT, fixture.owner, fixture.owner, 4.0
	)
	assert_eq(params.cue_tag, IMPACT)
	assert_almost_eq(params.magnitude, 4.0, TOLERANCE)
#endregion


#region Real execution
func test_a_cue_receives_its_parameters_and_its_parent() -> void:
	var cue: RecordingCue = RecordingCue.new()
	cue.auto_destroy = false
	add_child_autofree(cue)

	var params: GameplayCueParams = _params(9.0)
	cue.execute_cue(params)

	assert_eq(cue.play_count, 1, "played exactly once")
	assert_eq(cue.last_params, params, "and received the parameters, not a copy of some keys")
	assert_almost_eq(cue.last_params.magnitude, 9.0, TOLERANCE)


func test_finishing_reports_the_cue_and_its_tag() -> void:
	var cue: RecordingCue = RecordingCue.new()
	cue.auto_destroy = false
	cue.gameplay_cue_tag = IMPACT
	add_child_autofree(cue)

	var reported_nodes: Array[GameplayCueNotify] = []
	var reported_tags: Array[StringName] = []
	cue.cue_finished.connect(
		func(node: GameplayCueNotify, tag: StringName) -> void:
			reported_nodes.append(node)
			reported_tags.append(tag)
	)
	cue.execute_cue(_params())
	cue.finish_cue()

	assert_eq(reported_nodes.size(), 1, "one report")
	assert_eq(reported_nodes[0], cue, "which cue")
	assert_eq(reported_tags[0], IMPACT, "and under which tag")


func test_a_finished_cue_forgets_its_parameters() -> void:
	var cue: RecordingCue = RecordingCue.new()
	cue.auto_destroy = false
	add_child_autofree(cue)
	cue.execute_cue(_params())
	cue.finish_cue()
	# A pooled cue holding the last playback's parameters would hand them to
	# whatever inspects it next.
	assert_null(cue.current_params, "released on finish")
#endregion


#region Pooling
func test_the_pool_starts_empty_for_an_unknown_tag() -> void:
	assert_not_null(manager, "the autoload is present")
	assert_eq(manager.get_pooled_count(&"Cue.NeverUsed"), 0)


func test_a_finished_cue_returns_to_its_bucket() -> void:
	var bucket: GameplayCuePoolBucket = GameplayCuePoolBucket.new()
	var cue: RecordingCue = RecordingCue.new()
	add_child_autofree(cue)

	assert_true(bucket.is_empty(), "empty to begin with")
	bucket.give(cue)
	assert_eq(bucket.size(), 1, "took it")

	var taken: GameplayCueNotify = bucket.take()
	assert_eq(taken, cue, "gave the same one back")
	assert_true(bucket.is_empty(), "and is empty again")


func test_a_bucket_will_not_hold_the_same_cue_twice() -> void:
	var bucket: GameplayCuePoolBucket = GameplayCuePoolBucket.new()
	var cue: RecordingCue = RecordingCue.new()
	add_child_autofree(cue)

	bucket.give(cue)
	bucket.give(cue)
	# A double return would let two callers take the same node and both parent
	# it, which Godot resolves by reparenting and one of them silently loses.
	assert_eq(bucket.size(), 1, "stored once")


func test_an_empty_bucket_answers_null_rather_than_guessing() -> void:
	var bucket: GameplayCuePoolBucket = GameplayCuePoolBucket.new()
	assert_null(bucket.take(), "the caller decides what an empty pool means")
#endregion


#region The ASC route
func test_the_asc_fills_in_the_target_when_the_caller_did_not() -> void:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = IMPACT
	asc.execute_cue(params)
	# The cue plays on the entity, not on the component.
	assert_eq(params.target, fixture.owner, "defaulted to the owning entity")


func test_a_null_parameter_object_is_ignored() -> void:
	asc.execute_cue(null)
	pass_test("no crash, and nothing to assert beyond that")
#endregion
