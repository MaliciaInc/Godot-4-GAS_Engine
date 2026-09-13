## What a receiver hears about an attribute when a reading writes it, base and
## current together - R7-02.
##
## `GameplayNetReplication.apply()` used to write base and current as two
## independent public mutations: the base write recomposed and could emit a
## value this machine's own (usually nonexistent) contributions produced,
## before an authoritative current then silently overwrote it. An observer of
## `attribute_changed` could hear a value nobody ever actually held, or hear
## nothing at all when only the silent write changed anything. This is split
## out of `test_network_replication.gd`, which is about the shape a reading
## takes on the wire rather than what applying one does to an observer.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const HEALTH: StringName = &"health"


## Base and current both moving in the same reading emits one signal, naming
## the authoritative jump rather than the value a bare recompose of the new
## base would answer. A receiver with no active modifiers recomposes a base
## write from 50 to 70 straight to 70 - a real value, and a wrong one, since
## the authority already knows current is 95.
func test_applying_a_reading_emits_the_authoritative_jump_and_not_a_recomposed_guess() -> void:
	var other: ASCFixture = Fixture.create("Onlooker")
	add_child_autofree(other.owner)
	other.set_base(HEALTH, 50.0)

	var heard_old: Array[float] = []
	var heard_new: Array[float] = []
	other.asc.attribute_changed.connect(
		func(_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec) -> void:
			heard_old.append(old_value)
			heard_new.append(new_value)
	)

	var state: GameplayNetState = GameplayNetState.snapshot()
	state.attributes[HEALTH] = 70.0
	state.current_attributes[HEALTH] = 95.0
	GameplayNetReplication.apply(state, other.asc)

	assert_eq(
		heard_new.size(), 1,
		"one signal - not the base write's own recompose and then a silent overwrite"
	)
	if heard_new.size() == 1:
		assert_almost_eq(heard_old[0], 50.0, 0.001, "what it was before this reading touched it")
		assert_almost_eq(
			heard_new[0], 95.0, 0.001,
			"the authoritative current - not 70, which is what recomposing the new base alone would answer"
		)
	assert_almost_eq(other.asc.get_attribute_base(HEALTH), 70.0, 0.001)
	assert_almost_eq(other.asc.get_attribute_current(HEALTH), 95.0, 0.001)


## A reading whose base moved but whose current, sent alongside it, did not -
## nothing is emitted, because nothing about what the entity currently is
## changed for anyone watching it.
func test_a_reading_that_moves_only_the_base_emits_nothing_when_current_holds() -> void:
	var other: ASCFixture = Fixture.create("Onlooker")
	add_child_autofree(other.owner)
	other.set_base(HEALTH, 70.0)

	var heard: Array[float] = []
	other.asc.attribute_changed.connect(
		func(_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec) -> void:
			heard.append(new_value)
	)

	var state: GameplayNetState = GameplayNetState.snapshot()
	state.attributes[HEALTH] = 80.0
	state.current_attributes[HEALTH] = 70.0
	GameplayNetReplication.apply(state, other.asc)

	assert_almost_eq(other.asc.get_attribute_base(HEALTH), 80.0, 0.001, "the base moved")
	assert_almost_eq(other.asc.get_attribute_current(HEALTH), 70.0, 0.001, "the current did not")
	assert_eq(heard.size(), 0, "and nothing was emitted for it")
