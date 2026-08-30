## Local input reaching a granted ability, and nothing else reaching it.
##
## Criterion 64 of the phase plan: ability input is proved local. There is no
## network path left in this addon, so "local" here means the whole route -
## press, slot lookup, activation gate, activation - runs inside one ASC with no
## authority check and no peer id anywhere in it.
##
## The routing is the part worth testing rather than activation itself: a slot
## that two abilities answer, or a press that reaches an ability nobody granted,
## is a bug the activation tests cannot see.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const SLOT: int = 3
const OTHER_SLOT: int = 4
const FIRE: StringName = &"Ability.Fire"
const GUARD: StringName = &"Ability.Guard"
const STUNNED: StringName = &"Status.Stunned"

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


## Grant an ability to the ASC. add_child triggers the grant the way a scene
## does, so the test exercises the same path a designer's scene takes.
func _granted(tag: StringName) -> ProbeAbility:
	var ability: ProbeAbility = Probe.build(tag)
	asc.add_child(ability)
	return ability


#region Routing a press
func test_a_bound_ability_activates_on_its_own_slot() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	assert_true(asc.bind_ability_to_input(ability, SLOT), "the ability was granted, so it binds")

	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 1, "the press reached it")


func test_a_press_on_another_slot_reaches_nothing() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	asc.bind_ability_to_input(ability, SLOT)

	asc.ability_local_input_pressed(OTHER_SLOT)
	assert_eq(ability.activations, 0, "a slot it does not hold is not its press")


func test_an_unbound_ability_never_hears_a_press() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	# Granted but never bound: input_id stays at its unbound default.
	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 0, "granting is not binding")


func test_binding_an_ungranted_ability_is_refused() -> void:
	var stranger: ProbeAbility = Probe.build(FIRE)
	autofree(stranger)
	assert_false(
		asc.bind_ability_to_input(stranger, SLOT),
		"an ASC will not route input to an ability it was never given"
	)
	# The refusal is also said out loud, so a designer who wired the scene
	# wrong is told rather than left with a button that does nothing.
	assert_push_error("GodotGAS: cannot bind an ability that was never granted to this ASC.")

	asc.ability_local_input_pressed(SLOT)
	assert_eq(stranger.activations, 0, "and the refusal is not cosmetic")
#endregion


#region One slot, one answer
## One binding case: whether the second binding evicts the first, and who then
## answers the press.
class SlotCase extends RefCounted:
	var label: String = ""
	## What the second bind passes for `unbind_others`.
	var unbind_others: bool = true
	var first_answers: int = 0
	var second_answers: int = 0


func _slot_cases() -> Array[SlotCase]:
	var evicting: SlotCase = SlotCase.new()
	evicting.label = "the second binding takes the slot"
	evicting.second_answers = 1

	var shared: SlotCase = SlotCase.new()
	shared.label = "a shared slot is kept when asked for"
	shared.unbind_others = false
	shared.first_answers = 1
	shared.second_answers = 1

	return [evicting, shared] as Array[SlotCase]


## Binding two abilities to one slot, evicting by default and sharing on request.
##
## The default matters: two abilities answering one press is the player tapping
## once and two things happening. Sharing has to be asked for.
func test_two_abilities_on_one_slot_answer_as_the_binding_said(
	scenario: SlotCase = use_parameters(_slot_cases())
) -> void:
	var first: ProbeAbility = _granted(FIRE)
	var second: ProbeAbility = _granted(GUARD)
	asc.bind_ability_to_input(first, SLOT)
	asc.bind_ability_to_input(second, SLOT, scenario.unbind_others)

	asc.ability_local_input_pressed(SLOT)
	assert_eq(first.activations, scenario.first_answers, scenario.label + ": first")
	assert_eq(second.activations, scenario.second_answers, scenario.label + ": second")
#endregion


#region Held inputs
func test_a_held_slot_is_reported_until_release() -> void:
	assert_eq(asc.ability_runtime.held_inputs().size(), 0, "nothing held to begin with")

	asc.ability_local_input_pressed(SLOT)
	assert_true(asc.ability_runtime.held_inputs().has(SLOT), "held while pressed")

	asc.ability_local_input_released(SLOT)
	assert_false(asc.ability_runtime.held_inputs().has(SLOT), "released")


func test_pressing_the_same_slot_twice_records_it_once() -> void:
	asc.ability_local_input_pressed(SLOT)
	asc.ability_local_input_pressed(SLOT)
	assert_eq(asc.ability_runtime.held_inputs().size(), 1, "held is a set, not a tally")


func test_releasing_a_slot_nobody_pressed_is_harmless() -> void:
	asc.ability_local_input_released(SLOT)
	assert_eq(asc.ability_runtime.held_inputs().size(), 0)
#endregion


#region Input while already running
## A channelling ability hears press and release without activating again.
##
## This is the hold-to-charge sequence as a player produces it: the ability is
## started by a press, then hears the next press and the release through the
## hooks that exist for "press again to detonate" and "release to fire". What
## must not happen is activation a second time.
func test_input_while_channelling_reaches_the_active_hooks() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	ability.channels = true
	asc.bind_ability_to_input(ability, SLOT)

	asc.ability_local_input_pressed(SLOT)
	assert_true(ability.is_active, "suspended inside _activate_ability")
	assert_eq(ability.activations, 1, "started once")

	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 1, "a second press does not start it again")
	assert_eq(ability.presses_while_active, 1, "it reaches the active hook instead")
	assert_eq(ability.releases_while_active, 0, "and is not mistaken for a release")

	asc.ability_local_input_released(SLOT)
	assert_eq(ability.releases_while_active, 1, "the release reaches its own hook")
	assert_eq(ability.activations, 1, "and starts nothing")

	ability.channel_gate.emit()
	assert_false(ability.is_active, "the channel closed once the gate opened")


func test_a_release_reaches_nothing_when_the_ability_is_idle() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	asc.bind_ability_to_input(ability, SLOT)

	asc.ability_local_input_released(SLOT)
	assert_eq(ability.releases_while_active, 0, "there was nothing running to tell")
	assert_eq(ability.activations, 0, "and a release does not start an ability")
#endregion


#region The gate still applies to input
func test_a_blocked_ability_does_not_activate_on_a_press() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	ability.activation_blocked_tags = [STUNNED] as Array[StringName]
	asc.bind_ability_to_input(ability, SLOT)
	asc.add_tag(STUNNED)

	asc.ability_local_input_pressed(SLOT)
	# Input routing does not bypass the activation gate. Routing that skipped it
	# would let a stunned player act by pressing rather than by calling the API.
	assert_eq(ability.activations, 0, "blocked while the tag is held")

	asc.clear_tag(STUNNED)
	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 1, "and allowed once it is not")


func test_a_press_cannot_pay_a_cost_the_owner_cannot_afford() -> void:
	fixture.set_base(&"mana", 5.0)
	var ability: ProbeAbility = _granted(FIRE)
	ability.cost_effect = Factory.instant([Factory.add(&"mana", -50.0)])
	asc.bind_ability_to_input(ability, SLOT)

	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 0, "the same gate the API uses")
	assert_almost_eq(fixture.current_of(&"mana"), 5.0, 0.0001, "and nothing was charged")
#endregion


#region Granting and removing
func test_removing_an_ability_stops_its_input() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	asc.bind_ability_to_input(ability, SLOT)
	asc.ability_runtime.remove(ability)

	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 0, "an ability the ASC no longer has hears nothing")


func test_ending_an_ability_leaves_it_granted_and_bound() -> void:
	var ability: ProbeAbility = _granted(FIRE)
	asc.bind_ability_to_input(ability, SLOT)

	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 1)
	assert_false(ability.is_active, "it ended")

	# Ending is not un-granting; the second press must work like the first.
	asc.ability_local_input_pressed(SLOT)
	assert_eq(ability.activations, 2, "still granted and still bound")
#endregion
