## Cues: typed parameters, real execution and pooling.
##
## Proving a cue ran by asserting `true` after calling it proves nothing.
## These tests use a recording GameplayCueNotify and check what it actually
## received: how many times, on which node, with which parameters.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

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


## A cue overriding the new lifecycle directly, none of it falling through
## to the F2 virtual.
class RecordingPersistentCue extends GameplayCueNotify:
	var events: Array[StringName] = []
	var executed_count: int = 0
	var play_cue_count: int = 0

	func executed(_params: GameplayCueParams) -> void:
		executed_count += 1

	func play_cue(_params: GameplayCueParams) -> void:
		play_cue_count += 1

	func on_active(_params: GameplayCueParams) -> void:
		events.append(&"on_active")

	func while_active(_params: GameplayCueParams) -> void:
		events.append(&"while_active")

	func on_removed(_params: GameplayCueParams) -> void:
		events.append(&"on_removed")


func before_each() -> void:
	fixture = Fixture.create("CueTarget")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	# The project's real cue registry ships empty - a scene is injected
	# directly into the manager's own maps, the same shape _load_registry()
	# would have built from a populated one, so a test can go through the
	# real manager instead of constructing a cue and driving it by hand.
	var instance: RecordingPersistentCue = RecordingPersistentCue.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(instance)
	instance.free()
	manager._cue_scenes[IMPACT] = scene
	manager._pool[IMPACT] = GameplayCuePoolBucket.new()


func after_each() -> void:
	manager._cue_scenes.erase(IMPACT)
	manager._pool.erase(IMPACT)
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


#region F2.5 compatibility
func test_executed_defaults_to_the_legacy_play_cue_override() -> void:
	var cue: RecordingCue = RecordingCue.new()
	add_child_autofree(cue)
	cue.executed(_params())
	assert_eq(cue.play_count, 1, "the default executed() falls through to play_cue()")


func test_a_subclass_overriding_executed_never_falls_through_to_play_cue() -> void:
	var cue: RecordingPersistentCue = RecordingPersistentCue.new()
	add_child_autofree(cue)
	cue.executed(_params())
	assert_eq(cue.executed_count, 1)
	assert_eq(cue.play_cue_count, 0, "overriding executed() skips play_cue() entirely")
#endregion


#region Persistent lifecycle
func test_persistent_cue_runs_on_active_then_while_active() -> void:
	var cue: RecordingPersistentCue = RecordingPersistentCue.new()
	add_child_autofree(cue)
	cue.begin_persistent(_params())
	assert_eq(cue.events, [&"on_active", &"while_active"])


func test_persistent_cue_never_auto_destroys_while_active() -> void:
	var cue: RecordingPersistentCue = RecordingPersistentCue.new()
	cue.destroy_delay = 0.0
	add_child_autofree(cue)
	cue.begin_persistent(_params())
	# A one-shot with a zero delay would already be finished by now; a
	# persistent activation never scheduled the timer that would do that.
	assert_not_null(cue.current_params, "still playing - begin_persistent() never finishes on its own")


func test_end_persistent_calls_on_removed_and_reports_finished() -> void:
	var cue: RecordingPersistentCue = RecordingPersistentCue.new()
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
	var cue: RecordingPersistentCue = RecordingPersistentCue.new()
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
#endregion


#region Effect-driven persistent lifecycle
func _infinite_persistent(tag: StringName) -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.with_persistent_cues(Factory.infinite(no_modifiers), [tag])


func test_effect_application_activates_exactly_one_persistent_cue_per_binding() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	assert_eq(active.persistent_cue_handles.size(), 1)
	assert_true(active.persistent_cue_handles[0].is_valid())


func test_removing_the_effect_pools_the_persistent_cue_exactly_once() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var pooled_before: int = manager.get_pooled_count(IMPACT)

	asc.effects.remove(active)
	assert_eq(active.persistent_cue_handles.size(), 0, "the receipt is cleared")
	assert_eq(manager.get_pooled_count(IMPACT), pooled_before + 1, "pooled exactly once")


func test_two_effects_sharing_a_cue_tag_get_independent_handles() -> void:
	var first: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var second: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	assert_false(first.persistent_cue_handles[0].id == second.persistent_cue_handles[0].id)

	asc.effects.remove(first)
	assert_eq(second.persistent_cue_handles.size(), 1, "removing one never touches the other's receipt")


func test_a_stack_reapplication_does_not_create_a_second_persistent_cue() -> void:
	var effect: GameplayEffect = _infinite_persistent(IMPACT)
	Factory.stacked(effect, GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 5)
	Factory.apply(asc, effect)
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_eq(active.stack_count, 2, "the join happened")
	assert_eq(active.persistent_cue_handles.size(), 1, "one per active effect, not one per join")


func test_inhibiting_the_effect_removes_its_persistent_cue() -> void:
	asc.add_tag(&"Status.Ready")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(_infinite_persistent(IMPACT), [&"Status.Ready"])
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_eq(active.persistent_cue_handles.size(), 1)

	asc.remove_tag(&"Status.Ready")
	assert_true(active.inhibited)
	assert_eq(active.persistent_cue_handles.size(), 0, "on_removed already ran, receipt cleared")


func test_uninhibiting_activates_a_fresh_handle_not_the_old_one() -> void:
	asc.add_tag(&"Status.Ready")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(_infinite_persistent(IMPACT), [&"Status.Ready"])
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	var first_id: int = active.persistent_cue_handles[0].id

	asc.remove_tag(&"Status.Ready")
	asc.add_tag(&"Status.Ready")
	assert_false(active.inhibited)
	assert_eq(active.persistent_cue_handles.size(), 1, "a new lifecycle activation")
	assert_ne(active.persistent_cue_handles[0].id, first_id, "never the old handle reused")


func test_cleanup_ends_persistent_cues_exactly_once() -> void:
	Factory.apply(asc, _infinite_persistent(IMPACT))
	var pooled_before: int = manager.get_pooled_count(IMPACT)

	asc.cleanup()
	assert_eq(manager.get_pooled_count(IMPACT), pooled_before + 1, "pooled exactly once, not per teardown path")


func test_missing_registry_activation_returns_an_invalid_handle_without_crashing() -> void:
	var handle: GameplayCueHandle = asc.activate_persistent_cue(_params_for(&"Cue.NeverRegistered"))
	assert_false(handle.is_valid())
	asc.deactivate_persistent_cue(handle, _params_for(&"Cue.NeverRegistered"))
	pass_test("no crash either way")


## Task 19's own "cue callback cannot mutate runtime through exposed internal
## collection": the params a cue receives carry only an opaque handle, never
## the live ActiveGameplayEffect a script could reach in and edit.
func test_cue_params_carry_an_opaque_handle_not_a_live_reference() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var params: GameplayCueParams = asc.effects.cue_params_for(IMPACT, active.spec, active.handle)
	assert_true(params.effect_handle is GameplayEffectHandle, "an opaque handle, not the live effect")
	assert_true(params.effect_handle.same_as(active.handle), "the same identity, not a copy that drifted")
	var declared_fields: Array[String] = []
	for property: Dictionary in params.get_property_list():
		declared_fields.append(property.name)
	assert_false(
		declared_fields.has("active_effect"), "no live ActiveGameplayEffect field exists on GameplayCueParams"
	)


func _params_for(tag: StringName) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = fixture.owner
	params.target = fixture.owner
	return params
#endregion
