## Firing one effect at several targets, and being told what became of each.
##
## A count of successes cannot distinguish the three ways a target drops out. A
## scene wired without an ability system is a bug in the scene; a target that
## refused the effect is gameplay working; two colliders that turn out to be one
## actor is neither, and silently applying twice there would double every area
## effect for anything with more than one hitbox.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Route = preload("res://test/fixtures/targeting_probe_ability.gd")

const TOLERANCE: float = 0.0001
const PROBE_TAG: StringName = &"Ability.Probe"
const ROUTE_TAG: StringName = &"Ability.Route"
const IMMUNE: StringName = &"State.Immune"
const COOLDOWN_TAG: StringName = &"Cooldown.Route"
const CONFIRMED: StringName = &"Event.Hit.Confirmed"
const HEALTH: StringName = &"health"
const MANA: StringName = &"mana"
const DAMAGE: float = -10.0
const COST: float = -20.0
const START_MANA: float = 50.0
const COOLDOWN_SECONDS: float = 5.0
const FULL_HEALTH: float = 100.0
const HURT_HEALTH: float = 40.0

var caster: ASCFixture = null
var ability: ProbeAbility = null

## The source the target reported for the effect it received.
var seen_source: AbilitySystemComponent = null


func before_each() -> void:
	caster = Fixture.create("Caster")
	add_child_autofree(caster.owner)
	ability = Probe.build(PROBE_TAG)
	caster.asc.grant_ability(ability)
	seen_source = null


func after_each() -> void:
	caster = null
	ability = null


#region Builders
## A target actor: a plain node with an ability system beside its colliders.
func _victim(actor_name: String) -> ASCFixture:
	var victim: ASCFixture = Fixture.create(actor_name)
	add_child_autofree(victim.owner)
	return victim


func _collider(parent: Node, collider_name: String) -> Node:
	var collider: Node = Node.new()
	collider.name = collider_name
	parent.add_child(collider)
	return collider


func _targets(nodes: Array[Node]) -> GameplayAbilityTargetData:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_overlap(nodes)
	return data


func _damage() -> GameplayEffect:
	return Factory.instant([Factory.add(HEALTH, DAMAGE)])


func _on_effect_received(source_asc: AbilitySystemComponent, _spec: GameplayEffectSpec) -> void:
	seen_source = source_asc
#endregion


#region Counting honestly
func test_unusable_arguments_still_answer_with_a_result() -> void:
	var empty: GameplayAbilityTargetData = GameplayAbilityTargetData.new()

	var no_effect: GameplayTargetApplicationResult = ability.apply_effect_to_targets(null, empty)
	assert_eq(no_effect.attempted_targets, 0, "nothing was attempted")
	assert_eq(no_effect.applied_count(), 0, "and nothing applied")

	var no_data: GameplayTargetApplicationResult = ability.apply_effect_to_targets(_damage(), null)
	assert_eq(no_data.applied_count(), 0, "a caller never has to check for null")


func test_a_target_without_an_ability_system_is_named_rather_than_missed() -> void:
	var scenery: Node = Node.new()
	scenery.name = "Crate"
	add_child_autofree(scenery)
	var nodes: Array[Node] = [scenery]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 1, "it was attempted")
	assert_eq(result.applied_count(), 0, "and nothing was applied")
	assert_eq(result.missing_asc_targets.size(), 1, "reported as a wiring problem")
	assert_eq(result.rejected_targets.size(), 0, "not as a refusal, which it was not")


## Two hitboxes on one actor are one target.
func test_two_colliders_on_one_actor_are_charged_once() -> void:
	var victim: ASCFixture = _victim("Victim")
	victim.set_base(HEALTH, 100.0)
	var nodes: Array[Node] = [
		_collider(victim.owner, "Torso"), _collider(victim.owner, "Head")
	]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 2, "two colliders were offered")
	assert_eq(result.applied_count(), 1, "and resolved to one actor")
	assert_almost_eq(victim.base_of(HEALTH), 90.0, TOLERANCE, "hit once, not twice")


func test_a_target_that_refuses_is_reported_as_refused() -> void:
	var victim: ASCFixture = _victim("Immune")
	victim.set_base(HEALTH, 100.0)
	victim.asc.add_tag(IMMUNE)
	var blocked: GameplayEffect = Factory.blocked_by(_damage(), [IMMUNE])
	var nodes: Array[Node] = [victim.owner]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		blocked, _targets(nodes)
	)

	assert_eq(result.rejected_targets.size(), 1, "the target refused it")
	assert_eq(result.missing_asc_targets.size(), 0, "and it was certainly found")
	assert_eq(result.applied_count(), 0, "so nothing landed")
	assert_almost_eq(victim.base_of(HEALTH), 100.0, TOLERANCE, "and it took no damage")
#endregion


#region Several targets at once
func test_each_target_is_evaluated_against_its_own_state() -> void:
	var healthy: ASCFixture = _victim("Healthy")
	var hurt: ASCFixture = _victim("Hurt")
	healthy.set_base(HEALTH, 100.0)
	hurt.set_base(HEALTH, 40.0)
	var nodes: Array[Node] = [healthy.owner, hurt.owner]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.applied_count(), 2, "both were reached")
	assert_almost_eq(healthy.base_of(HEALTH), 90.0, TOLERANCE, "the first took its own damage")
	assert_almost_eq(hurt.base_of(HEALTH), 30.0, TOLERANCE, "and the second took its own")


## The source of an effect is found by the same search as any other component.
##
## The ASC used to answer this with a lookup of its own: a direct child under
## the conventional name, unchecked. A node merely called that would have been
## handed back as the source, and a caster whose component sits beside a
## collider would not have been found at all.
func test_the_source_of_an_effect_is_found_by_the_same_search() -> void:
	var victim: ASCFixture = _victim("Victim")
	victim.set_base(HEALTH, 100.0)
	victim.asc.effect_received.connect(_on_effect_received)
	var nodes: Array[Node] = [victim.owner]

	ability.apply_effect_to_targets(_damage(), _targets(nodes))

	assert_eq(seen_source, caster.asc, "the source resolved to the caster's own component")


func test_the_result_separates_the_three_ways_a_target_drops_out() -> void:
	var reached: ASCFixture = _victim("Reached")
	var refusing: ASCFixture = _victim("Refusing")
	reached.set_base(HEALTH, 100.0)
	refusing.asc.add_tag(IMMUNE)
	var scenery: Node = Node.new()
	scenery.name = "Crate"
	add_child_autofree(scenery)
	var nodes: Array[Node] = [reached.owner, refusing.owner, scenery]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		Factory.blocked_by(_damage(), [IMMUNE]), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 3, "three were offered")
	assert_eq(result.applied_targets.size(), 1, "one was reached and accepted")
	assert_eq(result.rejected_targets.size(), 1, "one was reached and refused")
	assert_eq(result.missing_asc_targets.size(), 1, "and one could not be reached at all")
	assert_eq(result.applied_count(), 1, "the handles agree with the accepted count")
#endregion


#region The whole route
func _live_tasks() -> int:
	return caster.asc.ability_runtime.tasks.active_count()


func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	return event


## An ability that pays, waits for targets, fires, and waits to be told it
## landed - suspending twice, which is where ownership mistakes surface.
func _route_ability() -> TargetingProbeAbility:
	caster.set_base(MANA, START_MANA)
	var probe: TargetingProbeAbility = Route.build(ROUTE_TAG)
	var no_modifiers: Array[GameplayEffectModifier] = []
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.target_attribute = MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = -COST
	probe.costs = [cost]
	probe.cooldown_effect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)
	probe.payload = _damage()
	probe.confirmation_tag = CONFIRMED
	caster.asc.grant_ability(probe)
	return probe


## The route, walked once, with every joint asserted where it happens.
##
## Split into separate tests each piece would still pass while the seams
## between them failed, which is the only thing this file exists to catch.
func test_the_whole_route_runs_from_activation_to_confirmation() -> void:
	var probe: TargetingProbeAbility = _route_ability()
	var first: ASCFixture = _victim("First")
	var second: ASCFixture = _victim("Second")
	first.set_base(HEALTH, FULL_HEALTH)
	second.set_base(HEALTH, HURT_HEALTH)

	assert_true(caster.asc.can_activate_ability(probe), "the gate lets it through")
	probe.try_activate()

	assert_true(probe.is_active, "and it suspends waiting for its targets")
	assert_almost_eq(
		caster.base_of(MANA), START_MANA + COST, TOLERANCE, "having paid exactly once"
	)
	assert_true(caster.asc.has_tag(COOLDOWN_TAG), "and started its cooldown")
	assert_eq(_live_tasks(), 1, "with one wait open")

	var nodes: Array[Node] = [first.owner, second.owner]
	probe.submit_target_data(_targets(nodes))

	assert_true(probe.reached_targets, "the targets arrived through the task")
	assert_eq(probe.application.applied_count(), 2, "and both were reached")
	assert_almost_eq(
		first.base_of(HEALTH), FULL_HEALTH + DAMAGE, TOLERANCE, "each hit its own state"
	)
	assert_almost_eq(
		second.base_of(HEALTH), HURT_HEALTH + DAMAGE, TOLERANCE, "and the other its own"
	)
	assert_true(probe.is_active, "and it is still waiting to be told it landed")

	caster.asc.send_gameplay_event(_event(CONFIRMED))

	assert_true(probe.finished_successfully, "the confirmation carried it to the end")
	assert_false(probe.is_active, "the ability closed")
	assert_eq(_live_tasks(), 0, "and nothing is left waiting")


## Two colliders on one actor are one target on the real route too.
func test_two_colliders_on_one_actor_are_hit_once_along_the_route() -> void:
	var probe: TargetingProbeAbility = _route_ability()
	var victim: ASCFixture = _victim("Twice")
	victim.set_base(HEALTH, FULL_HEALTH)
	var nodes: Array[Node] = [
		_collider(victim.owner, "Torso"), _collider(victim.owner, "Head")
	]

	probe.try_activate()
	probe.submit_target_data(_targets(nodes))

	assert_almost_eq(
		victim.base_of(HEALTH), FULL_HEALTH + DAMAGE, TOLERANCE, "one actor, one hit"
	)


func test_a_cast_cancelled_before_its_targets_arrive_fires_nothing() -> void:
	var probe: TargetingProbeAbility = _route_ability()
	var victim: ASCFixture = _victim("Untouched")
	victim.set_base(HEALTH, FULL_HEALTH)
	probe.try_activate()

	probe.abort_ability()

	assert_false(probe.reached_targets, "it never got its targets")
	assert_null(probe.application, "so it fired nothing")
	assert_almost_eq(victim.base_of(HEALTH), FULL_HEALTH, TOLERANCE, "and nobody was hit")
	assert_eq(_live_tasks(), 0, "and the wait was closed rather than left open")


## A suspended cast whose ability is taken away must be closed, not left
## waiting on a task nobody owns any more.
func test_removing_the_ability_mid_cast_leaves_nothing_waiting() -> void:
	var probe: TargetingProbeAbility = _route_ability()
	probe.try_activate()
	watch_signals(probe)

	caster.asc.remove_ability(probe)

	assert_signal_emit_count(probe, "ability_ended", 1, "closed exactly once")
	assert_eq(_live_tasks(), 0, "and its wait went with it")


func test_tearing_down_the_asc_mid_cast_leaves_nothing_behind() -> void:
	var probe: TargetingProbeAbility = _route_ability()
	probe.try_activate()

	caster.asc.cleanup()

	assert_eq(_live_tasks(), 0, "no task survived the teardown")
	assert_eq(
		caster.asc.get_active_effects().size(), 0, "and neither did the cooldown it had started"
	)
	assert_false(probe.is_active, "and the cast is closed")
#endregion
