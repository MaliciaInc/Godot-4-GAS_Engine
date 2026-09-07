## Deciding what an ability costs, separately from paying it.
##
## Committing was one function that resolved, checked, charged and started
## cooldowns, so nothing could ask "can this be afforded" without charging for
## it - which is what a button that greys itself out needs, and what a preview
## needs, and what an AI weighing two abilities needs.
##
## It is four now, and the coordinator is still one: check the cost, check the
## cooldown, start the cooldowns, ask the cost again, take it. The second ask is
## not caution. Starting a cooldown raises signals, and a listener is entitled
## to spend the resources the commit was about to take - so the answer from a
## moment ago is an answer about a world that has since moved.
##
## And what "afforded" means differs by profile. Unreal prices against the
## current value, this engine has always priced against the durable base, and on
## a buffed attribute those are different numbers.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const MANA: StringName = &"mana"
const PROBE_TAG: StringName = &"Ability.Probe"
const COOLDOWN_TAG: StringName = &"Cooldown.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _use_unreal() -> void:
	asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7


func _cost(amount: float) -> GameplayAbilityCost:
	var made: GameplayAbilityCost = GameplayAbilityCost.new()
	made.mode = GameplayAbilityCost.Mode.ABSOLUTE
	made.target_attribute = MANA
	made.amount = GameplayScalableFloat.new()
	made.amount.value = amount
	return made


func _cooldown() -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.duration(no_modifiers, 5.0), [COOLDOWN_TAG])


## An ability priced and cooled the way the row wants, already activated.
func _ready_to_commit(price: float, cooled: bool = false) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	probe.costs = [_cost(price)] as Array[GameplayAbilityCost]
	if cooled:
		probe.cooldown_effect = _cooldown()
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	asc.ability_runtime.try_activate(spec.handle)
	return spec.per_actor_instance as ProbeAbility
#endregion


#region Asking without paying
## Checking a cost answers, and charges nothing either way.
##
## The whole reason the check is separable: a button that greys itself out asks
## this every frame, and an ask that charged would empty the player. Both
## answers are asked, because a check that always said no would also never
## charge anybody.
##
##     [what it is, mana at hand, price, expected]
func _asks() -> Array:
	return [
		["affordable", 50.0, 20.0, AbilityCommitPreflight.Status.OK],
		["out of reach", 10.0, 20.0, AbilityCommitPreflight.Status.INSUFFICIENT_RESOURCES],
	]


func test_checking_a_cost_answers_without_taking_anything() -> void:
	var rows: Array = _asks()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var at_hand: float = row[1]
		var price: float = row[2]
		var expected: AbilityCommitPreflight.Status = row[3]

		before_each()
		asc.set_attribute_base(MANA, at_hand)
		var ability: ProbeAbility = _ready_to_commit(price)

		var preflight: AbilityCommitPreflight = ability.check_cost()

		assert_eq(preflight.status, expected, "%s: the answer" % described)
		assert_not_null(preflight.resolved_cost, "%s: and the price it worked out" % described)
		assert_almost_eq(
			asc.get_attribute_base(MANA), at_hand, TOLERANCE, "%s: nothing taken" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "both answers were asked for")


## Checking a cooldown finds the one already running, and starts none.
func test_checking_a_cooldown_finds_a_running_one_and_starts_nothing() -> void:
	asc.set_attribute_base(MANA, 50.0)
	var ability: ProbeAbility = _ready_to_commit(1.0, true)
	Factory.apply(asc, _cooldown())
	var before: int = asc.effects.active_count()

	var preflight: AbilityCommitPreflight = ability.check_cooldown()

	assert_eq(
		preflight.status,
		AbilityCommitPreflight.Status.ON_COOLDOWN,
		"the cooldown is already running"
	)
	assert_eq(asc.effects.active_count(), before, "and checking started nothing")


## A cooldown check lists what it would start.
##
## Carried out rather than recomputed by whoever pays: two resolutions of one
## ability's cooldowns are two opinions about what it starts.
func test_a_cooldown_check_says_which_cooldowns_it_would_start() -> void:
	asc.set_attribute_base(MANA, 50.0)
	var ability: ProbeAbility = _ready_to_commit(1.0, true)

	var preflight: AbilityCommitPreflight = ability.check_cooldown()

	assert_true(preflight.is_ok(), "nothing is running yet")
	assert_eq(preflight.cooldowns.size(), 1, "and one cooldown would start")
#endregion


#region Asking twice
## A listener that spends the mana while the cooldown starts is caught.
##
## The reason the second check exists. Applying a cooldown raises signals, and a
## listener is entitled to do anything - including spending exactly what the
## commit was about to take. An answer from before that is an answer about a
## world that has moved.
func test_a_listener_that_spends_the_mana_mid_commit_is_caught() -> void:
	asc.set_attribute_base(MANA, 20.0)
	var ability: ProbeAbility = _ready_to_commit(20.0, true)
	asc.active_effect_added.connect(
		func _emptied(_active: ActiveGameplayEffect) -> void:
			asc.set_attribute_base(MANA, 0.0)
	)

	var result: AbilityCommitResult = ability.commit_ability()

	assert_eq(
		result.status,
		AbilityCommitResult.Status.RESOURCES_CHANGED_DURING_COMMIT,
		"the second look caught it"
	)
	assert_false(asc.tags.has(COOLDOWN_TAG), "and the cooldown it started was undone")
	assert_eq(result.applied_cooldowns.size(), 0, "with the result reporting none")


## A commit that goes through pays both halves exactly once.
func test_a_commit_that_goes_through_pays_both_halves_once() -> void:
	asc.set_attribute_base(MANA, 50.0)
	var ability: ProbeAbility = _ready_to_commit(20.0, true)

	var result: AbilityCommitResult = ability.commit_ability()

	assert_true(result.is_ok(), "it committed: %s" % result.status)
	assert_almost_eq(asc.get_attribute_base(MANA), 30.0, TOLERANCE, "charged once")
	assert_eq(result.applied_cooldowns.size(), 1, "and started one cooldown")
	assert_true(asc.tags.has(COOLDOWN_TAG), "which is running")
#endregion


#region What afforded means
## A buff that raises the current value pays for a cost under Unreal, and not
## under this engine's own rules.
##
## Base 10, buffed to 60, cost 20. Unreal prices against what the attribute is
## worth now and lets it through; Godot-native prices against the durable base
## and refuses. Both rows are asserted, because a change that made them agree
## would silently reprice every cost in somebody's game.
func test_a_buff_pays_for_a_cost_under_one_profile_and_not_the_other() -> void:
	asc.set_attribute_base(MANA, 10.0)
	var buff: Array[GameplayEffectModifier] = [Factory.add(MANA, 50.0)]
	Factory.apply(asc, Factory.infinite(buff))
	assert_almost_eq(asc.get_attribute_current(MANA), 60.0, TOLERANCE, "buffed to sixty")

	var natively: ProbeAbility = _ready_to_commit(20.0)
	assert_eq(
		natively.check_cost().status,
		AbilityCommitPreflight.Status.INSUFFICIENT_RESOURCES,
		"Godot-native prices against the durable base"
	)

	before_each()
	_use_unreal()
	asc.set_attribute_base(MANA, 10.0)
	var buffed: Array[GameplayEffectModifier] = [Factory.add(MANA, 50.0)]
	Factory.apply(asc, Factory.infinite(buffed))
	var unreally: ProbeAbility = _ready_to_commit(20.0)
	assert_true(
		unreally.check_cost().is_ok(), "Unreal prices against what it is worth now"
	)


## And what neither profile allows is spending more than either number.
func test_neither_profile_lets_an_ability_spend_what_is_not_there() -> void:
	_use_unreal()
	asc.set_attribute_base(MANA, 10.0)
	var ability: ProbeAbility = _ready_to_commit(80.0)

	assert_eq(
		ability.check_cost().status,
		AbilityCommitPreflight.Status.INSUFFICIENT_RESOURCES,
		"eighty is more than there has ever been"
	)
#endregion
