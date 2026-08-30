## Ability tasks: owned waits that always end, and always end exactly once.
##
## Before there was a runtime, an ability suspended on whatever was convenient
## and nothing owned the wait. Ending a cast early left it running, so a
## cancelled ability could still be resumed by a signal it never disconnected,
## into an object that no longer existed.
##
## The claims worth proving are therefore about endings rather than about
## waiting: every path that closes an ability closes its tasks, every ending
## says why, and after teardown the count is zero rather than merely small.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/task_probe_ability.gd")

const PROBE_TAG: StringName = &"Ability.TaskProbe"
const OTHER_TAG: StringName = &"Ability.Other"
const SLOT: int = 3
const FRAME: float = 0.25

const BY_ENDING: StringName = &"ending"
const BY_ABORTING: StringName = &"aborting"
const BY_REMOVING: StringName = &"removing"
const BY_TAG: StringName = &"tag"


## One way an ability can close, and the reason its tasks are owed for it.
class ClosingCase extends RefCounted:
	var how: StringName = &""
	var expected: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.NONE

	func _init(closing: StringName, reason: GameplayAbilityTask.CancelReason) -> void:
		how = closing
		expected = reason

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: TaskProbeAbility = null

## The reason carried by the last `finished` this test watched.
var seen_reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.NONE

## How many `finished` emissions the watched tasks produced in total.
var seen_finishes: int = 0


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	ability = Probe.build(PROBE_TAG)
	asc.grant_ability(ability)
	seen_reason = GameplayAbilityTask.CancelReason.NONE
	seen_finishes = 0


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Helpers
func _running() -> int:
	return asc.ability_runtime.tasks.active_count()


func _watch(task: GameplayAbilityTask) -> GameplayAbilityTask:
	task.finished.connect(_on_finished)
	return task


func _on_finished(
	_task: GameplayAbilityTask, _succeeded: bool, reason: GameplayAbilityTask.CancelReason
) -> void:
	seen_reason = reason
	seen_finishes += 1
#endregion


#region Registration
func test_registering_a_task_starts_it() -> void:
	var task: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	assert_eq(task.state, GameplayAbilityTask.State.RUNNING, "registration starts the task")
	assert_eq(task.starts, 1, "and starts it once")
	assert_eq(_running(), 1, "and the runtime is holding it")


func test_a_task_without_an_owner_is_refused() -> void:
	var orphan: GameplayAbilityTask = GameplayAbilityTask.new()
	assert_null(asc.register_ability_task(orphan), "nothing could ever cancel it")
	assert_eq(_running(), 0, "so it was not taken")
	# Said out loud as well: cancellation is addressed by ability, so a task
	# without one would simply never be reached, and silence would hide that.
	assert_push_error("GodotGAS: an ability task must name the ability that owns it.")


func test_a_task_that_succeeds_is_dropped() -> void:
	var task: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	task.succeed()
	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "it ended by succeeding")
	assert_eq(_running(), 0, "and the runtime let it go")


func test_a_task_that_is_cancelled_is_dropped() -> void:
	var task: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)
	assert_eq(task.state, GameplayAbilityTask.State.CANCELLED, "it ended by being cancelled")
	assert_eq(_running(), 0, "and the runtime let it go too")


func test_cancelling_still_emits_finished() -> void:
	var task: GameplayAbilityTask = _watch(ability.register_loose_task())
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)

	# The whole point: `await task.finished` in a caller must be woken by a
	# cancellation, which is exactly when it most needs to stop waiting.
	assert_eq(seen_finishes, 1, "cancellation reports, it does not go quiet")
	assert_eq(seen_reason, GameplayAbilityTask.CancelReason.MANUAL, "and says why")


func test_an_ending_is_reported_exactly_once() -> void:
	var task: GameplayAbilityTask = _watch(ability.register_loose_task())
	task.succeed()
	task.succeed()
	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)
	assert_eq(seen_finishes, 1, "a finished task cannot finish again")
#endregion


#region Every way an ability closes
func _closing_cases() -> Array[ClosingCase]:
	return [
		ClosingCase.new(BY_ENDING, GameplayAbilityTask.CancelReason.ABILITY_ENDED),
		ClosingCase.new(BY_ABORTING, GameplayAbilityTask.CancelReason.ABILITY_ABORTED),
		ClosingCase.new(BY_REMOVING, GameplayAbilityTask.CancelReason.ABILITY_REMOVED),
		ClosingCase.new(BY_TAG, GameplayAbilityTask.CancelReason.CANCEL_TAG),
	] as Array[ClosingCase]


func _close(how: StringName) -> void:
	if how == BY_ENDING:
		ability.end_ability()
	elif how == BY_ABORTING:
		ability.abort_ability()
	elif how == BY_REMOVING:
		asc.remove_ability(ability)
	else:
		var tags: Array[StringName] = [PROBE_TAG]
		asc.cancel_abilities_with_tags(tags)


## Every way an ability closes ends its tasks, and each says which way it was.
##
## Four paths arrive at the same place and only the reason differs. Asked as
## four tests they were four copies of one claim, and copies drift: the day a
## fifth way to close is added, the other four keep passing while it leaks.
func test_every_way_of_closing_an_ability_cancels_its_tasks(
	scenario: ClosingCase = use_parameters(_closing_cases())
) -> void:
	ability.try_activate()
	var task: GameplayAbilityTask = _watch(ability.last_task)

	_close(scenario.how)

	assert_true(task.is_finished(), "the wait did not outlive the cast")
	assert_eq(seen_reason, scenario.expected, "and the reason names how it closed")
	assert_eq(_running(), 0, "and nothing is left running")


func test_cleanup_cancels_every_task() -> void:
	ability.try_activate()
	_watch(ability.last_task)
	_watch(ability.register_loose_task())

	asc.cleanup()

	assert_eq(seen_reason, GameplayAbilityTask.CancelReason.ASC_CLEANUP, "reported as teardown")
	assert_eq(seen_finishes, 2, "both of them, not only the one a cast owned")
	assert_eq(_running(), 0, "and the ASC is left holding nothing")


func test_cleaning_up_twice_does_not_report_twice() -> void:
	_watch(ability.register_loose_task())

	asc.cleanup()
	asc.cleanup()

	assert_eq(seen_finishes, 1, "the second teardown has nothing left to end")
	assert_eq(_running(), 0, "and still holds nothing")
#endregion


#region Dispatch
func test_a_finished_task_hears_nothing_further() -> void:
	var task: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	task.succeed()

	asc._process(FRAME)
	asc.ability_local_input_pressed(SLOT)
	asc.ability_local_input_released(SLOT)
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = PROBE_TAG
	asc.send_gameplay_event(event)
	asc.submit_ability_target_data(ability, GameplayAbilityTargetData.new())

	assert_eq(task.deltas.size(), 0, "no frame reached it")
	assert_eq(task.presses.size(), 0, "no press reached it")
	assert_eq(task.releases.size(), 0, "no release reached it")
	assert_eq(task.events.size(), 0, "no event reached it")
	assert_eq(task.targets.size(), 0, "no target data reached it")


func test_a_live_task_hears_every_channel() -> void:
	var task: TaskProbeAbility.ProbeTask = ability.register_loose_task()

	asc._process(FRAME)
	asc.ability_local_input_pressed(SLOT)
	asc.ability_local_input_released(SLOT)
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = PROBE_TAG
	asc.send_gameplay_event(event)
	asc.submit_ability_target_data(ability, GameplayAbilityTargetData.new())

	assert_eq(task.deltas, [FRAME] as Array[float], "the frame arrived intact")
	assert_eq(task.presses, [SLOT] as Array[int], "the press arrived")
	assert_eq(task.releases, [SLOT] as Array[int], "the release arrived")
	assert_eq(task.events.size(), 1, "the event arrived")
	assert_eq(task.targets.size(), 1, "the target data arrived")


func test_target_data_reaches_only_the_ability_it_was_addressed_to() -> void:
	var other: TaskProbeAbility = Probe.build(OTHER_TAG)
	asc.grant_ability(other)
	var mine: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	var theirs: TaskProbeAbility.ProbeTask = other.register_loose_task()

	asc.submit_ability_target_data(ability, GameplayAbilityTargetData.new())

	assert_eq(mine.targets.size(), 1, "the ability that asked was answered")
	assert_eq(theirs.targets.size(), 0, "the one that did not ask was not")


func test_a_task_ending_its_neighbour_does_not_skip_the_rest() -> void:
	var first: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	var doomed: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	var last: TaskProbeAbility.ProbeTask = ability.register_loose_task()
	first.cancels_on_delta = doomed

	asc._process(FRAME)

	# Iterating the live array would have skipped `last` when `doomed` was
	# removed mid-loop; a snapshot without a finished check would have delivered
	# to `doomed` after it ended.
	assert_eq(first.deltas.size(), 1, "the task that cancelled still received")
	assert_eq(doomed.deltas.size(), 0, "the cancelled one did not")
	assert_eq(last.deltas.size(), 1, "and its neighbour was not skipped")
	assert_eq(_running(), 2, "one of the three is gone")
#endregion


#region Teardown
func test_nothing_is_left_running_after_the_ability_goes() -> void:
	ability.try_activate()
	ability.register_loose_task()
	assert_eq(_running(), 2, "two waits are open")

	asc.remove_ability(ability)
	assert_eq(_running(), 0, "and none survive the ability")


func test_nothing_is_left_running_after_the_asc_goes() -> void:
	ability.try_activate()
	ability.register_loose_task()

	asc.cleanup()
	assert_eq(_running(), 0, "teardown leaves the count at zero, not merely small")
#endregion
