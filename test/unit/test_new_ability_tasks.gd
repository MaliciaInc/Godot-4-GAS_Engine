## Nine tasks, and the promise every one of them makes.
##
## A task is a promise to end. What goes wrong is never the waiting - it is the
## not-ending: a signal still connected after the ability was cancelled, a node
## left in the world by a cast that was interrupted, a condition that will never
## be true and nothing to notice. So this file asks the same questions of all
## nine at once: is each owned by something that can end it, does each end when
## the ability does, and does each end exactly once however often it is told to.
##
## What each of them is individually for is the file beside this one,
## `test_new_ability_task_behaviour.gd`. The split is the subject, not the
## length: one file builds all nine and asks them one thing, the other builds
## one at a time and asks it everything.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Bench = preload("res://test/fixtures/ability_task_bench.gd")

const ABILITY_TAG: StringName = &"Ability.Waiting"
const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const BURNING: StringName = &"Status.Burning"

var bench: AbilityTaskBench = null
var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null


func before_each() -> void:
	bench = Bench.stand(self, ABILITY_TAG)
	fixture = bench.fixture
	asc = bench.asc
	ability = bench.ability


func after_each() -> void:
	bench = null
	fixture = null
	asc = null
	ability = null


#region Getting there
## Every task the phase names, built through its own factory.
##
## Through the factory rather than by hand, because "registered on the runtime"
## is half of what makes a task cancellable - one built directly is one nothing
## will ever end.
func _all_of_them() -> Array:
	return [
		["a commit", AbilityTaskFactory.wait_ability_commit(ability)],
		["an immunity block", AbilityTaskFactory.wait_effect_blocked_by_immunity(ability)],
		[
			"a ratio threshold",
			AbilityTaskFactory.wait_attribute_ratio_threshold(ability, HEALTH, MAX_HEALTH, 0.25),
		],
		["a tag count change", AbilityTaskFactory.wait_tag_count_change(ability, BURNING)],
		["a spawn", AbilityTaskFactory.spawn_actor(ability, Bench.scene())],
		["a condition", AbilityTaskFactory.wait_state(ability, func() -> bool: return false)],
		[
			"a move",
			AbilityTaskFactory.move_to_2d(ability, Bench.body(self), Vector2(10.0, 0.0), 1.0),
		],
		["root motion", AbilityTaskFactory.root_motion(ability, Bench.tree(self), Bench.spatial(self), 1.0)],
		["a sync point", AbilityTaskFactory.network_sync_point(ability)],
	]
#endregion


#region What every one of them promises
## Every task is registered, so something can end it.
##
## A task nothing owns is a task nothing will cancel, which is the whole of the
## failure this is guarding: an ability interrupted mid-cast leaving a wait
## behind it.
func test_every_task_is_owned_by_the_runtime_that_can_end_it() -> void:
	var rows: Array = _all_of_them()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var task: GameplayAbilityTask = row[1]

		assert_not_null(task, "%s: was created" % described)
		assert_same(task.owner_ability, ability, "%s: knows whose it is" % described)
		checked += 1
	assert_eq(checked, 9, "all nine were built")


## Every task ends when the ability does, whichever state it was in.
##
## The one that matters. A task still waiting after its ability was cancelled is
## a signal still connected, a node still in the world, or a condition nobody
## will ever answer.
func test_every_task_ends_when_the_ability_does() -> void:
	var rows: Array = _all_of_them()
	var still_going: Array[String] = []
	for row: Array in rows:
		var task: GameplayAbilityTask = row[1]
		if not task.is_finished():
			still_going.append(row[0])

	ability.end_ability(true)

	var left_behind: Array[String] = []
	for row: Array in rows:
		var task: GameplayAbilityTask = row[1]
		if not task.is_finished():
			left_behind.append(row[0])

	assert_gt(still_going.size(), 4, "several were genuinely waiting")
	assert_eq(left_behind, [] as Array[String], "and none of them is still waiting")


## Every task ends once, however many times it is told to.
func test_every_task_ends_exactly_once() -> void:
	var rows: Array = _all_of_them()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var task: GameplayAbilityTask = row[1]
		var endings: Array[bool] = []
		task.finished.connect(
			func(_task: GameplayAbilityTask, ok: bool, _why: GameplayAbilityTask.CancelReason) -> void:
				endings.append(ok)
		)

		task.succeed()
		task.succeed()
		task.cancel(GameplayAbilityTask.CancelReason.ABILITY_ENDED)

		assert_lt(endings.size(), 2, "%s: it ended at most once more" % described)
		assert_true(task.is_finished(), "%s: and it is over" % described)
		checked += 1
	assert_eq(checked, 9, "all nine were asked")
#endregion
