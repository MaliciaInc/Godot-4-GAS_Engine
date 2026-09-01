## Task 17's canonical lifecycle: AbilityRuntime.try_activate() by handle,
## GameplayAbilityActivationResult's closed Status, remove_ability()'s two
## policies, and give_and_activate_once() on top of them.
##
## @meta_license: MIT
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const BLOCKED: StringName = &"Status.Silenced"
const REQUIRED: StringName = &"Status.Ready"
const COOLDOWN_TAG: StringName = &"Cooldown.Probe"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


func _query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = tags
	var q: GameplayTagQuery = GameplayTagQuery.new()
	q.root = expression
	return q


#region try_activate() by handle
func test_try_activate_starts_a_manual_ability() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.Lifecycle")
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.SUCCESS)
	assert_eq(result.instance, spec.per_actor_instance)
	assert_eq((spec.per_actor_instance as ProbeAbility).activations, 1)


func test_try_activate_reports_spec_not_found_for_an_unresolvable_handle() -> void:
	var stale: GameplayAbilityHandle = GameplayAbilityHandle.new()
	stale.owner_instance_id = target.asc.get_instance_id()
	stale.id = 999999
	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(stale)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.SPEC_NOT_FOUND)


func test_try_activate_maps_a_blocked_query_to_blocked_by_tags() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecycleBlocked")
	probe.activation_blocked_query = _query([BLOCKED])
	target.asc.add_tag(BLOCKED)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.BLOCKED_BY_TAGS)


func test_try_activate_maps_a_missing_required_query_to_missing_required_tags() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecycleRequired")
	probe.activation_required_query = _query([REQUIRED])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.MISSING_REQUIRED_TAGS)


func test_try_activate_maps_an_active_cooldown_tag_to_on_cooldown() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecycleCooldown")
	probe.cooldown_effect = EffectFactory.granting(EffectFactory.duration(no_modifiers, 5.0), [COOLDOWN_TAG])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.add_tag(COOLDOWN_TAG)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.ON_COOLDOWN)


## Task 17's own required regression: the activation result reports SUCCESS
## the instant it starts, never waiting for a channelled ability's own end.
func test_a_channelled_ability_reports_success_immediately_and_stays_active() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleChannel"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.SUCCESS)
	assert_true(spec.per_actor_instance.is_active, "still channelling - try_activate() did not wait for it")

	(spec.per_actor_instance as ChannelingAbility).channel_gate.emit()


func test_ability_activated_signal_fires_with_handle_and_instance() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecycleSignal")
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	watch_signals(target.asc)

	target.asc.ability_runtime.try_activate(spec.handle)
	assert_signal_emitted_with_parameters(
		target.asc, "ability_activated", [spec.handle, spec.per_actor_instance]
	)


func test_ability_runtime_ended_signal_fires_when_the_activation_finishes() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleEndedSignal"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	watch_signals(target.asc)

	target.asc.ability_runtime.try_activate(spec.handle)
	assert_signal_not_emitted(target.asc, "ability_runtime_ended", "still running")

	(spec.per_actor_instance as ChannelingAbility).channel_gate.emit()
	assert_signal_emitted_with_parameters(
		target.asc,
		"ability_runtime_ended",
		[spec.handle, spec.per_actor_instance, false, GameplayAbilityTask.CancelReason.ABILITY_ENDED]
	)
#endregion


#region remove_ability() policies
func test_cancel_immediately_aborts_a_running_instance_and_drops_the_spec() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleRemoveNow"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.ability_runtime.try_activate(spec.handle)
	var instance: ChannelingAbility = spec.per_actor_instance as ChannelingAbility

	target.asc.ability_runtime.remove_ability(spec.handle)
	assert_false(instance.is_active, "aborted, not left running")
	assert_null(target.asc.ability_runtime.get_spec(spec.handle), "retired immediately")


func test_after_active_end_lets_a_running_instance_finish_first() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleRemoveAfter"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.ability_runtime.try_activate(spec.handle)
	var instance: ChannelingAbility = spec.per_actor_instance as ChannelingAbility

	target.asc.ability_runtime.remove_ability(
		spec.handle, AbilityRuntime.AbilityRemovalPolicy.AFTER_ACTIVE_END
	)
	assert_true(instance.is_active, "current execution continues")
	assert_not_null(target.asc.ability_runtime.get_spec(spec.handle), "not retired yet")

	instance.channel_gate.emit()
	assert_null(target.asc.ability_runtime.get_spec(spec.handle), "retired once active_count hit 0")


func test_remove_ability_on_end_is_the_after_active_end_convenience() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleRemoveOnEnd"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.ability_runtime.try_activate(spec.handle)

	target.asc.ability_runtime.remove_ability_on_end(spec.handle)
	assert_not_null(target.asc.ability_runtime.get_spec(spec.handle), "waits for the run to finish")

	(spec.per_actor_instance as ChannelingAbility).channel_gate.emit()
	assert_null(target.asc.ability_runtime.get_spec(spec.handle))


func test_pending_removal_blocks_a_reactivation_attempt() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecyclePending"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.ability_runtime.try_activate(spec.handle)
	target.asc.ability_runtime.remove_ability_on_end(spec.handle)

	var second: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(spec.handle)
	assert_eq(second.status, GameplayAbilityActivationResult.Status.PENDING_REMOVAL)

	(spec.per_actor_instance as ChannelingAbility).channel_gate.emit()


func test_removing_a_running_passive_does_not_let_it_restart_mid_removal() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecyclePassiveRemove"]
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_true(spec.per_actor_instance.is_active)

	target.asc.ability_runtime.remove_ability(spec.handle)
	assert_null(target.asc.ability_runtime.get_spec(spec.handle), "gone, not resurrected by its own abort")
#endregion


#region give_and_activate_once
func test_give_and_activate_once_success() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleGiveOnce"]
	var scene: PackedScene = EffectFactory.ability_scene(probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.give_and_activate_once(scene)
	assert_eq(result.status, GameplayAbilityActivationResult.Status.SUCCESS)
	assert_not_null(target.asc.ability_runtime.get_spec(result.handle), "still running")

	(result.instance as ChannelingAbility).channel_gate.emit()
	assert_null(target.asc.ability_runtime.get_spec(result.handle), "retired once it ended")


func test_give_and_activate_once_failure_leaves_no_spec_behind() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecycleGiveOnceFails")
	probe.activation_blocked_query = _query([BLOCKED])
	target.asc.add_tag(BLOCKED)
	var scene: PackedScene = EffectFactory.ability_scene(probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.give_and_activate_once(scene)
	assert_ne(result.status, GameplayAbilityActivationResult.Status.SUCCESS)
	assert_null(target.asc.ability_runtime.get_spec(result.handle), "never started, never left granted")


func test_give_and_activate_once_cannot_be_activated_a_second_time() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleGiveOnceTwice"]
	var scene: PackedScene = EffectFactory.ability_scene(probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.give_and_activate_once(scene)
	var second: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(result.handle)
	assert_eq(second.status, GameplayAbilityActivationResult.Status.PENDING_REMOVAL)

	(result.instance as ChannelingAbility).channel_gate.emit()


func test_give_and_activate_once_per_execution_runs_only_that_one_execution() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleGiveOncePerExecution"]
	probe.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION
	var scene: PackedScene = EffectFactory.ability_scene(probe)

	var result: GameplayAbilityActivationResult = target.asc.ability_runtime.give_and_activate_once(scene)
	var spec: GameplayAbilitySpec = target.asc.ability_runtime.get_spec(result.handle)
	assert_eq(spec.active_instances.size(), 1)

	var second: GameplayAbilityActivationResult = target.asc.ability_runtime.try_activate(result.handle)
	assert_eq(second.status, GameplayAbilityActivationResult.Status.PENDING_REMOVAL, "no second execution")
	assert_eq(spec.active_instances.size(), 1, "still just the one")

	(result.instance as ChannelingAbility).channel_gate.emit()
#endregion


#region Cleanup and effect-granted removal
func test_cleanup_retires_a_pending_removal_spec_along_with_everything_else() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleCleanupPending"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.ability_runtime.try_activate(spec.handle)
	target.asc.ability_runtime.remove_ability_on_end(spec.handle)

	target.asc.cleanup()
	assert_false(is_instance_valid(spec.per_actor_instance) and spec.per_actor_instance.is_active)


func test_effect_removal_still_defers_a_grant_marked_remove_on_active_end() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.LifecycleEffectGrantRemoval"]
	var scene: PackedScene = EffectFactory.ability_scene(probe)
	var effect: GameplayEffect = EffectFactory.granting_ability(
		EffectFactory.infinite([]), scene, GameplayEffectAbilityGrant.RemovalPolicy.REMOVE_ON_ACTIVE_END
	)

	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, effect)
	var handle: GameplayAbilityHandle = active.granted_ability_handles[0]
	target.asc.ability_runtime.try_activate(handle)
	var instance: ChannelingAbility = target.asc.ability_runtime.get_spec(handle).per_actor_instance as ChannelingAbility

	target.asc.remove_active_effect(active)
	assert_true(instance.is_active, "current execution continues past the effect's own removal")
	assert_not_null(target.asc.ability_runtime.get_spec(handle))

	instance.channel_gate.emit()
	assert_null(target.asc.ability_runtime.get_spec(handle), "retired once the execution ended")


## Cleanup owns four things - effects, abilities, tags and contributions - and
## its "already clean, say nothing" shortcut asked only about effects.
##
## The flag behind it is lowered when an effect is applied and nowhere else, so
## an ASC cleaned up once and then given an ability had a flag saying clean and
## no effects to contradict it. The second cleanup returned before aborting
## anything: the ability kept running, its tasks were never cancelled, and the
## spec registry was never emptied. Reusing a component - pooling an actor, or
## simply tearing one down twice - is all it takes.
func test_a_second_cleanup_still_stops_an_ability_granted_since_the_first() -> void:
	target.asc.cleanup()

	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.AfterCleanup"]
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_true(spec.per_actor_instance.is_active, "granted and running after the first cleanup")

	target.asc.cleanup()

	assert_false(
		is_instance_valid(spec.per_actor_instance) and spec.per_actor_instance.is_active,
		"the second cleanup stopped it"
	)
	assert_true(target.asc.ability_runtime.specs().is_empty(), "and emptied the registry")
#endregion
#region Grant refusals
## Every AbilityGrantValidationResult.Status but OK, none of which any test
## named. Each is a path `prepare_ability_grant()` takes and then has to clean
## up after itself: the suite fails on a single orphan node, so these also
## prove the instance it made was freed rather than leaked.
func _plain_scene() -> PackedScene:
	var node: Node = Node.new()
	node.name = "NotAnAbility"
	var scene: PackedScene = PackedScene.new()
	assert_eq(scene.pack(node), OK, "packing the stand-in root")
	node.free()
	return scene


func test_a_missing_scene_is_refused_by_name() -> void:
	var prepared: PreparedAbilityGrant = target.asc.ability_runtime.prepare_ability_grant(
		null, 1.0, -1, null
	)
	assert_eq(prepared.validation.status, AbilityGrantValidationResult.Status.SCENE_MISSING)
	assert_false(prepared.validation.is_ok())
	assert_null(prepared.probe, "nothing was instantiated to clean up")

	assert_false(target.asc.ability_runtime.give_ability(null).is_valid())
	assert_eq(target.asc.ability_runtime.specs().size(), 0, "and nothing was registered")


func test_a_scene_whose_root_is_not_an_ability_is_refused_and_freed() -> void:
	var prepared: PreparedAbilityGrant = target.asc.ability_runtime.prepare_ability_grant(
		_plain_scene(), 1.0, -1, null
	)
	assert_eq(
		prepared.validation.status,
		AbilityGrantValidationResult.Status.ROOT_NOT_GAMEPLAY_ABILITY
	)
	# The instance it made is freed on this path, not handed back - so there is
	# nothing for discard_prepared_grant() to release, and no orphan either.
	assert_null(prepared.probe)


func test_a_passive_that_asks_for_per_execution_is_refused_and_freed() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LifecyclePassivePerExecution")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	probe.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION

	var prepared: PreparedAbilityGrant = target.asc.ability_runtime.prepare_ability_grant(
		EffectFactory.ability_scene(probe), 1.0, -1, null
	)
	assert_eq(
		prepared.validation.status, AbilityGrantValidationResult.Status.INVALID_DEFINITION,
		"a continuous state has no stable meaning as several per-execution instances"
	)
	assert_null(prepared.probe)


## `give_ability()` discards whatever a refused preparation made, and
## `discard_prepared_grant()` is idempotent - so calling it again after the
## refusal has already been handled must not double-free.
func test_discarding_a_refused_preparation_twice_is_safe() -> void:
	var prepared: PreparedAbilityGrant = target.asc.ability_runtime.prepare_ability_grant(
		_plain_scene(), 1.0, -1, null
	)
	target.asc.ability_runtime.discard_prepared_grant(prepared)
	target.asc.ability_runtime.discard_prepared_grant(prepared)
	assert_true(prepared.consumed)
#endregion
