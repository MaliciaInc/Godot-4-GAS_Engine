## LIVE captures: the reactive half of GameplayAttributeBasedMagnitude.
##
## Split from `test_gameplay_magnitudes.gd`, which covers how a magnitude
## resolves. This file covers what happens afterwards: a persistent
## contribution whose capture keeps moving, the binding that keeps it current,
## what a cycle does, and what a watched actor leaving - or merely moving -
## does to it.
##
## DEFENSE/ATTACK are the output attributes throughout, never HEALTH:
## TestAttributeSet clamps HEALTH to [0, max_health], and a +10 on a base of
## 100 is silently clamped straight back down, masking the very reactivity
## these tests exist to prove.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"

var source: ASCFixture = null
var target: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


func _live_capture(
	actor: GameplayAttributeCaptureDefinition.Actor, attribute_name: StringName
) -> GameplayAttributeCaptureDefinition:
	return Factory.capture_definition(
		actor, attribute_name,
		GameplayAttributeCaptureDefinition.Value.CURRENT, GameplayAttributeCaptureDefinition.Policy.LIVE
	)


func _add_modifier(output_attribute: StringName, magnitude: GameplayMagnitude) -> GameplayEffectModifier:
	var modifier: GameplayEffectModifier = Factory.modifier(output_attribute, GameplayEffectModifier.Operation.ADD, 0.0)
	modifier.magnitude = magnitude
	return modifier


func test_live_instant_resolves_fresh_each_time_without_a_binding() -> void:
	source.set_base(ATTACK, 10.0)
	target.set_base(DEFENSE, 5.0)
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	var effect: GameplayEffect = Factory.instant([_add_modifier(DEFENSE, magnitude)])

	Factory.apply(target.asc, effect, source.owner)
	assert_almost_eq(target.base_of(DEFENSE), 15.0, TOLERANCE, "first application read 10")

	source.set_base(ATTACK, 50.0)
	Factory.apply(target.asc, effect, source.owner)
	assert_almost_eq(target.base_of(DEFENSE), 65.0, TOLERANCE, "second read the fresh 50, no binding needed")


## One shape, two directions: a persistent contribution whose LIVE capture
## points at the source actor, and one whose LIVE capture points back at the
## target itself.
## No _init(): eight constructor parameters would trip the LOC gate's
## per-function parameter limit for no reason worth having - GDScript has no
## named-argument constructor, so each case is simply assembled field by field
## in _live_reaction_cases() below instead.
class LiveReactionCase extends RefCounted:
	var capture: GameplayAttributeCaptureDefinition
	var output_attribute: StringName
	var starting_capture_value: float
	var starting_output_base: float
	var changed_capture_value: float
	var change_is_on_source: bool
	var label: String


func _live_reaction_cases() -> Array[LiveReactionCase]:
	var source_feeds_target: LiveReactionCase = LiveReactionCase.new()
	source_feeds_target.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	source_feeds_target.output_attribute = DEFENSE
	source_feeds_target.starting_capture_value = 10.0
	source_feeds_target.starting_output_base = 5.0
	source_feeds_target.changed_capture_value = 40.0
	source_feeds_target.change_is_on_source = true
	source_feeds_target.label = "source attribute feeds a target contribution"

	var target_feeds_itself: LiveReactionCase = LiveReactionCase.new()
	target_feeds_itself.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.TARGET, DEFENSE)
	target_feeds_itself.output_attribute = ATTACK
	target_feeds_itself.starting_capture_value = 5.0
	target_feeds_itself.starting_output_base = 10.0
	target_feeds_itself.changed_capture_value = 30.0
	target_feeds_itself.change_is_on_source = false
	target_feeds_itself.label = "target attribute feeds its own contribution"

	return [source_feeds_target, target_feeds_itself] as Array[LiveReactionCase]


func test_live_persistent_contribution_updates_when_its_capture_changes(
	case: LiveReactionCase = use_parameters(_live_reaction_cases())
) -> void:
	if case.change_is_on_source:
		source.set_base(case.capture.attribute_name, case.starting_capture_value)
	else:
		target.set_base(case.capture.attribute_name, case.starting_capture_value)
	target.set_base(case.output_attribute, case.starting_output_base)

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = case.capture
	var effect: GameplayEffect = Factory.infinite([_add_modifier(case.output_attribute, magnitude)])

	Factory.apply(target.asc, effect, source.owner)
	assert_almost_eq(
		target.current_of(case.output_attribute),
		case.starting_output_base + case.starting_capture_value,
		TOLERANCE, case.label + ": starting reading"
	)

	if case.change_is_on_source:
		source.set_base(case.capture.attribute_name, case.changed_capture_value)
	else:
		target.set_base(case.capture.attribute_name, case.changed_capture_value)
	assert_almost_eq(
		target.current_of(case.output_attribute),
		case.starting_output_base + case.changed_capture_value,
		TOLERANCE, case.label + ": reacted on its own"
	)


func test_snapshot_persistent_contribution_does_not_change() -> void:
	source.set_base(ATTACK, 10.0)
	target.set_base(DEFENSE, 5.0)
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	var effect: GameplayEffect = Factory.infinite([_add_modifier(DEFENSE, magnitude)])

	Factory.apply(target.asc, effect, source.owner)
	assert_almost_eq(target.current_of(DEFENSE), 15.0, TOLERANCE)

	source.set_base(ATTACK, 999.0)
	assert_almost_eq(target.current_of(DEFENSE), 15.0, TOLERANCE, "frozen - no subscription was ever made")


## Reparenting the watched actor must not silently freeze the buff it feeds.
##
## The registry drops a binding on the observed ASC's `tree_exiting`, meaning
## to catch the source despawning while its buff is still on the target. But
## `tree_exiting` also fires when a node is merely moved - `remove_child` then
## `add_child`, which is what reparenting and pooling are - and the binding does
## not come back.
func test_a_live_binding_survives_the_watched_actor_being_reparented() -> void:
	source.set_base(ATTACK, 10.0)
	target.set_base(DEFENSE, 5.0)

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	Factory.apply(target.asc, Factory.infinite([_add_modifier(DEFENSE, magnitude)]), source.owner)
	assert_almost_eq(target.current_of(DEFENSE), 15.0, TOLERANCE, "the buff reads the source")

	var holder: Node = source.owner.get_parent()
	holder.remove_child(source.owner)
	holder.add_child(source.owner)

	source.set_base(ATTACK, 40.0)
	assert_almost_eq(
		target.current_of(DEFENSE), 45.0, TOLERANCE,
		"the source only moved; the buff still reads it"
	)


## A source that really goes away is survivable, and the buff it fed keeps its
## last reading rather than blanking to zero - the documented behaviour of a
## capture that stops resolving.
##
## The hazard being pinned is the process, not the number. Assigning a freed
## instance to a typed property stops Godot 4.7.2 at the debugger and never
## returns, so a reevaluation that reached a departed source took the whole
## game down. It is refused before the context is built now.
func test_a_departed_source_leaves_the_buff_at_its_last_reading() -> void:
	source.set_base(ATTACK, 10.0)
	target.set_base(DEFENSE, 5.0)

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	var active: ActiveGameplayEffect = Factory.apply(
		target.asc, Factory.infinite([_add_modifier(DEFENSE, magnitude)]), source.owner
	)
	assert_almost_eq(target.current_of(DEFENSE), 15.0, TOLERANCE, "the buff reads the source")

	var departing: Node = source.owner
	source = null
	departing.free()

	# Anything that recomposes the target now walks the same contribution the
	# departed source used to feed.
	target.set_base(ATTACK, 3.0)
	assert_almost_eq(
		target.current_of(DEFENSE), 15.0, TOLERANCE,
		"the buff kept what it last resolved to rather than blanking"
	)

	target.asc.effects.remove(active)
	assert_eq(
		target.asc.effects.live_magnitudes._bindings.size(), 0,
		"and removing the effect let the binding go"
	)


func test_a_direct_live_self_cycle_is_rejected() -> void:
	target.set_base(ATTACK, 10.0)
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.TARGET, ATTACK)
	var effect: GameplayEffect = Factory.infinite([_add_modifier(ATTACK, magnitude)])

	watch_signals(target.asc)
	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied, "a modifier cannot read LIVE the exact attribute it writes")
	assert_signal_emitted(target.asc, "effect_application_refused")
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE, "refused, so nothing landed at all")


## Effect A on the target reads DEFENSE (LIVE) into ATTACK; effect B reads
## ATTACK (LIVE) into DEFENSE. Neither is a direct self-cycle - each reads an
## attribute it does not itself write - so both are accepted, and reacting to
## one another is exactly what would hang without the reevaluation cap.
func test_an_indirect_live_cycle_does_not_hang_and_reports_it() -> void:
	target.set_base(ATTACK, 10.0)
	target.set_base(DEFENSE, 5.0)

	var attack_reads_defense: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	attack_reads_defense.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.TARGET, DEFENSE)
	Factory.apply(target.asc, Factory.infinite([_add_modifier(ATTACK, attack_reads_defense)]), source.owner)

	var defense_reads_attack: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	defense_reads_attack.capture = _live_capture(GameplayAttributeCaptureDefinition.Actor.TARGET, ATTACK)

	watch_signals(target.asc)
	# Applying B is what closes the loop: it reads ATTACK once to compute its
	# own contribution, and that write to DEFENSE is what the cascade starts
	# from.
	Factory.apply(target.asc, Factory.infinite([_add_modifier(DEFENSE, defense_reads_attack)]), source.owner)

	assert_signal_emitted(target.asc, "live_magnitude_cycle_aborted")
	assert_true(is_finite(target.current_of(ATTACK)), "the cascade was cut, not left to diverge")
	assert_true(is_finite(target.current_of(DEFENSE)), "same for the other side")
