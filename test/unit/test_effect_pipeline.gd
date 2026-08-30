## The application pipeline end to end: gates, tags, signals and atomicity.
##
## Characterises what an application does and, more importantly, what a refused
## application does not do. A refusal that leaves a tag behind, or plays a cue,
## or wakes a passive, is worse than a crash: the world moved and the ledger
## says it did not.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const MANA: StringName = &"mana"
const HEALTH: StringName = &"health"
const STUNNED: StringName = &"Status.Stunned"
const IMMUNE: StringName = &"Status.Immune"
const POISON: StringName = &"Status.Poison"
const WOKEN: StringName = &"Event.Woken"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Application gates
## One gate case: which tag decides, and whether holding it blocks or allows.
class GateCase extends RefCounted:
	var label: String = ""
	var tag: StringName = &""
	## True when holding the tag blocks the effect; false when it is required.
	var holding_blocks: bool = false


static func _gate_case(label: String, tag: StringName, holding_blocks: bool) -> GateCase:
	var built: GateCase = GateCase.new()
	built.label = label
	built.tag = tag
	built.holding_blocks = holding_blocks
	return built


func _gate_cases() -> Array[GateCase]:
	return [
		_gate_case("an immunity blocks the application", IMMUNE, true),
		_gate_case("a missing requirement blocks the application", STUNNED, false),
	] as Array[GateCase]


## An application gate refuses while its condition is unmet and allows once met.
##
## Both directions are one procedure: set the ASC to the refusing state, assert
## nothing applied, flip it, assert it did. Writing that twice was two places to
## fix when the shape changed, which the duplication gate reported.
func test_an_application_gate_refuses_then_allows(
	scenario: GateCase = use_parameters(_gate_cases())
) -> void:
	fixture.set_base(ATTACK, 10.0)
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 5.0)]
	var gated: GameplayEffect = Factory.infinite(modifiers)
	if scenario.holding_blocks:
		gated = Factory.blocked_by(gated, [scenario.tag] as Array[StringName])
		asc.add_tag(scenario.tag)
	else:
		gated = Factory.requiring(gated, [scenario.tag] as Array[StringName])

	assert_null(Factory.apply(asc, gated), scenario.label)
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "nothing applied")

	# Flip the condition and the same effect now lands.
	if scenario.holding_blocks:
		asc.clear_tag(scenario.tag)
	else:
		asc.add_tag(scenario.tag)

	assert_not_null(Factory.apply(asc, gated), "allowed once the condition holds")
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE)
#endregion


#region The cleanser
func test_an_effect_can_purge_effects_granting_a_tag() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(
		asc,
		Factory.granting(Factory.infinite([Factory.add(ATTACK, -5.0)]), [POISON] as Array[StringName])
	)
	assert_almost_eq(fixture.current_of(ATTACK), 5.0, TOLERANCE, "poisoned")

	var cure: GameplayEffect = Factory.instant([])
	cure.remove_effects_with_tags = [POISON] as Array[StringName]
	Factory.apply(asc, cure)

	assert_eq(asc.get_active_effects().size(), 0, "the poison is gone")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "and its debuff with it")
	assert_false(asc.has_tag_exact(POISON))
#endregion


#region Policies
func test_an_instant_effect_registers_nothing_and_grants_no_tag() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.instant([Factory.add(ATTACK, 5.0)]), [STUNNED] as Array[StringName]
	)
	Factory.apply(asc, effect)
	assert_eq(asc.get_active_effects().size(), 0, "nothing to track")
	# An instant effect leaves nothing behind that could hold a tag, so granting
	# one would leak it forever.
	assert_false(asc.has_tag_exact(STUNNED), "no tag leaked")


func test_a_duration_effect_registers_and_grants() -> void:
	Factory.apply(
		asc,
		Factory.granting(Factory.duration([Factory.add(ATTACK, 5.0)], 3.0), [STUNNED] as Array[StringName])
	)
	assert_eq(asc.get_active_effects().size(), 1)
	assert_true(asc.has_tag_exact(STUNNED))


func test_an_infinite_effect_does_not_expire() -> void:
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))
	asc.scheduler.advance_time(1000.0)
	assert_eq(asc.get_active_effects().size(), 1, "still there after a long time")
#endregion


#region Atomicity of a refusal
func test_a_failed_multi_attribute_effect_changes_nothing_at_all() -> void:
	fixture.set_base(ATTACK, 10.0)
	var before_mana: float = fixture.current_of(MANA)

	var broken: GameplayEffect = Factory.granting(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.divide(MANA, 0.0)]),
		[STUNNED] as Array[StringName]
	)
	broken.event_tags = [WOKEN] as Array[StringName]

	var heard: Array[GameplayEventData] = []
	asc.gameplay_event_received.connect(func(e: GameplayEventData) -> void: heard.append(e))

	watch_signals(asc)
	var applied: ActiveGameplayEffect = Factory.apply(asc, broken)

	assert_null(applied, "refused")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "the valid modifier did not land")
	assert_almost_eq(fixture.current_of(MANA), before_mana, TOLERANCE, "nor the invalid one")
	assert_eq(asc.get_active_effects().size(), 0, "no active effect registered")
	assert_false(asc.has_tag_exact(STUNNED), "no tag granted")
	assert_eq(heard.size(), 0, "no event dispatched")
	assert_signal_not_emitted(asc, "attribute_changed", "no partial signal")
	assert_signal_not_emitted(asc, "active_effect_added")


func test_a_refusal_reports_its_typed_reason() -> void:
	var reasons: Array[int] = []
	asc.effect_application_refused.connect(
		func(status: int, _name: StringName) -> void: reasons.append(status)
	)
	Factory.apply(asc, Factory.infinite([Factory.divide(MANA, 0.0)]))

	assert_eq(reasons.size(), 1, "one refusal")
	assert_eq(
		reasons[0],
		AttributeEvaluationResult.Status.DIVISION_BY_ZERO,
		"the machine-readable reason, not a message to parse"
	)


func test_writing_an_unknown_attribute_is_refused() -> void:
	watch_signals(asc)
	var applied: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite([Factory.add(&"no_such_attribute", 5.0)])
	)
	assert_null(applied)
	assert_signal_not_emitted(asc, "active_effect_added")
#endregion


#region Signal cardinality
func test_an_effect_that_changes_nothing_emits_no_attribute_signal() -> void:
	fixture.set_base(ATTACK, 10.0)
	watch_signals(asc)
	# Adding zero composes to the same value, so nothing moved and nothing is
	# announced. A signal per application rather than per change would make
	# every listener re-render on every effect.
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 0.0)]))
	assert_signal_not_emitted(asc, "attribute_changed", "no change, no signal")


func test_one_signal_per_attribute_that_actually_moved() -> void:
	fixture.set_base(ATTACK, 10.0)
	watch_signals(asc)
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0), Factory.add(HEALTH, -5.0)]))
	assert_signal_emit_count(asc, "attribute_changed", 2, "attack and health, once each")


func test_removal_announces_the_effect_once() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))
	watch_signals(asc)
	asc.remove_active_effect(active)
	assert_signal_emit_count(asc, "active_effect_removed", 1)


func test_removing_an_effect_twice_announces_it_once() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))
	asc.remove_active_effect(active)
	watch_signals(asc)
	asc.remove_active_effect(active)
	assert_signal_not_emitted(asc, "active_effect_removed", "already gone")
#endregion


#region Source and target
func test_an_effect_applied_from_a_source_records_its_instigator() -> void:
	var source: ASCFixture = Fixture.create("Caster")
	add_child_autofree(source.owner)

	var active: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite([Factory.add(ATTACK, 5.0)]), source.owner
	)
	assert_eq(active.get_instigator(), source.owner, "who cast it")


func test_effects_can_be_removed_by_their_source() -> void:
	var source: ASCFixture = Fixture.create("Caster")
	var other: ASCFixture = Fixture.create("Someone")
	add_child_autofree(source.owner)
	add_child_autofree(other.owner)

	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0)]), source.owner)
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 3.0)]), other.owner)

	asc.remove_effects_from_source(source.owner)
	assert_eq(asc.get_active_effects().size(), 1, "only that source's effects went")
#endregion
