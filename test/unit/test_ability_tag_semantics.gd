## Task 15's complete ability tag semantics: identity, activation
## required/blocked queries, activation-owned tags, cancel/block queries -
## both an ability's own and an effect's - and target requirements.
##
## @meta_license: MIT
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const FIRE: StringName = &"Ability.Fire"
const ICE: StringName = &"Ability.Ice"
const DAMAGE_FIRE: StringName = &"Damage.Fire"
const DAMAGE_FIRESTORM: StringName = &"Damage.Firestorm"
const STUNNED: StringName = &"Status.Stunned"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


func _tag_query(tags: Array[StringName], op: GameplayTagQueryExpression.Operator = GameplayTagQueryExpression.Operator.ALL) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = op
	expression.tags = tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


#region Identity and effective tags
func test_an_ability_can_carry_multiple_identity_tags() -> void:
	var probe: ProbeAbility = ProbeAbility.new()
	probe.ability_tags = [FIRE, ICE]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var effective: Array[StringName] = AbilityRuntime.effective_ability_tags(spec)
	assert_true(effective.has(FIRE))
	assert_true(effective.has(ICE))


func test_effective_tags_include_the_specs_own_dynamic_tags() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	spec.dynamic_tags.append(&"Status.Empowered")

	var effective: Array[StringName] = AbilityRuntime.effective_ability_tags(spec)
	assert_true(effective.has(FIRE))
	assert_true(effective.has(&"Status.Empowered"))
#endregion


#region Activation required/blocked queries
func test_activation_required_query_blocks_until_satisfied() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	probe.activation_required_query = _tag_query([&"Status.Channeling"])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.MISSING_TAG)
	target.asc.add_tag(&"Status.Channeling")
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.NONE)


func test_activation_blocked_query_blocks_while_it_matches() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	probe.activation_blocked_query = _tag_query([STUNNED], GameplayTagQueryExpression.Operator.ANY)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.NONE)
	target.asc.add_tag(STUNNED)
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.BLOCKED_TAG)
#endregion


#region Cancel/block between abilities
func test_an_active_ability_blocks_another_matching_its_block_query() -> void:
	var blocker: ChannelingAbility = ChannelingAbility.new()
	blocker.ability_tags = [ICE]
	blocker.block_abilities_query = _tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY)
	var blocker_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, blocker)

	var fire_probe: ProbeAbility = ProbeAbility.build(FIRE)
	var fire_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, fire_probe)

	assert_eq(target.asc.ability_runtime.activation_error(fire_spec), AbilityRuntime.ActivationError.NONE)
	blocker_spec.per_actor_instance.try_activate()
	assert_eq(
		target.asc.ability_runtime.activation_error(fire_spec), AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY
	)
	(blocker_spec.per_actor_instance as ChannelingAbility).channel_gate.emit()


func test_activating_an_ability_cancels_others_matching_its_cancel_query() -> void:
	var channeling: ChannelingAbility = ChannelingAbility.new()
	channeling.ability_tags = [ICE]
	var channeling_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, channeling)
	channeling_spec.per_actor_instance.try_activate()
	assert_true(channeling_spec.per_actor_instance.is_active)

	var canceller: ProbeAbility = ProbeAbility.build(FIRE)
	canceller.cancel_abilities_query = _tag_query([ICE], GameplayTagQueryExpression.Operator.ANY)
	var canceller_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, canceller)

	canceller_spec.per_actor_instance.try_activate()
	assert_false(channeling_spec.per_actor_instance.is_active, "cancelled the moment the cancelling ability started")


func test_an_ability_does_not_cancel_itself_by_default() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [FIRE]
	probe.cancel_abilities_query = _tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	spec.per_actor_instance.try_activate()
	assert_true(spec.per_actor_instance.is_active, "would match its own tag, but allow_self_cancel defaults false")
	(spec.per_actor_instance as ChannelingAbility).channel_gate.emit()
#endregion


#region Activation-owned tags with PER_EXECUTION
func test_activation_owned_tags_are_a_single_ref_across_per_execution_instances() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [FIRE]
	probe.activation_owned_tags = [&"Status.Casting"]
	probe.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var a: ChannelingAbility = target.asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	a.try_activate()
	assert_true(target.asc.has_tag(&"Status.Casting"))

	var b: ChannelingAbility = target.asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	b.try_activate()
	var c: ChannelingAbility = target.asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	c.try_activate()
	assert_eq(spec.active_count, 3)
	assert_true(target.asc.has_tag(&"Status.Casting"), "still just the one ref")

	a.channel_gate.emit()
	b.channel_gate.emit()
	assert_true(target.asc.has_tag(&"Status.Casting"), "one execution still running")

	c.channel_gate.emit()
	assert_false(target.asc.has_tag(&"Status.Casting"), "the last one to end drops it")
#endregion


#region Effect components
func test_a_block_ability_tags_effect_blocks_matching_activation() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var block_component: GameplayEffectBlockAbilityTagsComponent = GameplayEffectBlockAbilityTagsComponent.new()
	block_component.query = _tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY)
	var blocking_effect: GameplayEffect = EffectFactory.infinite([])
	blocking_effect.components.append(block_component)

	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.NONE)
	EffectFactory.apply(target.asc, blocking_effect)
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY)


func test_an_inhibited_block_ability_tags_effect_stops_blocking() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	var block_component: GameplayEffectBlockAbilityTagsComponent = GameplayEffectBlockAbilityTagsComponent.new()
	block_component.query = _tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY)
	var blocking_effect: GameplayEffect = EffectFactory.with_ongoing_requirement(
		EffectFactory.infinite([]), [&"Status.Blessed"]
	)
	blocking_effect.components.append(block_component)
	EffectFactory.apply(target.asc, blocking_effect)
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY)

	target.asc.remove_tag(&"Status.Blessed")
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.NONE, "inhibited, stopped blocking")


func test_a_cancel_ability_tags_effect_cancels_matching_active_abilities() -> void:
	var channeling: ChannelingAbility = ChannelingAbility.new()
	channeling.ability_tags = [FIRE]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, channeling)
	spec.per_actor_instance.try_activate()
	assert_true(spec.per_actor_instance.is_active)

	var cancel_component: GameplayEffectCancelAbilityTagsComponent = GameplayEffectCancelAbilityTagsComponent.new()
	cancel_component.query = _tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY)
	var cancelling_effect: GameplayEffect = EffectFactory.infinite([])
	cancelling_effect.components.append(cancel_component)

	EffectFactory.apply(target.asc, cancelling_effect)
	assert_false(spec.per_actor_instance.is_active, "cancelled the moment the effect applied")
#endregion


#region Target requirements
func test_target_required_query_is_enforced_at_effect_application() -> void:
	var source: ASCFixture = Fixture.create("Source")
	add_child_autofree(source.owner)
	var probe: TargetingProbeAbility = TargetingProbeAbility.new()
	probe.ability_tags = [FIRE]
	probe.target_required_query = _tag_query([&"Status.Flammable"])
	var spec: GameplayAbilitySpec = AbilityFactory.give(source.asc, probe)

	var target_data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	target_data.append_node(target.owner)
	var result: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		EffectFactory.infinite([]), target_data
	)
	assert_eq(result.applied_targets.size(), 0)
	assert_true(result.rejected_targets.has(target.asc))

	target.asc.add_tag(&"Status.Flammable")
	var second: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		EffectFactory.infinite([]), target_data
	)
	assert_eq(second.applied_targets.size(), 1)


func test_target_blocked_query_is_enforced_at_effect_application() -> void:
	var source: ASCFixture = Fixture.create("Source")
	add_child_autofree(source.owner)
	var probe: TargetingProbeAbility = TargetingProbeAbility.new()
	probe.ability_tags = [FIRE]
	probe.target_blocked_query = _tag_query([&"Status.FireImmune"], GameplayTagQueryExpression.Operator.ANY)
	var spec: GameplayAbilitySpec = AbilityFactory.give(source.asc, probe)

	target.asc.add_tag(&"Status.FireImmune")
	var target_data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	target_data.append_node(target.owner)
	var result: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		EffectFactory.infinite([]), target_data
	)
	assert_eq(result.applied_targets.size(), 0)
	assert_true(result.rejected_targets.has(target.asc))
#endregion


#region Hierarchical matching
func test_a_query_matches_a_more_specific_descendant_tag() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	probe.activation_blocked_query = _tag_query([&"Damage"], GameplayTagQueryExpression.Operator.ANY)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	target.asc.add_tag(DAMAGE_FIRE)
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.BLOCKED_TAG)


func test_a_query_does_not_match_a_tag_sharing_only_a_string_prefix() -> void:
	var probe: ProbeAbility = ProbeAbility.build(FIRE)
	probe.activation_blocked_query = _tag_query([DAMAGE_FIRE], GameplayTagQueryExpression.Operator.ANY)
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	target.asc.add_tag(DAMAGE_FIRESTORM)
	assert_eq(target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.NONE, "a sibling, not a descendant")
#endregion


#region Legacy convenience and signal discipline
func test_legacy_cancel_with_tags_still_cancels_by_effective_tags() -> void:
	var channeling: ChannelingAbility = ChannelingAbility.new()
	channeling.ability_tags = [FIRE]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, channeling)
	spec.per_actor_instance.try_activate()

	target.asc.cancel_abilities_with_tags([FIRE] as Array[StringName])
	assert_false(spec.per_actor_instance.is_active)


func test_cancelling_an_active_ability_emits_ability_ended_exactly_once() -> void:
	var channeling: ChannelingAbility = ChannelingAbility.new()
	channeling.ability_tags = [FIRE]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, channeling)
	var instance: ChannelingAbility = spec.per_actor_instance
	instance.try_activate()

	watch_signals(instance)
	target.asc.ability_runtime.cancel_matching_query(_tag_query([FIRE], GameplayTagQueryExpression.Operator.ANY))
	assert_signal_emit_count(instance, "ability_ended", 1)
#endregion
