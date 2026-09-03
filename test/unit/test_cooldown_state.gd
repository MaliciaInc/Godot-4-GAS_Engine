## Cooldown state: what a UI would draw, read from the tags rather than a timer.
##
## The temptation is a countdown on the ability. It would be simpler and it
## would be wrong: the effect already keeps a clock, and a second one would part
## company with it the first time the cooldown was refreshed, removed early, or
## measured in turns instead of seconds. Everything here is asked, never stored.
##
## cooldown_effect and its siblings are read from the frozen definition a grant
## captured, so every test that needs a specific one configures a fresh probe
## before granting it - editing `ability.cooldown_effect` after the grant would
## simply not reach what get_cooldown_state() reads.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const TOLERANCE: float = 0.0001
const PROBE_TAG: StringName = &"Ability.Probe"
const OWN_COOLDOWN: StringName = &"Cooldown.Own"
const SHARED_COOLDOWN: StringName = &"Cooldown.Shared"
const SECONDS: float = 5.0
const SHORTER: float = 2.0
const TURNS: int = 3


## One kind of cooldown, and the unit it is owed a reading in.
class UnitCase extends RefCounted:
	var turn_based: bool = false
	var expected_seconds: float = 0.0
	var expected_turns: int = 0

	func _init(by_turns: bool, seconds: float, turns: int) -> void:
		turn_based = by_turns
		expected_seconds = seconds
		expected_turns = turns


var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: ProbeAbility = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	ability = _granted(Callable())


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Builders
func _seconds_cooldown(tag: StringName, seconds: float) -> GameplayEffect:
	var none: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.duration(none, seconds), [tag])


func _turns_cooldown(tag: StringName, turns: int) -> GameplayEffect:
	var none: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.turn_based(none, turns), [tag])


func _endless_effect(tag: StringName) -> GameplayEffect:
	var none: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.infinite(none), [tag])


## Grant a fresh probe, configured before the grant so what it sets - the
## cooldown effect and its siblings - reaches the frozen definition
## get_cooldown_state() actually reads.
func _granted(configure: Callable) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	if configure.is_valid():
		configure.call(probe)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	return spec.per_actor_instance as ProbeAbility


## Start the cooldowns, and refuse to continue quietly if they were not started.
##
## Without this a mis-built cooldown would be refused by the commit and every
## assertion below would still pass, against an ability that simply has no
## cooldown at all.
func _commit() -> void:
	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "the cooldown was accepted and applied")


## Why the engine would refuse to activate this ability right now.
func _refusal() -> AbilityRuntime.ActivationError:
	return asc.ability_runtime.activation_error(ability.current_spec)
#endregion


#region Reading the wait
func test_an_ability_without_a_cooldown_is_never_on_one() -> void:
	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_false(state.active, "there is nothing to wait for")
	assert_eq(state.tags.size(), 0, "and no tag to consult")
	assert_almost_eq(state.seconds_remaining, 0.0, TOLERANCE, "no seconds")
	assert_eq(state.turns_remaining, 0, "and no turns")


func _unit_cases() -> Array[UnitCase]:
	return [
		UnitCase.new(false, SECONDS, 0),
		UnitCase.new(true, 0.0, TURNS),
	] as Array[UnitCase]


## A cooldown is reported in its own unit and claims nothing in the other.
##
## Seconds and turns are not convertible here: a turn-based cooldown that also
## reported seconds would let a UI draw a bar that never moves, and a real-time
## one reporting turns would be counted down by a turn manager that does not own
## it. Asked as one test because it is one rule with two sides.
func test_a_cooldown_is_reported_in_its_own_unit(
	scenario: UnitCase = use_parameters(_unit_cases())
) -> void:
	if scenario.turn_based:
		ability = _granted(func(p: ProbeAbility) -> void:
			p.cooldown_effect = _turns_cooldown(OWN_COOLDOWN, TURNS)
		)
	else:
		ability = _granted(func(p: ProbeAbility) -> void:
			p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SECONDS)
		)
	_commit()

	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_true(state.active, "the ability is waiting")
	assert_false(state.infinite, "and it does end")
	assert_almost_eq(
		state.seconds_remaining,
		scenario.expected_seconds,
		TOLERANCE,
		"the seconds it is owed, and no others"
	)
	assert_eq(
		state.turns_remaining, scenario.expected_turns, "the turns it is owed, and no others"
	)


func test_time_passing_lowers_the_reported_wait() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SECONDS)
	)
	_commit()

	asc.scheduler.advance_time(SHORTER)

	assert_almost_eq(
		ability.get_cooldown_state().seconds_remaining,
		SECONDS - SHORTER,
		TOLERANCE,
		"the clock the effect already keeps is the one reported"
	)


## An endless cooldown says so rather than claiming an enormous number.
##
## It cannot arrive by being committed - the commit contract only accepts a
## cooldown that expires - so it arrives the way a real one would: something else
## grants the tag, and the ability names that tag as one of its cooldowns.
func test_an_endless_cooldown_tag_is_reported_as_infinite() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.shared_cooldown_tags = [OWN_COOLDOWN]
	)
	Factory.apply(asc, _endless_effect(OWN_COOLDOWN))

	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_true(state.infinite, "there is no bar to draw for this one")
	assert_true(state.active, "but it is certainly not ready")
	assert_almost_eq(state.seconds_remaining, 0.0, TOLERANCE, "and no finite time is claimed")
#endregion


#region Several cooldowns at once
func test_the_longest_of_several_waits_is_the_one_reported() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SHORTER)
		p.shared_cooldown_effects = [_seconds_cooldown(SHARED_COOLDOWN, SECONDS)]
	)
	_commit()

	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_eq(state.tags.size(), 2, "both cooldowns were consulted")
	assert_almost_eq(state.seconds_remaining, SECONDS, TOLERANCE, "and the longer one decides")


func test_a_tag_named_twice_is_consulted_once() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SECONDS)
		p.shared_cooldown_tags = [OWN_COOLDOWN]
	)
	_commit()

	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_eq(state.tags, [OWN_COOLDOWN] as Array[StringName], "one wait, listed once")
	assert_almost_eq(state.seconds_remaining, SECONDS, TOLERANCE, "and counted once")
#endregion


#region Staying honest
func test_a_refreshed_cooldown_reports_the_new_time() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = Factory.refreshing(_seconds_cooldown(OWN_COOLDOWN, SECONDS))
	)
	_commit()
	asc.scheduler.advance_time(SHORTER)

	Factory.apply(asc, ability.current_spec.definition.cooldown_effect)

	assert_almost_eq(
		ability.get_cooldown_state().seconds_remaining,
		SECONDS,
		TOLERANCE,
		"the refresh put the wait back to full, and the reading followed"
	)


## A turn-counted cooldown lifts on the turn it says, and not one before.
##
## The seconds case above proves the reported number falls. This proves the
## refusal itself ends, on the exact turn, through a clock nothing advances on
## its own: `advance_turn()` is called by whatever manages the turns, so a game
## that forgets it has a cooldown that lifts never.
##
## Nothing else here tied that clock to whether an ability may be activated. A
## turn-based game built on this addon reaches the path on its first cooldown -
## an ability affordable again before its cooldown is over is refused, and the
## refusal has to end by itself.
##
## Asked for the reason rather than the verdict. `can_activate_ability()` is
## false for eight different reasons, and a test that only reads the bool would
## pass just as well against an ability refused for being already active.
func test_a_turn_counted_cooldown_lifts_on_the_turn_it_says() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _turns_cooldown(OWN_COOLDOWN, TURNS)
	)
	_commit()

	assert_eq(
		_refusal(), AbilityRuntime.ActivationError.ON_COOLDOWN,
		"used, and refused for the cooldown rather than for anything else"
	)

	for elapsed: int in TURNS - 1:
		asc.advance_turn()
		assert_eq(
			_refusal(), AbilityRuntime.ActivationError.ON_COOLDOWN,
			"still owed %d of %d turns" % [TURNS - elapsed - 1, TURNS]
		)

	asc.advance_turn()
	assert_eq(
		_refusal(), AbilityRuntime.ActivationError.NONE,
		"the last turn owed is the one that lifts it"
	)


func test_removing_the_effect_makes_the_ability_ready_again() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SECONDS)
	)
	_commit()
	assert_true(ability.get_cooldown_state().active, "on cooldown to begin with")

	asc.remove_effects_with_tag(OWN_COOLDOWN)

	var state: AbilityCooldownState = ability.get_cooldown_state()
	assert_false(state.active, "ready the moment the effect goes")
	assert_almost_eq(state.seconds_remaining, 0.0, TOLERANCE, "with no time still claimed")


func test_asking_for_the_state_changes_nothing() -> void:
	ability = _granted(func(p: ProbeAbility) -> void:
		p.cooldown_effect = _seconds_cooldown(OWN_COOLDOWN, SECONDS)
	)
	_commit()
	var before: int = asc.get_active_effects().size()
	watch_signals(asc)

	ability.get_cooldown_state()
	ability.get_cooldown_state()

	assert_eq(asc.get_active_effects().size(), before, "no effect was added or dropped")
	assert_signal_not_emitted(asc, "active_effect_removed", "and none was announced")
	assert_almost_eq(
		ability.get_cooldown_state().seconds_remaining,
		SECONDS,
		TOLERANCE,
		"and reading it three times spent no time"
	)
#endregion
