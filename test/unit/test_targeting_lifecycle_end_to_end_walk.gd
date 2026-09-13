## The ten cases where targeting, applying, animating and announcing meet.
##
## Aiming, applying, animating and announcing are four subsystems, and each has
## its own suite. What this file asks is the thing none of those can: that the
## seams between them hold. A target chosen by a person, applied to two victims,
## animated by a task somebody else takes over, and announced by a cue that
## nobody bound - one road, and every case below is a place the road has
## actually broken.
##
## Each test is one of the ten cases, in the order they were found in.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Bench = preload("res://test/fixtures/ability_task_bench.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const ABILITY_TAG: StringName = &"Ability.Gate"
const ATTACK: StringName = &"attack"
const CUE_FAMILY: StringName = &"Cue.Gate"
const CUE_LEAF: StringName = &"Cue.Gate.Impact.Critical"
const CAST: StringName = &"cast"
const OTHER: StringName = &"other"

var caster: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null
var manager: CueManagerScript = null
var _bound: Array[StringName] = []


func before_each() -> void:
	caster = Fixture.create("Caster")
	add_child_autofree(caster.owner)
	asc = caster.asc
	asc.set_process(false)
	ability = AbilityFactory.give(asc, Probe.build(ABILITY_TAG)).per_actor_instance
	ability.is_active = true
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript


func after_each() -> void:
	for tag: StringName in _bound:
		CueProbe.uninstall(manager, tag)
	_bound = []
	caster = null
	asc = null
	ability = null
	manager = null


#region Getting there
func _victim(named: String) -> ASCFixture:
	var made: ASCFixture = Fixture.create(named)
	add_child_autofree(made.owner)
	return made


func _aiming_at(nodes: Array[Node]) -> FixedTargetProvider:
	var provider: FixedTargetProvider = FixedTargetProvider.new()
	provider.aimed_at = nodes
	return provider


func _bind_cue(tag: StringName) -> void:
	CueProbe.install(manager, tag)
	_bound.append(tag)
#endregion


#region 1-4: choosing a target, and what it costs the victims
## 1. A person aims, sees a preview, and either takes it or does not.
##
## The join: what the provider confirms reaches the ability, and a cancelled
## one reaches it with nothing. `aim_with` is what wires the two together, and
## before F5.4.1 there was nothing between them to wire.
func test_case_one_previewing_confirming_and_cancelling() -> void:
	var victim: ASCFixture = _victim("Victim")
	var taken: FixedTargetProvider = _aiming_at([victim.owner] as Array[Node])
	ability.aim_with(taken)

	assert_eq(taken.state, GameplayTargetProvider.State.PREVIEWING, "it is in the middle")
	assert_eq(taken.update_preview().get_target_nodes().size(), 1, "aimed at one")
	taken.confirm()
	assert_eq(taken.state, GameplayTargetProvider.State.CONFIRMED, "and it was taken")

	var dropped: FixedTargetProvider = _aiming_at([victim.owner] as Array[Node])
	ability.aim_with(dropped)
	dropped.update_preview()
	dropped.cancel()

	assert_eq(dropped.state, GameplayTargetProvider.State.CANCELLED, "the second was not")
	assert_false(dropped.is_choosing(), "and neither is still going")
	assert_false(taken.is_choosing())


## 2. The thing being aimed at dies while the aiming is still going on.
##
## What `confirm()` hands over is the last preview rather than a fresh look at
## the world, so this is the case where a dead target reaches an ability. It
## does not: target data answers with what is still there.
func test_case_two_a_target_destroyed_during_the_preview_is_not_confirmed() -> void:
	var doomed: Node = Node.new()
	add_child(doomed)
	var provider: FixedTargetProvider = _aiming_at([doomed] as Array[Node])
	ability.aim_with(provider)
	var previewed: GameplayAbilityTargetData = provider.update_preview()
	assert_eq(previewed.get_target_nodes().size(), 1, "it was aimed at while it lived")

	doomed.free()
	provider.confirm()

	assert_eq(previewed.get_target_nodes().size(), 0, "what was confirmed is nobody")
	assert_false(previewed.has_targets(), "and it says so when asked")
	assert_false(
		provider.validate_authoritative(previewed, asc),
		"which is also what an authority would answer"
	)


## 3. One actor wearing two collision shapes is one target.
##
## The physics half is proved against a real world in the targeting suites.
## What is asserted here is the join above it: however many times an actor is
## reported, an ability applies to it once.
func test_case_three_two_hits_on_one_actor_are_one_target() -> void:
	var victim: ASCFixture = _victim("TwoShapes")
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(victim.owner)
	aimed.append_node(victim.owner)

	assert_eq(aimed.get_all_hits().size(), 2, "both shapes were reported")
	assert_eq(aimed.get_target_nodes().size(), 1, "and they are one target")

	var landed: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		EffectFactory.infinite([] as Array[GameplayEffectModifier]), aimed
	)
	assert_eq(landed.applied_targets.size(), 1, "so the effect landed once")


## 4. An area effect on two victims tells each of them only about itself.
func test_case_four_an_area_effect_does_not_contaminate_hits() -> void:
	var first: ASCFixture = _victim("First")
	var second: ASCFixture = _victim("Second")
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(first.owner)
	aimed.append_node(second.owner)

	var landed: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		EffectFactory.infinite([EffectFactory.add(ATTACK, -1.0)] as Array[GameplayEffectModifier]),
		aimed
	)

	assert_eq(landed.applied_targets.size(), 2, "it landed on both")
	var told: Array[Node] = []
	for applied: GameplayEffectApplicationResult in landed.applications:
		var theirs: Array[Node] = applied.active_effect.spec.context.get_target_nodes()
		assert_eq(theirs.size(), 1, "each was told about one thing")
		told.append(theirs[0])
	assert_true(told.has(first.owner) and told.has(second.owner), "and it was itself")
#endregion


#region 5-7: what an interruption has to let go of
## 5. A channelled ability cancelled mid-channel lets go of everything.
##
## The join: cancelling reaches the tasks and the providers at once. A cast
## interrupted half way used to leave a wait connected and a preview on screen,
## because each of those was cleaned up by whoever remembered to.
func test_case_five_cancelling_a_channel_releases_its_tasks_and_its_aiming() -> void:
	var probe: ProbeAbility = ability as ProbeAbility
	probe.channels = true
	ability.is_active = false
	asc.try_activate_ability_handle(ability.get_ability_handle())
	assert_true(ability.is_active, "it is channelling")

	var waiting: AbilityTaskWaitState = AbilityTaskFactory.wait_state(
		ability, func() -> bool: return false
	)
	var provider: FixedTargetProvider = _aiming_at([] as Array[Node])
	ability.aim_with(provider)

	ability.end_ability(true)

	assert_false(ability.is_active, "the channel is over")
	assert_true(waiting.is_finished(), "the wait is not still waiting")
	assert_false(provider.is_choosing(), "and nobody is still aiming")


## 6. An animation another ability takes over ends the first one's wait.
func test_case_six_a_replaced_animation_interrupts_the_task_that_owned_it() -> void:
	var player: AnimationPlayer = Bench.player(self, [CAST, OTHER] as Array[StringName])
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
		ability, player, CAST
	)

	var thief: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(&"Ability.Thief"))
	GameplayAnimationOwnership.claim(player, thief.per_actor_instance, OTHER)
	asc.ability_runtime.advance_time(0.1)

	assert_eq(task.outcome, AbilityTaskPlayAnimationAndWait.Outcome.INTERRUPTED)
	assert_true(task.is_finished(), "rather than waiting for a name never coming")


## 7. A cancelled move leaves the body where it got to.
func test_case_seven_a_cancelled_move_stops_where_it_was() -> void:
	var body: Node2D = Node2D.new()
	add_child_autofree(body)
	AbilityTaskFactory.move_to_2d(ability, body, Vector2(10.0, -4.0), 1.0)
	asc.ability_runtime.advance_time(0.5)

	ability.end_ability(true)
	asc.ability_runtime.advance_time(0.5)

	assert_almost_eq(body.global_position.x, 5.0, 0.001, "it stopped half way")
	assert_almost_eq(body.global_position.y, -2.0, 0.001, "on both axes")
#endregion


#region 8-10: what the world is told, and what is left behind
## 8. A cue nobody bound is played by the family that has one.
func test_case_eight_a_cue_falls_back_to_its_parent() -> void:
	_bind_cue(CUE_FAMILY)
	var params: GameplayCueParams = CueProbe.params_for(CUE_LEAF, caster.owner)

	asc.execute_cue(params)

	assert_eq(params.matched_cue_tag, CUE_FAMILY, "the family answered for the leaf")
	assert_eq(
		CueProbe.executions(manager, caster.owner, CUE_LEAF), 1, "and it actually played"
	)


## 9. Removing the effect ends the persistent cue it started, exactly once.
func test_case_nine_removing_an_effect_purges_its_persistent_cue() -> void:
	_bind_cue(CUE_FAMILY)
	var carrier: GameplayEffect = EffectFactory.with_persistent_cues(
		EffectFactory.infinite([] as Array[GameplayEffectModifier]), [CUE_FAMILY]
	)
	var active: ActiveGameplayEffect = EffectFactory.apply(asc, carrier)
	assert_eq(active.persistent_cue_handles.size(), 1, "the effect started one")
	var pooled_before: int = manager.get_pooled_count(CUE_FAMILY)

	asc.effects.remove(active)

	assert_eq(active.persistent_cue_handles.size(), 0, "the receipt is gone")
	assert_eq(manager.get_pooled_count(CUE_FAMILY), pooled_before + 1, "pooled exactly once")


## 10. And what came back out of the pool carries nothing of the run before.
##
## Through two applications of the same effect rather than through the manager
## directly, because that is the join: the second cast is handed the instance
## the first one used, and what it must not be handed is the first one's handle
## - a cue asked which effect it belongs to would name one that is over.
func test_case_ten_a_reused_cue_carries_nothing_of_the_previous_one() -> void:
	_bind_cue(CUE_FAMILY)
	var carrier: GameplayEffect = EffectFactory.with_persistent_cues(
		EffectFactory.infinite([] as Array[GameplayEffectModifier]), [CUE_FAMILY]
	)
	var first: ActiveGameplayEffect = EffectFactory.apply(asc, carrier)
	var instance: GameplayCueNotify = _the_cue_on_the_caster()
	var over: GameplayEffectHandle = first.handle

	asc.effects.remove(first)
	assert_null(instance.current_params, "it went into the pool holding nothing")

	var second: ActiveGameplayEffect = EffectFactory.apply(asc, carrier)

	assert_same(_the_cue_on_the_caster(), instance, "the same instance came back out")
	assert_not_null(instance.current_params, "running the second cast")
	assert_true(
		instance.current_params.effect_handle.same_as(second.handle),
		"whose effect is the one that is running"
	)
	assert_false(
		instance.current_params.effect_handle.same_as(over), "and not the one that is over"
	)


func _the_cue_on_the_caster() -> GameplayCueNotify:
	for child: Node in caster.owner.get_children():
		var cue: GameplayCueNotify = child as GameplayCueNotify
		if cue != null:
			return cue
	return null
#endregion
