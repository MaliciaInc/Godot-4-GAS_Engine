## Task 18's standard task library: each new task's success and
## wrong-source-ignored contract, plus the doc's own required extras. Cancel,
## "remove ability", "cleanup" and "no connection leak" are the
## AbilityTaskRuntime contract every task already shares - proven once,
## generically, in test_ability_tasks.gd - except for the direct-signal-
## connect shape these tasks introduce, proven here instead.
##
## @meta_license: MIT
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const BUFF: StringName = &"Status.Buffed"
const BUFF_STRENGTH: StringName = &"Status.Buffed.Strength"
const SILENCED: StringName = &"Status.Silenced"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)
	target.asc.set_process(false)


func after_each() -> void:
	target = null


func _probe(tag: StringName = &"Ability.TaskLibraryProbe") -> ProbeAbility:
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, ProbeAbility.build(tag))
	return spec.per_actor_instance as ProbeAbility


func _query(tags: Array[StringName], op: GameplayTagQueryExpression.Operator = GameplayTagQueryExpression.Operator.ANY) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = op
	expression.tags = tags
	var q: GameplayTagQuery = GameplayTagQuery.new()
	q.root = expression
	return q


#region Attributes
func test_wait_attribute_change_succeeds_on_the_named_attribute() -> void:
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitAttributeChange = AbilityTaskFactory.wait_attribute_change(probe, ATTACK)
	target.set_base(HEALTH, target.base_of(HEALTH) + 1.0)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "a different attribute must not wake it")

	target.set_base(ATTACK, target.base_of(ATTACK) + 5.0)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_almost_eq(task.new_value - task.old_value, 5.0, 0.0001)


func test_wait_attribute_threshold_triggers_immediately_when_already_true() -> void:
	target.set_base(ATTACK, 20.0)
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitAttributeThreshold = AbilityTaskFactory.wait_attribute_threshold(
		probe, ATTACK, 10.0, AbilityTaskWaitAttributeThreshold.Comparison.GREATER_OR_EQUAL, true
	)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "already past the threshold at start")


## A task that ended before the caller held it must still be waitable.
##
## `AbilityTaskRuntime.register()` starts a task before handing it back, so one
## that ends inside `start()` has already emitted `finished` by the time the
## ability has a reference. Awaiting that signal waits for the next emission and
## a task emits exactly once - the ability would stop there and never resume,
## which is the opposite of what GameplayAbilityTask promises about being woken
## up however the task ended.
##
## If `completed()` were wrong this test would hang rather than fail, which is
## why it also asserts the state after the wait rather than only reaching it.
func test_a_task_that_ended_during_start_can_still_be_waited_on() -> void:
	target.set_base(ATTACK, 20.0)
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitAttributeThreshold = AbilityTaskFactory.wait_attribute_threshold(
		probe, ATTACK, 10.0, AbilityTaskWaitAttributeThreshold.Comparison.GREATER_OR_EQUAL, true
	)
	assert_true(task.is_finished(), "it ended before this line ran")

	await task.completed()
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "and waiting on it returned")


func test_wait_attribute_threshold_waits_for_the_comparison_to_hold() -> void:
	target.set_base(ATTACK, 0.0)
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitAttributeThreshold = AbilityTaskFactory.wait_attribute_threshold(
		probe, ATTACK, 10.0, AbilityTaskWaitAttributeThreshold.Comparison.GREATER_OR_EQUAL
	)
	target.set_base(ATTACK, 5.0)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "not there yet")
	target.set_base(ATTACK, 10.0)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
#endregion


#region Tags
func test_wait_tag_added_succeeds_hierarchically() -> void:
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitTagAdded = AbilityTaskFactory.wait_tag_added(probe, BUFF)
	target.asc.add_tag(SILENCED)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "an unrelated tag must not wake it")

	target.asc.add_tag(BUFF_STRENGTH)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "a descendant of the watched tag wakes it")


func test_wait_tag_removed_succeeds_once_nothing_still_matches() -> void:
	target.asc.add_tag(BUFF)
	target.asc.add_tag(BUFF_STRENGTH)
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitTagRemoved = AbilityTaskFactory.wait_tag_removed(probe, BUFF)

	target.asc.remove_tag(BUFF_STRENGTH)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "BUFF itself still matches")
	target.asc.remove_tag(BUFF)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "nothing left matches the pattern")


func test_wait_tag_query_nested_expression() -> void:
	# (ANY[BUFF] AND NONE[SILENCED]) - nested, not a single flat expression.
	var inner: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	inner.operator = GameplayTagQueryExpression.Operator.NONE
	inner.tags = [SILENCED]
	var outer: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	outer.operator = GameplayTagQueryExpression.Operator.ALL
	outer.tags = [BUFF]
	outer.expressions = [inner]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = outer

	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitTagQuery = AbilityTaskFactory.wait_tag_query(probe, query)
	target.asc.add_tag(SILENCED)
	target.asc.add_tag(BUFF)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "buffed but also silenced")

	target.asc.remove_tag(SILENCED)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
#endregion


#region Gameplay effects
func test_wait_gameplay_effect_applied_matches_by_query_including_instant_success() -> void:
	var effect_query: GameplayEffectQuery = GameplayEffectQuery.new()
	effect_query.granted_tags = _query([BUFF])
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitGameplayEffectApplied = AbilityTaskFactory.wait_gameplay_effect_applied(
		probe, effect_query
	)

	var no_modifiers: Array[GameplayEffectModifier] = []
	var instant_effect: GameplayEffect = EffectFactory.granting(EffectFactory.instant(no_modifiers), [BUFF])
	EffectFactory.apply(target.asc, instant_effect)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "INSTANT success has no active handle, still observed")
	assert_null(task.last_result.active_handle)


func test_wait_gameplay_effect_applied_multiple_executions_stays_running() -> void:
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitGameplayEffectApplied = AbilityTaskFactory.wait_gameplay_effect_applied(
		probe, null, null, false, false
	)
	var no_modifiers: Array[GameplayEffectModifier] = []
	EffectFactory.apply(target.asc, EffectFactory.instant(no_modifiers))
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "trigger_once is false")
	EffectFactory.apply(target.asc, EffectFactory.instant(no_modifiers))
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "still open for a third")
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)


func test_wait_gameplay_effect_removed_matches_by_handle() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, EffectFactory.infinite(no_modifiers))
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitGameplayEffectRemoved = AbilityTaskFactory.wait_gameplay_effect_removed(
		probe, active.handle
	)

	var other: ActiveGameplayEffect = EffectFactory.apply(target.asc, EffectFactory.infinite(no_modifiers))
	target.asc.remove_active_effect(other)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "a different effect's removal is not this one")

	target.asc.remove_active_effect(active)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_eq(task.removal_reason, ActiveGameplayEffect.RemovalReason.EXPLICIT)


func test_wait_gameplay_effect_stack_change_reports_old_and_new() -> void:
	var effect: GameplayEffect = EffectFactory.infinite([])
	effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_SOURCE
	effect.stack_limit_count = 5
	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, effect)
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskWaitGameplayEffectStackChange = AbilityTaskFactory.wait_gameplay_effect_stack_change(
		probe, active.handle
	)

	EffectFactory.apply(target.asc, effect)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_eq(task.old_count, 1)
	assert_eq(task.new_count, 2)
#endregion


#region Abilities
func test_wait_ability_activated_matches_by_handle() -> void:
	# The watcher's own ability owns the task, and it must survive the watcher's
	# own (unrelated) activation - a third, unrelated probe stands in for
	# "someone else activated", so the watcher's own end_ability() never runs
	# and never cancels the task through owning it.
	var watcher: ProbeAbility = _probe(&"Ability.TaskLibraryWatcher")
	var bystander: ProbeAbility = _probe(&"Ability.TaskLibraryBystander")
	var watched: ProbeAbility = ProbeAbility.build(&"Ability.TaskLibraryWatched")
	var watched_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, watched)
	var task: AbilityTaskWaitAbilityActivated = AbilityTaskFactory.wait_ability_activated(
		watcher, watched_spec.handle
	)

	target.asc.ability_runtime.try_activate(bystander.get_ability_handle())
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "an unrelated activation is not the watched one")

	target.asc.ability_runtime.try_activate(watched_spec.handle)
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)


func test_wait_ability_ended_matches_by_tag_query() -> void:
	var watcher: ProbeAbility = _probe(&"Ability.TaskLibraryEndWatcher")
	var bystander: ProbeAbility = _probe(&"Ability.TaskLibraryEndBystander")
	var watched: ProbeAbility = ProbeAbility.build(&"Ability.TaskLibraryEndWatched")
	AbilityFactory.give(target.asc, watched)
	var task: AbilityTaskWaitAbilityEnded = AbilityTaskFactory.wait_ability_ended_matching(
		watcher, _query([&"Ability.TaskLibraryEndWatched"])
	)

	target.asc.ability_runtime.try_activate(bystander.get_ability_handle())
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "an unrelated ability ending is not the watched one")
#endregion


#region Confirm/cancel, repeat, animation
func test_wait_confirm_cancel_distinguishes_the_two_decisions() -> void:
	var probe: ProbeAbility = _probe()
	var confirming: AbilityTaskWaitConfirmCancel = AbilityTaskFactory.wait_confirm_cancel(probe, 1, 2)
	confirming.handle_input_pressed(1)
	assert_eq(confirming.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_eq(confirming.decision, AbilityTaskWaitConfirmCancel.Decision.CONFIRMED)

	var cancelling: AbilityTaskWaitConfirmCancel = AbilityTaskFactory.wait_confirm_cancel(probe, 1, 2)
	cancelling.handle_input_pressed(2)
	assert_eq(cancelling.decision, AbilityTaskWaitConfirmCancel.Decision.CANCELLED)


func test_repeat_pays_a_large_delta_with_a_cap_and_backlog() -> void:
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskRepeat = AbilityTaskFactory.repeat(probe, 1.0, 0)
	task.advance_time(70.0)
	assert_eq(task.completed_count, AbilityTaskRepeat.MAX_CATCH_UP_REPETITIONS_PER_UPDATE, "capped this update")

	task.advance_time(0.0)
	assert_eq(task.completed_count, 70, "the backlog paid on the next update")
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)


func test_repeat_indefinite_keeps_going_until_cancelled() -> void:
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskRepeat = AbilityTaskFactory.repeat(probe, 1.0, 0)
	for _tick: int in 5:
		task.advance_time(1.0)
	assert_eq(task.completed_count, 5)
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "0 repetitions means indefinite")
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)
	assert_eq(task.state, GameplayAbilityTask.State.CANCELLED)


func _player_with_animation(anim_name: StringName) -> AnimationPlayer:
	var player: AnimationPlayer = AnimationPlayer.new()
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation(anim_name, Animation.new())
	player.add_animation_library("", library)
	add_child_autofree(player)
	return player


func test_play_animation_and_wait_succeeds_only_for_the_requested_animation() -> void:
	var player: AnimationPlayer = _player_with_animation(&"cast")
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(probe, player, &"cast")

	player.animation_finished.emit(&"other")
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "the wrong animation finishing must not wake it")

	player.animation_finished.emit(&"cast")
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED)


func test_play_animation_and_wait_cancel_does_not_stop_a_shared_player_by_default() -> void:
	var player: AnimationPlayer = _player_with_animation(&"cast")
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(probe, player, &"cast")

	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)
	assert_true(player.is_playing(), "stop_on_cancel defaults false - a shared player is not stopped")


func test_play_animation_and_wait_cancel_tolerates_a_freed_player() -> void:
	var player: AnimationPlayer = _player_with_animation(&"cast")
	var probe: ProbeAbility = _probe()
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		probe, player, &"cast", true
	)

	player.free()
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)

	assert_eq(task.state, GameplayAbilityTask.State.CANCELLED)
#endregion


#region Removal disconnects the new direct-signal-connect shape
func test_removing_the_ability_disconnects_a_signal_based_task() -> void:
	var probe: ProbeAbility = _probe()
	var handle: GameplayAbilityHandle = probe.get_ability_handle()
	var task: AbilityTaskWaitTagAdded = AbilityTaskFactory.wait_tag_added(probe, BUFF)
	assert_eq(target.asc.ability_runtime.tasks.active_count(), 1)

	target.asc.ability_runtime.remove_ability(handle)
	assert_eq(task.state, GameplayAbilityTask.State.CANCELLED, "ABILITY_REMOVED cancels it")
	assert_false(
		target.asc.tag_added.is_connected(task._on_tag_added), "the direct connection was released, not leaked"
	)
	assert_eq(target.asc.ability_runtime.tasks.active_count(), 0)


func test_zero_tasks_remain_after_a_batch_of_tasks_end() -> void:
	var probe: ProbeAbility = _probe()
	AbilityTaskFactory.wait_tag_added(probe, BUFF)
	AbilityTaskFactory.wait_attribute_change(probe, ATTACK)
	var repeating: AbilityTaskRepeat = AbilityTaskFactory.repeat(probe, 1.0, 0)
	assert_eq(target.asc.ability_runtime.tasks.active_count(), 3)

	target.asc.ability_runtime.remove_ability(probe.get_ability_handle())
	assert_eq(target.asc.ability_runtime.tasks.active_count(), 0)
	assert_eq(repeating.state, GameplayAbilityTask.State.CANCELLED)
#endregion
