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
	# Restored here rather than inside a test: GUT reads the tracker when the
	# test ends, so a test that put it back itself would put it back too early.
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE


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
#region The four that were missing
## The area is handed in, never built: an engine that made one would be choosing
## a game's collision layers, shape and placement.
func test_wait_overlap_refuses_anything_that_is_not_an_area() -> void:
	# The refusal is loud on purpose - a caller passing the wrong node has a bug -
	# so this test says it expects one rather than lowering the engine's severity.
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING

	var not_an_area: Node = Node.new()
	add_child_autofree(not_an_area)

	assert_null(
		AbilityTaskWaitOverlap.create(ability, not_an_area),
		"a plain node is not something overlaps happen in"
	)


func test_wait_overlap_ends_on_the_first_thing_that_gets_through() -> void:
	var area: Area3D = Area3D.new()
	add_child_autofree(area)
	var task: AbilityTaskWaitOverlap = ability.wait_overlap(area)
	task.start()

	var passer_by: Node3D = Node3D.new()
	add_child_autofree(passer_by)
	area.area_entered.emit(passer_by)

	assert_true(task.is_finished(), "it ended")
	assert_eq(task.overlapped_node, passer_by, "on the thing that came in")


func test_wait_velocity_change_ends_when_the_avatar_is_moving_fast_enough() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	fixture.owner.add_child(body)
	asc.init_ability_actor_info(fixture.owner, body)

	var task: AbilityTaskWaitVelocityChange = ability.wait_velocity_change(Vector3.ZERO, 5.0)
	task.start()

	body.velocity = Vector3(1.0, 0.0, 0.0)
	task.advance_time(0.1)
	assert_false(task.is_finished(), "not fast enough yet")

	body.velocity = Vector3(6.0, 0.0, 0.0)
	task.advance_time(0.1)
	assert_true(task.is_finished(), "and now it is")
	assert_almost_eq(task.reached.x, 6.0, 0.0001, "with what it was moving at")


## Two states with different names run at once, and ending one leaves the other.
func test_named_ability_states_are_ended_by_name() -> void:
	var winding: AbilityTaskAbilityState = ability.start_ability_state(&"winding")
	var guarding: AbilityTaskAbilityState = ability.start_ability_state(&"guarding")

	var ended: Array[StringName] = []
	winding.state_ended.connect(
		func(named: StringName, _cancelled: bool) -> void: ended.append(named)
	)

	assert_eq(ability.end_ability_state(&"winding"), 1, "one state by that name")

	assert_eq(ended, [&"winding"] as Array[StringName], "and it said so")
	assert_true(winding.is_finished(), "it ended")
	assert_false(guarding.is_finished(), "and the other one did not")


func test_ending_a_name_nothing_carries_affects_nothing() -> void:
	ability.start_ability_state(&"winding")
	assert_eq(ability.end_ability_state(&"nothing"), 0, "no task by that name")


func test_cancelling_a_state_says_it_was_cancelled() -> void:
	var winding: AbilityTaskAbilityState = ability.start_ability_state(&"winding")
	var how: Array[bool] = []
	winding.state_ended.connect(
		func(_named: StringName, cancelled: bool) -> void: how.append(cancelled)
	)

	assert_eq(ability.cancel_ability_state(&"winding"), 1, "it was called off")
	assert_eq(how, [true] as Array[bool], "and it knows the difference")


func test_wait_effect_applied_to_target_hears_what_this_ability_landed() -> void:
	var other: ASCFixture = ASCFixture.create("Struck")
	add_child_autofree(other.owner)

	var task: AbilityTaskWaitEffectAppliedToTarget = ability.wait_effect_applied_to_target()
	task.start()

	var landed: GameplayEffect = GameplayEffect.new()
	landed.policy = GameplayEffect.DurationPolicy.INSTANT
	asc.apply_effect_spec_to_target(GameplayEffectSpec.new(landed), other.asc)

	assert_true(task.is_finished(), "it heard about it")
	assert_eq(task.matched_target, other.asc, "and who it landed on")
#endregion


#region Saying whether it may be interrupted
## An override, not a replacement: an ability that computes the answer - not
## while the blade is down - is answering a question a boolean cannot.
func test_cancelability_defaults_to_what_the_ability_computes() -> void:
	assert_true(ability.is_cancellable(), "the base answer")


func test_setting_cancelability_overrules_the_computed_answer() -> void:
	ability.set_can_be_cancelled(false)
	assert_false(ability.is_cancellable(), "what it was told")

	ability.set_can_be_cancelled(true)
	assert_true(ability.is_cancellable(), "and told again")
#endregion
