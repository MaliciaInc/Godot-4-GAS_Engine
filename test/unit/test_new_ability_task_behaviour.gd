## What each of the nine tasks is individually for.
##
## The contract they all share - owned, ended with the ability, ended once - is
## asked of all nine at once in `test_new_ability_tasks.gd`. This file is the
## other half: one task at a time, and the specific thing it exists to notice
## that nothing else in the engine announces.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
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


#region What each of them is for
## A commit is a different moment from an activation.
func test_waiting_for_a_commit_wakes_on_the_commit_and_not_the_activation() -> void:
	var task: AbilityTaskWaitAbilityCommit = AbilityTaskFactory.wait_ability_commit(ability)
	assert_false(task.is_finished(), "nothing has paid for itself yet")

	var probe: ProbeAbility = ability as ProbeAbility
	probe.commits = true
	# Put back to not-running first: `before_each` marks it active so the tasks
	# above have something that can end, and an ability already running refuses
	# to activate rather than committing again.
	ability.is_active = false
	asc.try_activate_ability_handle(ability.get_ability_handle())

	# Succeeded, not merely finished. The template ability ends when its body
	# returns, which cancels every task it owns - so "is_finished" is true either
	# way and says nothing about what woke this one.
	assert_eq(
		task.state, GameplayAbilityTask.State.SUCCEEDED,
		"the commit woke it, rather than the ability ending cancelling it"
	)
	assert_not_null(task.result, "and it knows what the commit said")
	assert_eq(
		task.result.status, AbilityCommitResult.Status.SUCCESS, "which is that it paid"
	)


## Watching one grant means another grant's commit is not the one.
##
## The filtered half of this task had no test, and what it called - `equals()` -
## is not a method GameplayAbilityHandle has. The first commit ever to reach a
## task watching a specific grant would have taken the frame down with it.
func test_a_commit_watch_aimed_at_one_grant_ignores_another_grants_commit() -> void:
	var other: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(&"Ability.Other"))
	var other_probe: ProbeAbility = other.per_actor_instance as ProbeAbility
	other_probe.commits = true

	var mine: GameplayAbilityHandle = ability.get_ability_handle()
	var task: AbilityTaskWaitAbilityCommit = AbilityTaskFactory.wait_ability_commit(ability, mine)

	asc.try_activate_ability_handle(other.handle)
	assert_eq(
		task.state, GameplayAbilityTask.State.RUNNING,
		"someone else paying is not what it was waiting for"
	)
	assert_null(task.committed_handle, "and it kept nothing from it")

	var probe: ProbeAbility = ability as ProbeAbility
	probe.commits = true
	ability.is_active = false
	asc.try_activate_ability_handle(mine)

	assert_eq(task.state, GameplayAbilityTask.State.SUCCEEDED, "its own grant paying is")
	assert_true(task.committed_handle.same_as(mine), "and it kept which grant that was")


## An effect turned away by an immunity is a moment nothing else announces.
func test_waiting_for_an_immunity_block_wakes_when_one_bounces() -> void:
	var task: AbilityTaskWaitEffectBlockedByImmunity = (
		AbilityTaskFactory.wait_effect_blocked_by_immunity(ability)
	)
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [&"Damage.Fire"] as Array[StringName]
	query.asset_tags = GameplayTagQuery.new()
	query.asset_tags.root = expression
	EffectFactory.apply(
		asc, EffectFactory.immune_to(
			EffectFactory.infinite([] as Array[GameplayEffectModifier]), query
		)
	)

	var tags: GameplayEffectAssetTagsComponent = GameplayEffectAssetTagsComponent.new()
	tags.asset_tags = [&"Damage.Fire"] as Array[StringName]
	var incoming: GameplayEffect = EffectFactory.infinite([] as Array[GameplayEffectModifier])
	incoming.components.append(tags)
	EffectFactory.apply_result(asc, incoming)

	assert_true(task.is_finished(), "the block woke it")
	assert_eq(
		task.blocked.status, GameplayEffectApplicationResult.Status.IMMUNE,
		"and it knows what turned it away"
	)


## A ratio is what a design means by "below a quarter health".
##
##     [what happens, the health, whether it wakes]
func _ratios() -> Array:
	return [
		["still above the line", 50.0, false],
		["exactly on it", 25.0, true],
		["below it", 10.0, true],
	]


func test_a_ratio_threshold_is_about_the_fraction_not_the_number() -> void:
	var rows: Array = _ratios()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var health: float = row[1]
		var wakes: bool = row[2]

		before_each()
		fixture.set_base(MAX_HEALTH, 100.0)
		fixture.set_base(HEALTH, 100.0)
		var task: AbilityTaskWaitAttributeRatioThreshold = (
			AbilityTaskFactory.wait_attribute_ratio_threshold(ability, HEALTH, MAX_HEALTH, 0.25)
		)
		asc.set_attribute_base(HEALTH, health)

		assert_eq(task.is_finished(), wakes, "%s: woke?" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every position was offered")


## A stack going from three to two is a change nothing else announces.
func test_a_tag_count_change_wakes_on_a_stack_that_did_not_arrive_or_leave() -> void:
	asc.add_tag(BURNING)
	asc.add_tag(BURNING)
	var task: AbilityTaskWaitTagCountChange = AbilityTaskFactory.wait_tag_count_change(
		ability, BURNING
	)
	assert_eq(task.old_count, 2, "two of it to begin with")

	asc.remove_tag(BURNING)

	assert_true(task.is_finished(), "the count moved")
	assert_eq(task.new_count, 1, "and it says what to")


## Spawning puts something in the world and takes it back out when cancelled.
##
## The failure it exists for: a cast interrupted half way leaving a turret in
## the level that nobody asked for.
func test_a_spawn_is_taken_back_when_the_ability_is_cancelled() -> void:
	var task: AbilityTaskSpawnActor = AbilityTaskFactory.spawn_actor(ability, Bench.scene())

	assert_not_null(task.spawned, "it is in the world")
	assert_false(task.is_finished(), "and the task holds it rather than letting go at once")
	var put_there: Node = task.spawned

	ability.end_ability(true)
	await wait_frames(2)

	assert_false(is_instance_valid(put_there), "and it is taken back out")


## Unless the ability said to keep it.
func test_a_spawn_the_ability_asked_to_keep_stays() -> void:
	var task: AbilityTaskSpawnActor = AbilityTaskFactory.spawn_actor(ability, Bench.scene())
	task.keep_on_finish = true
	var put_there: Node = task.spawned

	ability.end_ability(true)
	await wait_frames(2)

	assert_true(is_instance_valid(put_there), "it stayed, because it was asked to")


## A condition already true is not waited a frame for.
func test_a_condition_already_true_is_not_waited_for() -> void:
	var task: AbilityTaskWaitState = AbilityTaskFactory.wait_state(
		ability, func() -> bool: return true
	)

	assert_true(task.is_finished(), "it was true when it was asked")


## And one that never comes true gives up rather than waiting for ever.
func test_a_condition_that_never_comes_true_gives_up() -> void:
	var task: AbilityTaskWaitState = AbilityTaskFactory.wait_state(
		ability, func() -> bool: return false, 0.5
	)

	asc.ability_runtime.advance_time(0.6)

	assert_true(task.is_finished(), "it stopped waiting")
	assert_true(task.timed_out, "and says why")


## A move arrives, by the clock the tasks are advanced by.
##
## Both bodies, and both axes of the flat one. The task keeps one Vector3
## destination and lifts a 2D point into it, so a move asked only about x
## could not tell that lift from a drop - and `move_to_3d` is a factory the
## phase names, which nothing else here would exercise.
func test_a_move_arrives_on_the_clock_the_tasks_are_advanced_by() -> void:
	var body: Node2D = Bench.body(self)
	var spatial: Node3D = Bench.spatial(self)
	var flat: AbilityTaskMoveTo = AbilityTaskFactory.move_to_2d(
		ability, body, Vector2(10.0, -4.0), 1.0
	)
	var solid: AbilityTaskMoveTo = AbilityTaskFactory.move_to_3d(
		ability, spatial, Vector3(2.0, 6.0, -8.0), 1.0
	)

	asc.ability_runtime.advance_time(0.5)
	assert_almost_eq(body.global_position.x, 5.0, 0.001, "half way across")
	assert_almost_eq(body.global_position.y, -2.0, 0.001, "and half way down")
	assert_almost_eq(spatial.global_position.y, 3.0, 0.001, "the solid one too")

	asc.ability_runtime.advance_time(0.5)
	assert_almost_eq(body.global_position.x, 10.0, 0.001, "and there")
	assert_almost_eq(body.global_position.y, -4.0, 0.001, "on both axes")
	assert_almost_eq(spatial.global_position.x, 2.0, 0.001, "and there in x")
	assert_almost_eq(spatial.global_position.y, 6.0, 0.001, "in y")
	assert_almost_eq(spatial.global_position.z, -8.0, 0.001, "and in z")
	assert_true(flat.is_finished(), "so the flat one is done")
	assert_true(solid.is_finished(), "and so is the solid one")


## A move cancelled leaves what was moved where it got to.
func test_a_cancelled_move_leaves_the_body_where_it_got_to() -> void:
	var body: Node2D = Bench.body(self)
	AbilityTaskFactory.move_to_2d(ability, body, Vector2(10.0, 0.0), 1.0)
	asc.ability_runtime.advance_time(0.5)

	ability.end_ability(true)
	asc.ability_runtime.advance_time(0.5)

	assert_almost_eq(body.global_position.x, 5.0, 0.001, "it stopped where it was")


## Root motion is claimed and released, including when the ability was cut off.
func test_root_motion_is_released_when_the_ability_is_cut_off() -> void:
	var task: AbilityTaskRootMotion = AbilityTaskFactory.root_motion(
		ability, Bench.tree(self), Bench.spatial(self), 5.0
	)
	assert_true(task.owns_motion, "it is driving")

	ability.end_ability(true)

	assert_false(task.owns_motion, "and it let go")


## A sync point waits for both, and can be told not to wait for ever.
##
##     [what it waits for, who arrives, whether it goes on]
func _rendezvous() -> Array:
	return [
		["both, and only the server arrives", "both", "server", false],
		["both, and both arrive", "both", "both", true],
		["only the server, and it arrives", "server", "server", true],
		["only the client, and the server arrives", "client", "server", false],
	]


func test_a_sync_point_waits_for_whoever_it_was_told_to() -> void:
	var rows: Array = _rendezvous()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var waits_for: String = row[1]
		var arrives: String = row[2]
		var goes_on: bool = row[3]

		before_each()
		var wanted: AbilityTaskNetworkSyncPoint.Wait = AbilityTaskNetworkSyncPoint.Wait.BOTH
		if waits_for == "server":
			wanted = AbilityTaskNetworkSyncPoint.Wait.ONLY_SERVER
		elif waits_for == "client":
			wanted = AbilityTaskNetworkSyncPoint.Wait.ONLY_CLIENT
		var task: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
			ability, wanted
		)

		if arrives == "server" or arrives == "both":
			task.server_arrives()
		if arrives == "both":
			task.client_arrives()

		assert_eq(task.is_finished(), goes_on, "%s: went on?" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every rendezvous was offered")


## A sync point that can hang is a predicted ability that can hang.
func test_a_sync_point_can_be_told_not_to_wait_for_ever() -> void:
	var task: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
		ability, AbilityTaskNetworkSyncPoint.Wait.BOTH, 0.5
	)

	asc.ability_runtime.advance_time(0.6)

	assert_true(task.is_finished(), "it went on")
	assert_true(task.timed_out, "and says it did so without them")
#endregion
