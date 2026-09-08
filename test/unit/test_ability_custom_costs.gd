## Three ways to price an ability, and one promise that covers all of them.
##
## The promise is F5's and it does not bend: a commit takes everything or
## nothing. What F6.1.6 adds is two more ways for a cost to arrive - an authored
## gameplay effect, and a cost this engine cannot price at all - without giving
## up the part that made the promise keepable.
##
## The state that must be unreachable is "a custom cost paid and the engine no
## longer holds the object that knows how to put it back". Every test here is
## about the order that keeps it unreachable.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const HEALTH: StringName = &"health"
const PROBE_TAG: StringName = &"Ability.Priced"
const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null

func before_each() -> void:
	fixture = Fixture.create("Payer")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	RecordingCustomCost.ledger = []


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _cost(label: StringName) -> RecordingCustomCost:
	var cost: RecordingCustomCost = RecordingCustomCost.new()
	cost.label = label
	return cost


## An instant, silent charge - which is the only shape the commit contract will
## accept as a cost, because it is the only one it can take back.
func _reversible_charge(amount: float) -> GameplayEffect:
	return Factory.instant(
		[Factory.add(HEALTH, -amount)] as Array[GameplayEffectModifier]
	)


func _granted(configure: Callable) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	probe.commits = true
	configure.call(probe)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	return spec.per_actor_instance as ProbeAbility


func _commit(ability: ProbeAbility) -> AbilityCommitResult:
	return ability.commit_ability()
#endregion


#region A cost authored as an effect
func test_a_reversible_cost_effect_can_be_used_as_an_ability_cost() -> void:
	var before: float = asc.get_attribute_current(HEALTH)
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.cost_effect = _reversible_charge(10.0)
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_eq(done.status, AbilityCommitResult.Status.SUCCESS, "it paid")
	assert_almost_eq(
		asc.get_attribute_current(HEALTH), before - 10.0, TOLERANCE, "and the charge landed"
	)


## An effect with a duration is not a charge: it is a thing that stays, and
## nothing about taking it back is defined. Refused before anything is charged.
func test_an_irreversible_cost_effect_is_rejected_at_definition_validation() -> void:
	var before: float = asc.get_attribute_current(HEALTH)
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.cost_effect = Factory.duration(
			[Factory.add(HEALTH, -10.0)] as Array[GameplayEffectModifier], 5.0
		)
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_eq(
		done.status,
		AbilityCommitResult.Status.INVALID_COST_DEFINITION,
		"refused as a definition mistake"
	)
	assert_almost_eq(
		asc.get_attribute_current(HEALTH), before, TOLERANCE, "and nothing was taken"
	)
#endregion


#region Costs this engine cannot price
func test_a_custom_cost_that_says_no_refuses_before_anything_is_prepared() -> void:
	var refusing: RecordingCustomCost = _cost(&"ammo")
	refusing.payable = false
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.custom_costs = [refusing] as Array[GameplayAbilityCustomCost]
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_eq(
		done.status, AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, "it could not be paid"
	)
	assert_false(RecordingCustomCost.ledger.has(&"prepare:ammo"), "and it was never asked to work out what")


## A cost that cannot be prepared stops the commit while nothing has been taken,
## including by the costs declared before it.
func test_a_custom_cost_is_not_committed_when_any_other_preflight_fails() -> void:
	var first: RecordingCustomCost = _cost(&"first")
	var second: RecordingCustomCost = _cost(&"second")
	second.preparable = false
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.custom_costs = [first, second] as Array[GameplayAbilityCustomCost]
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_false(done.is_ok(), "the commit was refused")
	assert_true(RecordingCustomCost.ledger.has(&"prepare:first"), "the first was prepared")
	assert_false(RecordingCustomCost.ledger.has(&"commit:first"), "and never asked to take anything")
	assert_false(RecordingCustomCost.ledger.has(&"rollback:first"), "so there was nothing to put back")


## The interesting failure: two costs took something, the third refused. What
## was taken goes back newest first, because a cost can depend on one declared
## before it.
func test_custom_costs_roll_back_in_reverse_order() -> void:
	var first: RecordingCustomCost = _cost(&"first")
	var second: RecordingCustomCost = _cost(&"second")
	var third: RecordingCustomCost = _cost(&"third")
	third.commits = false
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.custom_costs = [first, second, third] as Array[GameplayAbilityCustomCost]
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_false(done.is_ok(), "the third refused")
	assert_eq(
		RecordingCustomCost.rollbacks(),
		[&"rollback:second", &"rollback:first"] as Array[StringName],
		"newest first, and the one that never took anything is not among them"
	)


## Everything, not only the custom half: the attribute charge and the cooldown
## go back too, or the ability paid for something it did not do.
func test_a_failure_after_custom_cost_commit_restores_the_exact_previous_state() -> void:
	var before: float = asc.get_attribute_current(HEALTH)
	var failing: RecordingCustomCost = _cost(&"ammo")
	failing.commits = false
	var ability: ProbeAbility = _granted(func(p: ProbeAbility) -> void:
		p.cost_effect = _reversible_charge(10.0)
		p.cooldown_effect = Factory.granting(
			Factory.duration([] as Array[GameplayEffectModifier], 5.0),
			[&"Cooldown.Priced"] as Array[StringName]
		)
		p.custom_costs = [failing] as Array[GameplayAbilityCustomCost]
	)

	var done: AbilityCommitResult = _commit(ability)

	assert_false(done.is_ok(), "it did not go through")
	assert_almost_eq(
		asc.get_attribute_current(HEALTH), before, TOLERANCE, "the charge went back"
	)
	assert_false(asc.has_tag(&"Cooldown.Priced"), "and so did the cooldown")


## A cost the journal cannot reverse is not something a client may guess at.
func test_custom_costs_are_not_predicted_without_an_explicit_prediction_kind() -> void:
	assert_eq(
		_cost(&"ammo").prediction_kind(),
		GameplayPredictionOperation.Kind.NONE,
		"nothing is promised about an inventory across a wire"
	)
#endregion
