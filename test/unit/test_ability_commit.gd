## Committing an ability is a transaction: the whole price, or none of it.
##
## Charging first and then failing to start a cooldown bills a player for
## nothing; starting a cooldown and then failing to charge locks an ability
## that never went off. Both are worse than refusing, so a commit that cannot
## finish undoes what it had already done and reports what it refused on.
##
## What a cost actually charges - absolute amounts, percentages, aggregation,
## the durable-funds rule - lives in test_ability_cost_pricing.gd. This file is
## the transaction around that price: cooldown legality, rollback, the second
## affordability check after cooldowns are applied, and the lifecycle of a
## commit itself.
##
## What a cost effect's own shape may be - INSTANT, ADD-only, no tags, no
## cues, no events - is no longer reachable through authoring at all: nothing
## but the resolver ever builds one. Those regression tests live in
## test_ability_commit_contract.gd, which tests AbilityCommitContract directly.
##
## costs and cooldown_effect are read from the frozen definition a grant
## captured, not from this Node's live exports, so every test that needs a
## specific one configures a fresh probe before granting it rather than
## editing `ability` afterward - the same discipline a real designer's scene
## follows, since the scene is exactly what the snapshot reads.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const TOLERANCE: float = 0.0001
const MANA: StringName = &"mana"
const OWN_COOLDOWN: StringName = &"Cooldown.Probe"
const SHARED_COOLDOWN: StringName = &"Cooldown.Shared"
const PROBE_TAG: StringName = &"Ability.Probe"
const STARTING_MANA: float = 50.0
const COST_AMOUNT: float = 20.0
const COOLDOWN_SECONDS: float = 5.0


## An ASC that refuses whatever `refuses` answers true for, and behaves
## normally otherwise.
##
## A predicate rather than an exact effect reference: the resolved cost effect
## is built fresh by GameplayAbilityCostResolver on every commit, so its
## identity cannot be known before the commit that builds it. Refusing by
## shape - "the INSTANT one" - reaches it without needing to.
class RefusingASC extends AbilitySystemComponent:
	var refuses: Callable = func(_effect: GameplayEffect) -> bool: return false

	func apply_gameplay_effect(
		effect: GameplayEffect,
		source_asc: AbilitySystemComponent = null,
		effect_level: float = 1.0
	) -> ActiveGameplayEffect:
		if effect != null and refuses.call(effect):
			return null
		return super(effect, source_asc, effect_level)


var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: ProbeAbility = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	fixture.set_base(MANA, STARTING_MANA)
	ability = _granted(asc)


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Builders
func _cost(target: StringName, positive_amount: float) -> GameplayAbilityCost:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = target
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = positive_amount
	return cost


## A single absolute mana cost, for the many tests that only care about the
## transaction shape and not the pricing model.
func _mana_cost(positive_amount: float) -> Array[GameplayAbilityCost]:
	return [_cost(MANA, positive_amount)]


func _cooldown(tag: StringName) -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.duration(no_modifiers, COOLDOWN_SECONDS), [tag])


## Grant a fresh probe on `on_asc`, configuring it first: costs, cooldowns and
## every other export a grant snapshots are authored before the grant, never
## edited on the instance afterward.
func _granted(on_asc: AbilitySystemComponent, configure: Callable = Callable()) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	if configure.is_valid():
		configure.call(probe)
	var spec: GameplayAbilitySpec = AbilityFactory.give(on_asc, probe)
	return spec.per_actor_instance as ProbeAbility


## The status of committing the ability under test, for the many cases whose
## whole claim is which refusal came back.
func _status() -> AbilityCommitResult.Status:
	return ability.commit_ability().status


## An ASC that will refuse whatever `refuses` matches, with a configured
## ability already granted on it.
func _caster_refusing(refuses: Callable, configure: Callable = Callable()) -> ProbeAbility:
	var host: Node = Node.new()
	host.name = "Refuser"

	var refusing: RefusingASC = RefusingASC.new()
	refusing.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	refusing.attribute_sets = [AttributeSetScript.new()]
	refusing.share_attributes = true
	refusing.refuses = refuses
	host.add_child(refusing)
	add_child_autofree(host)

	return _granted(refusing, configure)
#endregion


#region Success and refusal basics
func test_an_ability_with_no_cost_and_no_cooldown_commits() -> void:
	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "having nothing to pay is not a reason to refuse")
	assert_eq(result.applied_cooldowns.size(), 0, "no cooldown was declared")
	assert_null(result.applied_cost, "no cost was declared")
	assert_null(result.resolved_cost.absolute_effect, "an empty cost list resolves to nothing")


func test_an_ability_with_no_owner_reports_owner_missing() -> void:
	var orphan: ProbeAbility = Probe.build(PROBE_TAG)
	add_child_autofree(orphan)
	assert_eq(
		orphan.commit_ability().status,
		AbilityCommitResult.Status.OWNER_MISSING,
		"there is nobody to charge"
	)


func test_a_second_commit_in_one_activation_is_refused() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void: p.costs = _mana_cost(COST_AMOUNT))
	assert_true(ability.commit_ability().is_ok(), "the first commit pays")

	assert_eq(_status(), AbilityCommitResult.Status.ALREADY_COMMITTED, "one activation, one charge")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA - COST_AMOUNT, TOLERANCE, "and it was taken once"
	)
#endregion


#region What a cooldown may be
func test_a_cooldown_that_moves_an_attribute_is_refused() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		p.cooldown_effect = Factory.granting(
			Factory.duration([Factory.add(MANA, -COST_AMOUNT)], COOLDOWN_SECONDS), [OWN_COOLDOWN]
		)
	)
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION, "a cooldown is not a debuff"
	)


func test_a_cooldown_without_a_granted_tag_is_refused() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		var no_modifiers: Array[GameplayEffectModifier] = []
		p.cooldown_effect = Factory.duration(no_modifiers, COOLDOWN_SECONDS)
	)
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION, "nothing could observe it"
	)


func test_an_instant_cooldown_is_refused() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		var no_modifiers: Array[GameplayEffectModifier] = []
		p.cooldown_effect = Factory.granting(Factory.instant(no_modifiers), [OWN_COOLDOWN])
	)
	assert_eq(
		_status(),
		AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION,
		"a cooldown that is over immediately is not a cooldown"
	)
#endregion


#region The transaction
func test_an_unaffordable_cost_starts_no_cooldown() -> void:
	fixture.set_base(MANA, 5.0)
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		p.costs = _mana_cost(COST_AMOUNT)
		p.cooldown_effect = _cooldown(OWN_COOLDOWN)
	)

	assert_eq(_status(), AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, "the owner cannot pay")
	assert_false(asc.has_tag(OWN_COOLDOWN), "and is therefore not on cooldown")
	assert_almost_eq(fixture.base_of(MANA), 5.0, TOLERANCE, "and kept what it had")


func test_a_cooldown_that_fails_to_apply_charges_nothing() -> void:
	var cooldown: GameplayEffect = _cooldown(OWN_COOLDOWN)
	var caster: ProbeAbility = _caster_refusing(
		func(effect: GameplayEffect) -> bool: return effect == cooldown,
		func(p: ProbeAbility) -> void:
			p.costs = _mana_cost(COST_AMOUNT)
			p.cooldown_effect = cooldown
	)

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
	var caster: ProbeAbility = _caster_refusing(
		func(effect: GameplayEffect) -> bool:
			return effect.policy == GameplayEffect.DurationPolicy.INSTANT,
		func(p: ProbeAbility) -> void:
			p.costs = _mana_cost(COST_AMOUNT)
			p.cooldown_effect = _cooldown(OWN_COOLDOWN)
	)

	var result: AbilityCommitResult = caster.commit_ability()

	assert_eq(result.status, AbilityCommitResult.Status.COST_APPLICATION_FAILED, "the charge refused")
	assert_false(caster.owner_asc.has_tag(OWN_COOLDOWN), "so the started cooldown was retired")
	assert_eq(caster.owner_asc.get_active_effects().size(), 0, "leaving nothing running")
	assert_eq(result.applied_cooldowns.size(), 0, "and the result reports none applied")


func test_a_cooldown_listed_twice_is_applied_once() -> void:
	var shared: GameplayEffect = _cooldown(SHARED_COOLDOWN)
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		p.cooldown_effect = shared
		p.shared_cooldown_effects = [shared]
	)

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "sharing a cooldown with itself is legal")
	assert_eq(result.applied_cooldowns.size(), 1, "one Resource is one application")
	assert_eq(asc.get_active_effects().size(), 1, "and one active effect on the owner")


func test_a_successful_commit_charges_exactly_once() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		p.costs = _mana_cost(COST_AMOUNT)
		p.cooldown_effect = _cooldown(OWN_COOLDOWN)
	)

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "affordable and well defined")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA - COST_AMOUNT, TOLERANCE, "the charge landed once"
	)
	assert_true(asc.has_tag(OWN_COOLDOWN), "and the cooldown started")
	assert_not_null(result.applied_cost, "and the charge handed back its handle")


func test_a_new_activation_may_commit_again() -> void:
	ability = _granted(asc, func(p: ProbeAbility) -> void: p.costs = _mana_cost(COST_AMOUNT))
	ability.commits = true

	var first: bool = await ability.try_activate()
	assert_true(first, "the first activation pays")
	assert_true(ability.last_commit.is_ok(), "and its commit was accepted")

	var second: bool = await ability.try_activate()
	assert_true(second, "and ending the first clears the way for the next")
	assert_almost_eq(
		fixture.base_of(MANA),
		STARTING_MANA - COST_AMOUNT * 2.0,
		TOLERANCE,
		"two activations, two charges"
	)
#endregion


#region The second, post-cooldown affordability check
## A synchronous listener on the cooldown's own tag can move the very
## resources the charge is about to take. The percentage was already frozen at
## resolve time and is never recalculated; only affordability is asked again.
func test_a_cooldown_listener_that_drains_resources_rolls_back_and_reports_the_change() -> void:
	fixture.set_base(MANA, COST_AMOUNT)
	ability = _granted(asc, func(p: ProbeAbility) -> void:
		p.costs = _mana_cost(COST_AMOUNT)
		p.cooldown_effect = _cooldown(OWN_COOLDOWN)
	)

	asc.tag_added.connect(func(_tag: StringName) -> void: asc.set_attribute_base(MANA, 0.0))

	var result: AbilityCommitResult = ability.commit_ability()
	assert_eq(
		result.status,
		AbilityCommitResult.Status.RESOURCES_CHANGED_DURING_COMMIT,
		"affordable a moment ago is not affordable now"
	)
	assert_false(asc.has_tag(OWN_COOLDOWN), "the cooldown the listener reacted to was rolled back")
	assert_almost_eq(fixture.base_of(MANA), 0.0, TOLERANCE, "the listener's own write stands")
	assert_null(result.applied_cost, "and nothing was charged")
#endregion


#region Activation shares the resolver
func test_activation_error_and_commit_ability_agree_on_affordability() -> void:
	fixture.set_base(MANA, 5.0)
	ability = _granted(asc, func(p: ProbeAbility) -> void: p.costs = _mana_cost(COST_AMOUNT))

	assert_eq(
		asc.ability_runtime.activation_error(ability.current_spec),
		AbilityRuntime.ActivationError.INSUFFICIENT_RESOURCES,
		"the gate refuses"
	)
	assert_eq(_status(), AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, "and the commit agrees")
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


#region Costs written after the grant
## Granting an ability freezes its definition, and the commit prices from that
## snapshot - so a cost written onto the running instance afterwards is ignored.
## That is the design and the snapshot's own header says so, but silence is a bad
## way to say it: an ability whose cost never reached the engine is simply free,
## and a green console and a won battle both look exactly the same as correct.
##
## The sandbox lost a whole session to it, and a screenshot caught it rather than
## any log. The commit says it out loud now.
func test_a_cost_written_after_the_grant_is_reported_not_swallowed() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.LateCost")
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	var instance: ProbeAbility = spec.per_actor_instance as ProbeAbility
	assert_true(spec.definition.costs.is_empty(), "granted with no costs")

	# Exactly the mistake: the instance is told what it costs, too late.
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = 5.0
	var late: GameplayAbilityCost = GameplayAbilityCost.new()
	late.mode = GameplayAbilityCost.Mode.ABSOLUTE
	late.target_attribute = &"mana"
	late.amount = amount
	instance.costs = [late] as Array[GameplayAbilityCost]

	# The commit still prices from the definition - the behaviour is unchanged -
	# but it no longer does so quietly. Through the engine's error channel, so
	# a game that wired up nothing at all is still told.
	var commit: AbilityCommitResult = instance.commit_ability()

	assert_true(commit.is_ok(), "priced from the definition, which has no costs")
	# The probe fixture leaves `ability_name` empty, so the report falls back to
	# the node name - the tag with its dots replaced.
	assert_push_error("ability 'Ability_LateCost' was given costs after it was granted")


func test_an_ability_whose_costs_match_its_definition_says_nothing() -> void:
	# The guard must not shout at every ordinary commit.
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.HonestCost")
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	var instance: ProbeAbility = spec.per_actor_instance as ProbeAbility

	instance.commit_ability()
	assert_push_error_count(0, "nothing drifted, so nothing to say")
## The list of captured fields is hand-kept, and a hand-kept list that falls
## behind `from_probe()` puts this check back in the silence it exists to end -
## a field added to the capture and forgotten here drifts unreported forever.
func test_every_captured_field_is_watched_for_drift() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://addons/GAS_Engine/abilities/gameplay_ability_definition_snapshot.gd"
	)
	var captured: Array[String] = []
	for line: String in source.split("
"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("snapshot.") and stripped.contains(" = probe."):
			captured.append(stripped.substr(9, stripped.find(" =") - 9))

	assert_false(captured.is_empty(), "the capture was found at all")
	for field: String in captured:
		assert_true(
			GameplayAbilityDefinitionSnapshot.CAPTURED_FIELDS.has(StringName(field)),
			"`%s` is captured from the probe but nothing watches it for drift" % field
		)
#endregion
