## Cues: typed parameters, real execution and pooling.
##
## Proving a cue ran by asserting `true` after calling it proves nothing.
## These tests use a recording GameplayCueNotify and check what it actually
## received: how many times, on which node, with which parameters.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

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
	CueProbe.install(manager, IMPACT)


func after_each() -> void:
	CueProbe.uninstall(manager, IMPACT)
	fixture = null
	asc = null
	manager = null


func _params(magnitude: float = 3.0) -> GameplayCueParams:
	return CueProbe.params_for(IMPACT, fixture.owner, magnitude)


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


#region F2.5 compatibility
func test_executed_defaults_to_the_legacy_play_cue_override() -> void:
	var cue: RecordingCue = RecordingCue.new()
	add_child_autofree(cue)
	cue.executed(_params())
	assert_eq(cue.play_count, 1, "the default executed() falls through to play_cue()")


func test_a_subclass_overriding_executed_never_falls_through_to_play_cue() -> void:
	var cue: CueProbe.RecordingPersistentCue = CueProbe.RecordingPersistentCue.new()
	add_child_autofree(cue)
	cue.executed(_params())
	assert_eq(cue.executed_count, 1)
	assert_eq(cue.play_cue_count, 0, "overriding executed() skips play_cue() entirely")
#endregion


#region Persistent lifecycle
func test_persistent_cue_runs_on_active_then_while_active() -> void:
	var cue: CueProbe.RecordingPersistentCue = CueProbe.RecordingPersistentCue.new()
	add_child_autofree(cue)
	cue.begin_persistent(_params())
	assert_eq(cue.events, [&"on_active", &"while_active"])


func test_persistent_cue_never_auto_destroys_while_active() -> void:
	var cue: CueProbe.RecordingPersistentCue = CueProbe.RecordingPersistentCue.new()
	cue.destroy_delay = 0.0
	add_child_autofree(cue)
	cue.begin_persistent(_params())
	# A one-shot with a zero delay would already be finished by now; a
	# persistent activation never scheduled the timer that would do that.
	assert_not_null(cue.current_params, "still playing - begin_persistent() never finishes on its own")


func test_end_persistent_calls_on_removed_and_reports_finished() -> void:
	var cue: CueProbe.RecordingPersistentCue = CueProbe.RecordingPersistentCue.new()
	add_child_autofree(cue)
	cue.begin_persistent(_params())

	# A lambda captures an outer local by value - a one-element array is
	# captured by the same reference on both sides, so writing into slot 0
	# is visible out here too.
	var finished_count: Array[int] = [0]
	cue.cue_finished.connect(func(_node: GameplayCueNotify, _tag: StringName) -> void: finished_count[0] += 1)
	cue.end_persistent(_params())

	assert_eq(cue.events, [&"on_active", &"while_active", &"on_removed"])
	assert_eq(finished_count[0], 1, "reused the one-shot pooling signal")


func test_a_stale_one_shot_timer_does_not_steal_a_reused_persistent_cue() -> void:
	var cue: CueProbe.RecordingPersistentCue = CueProbe.RecordingPersistentCue.new()
	cue.destroy_delay = 1000.0
	add_child_autofree(cue)

	# One-shot playback schedules a timer for _playback_id 1, then the cue is
	# pooled early (finish_cue() called directly, the way a real cue's own
	# AudioStreamPlayer.finished would) - the timer is still pending.
	cue.execute_cue(_params())
	cue.finish_cue()

	# Reused for a persistent activation - a fresh _playback_id.
	cue.begin_persistent(_params())
	assert_not_null(cue.current_params, "the persistent activation is live")

	# The stale timer fires now, bound to the old (no longer current) id.
	cue._on_auto_destroy_elapsed(1)
	assert_not_null(
		cue.current_params, "the stale one-shot timer must not finish the persistent reuse"
	)


func test_deactivate_persistent_cue_tolerates_target_freed_first() -> void:
	var target_node: Node = Node.new()
	add_child(target_node)

	var params: GameplayCueParams = _params()
	params.target = target_node
	var handle: GameplayCueHandle = manager.activate_persistent_cue(params)
	assert_true(handle.is_valid())

	target_node.free()
	manager.deactivate_persistent_cue(handle, params)

	assert_false(manager._active_persistent_by_id.has(handle.id))


func test_persistent_cue_rejects_an_invalid_target_reference() -> void:
	var target_node: Node = Node.new()
	add_child(target_node)

	var params: GameplayCueParams = _params()
	# Assigned while still valid, then freed: Godot 4.7.2 hangs the process
	# when a freed instance is assigned directly into a typed Node property,
	# which is not the behavior under test here.
	params.target = target_node
	target_node.free()
	var handle: GameplayCueHandle = manager.activate_persistent_cue(params)

	assert_false(handle.is_valid())


func test_a_persistent_cue_that_ends_itself_leaves_no_handle_behind() -> void:
	var target_node: Node = Node.new()
	add_child_autofree(target_node)

	var params: GameplayCueParams = _params()
	params.target = target_node
	var handle: GameplayCueHandle = manager.activate_persistent_cue(params)
	assert_true(handle.is_valid())

	var cue: GameplayCueNotify = manager._active_persistent_by_id[handle.id]
	# `finish_cue()` is the documented way for a cue to report itself done, and
	# a persistent one is not stopped from using it. The manager hears that
	# signal and pools the node, so the registration has to go with it.
	cue.finish_cue()

	assert_false(
		manager._active_persistent_by_id.has(handle.id),
		"a pooled cue is no longer an active persistent one"
	)
	assert_eq(manager.get_pooled_count(IMPACT), 1, "it went back to its bucket")


func test_a_stale_handle_cannot_end_the_cue_the_pool_handed_to_someone_else() -> void:
	var target_node: Node = Node.new()
	add_child_autofree(target_node)

	var first_params: GameplayCueParams = _params()
	first_params.target = target_node
	var stale: GameplayCueHandle = manager.activate_persistent_cue(first_params)
	var instance: GameplayCueNotify = manager._active_persistent_by_id[stale.id]
	instance.finish_cue()

	# The pool has one instance and hands that same one to the next activation.
	var second_params: GameplayCueParams = _params()
	second_params.target = target_node
	var live: GameplayCueHandle = manager.activate_persistent_cue(second_params)
	assert_eq(
		manager._active_persistent_by_id[live.id], instance, "the pool reused the instance"
	)

	manager.deactivate_persistent_cue(stale, first_params)

	assert_true(
		manager._active_persistent_by_id.has(live.id),
		"a handle from a finished playback must not end the activation that followed it"
	)
	assert_not_null(instance.current_params, "the live cue is still playing")

	manager.deactivate_persistent_cue(live, second_params)
#endregion
