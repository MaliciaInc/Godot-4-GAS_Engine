## Fase 3 closure: the five vertical scenarios the phase document's own
## "Final regression suite" section names, plus its seeded stress sequence.
##
## Every feature these scenarios touch already has its own unit suite - this
## file exists only to prove the SEAMS between features hold, the same
## reason test_ability_target_application.gd's own "whole route" test exists.
## Split into single-feature tests, each would still pass while the joins
## between them failed.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Slot = preload("res://test/fixtures/fake_gloot_slot.gd")
const Item = preload("res://test/fixtures/fake_gloot_item.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = TestAttributeSet.ATTACK
const DEFENSE: StringName = TestAttributeSet.DEFENSE
const HEALTH: StringName = TestAttributeSet.HEALTH
const MANA: StringName = TestAttributeSet.MANA
const MAX_MANA: StringName = TestAttributeSet.MAX_MANA


func after_each() -> void:
	restore_error_reporting()


func expect_engine_error() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING


func restore_error_reporting() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE


func _victim(actor_name: String) -> ASCFixture:
	var victim: ASCFixture = Fixture.create(actor_name)
	add_child_autofree(victim.owner)
	return victim


#region Scenario A - RPG cast
## Damage = SetByCaller base + Source.attack (SNAPSHOT) - Target.defense
## (LIVE), clamped so this scenario is always damage, never a heal.
##
## The two capture definitions are instance fields, built once in _init() and
## reused by both required_captures() and execute() - GameplayEffectSpec
## keys its captured-value cache by the definition object's own identity, so
## a fresh Resource built again at read time would simply never match what
## prepare_captures() snapshotted under the other instance.
class FireballExecution extends GameplayExecutionCalculation:
	var power_capture: GameplayAttributeCaptureDefinition = null
	var defense_capture: GameplayAttributeCaptureDefinition = null

	func _init() -> void:
		power_capture = GameplayAttributeCaptureDefinition.new()
		power_capture.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
		power_capture.attribute_name = ATTACK
		power_capture.value = GameplayAttributeCaptureDefinition.Value.CURRENT
		power_capture.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

		defense_capture = GameplayAttributeCaptureDefinition.new()
		defense_capture.actor = GameplayAttributeCaptureDefinition.Actor.TARGET
		defense_capture.attribute_name = DEFENSE
		defense_capture.value = GameplayAttributeCaptureDefinition.Value.CURRENT
		defense_capture.policy = GameplayAttributeCaptureDefinition.Policy.LIVE

	func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
		return [power_capture, defense_capture]

	func execute(spec: GameplayEffectSpec, target_asc: AbilitySystemComponent) -> Dictionary[StringName, float]:
		var base_damage: float = spec.get_set_by_caller(&"Damage").value
		var power: float = spec.resolve_capture(power_capture, spec.source_asc, target_asc).value
		var defense: float = spec.resolve_capture(defense_capture, spec.source_asc, target_asc).value
		var delta: float = -maxf(base_damage + power - defense, 1.0)
		return {HEALTH: delta}


func test_scenario_a_rpg_cast() -> void:
	var caster: ASCFixture = _victim("Caster")
	var target: ASCFixture = _victim("Target")
	caster.set_base(MANA, 100.0)
	caster.set_base(MAX_MANA, 100.0)
	caster.set_base(ATTACK, 20.0)
	# MAX_HEALTH first - HEALTH's own base clamp ceilings at whatever
	# MAX_HEALTH.current_value already is.
	target.set_base(TestAttributeSet.MAX_HEALTH, 200.0)
	target.set_base(HEALTH, 200.0)
	target.set_base(DEFENSE, 5.0)
	target.asc.add_tag(&"Status.Targetable")

	var manager: CueManagerScript = caster.asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	var cue_instance: GameplayCueNotify = GameplayCueNotify.new()
	var cue_scene: PackedScene = PackedScene.new()
	cue_scene.pack(cue_instance)
	cue_instance.free()
	manager._cue_scenes[&"Cue.Fireball.Impact"] = cue_scene
	manager._pool[&"Cue.Fireball.Impact"] = GameplayCuePoolBucket.new()
	var pooled_before: int = manager.get_pooled_count(&"Cue.Fireball.Impact")

	var payload: GameplayEffect = Factory.instant([])
	payload.executions = [FireballExecution.new()]
	Factory.with_application_cues(payload, [&"Cue.Fireball.Impact"])

	var fireball: FireballAbility = FireballAbility.new()
	fireball.name = "Ability_Fireball"
	fireball.ability_tags = [&"Ability.Fireball"]
	fireball.target_required_query = _all_tag_query([&"Status.Targetable"])
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.PERCENT_OF_CURRENT
	cost.target_attribute = MANA
	cost.reference_attribute = MAX_MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = 0.1
	fireball.costs = [cost]
	fireball.cooldown_effect = Factory.granting(
		Factory.duration([], 3.0), [&"Cooldown.Fireball"]
	)

	var spec: GameplayAbilitySpec = AbilityFactory.give(caster.asc, fireball)
	# payload/damage/confirmation_tag are not @export, so they never survive
	# packing - set on the granted instance, the same rule
	# TestAbilityFactory's own doc comment states.
	var instance: FireballAbility = spec.per_actor_instance as FireballAbility
	instance.payload = payload
	instance.damage = 15.0
	instance.confirmation_tag = &"Event.Fireball.Confirmed"

	instance.try_activate()
	assert_almost_eq(caster.base_of(MANA), 90.0, TOLERANCE, "10% of current mana, paid once")
	assert_true(caster.asc.has_tag(&"Cooldown.Fireball"), "cooldown started with the commit")

	instance.submit_target_data(_targets([target.owner]))
	# damage = -(15 + 20 - 5) = -30
	assert_almost_eq(target.base_of(HEALTH), 170.0, TOLERANCE, "SetByCaller + snapshot power - live defense")
	# A one-shot cue pools itself on a real SceneTreeTimer (auto_destroy), not
	# synchronously - get_pooled_count() would still read pooled_before here
	# with no engine frame having actually elapsed. Parented-under-target is
	# what happens synchronously, inside _resolve_and_parent(), and is proof
	# enough that execute_cue() really ran.
	var impact_cue: Node = null
	for child: Node in target.owner.get_children():
		if child is GameplayCueNotify:
			impact_cue = child
	assert_not_null(impact_cue, "the impact cue instantiated and parented under the target")
	assert_eq(pooled_before, manager.get_pooled_count(&"Cue.Fireball.Impact"), "not pooled yet - still playing")

	caster.asc.send_gameplay_event(_event(&"Event.Fireball.Confirmed"))
	assert_true(instance.finished_successfully)

	manager._cue_scenes.erase(&"Cue.Fireball.Impact")
	manager._pool.erase(&"Cue.Fireball.Impact")
#endregion


#region Scenario B - Stack, inhibit, immunity
func test_scenario_b_stack_inhibit_immunity() -> void:
	var target: ASCFixture = _victim("Poisoned")
	target.set_base(HEALTH, 200.0)

	var poison: GameplayEffect = Factory.stacked(
		Factory.granting(
			Factory.with_ongoing_requirement(
				Factory.infinite([Factory.add(ATTACK, -1.0)]), [&"Status.Vulnerable"]
			),
			[&"Status.Poisoned"]
		),
		GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 3
	)
	target.asc.add_tag(&"Status.Vulnerable")
	var active: ActiveGameplayEffect = Factory.apply(target.asc, poison)
	Factory.apply(target.asc, poison)
	Factory.apply(target.asc, poison)
	assert_eq(active.stack_count, 3, "stack limit reached")
	assert_almost_eq(target.current_of(ATTACK), 9.0, TOLERANCE, "10 - 3 while active")

	target.asc.remove_tag(&"Status.Vulnerable")
	assert_true(active.inhibited, "ongoing requirement lost")
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE, "contribution detached while inhibited")
	assert_false(target.asc.has_tag(&"Status.Poisoned"), "the granted tag detaches too, along with the contribution")
	assert_true(active.granted_tags.has(&"Status.Poisoned"), "but the receipt itself is kept, ready to reattach")

	target.asc.add_tag(&"Status.Vulnerable")
	assert_false(active.inhibited, "requirement satisfied again")
	assert_almost_eq(target.current_of(ATTACK), 9.0, TOLERANCE, "reattached at the same stack count")

	var immunity: GameplayEffect = Factory.immune_to(
		Factory.infinite([]), _effect_query_for_tags([&"Status.Poisoned"])
	)
	Factory.apply(target.asc, immunity)
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, poison)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE, "a new poison stack is refused")
	assert_eq(active.stack_count, 3, "the existing stack is untouched by the refusal")
	assert_almost_eq(target.current_of(ATTACK), 9.0, TOLERANCE, "still exactly what it was")
#endregion


#region Scenario C - Equipment/ability lifecycle
func test_scenario_c_equipment_ability_lifecycle() -> void:
	var wearer: ASCFixture = _victim("Wearer")
	wearer.set_base(ATTACK, 10.0)

	var slot: FakeGlootSlot = Slot.build()
	add_child_autofree(slot)
	var bridge: GlootGasBridge = GlootGasBridge.new()
	add_child_autofree(bridge)

	var sword_ability: StaysActiveAbility = StaysActiveAbility.new()
	sword_ability.ability_tags = [&"Ability.Cleave"]
	sword_ability.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	sword_ability.activation_owned_tags = [&"State.Cleaving"]
	var ability_scene: PackedScene = PackedScene.new()
	ability_scene.pack(sword_ability)
	sword_ability.free()

	var grant: GlootGasEquipmentGrant = GlootGasEquipmentGrant.new()
	grant.prototype_id = &"item.sword"
	grant.abilities = [ability_scene]
	grant.passive_effects = [Factory.infinite([Factory.add(ATTACK, 10.0)])]
	grant.direct_tags = [&"State.Sworn"]
	var catalog: GlootGasEquipmentCatalog = GlootGasEquipmentCatalog.new()
	catalog.grants = [grant]
	assert_true(bridge.bind(slot, wearer.asc, catalog))

	slot.equip(Item.build(&"item.sword"))
	assert_almost_eq(wearer.current_of(ATTACK), 20.0, TOLERANCE, "the passive buff landed")
	assert_true(wearer.asc.has_tag(&"State.Sworn"))
	assert_eq(wearer.asc.ability_runtime.specs().size(), 1, "the ability was granted")
	assert_true(wearer.asc.has_tag(&"State.Cleaving"), "the passive already activated once, tags owned")

	slot.clear()
	assert_almost_eq(wearer.current_of(ATTACK), 10.0, TOLERANCE, "the passive buff is gone")
	assert_false(wearer.asc.has_tag(&"State.Sworn"))
	assert_eq(wearer.asc.ability_runtime.specs().size(), 0, "the ability was removed, not merely deactivated")
	assert_false(wearer.asc.has_tag(&"State.Cleaving"), "activation-owned tag released with it")
	assert_eq(wearer.asc.ability_runtime.tasks.active_count(), 0, "nothing left waiting")
#endregion


#region Scenario D - Chained effects
## Reads the target's own attack, captured fresh for THIS application - the
## additional-effect child gets its own spec, so a capture resolved at the
## child's own commit is the correct way to size it, never a SetByCaller
## carried over from the parent's cast (the child spec never inherits one).
class BurstExecution extends GameplayExecutionCalculation:
	var power_capture: GameplayAttributeCaptureDefinition = null

	func _init() -> void:
		power_capture = GameplayAttributeCaptureDefinition.new()
		power_capture.actor = GameplayAttributeCaptureDefinition.Actor.TARGET
		power_capture.attribute_name = ATTACK
		power_capture.value = GameplayAttributeCaptureDefinition.Value.CURRENT
		power_capture.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

	func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
		return [power_capture]

	func execute(spec: GameplayEffectSpec, target_asc: AbilitySystemComponent) -> Dictionary[StringName, float]:
		var power: float = spec.resolve_capture(power_capture, spec.source_asc, target_asc).value
		return {HEALTH: -2.0 * power}


## post_gameplay_effect_execute fires a gameplay event - the T20 hook - which
## an ON_GAMEPLAY_EVENT passive then reacts to through the normal GAS event
## route. Only this test's own AttributeSet does this, never the shared
## TestAttributeSet every other suite in the project also uses.
class EventEmittingAttributeSet extends TestAttributeSet:
	func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
		if data.attribute_name != HEALTH or data.target_asc == null:
			return
		var event: GameplayEventData = GameplayEventData.new()
		event.event_tag = &"Event.Hit.Taken"
		data.target_asc.send_gameplay_event(event)


func test_scenario_d_chained_effects_and_post_execute_event() -> void:
	var target: ASCFixture = Fixture.create("Shielded", EventEmittingAttributeSet)
	add_child_autofree(target.owner)
	target.set_base(HEALTH, 100.0)
	target.set_base(ATTACK, 20.0)

	var reactor: ProbeAbility = Probe.build(&"Ability.Reactor")
	reactor.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	reactor.gameplay_event_triggers = [GameplayAbilityEventTrigger.for_tag(&"Event.Hit.Taken")]
	var reactor_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, reactor)
	var reactor_instance: ProbeAbility = reactor_spec.per_actor_instance as ProbeAbility

	var burst: GameplayEffect = Factory.instant([])
	burst.executions = [BurstExecution.new()]
	var shield: GameplayEffect = Factory.with_additional_effects(
		Factory.duration([], 0.1), [], [Factory.conditional_effect(burst)]
	)

	watch_signals(target.asc)
	Factory.apply(target.asc, shield)
	target.asc.scheduler.advance_time(1.0)

	assert_eq(target.asc.get_active_effects().size(), 0, "the shield expired naturally")
	assert_almost_eq(target.base_of(HEALTH), 60.0, TOLERANCE, "burst captured the target's own attack: -2 * 20")
	assert_signal_emitted(target.asc, "gameplay_event_received", "post_gameplay_effect_execute fired the event")
	assert_eq(reactor_instance.activations, 1, "the passive reacted through the normal event route")
#endregion


#region Scenario E - Stress
const STRESS_STEPS: int = 200


func test_scenario_e_stress_sequence_holds_every_invariant() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260831
	var target: ASCFixture = _victim("Stressed")
	target.set_base(HEALTH, 1000.0)
	target.set_base(ATTACK, 10.0)

	var burst_stack: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 1.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 5
	)
	var periodic: GameplayEffect = Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 0.5)
	var active_periodic: Array[ActiveGameplayEffect] = []

	for step: int in STRESS_STEPS:
		var roll: int = rng.randi_range(0, 3)
		match roll:
			0:
				Factory.apply(target.asc, burst_stack)
			1:
				target.asc.remove_effects_with_tag(&"__never_granted__")
			2:
				target.asc.scheduler.advance_time(rng.randf_range(0.0, 1.0))
			3:
				var applied: ActiveGameplayEffect = Factory.apply(target.asc, periodic)
				if applied != null:
					active_periodic.append(applied)

		_assert_invariants(target.asc)
#endregion


#region Shared invariant checks
func _assert_invariants(asc: AbilitySystemComponent) -> void:
	for attribute_name: StringName in asc.attributes.all_attribute_names():
		assert_true(is_finite(asc.get_attribute_base(attribute_name)), "base stayed finite")
		assert_true(is_finite(asc.get_attribute_current(attribute_name)), "current stayed finite")

	var active: Array[ActiveGameplayEffect] = asc.effects.active_effects()
	var seen_orders: Array[int] = []
	for effect: ActiveGameplayEffect in active:
		assert_false(seen_orders.has(effect.application_order), "one active effect handle maps exactly once")
		seen_orders.append(effect.application_order)
		if not effect.state_attached:
			continue
		for contribution: AttributeModifierContribution in effect.contributed_modifiers:
			assert_true(
				asc.attributes.contributions_for(contribution.attribute_name).has(contribution),
				"every attached contribution belongs to an active, uninhibited effect"
			)

	for tag: StringName in asc.tags.active_tags():
		assert_true(asc.tags.count(tag) >= 0, "tag counts never go negative")
#endregion


#region Helpers
func _targets(nodes: Array[Node]) -> GameplayAbilityTargetData:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_overlap(nodes)
	return data


func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	return event


func _all_tag_query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


func _effect_query_for_tags(tags: Array[StringName]) -> GameplayEffectQuery:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.granted_tags = _all_tag_query(tags)
	return query
#endregion
