## Committing an ability is a transaction: the whole price, or none of it.
##
## The price is a cost and some cooldowns, and the two can disagree. Charging
## first and then failing to start a cooldown bills a player for nothing;
## starting a cooldown and then failing to charge locks an ability that never
## went off. Both are worse than refusing, so a commit that cannot finish undoes
## what it had already done and reports what it refused on.
##
## The refusals are also a design boundary rather than defensiveness. A cost has
## to be previewable by `can_afford_cost` and reversible by adding a fixed
## amount back, and only an instant, purely additive charge is both. That is why
## a percentage cost cannot be written here at all.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const MANA: StringName = &"mana"
const OWN_COOLDOWN: StringName = &"Cooldown.Probe"
const SHARED_COOLDOWN: StringName = &"Cooldown.Shared"
const PROBE_TAG: StringName = &"Ability.Probe"
const STARTING_MANA: float = 50.0
const COST_AMOUNT: float = -20.0
const COOLDOWN_SECONDS: float = 5.0


## An ASC that refuses to apply one designated effect, and behaves normally
## otherwise.
##
## The validated contract makes both application failures unreachable through
## the engine: a cooldown carries no modifiers to fail on, and a cost nobody can
## pay is refused by `can_afford_cost` before it is ever applied. The rollback
## still has to be correct, so the refusal is injected at the seam the commit
## actually calls rather than left as untested defensive code.
class RefusingASC extends AbilitySystemComponent:
	var refused: GameplayEffect = null

	func apply_gameplay_effect(
		effect: GameplayEffect,
		source_asc: AbilitySystemComponent = null,
		effect_level: float = 1.0
	) -> ActiveGameplayEffect:
		if effect != null and effect == refused:
			return null
		return super(effect, source_asc, effect_level)


## An execution that never runs, because a cost carrying one is refused before
## anything is applied. It exists only so the executions array can be non-empty:
## the base class is abstract and cannot be instantiated directly.
class NeverRuns extends GameplayExecutionCalculation:
	func execute(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var nothing: Dictionary[StringName, float] = {}
		return nothing


var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: ProbeAbility = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	fixture.set_base(MANA, STARTING_MANA)
	ability = Probe.build(PROBE_TAG)
	asc.grant_ability(ability)


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Builders
func _cost(amount: float) -> GameplayEffect:
	return Factory.instant([Factory.add(MANA, amount)])


func _cooldown(tag: StringName) -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.duration(no_modifiers, COOLDOWN_SECONDS), [tag])


## The status of committing the ability under test, for the many cases whose
## whole claim is which refusal came back.
func _status() -> AbilityCommitResult.Status:
	return ability.commit_ability().status


## An ASC that will refuse `refused`, with an ability already granted on it.
func _caster_refusing(refused: GameplayEffect) -> ProbeAbility:
	var host: Node = Node.new()
	host.name = "Refuser"

	var refusing: RefusingASC = RefusingASC.new()
	refusing.name = "AbilitySystemComponent"
	refusing.attribute_sets = [AttributeSetScript.new()]
	refusing.share_attributes = true
	refusing.refused = refused
	host.add_child(refusing)
	add_child_autofree(host)

	var caster: ProbeAbility = Probe.build(PROBE_TAG)
	refusing.grant_ability(caster)
	return caster
#endregion


#region Success and refusal basics
func test_an_ability_with_no_cost_and_no_cooldown_commits() -> void:
	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "having nothing to pay is not a reason to refuse")
	assert_eq(result.applied_cooldowns.size(), 0, "no cooldown was declared")
	assert_null(result.applied_cost, "no cost was declared")


func test_an_ability_with_no_owner_reports_owner_missing() -> void:
	var orphan: ProbeAbility = Probe.build(PROBE_TAG)
	add_child_autofree(orphan)
	assert_eq(
		orphan.commit_ability().status,
		AbilityCommitResult.Status.OWNER_MISSING,
		"there is nobody to charge"
	)


func test_a_second_commit_in_one_activation_is_refused() -> void:
	ability.cost_effect = _cost(COST_AMOUNT)
	assert_true(ability.commit_ability().is_ok(), "the first commit pays")

	assert_eq(_status(), AbilityCommitResult.Status.ALREADY_COMMITTED, "one activation, one charge")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA + COST_AMOUNT, TOLERANCE, "and it was taken once"
	)
#endregion


#region What a cost may be
func test_a_cost_that_is_not_instant_is_refused() -> void:
	ability.cost_effect = Factory.duration([Factory.add(MANA, COST_AMOUNT)], COOLDOWN_SECONDS)
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "a cost is paid, not sustained")


func test_a_cost_with_an_execution_is_refused() -> void:
	var computed: GameplayEffect = _cost(COST_AMOUNT)
	computed.executions = [NeverRuns.new()] as Array[GameplayExecutionCalculation]
	ability.cost_effect = computed
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "an execution cannot be previewed")


func test_a_cost_using_anything_but_add_is_refused() -> void:
	ability.cost_effect = Factory.instant([Factory.multiply(MANA, 0.9)])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "multiply reads the value")

	ability.cost_effect = Factory.instant([Factory.divide(MANA, 2.0)])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "divide reads the value")

	ability.cost_effect = Factory.instant([Factory.override(MANA, 0.0)])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "override discards the value")


func test_this_phase_has_no_way_to_write_a_percentage_cost() -> void:
	# The operations that read the attribute are refused, so all that remains is
	# ADD with a fixed magnitude. This proves what that leaves: the same charge
	# whatever the pool holds. A percentage is not a cost this vocabulary can
	# express, which is the point rather than an oversight.
	ability.cost_effect = _cost(COST_AMOUNT)
	assert_true(ability.commit_ability().is_ok(), "a flat charge is the whole vocabulary")
	var taken_from_full: float = STARTING_MANA - fixture.base_of(MANA)

	ability.end_ability()
	var doubled: float = STARTING_MANA * 2.0
	fixture.set_base(MANA, doubled)
	assert_true(ability.commit_ability().is_ok(), "the same cost against a larger pool")
	var taken_from_double: float = doubled - fixture.base_of(MANA)

	assert_almost_eq(taken_from_double, taken_from_full, TOLERANCE, "flat, never proportional")


func test_a_cost_with_a_positive_magnitude_is_refused() -> void:
	ability.cost_effect = _cost(10.0)
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "a cost that pays out is not one")


func test_a_cost_that_announces_itself_is_refused() -> void:
	ability.cost_effect = Factory.granting(_cost(COST_AMOUNT), [OWN_COOLDOWN])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "a cost grants nothing")

	ability.cost_effect = Factory.with_events(_cost(COST_AMOUNT), [PROBE_TAG])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "a cost dispatches nothing")

	ability.cost_effect = Factory.with_application_cues(_cost(COST_AMOUNT), [OWN_COOLDOWN])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "a cost plays nothing")
#endregion


#region What a cooldown may be
func test_a_cooldown_that_moves_an_attribute_is_refused() -> void:
	ability.cooldown_effect = Factory.granting(
		Factory.duration([Factory.add(MANA, COST_AMOUNT)], COOLDOWN_SECONDS), [OWN_COOLDOWN]
	)
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION, "a cooldown is not a debuff"
	)


func test_a_cooldown_without_a_granted_tag_is_refused() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	ability.cooldown_effect = Factory.duration(no_modifiers, COOLDOWN_SECONDS)
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION, "nothing could observe it"
	)


func test_an_instant_cooldown_is_refused() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	ability.cooldown_effect = Factory.granting(Factory.instant(no_modifiers), [OWN_COOLDOWN])
	assert_eq(
		_status(),
		AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION,
		"a cooldown that is over immediately is not a cooldown"
	)
#endregion


#region The transaction
func test_an_unaffordable_cost_starts_no_cooldown() -> void:
	fixture.set_base(MANA, 5.0)
	ability.cost_effect = _cost(COST_AMOUNT)
	ability.cooldown_effect = _cooldown(OWN_COOLDOWN)

	assert_eq(_status(), AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, "the owner cannot pay")
	assert_false(asc.has_tag(OWN_COOLDOWN), "and is therefore not on cooldown")
	assert_almost_eq(fixture.base_of(MANA), 5.0, TOLERANCE, "and kept what it had")


func test_a_cooldown_that_fails_to_apply_charges_nothing() -> void:
	var cooldown: GameplayEffect = _cooldown(OWN_COOLDOWN)
	var caster: ProbeAbility = _caster_refusing(cooldown)
	caster.cost_effect = _cost(COST_AMOUNT)
	caster.cooldown_effect = cooldown

	var before: float = caster.owner_asc.get_attribute_base(MANA)
	var result: AbilityCommitResult = caster.commit_ability()

	assert_eq(
		result.status, AbilityCommitResult.Status.COOLDOWN_APPLICATION_FAILED, "the cooldown refused"
	)
	assert_almost_eq(
		caster.owner_asc.get_attribute_base(MANA), before, TOLERANCE, "so no mana was spent"
	)
	assert_eq(result.applied_cooldowns.size(), 0, "and the result claims nothing was applied")


func test_a_cost_that_fails_to_apply_retires_the_cooldowns() -> void:
	var cost: GameplayEffect = _cost(COST_AMOUNT)
	var caster: ProbeAbility = _caster_refusing(cost)
	caster.cost_effect = cost
	caster.cooldown_effect = _cooldown(OWN_COOLDOWN)

	var result: AbilityCommitResult = caster.commit_ability()

	assert_eq(result.status, AbilityCommitResult.Status.COST_APPLICATION_FAILED, "the charge refused")
	assert_false(caster.owner_asc.has_tag(OWN_COOLDOWN), "so the started cooldown was retired")
	assert_eq(caster.owner_asc.get_active_effects().size(), 0, "leaving nothing running")
	assert_eq(result.applied_cooldowns.size(), 0, "and the result reports none applied")


func test_a_cooldown_listed_twice_is_applied_once() -> void:
	var shared: GameplayEffect = _cooldown(SHARED_COOLDOWN)
	ability.cooldown_effect = shared
	ability.shared_cooldown_effects = [shared]

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "sharing a cooldown with itself is legal")
	assert_eq(result.applied_cooldowns.size(), 1, "one Resource is one application")
	assert_eq(asc.get_active_effects().size(), 1, "and one active effect on the owner")


func test_a_successful_commit_charges_exactly_once() -> void:
	ability.cost_effect = _cost(COST_AMOUNT)
	ability.cooldown_effect = _cooldown(OWN_COOLDOWN)

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "affordable and well defined")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA + COST_AMOUNT, TOLERANCE, "the charge landed once"
	)
	assert_true(asc.has_tag(OWN_COOLDOWN), "and the cooldown started")
	assert_not_null(result.applied_cost, "and the charge handed back its handle")


func test_a_new_activation_may_commit_again() -> void:
	ability.cost_effect = _cost(COST_AMOUNT)
	assert_true(ability.commit_ability().is_ok(), "the first activation pays")

	ability.end_ability()
	assert_true(ability.commit_ability().is_ok(), "and ending it clears the way for the next")
	assert_almost_eq(
		fixture.base_of(MANA),
		STARTING_MANA + COST_AMOUNT * 2.0,
		TOLERANCE,
		"two activations, two charges"
	)
#endregion


#region Lifecycle
func test_removing_an_active_ability_ends_it_exactly_once() -> void:
	ability.channels = true
	watch_signals(ability)
	ability.try_activate()
	assert_true(ability.is_active, "the channel is holding the activation open")

	asc.remove_ability(ability)

	assert_signal_emit_count(ability, "ability_ended", 1, "ended once, not never and not twice")
	assert_false(ability.is_active, "and is no longer running")
	assert_null(ability.owner_asc, "and no longer points at the ASC that dropped it")
#endregion
