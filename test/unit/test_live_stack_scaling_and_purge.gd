## What a stacked LIVE contribution is worth, and what a purge leaves running.
##
## Two things a stack has to agree about. A magnitude resolved once, at
## application, is multiplied by the stack count; a LIVE one, re-resolved every
## time its capture moves, was not - so an effect was worth two stacks until
## something it watched changed, and one stack from then on. The scaling is now
## one function, asked by both paths.
##
## And a purge is an extraction, not a removal: it takes an effect's tags and
## contributions out inside a transaction that may still roll back. What it did
## not take out were the receipts nothing else owns - the LIVE bindings still
## wired to attributes, and the persistent cues still on screen - so a cleansed
## effect went on reacting and went on being drawn.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"
const AURA: StringName = &"Cue.Aura"
const CLEANSED: StringName = &"Effect.Cleansable"

var source: ASCFixture = null
var target: ASCFixture = null
var manager: CueManagerScript = null


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)
	manager = target.asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, AURA)


func after_each() -> void:
	CueProbe.uninstall(manager, AURA)
	source = null
	target = null
	manager = null


#region Getting there
func _live_from_source(attribute_name: StringName) -> GameplayAttributeBasedMagnitude:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE,
		attribute_name,
		GameplayAttributeCaptureDefinition.Value.CURRENT,
		GameplayAttributeCaptureDefinition.Policy.LIVE
	)
	return magnitude


func _live_modifier(
	output_attribute: StringName, operation: GameplayEffectModifier.Operation
) -> GameplayEffectModifier:
	var modifier: GameplayEffectModifier = Factory.modifier(output_attribute, operation, 0.0)
	modifier.magnitude = _live_from_source(ATTACK)
	return modifier


## An infinite effect that stacks by source and scales with the count.
func _stacking_live(operation: GameplayEffectModifier.Operation) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [_live_modifier(DEFENSE, operation)]
	return Factory.stacked(
		Factory.infinite(modifiers),
		GameplayEffect.StackingType.AGGREGATE_BY_SOURCE,
		4,
		true
	)
#endregion


#region A stack is worth its count, whichever path resolved it
## What two stacks of a LIVE magnitude are worth, before and after it moves.
##
## B10. The application path multiplied the magnitude by the stack count and the
## LIVE update path did not, so an effect was worth two stacks until something
## it watched changed and one stack from then on. Both columns are asserted
## because only the pair separates the two paths: the first is what application
## resolved, the second is what the binding re-resolved, and the bug is that
## they disagreed.
##
## Every operation, because the scaling happens to the magnitude before the
## operation sees it: a MULTIPLY whose factor was scaled wrongly is wrong in a
## way an ADD would never show.
##
##     [what it is, operation, attack, moved to, defense, after applying, after moving]
func _operations() -> Array:
	return [
		["added", GameplayEffectModifier.Operation.ADD, 7.0, 12.0, 5.0, 19.0, 29.0],
		["multiplied", GameplayEffectModifier.Operation.MULTIPLY, 2.0, 3.0, 5.0, 20.0, 30.0],
		["divided", GameplayEffectModifier.Operation.DIVIDE, 2.0, 4.0, 40.0, 10.0, 5.0],
		["overridden", GameplayEffectModifier.Operation.OVERRIDE, 3.0, 4.0, 5.0, 6.0, 8.0],
	]


func test_two_stacks_are_worth_two_whether_applied_or_re_resolved() -> void:
	var rows: Array = _operations()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var operation: GameplayEffectModifier.Operation = row[1]
		var attack: float = row[2]
		var moved_to: float = row[3]
		var defense: float = row[4]
		var applied: float = row[5]
		var moved: float = row[6]

		before_each()
		source.set_base(ATTACK, attack)
		target.set_base(DEFENSE, defense)
		var effect: GameplayEffect = _stacking_live(operation)
		Factory.apply(target.asc, effect, source.owner)
		Factory.apply(target.asc, effect, source.owner)

		assert_almost_eq(
			target.current_of(DEFENSE),
			applied,
			TOLERANCE,
			"%s: two stacks, as applied" % described
		)

		# A different value, so what is read next came from the binding
		# re-resolving and not from the application that first resolved it.
		source.set_base(ATTACK, moved_to)

		assert_almost_eq(
			target.current_of(DEFENSE),
			moved,
			TOLERANCE,
			"%s: still two stacks after the capture moved" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every operation was asked")
#endregion


#region What a purge leaves behind
## An effect that reacts and is drawn, so a purge has both kinds of receipt to
## finish.
func _watched_and_drawn() -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [
		_live_modifier(DEFENSE, GameplayEffectModifier.Operation.ADD)
	]
	return Factory.with_persistent_cues(
		Factory.granting(Factory.infinite(modifiers), [CLEANSED]), [AURA]
	)


## Reached the same way the existing LIVE battery reaches it: the registry keeps
## its bindings private, and counting them is the only way to see a receipt that
## nothing else in the world reflects.
func _bindings() -> int:
	return target.asc.effects.live_magnitudes._bindings.size()


## An effect whose application cleanses whatever grants that tag.
##
## This is the path a purge transaction actually opens on: an incoming effect
## that removes others, extracted provisionally before the incoming one's own
## outcome is known. `remove_active_effects()` is the ordinary removal instead,
## and finishes its own receipts - a test driving that would be green either
## way, which is how this one started out.
func _cleanser(tag: StringName, output_attribute: StringName = DEFENSE) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(output_attribute, 1.0)]
	return Factory.removing_effects_with_tags(Factory.instant(modifiers), [tag])


func _cues_on_screen() -> int:
	var count: int = 0
	for child: Node in target.asc.get_effect_target().get_children():
		if child is GameplayCueNotify:
			count += 1
	return count


## A cleansed effect stops reacting and stops being drawn.
##
## B11. The purge took the tags and the contributions out and left the rest: the
## LIVE binding stayed wired, so a cleansed buff went on recomputing against an
## attribute it no longer contributed to, and the persistent cue stayed on
## screen with nothing behind it.
func test_a_purge_finishes_the_receipts_nothing_else_owns() -> void:
	source.set_base(ATTACK, 7.0)
	Factory.apply(target.asc, _watched_and_drawn(), source.owner)
	assert_eq(_bindings(), 1, "it is watching something")
	assert_eq(_cues_on_screen(), 1, "and it is on screen")

	assert_not_null(
		Factory.apply(target.asc, _cleanser(CLEANSED), source.owner), "the cleanse landed"
	)
	assert_eq(target.asc.effects.active_count(), 0, "and took the effect with it")

	assert_eq(_bindings(), 0, "and it stopped watching")
	assert_eq(_cues_on_screen(), 0, "and stopped being drawn")


## A purge that does not happen changes nothing, and changes it once.
##
## The other half, and the reason `finalize_purged` is not called from the
## rollback: an extraction that is put back must leave exactly the receipts it
## started with - not none, and not two.
func test_a_purge_that_rolls_back_leaves_one_binding_and_one_cue() -> void:
	source.set_base(ATTACK, 7.0)
	var active: ActiveGameplayEffect = Factory.apply(
		target.asc, _watched_and_drawn(), source.owner
	)
	assert_not_null(active, "it was applied")

	# A cleanser that cannot be applied: it extracts the effect provisionally
	# and then fails its own evaluation, so the transaction rolls the extraction
	# back. Naming an attribute nothing has is the deterministic way to fail
	# after the purge has already opened.
	var doomed: GameplayEffect = _cleanser(CLEANSED, &"no_such_attribute")
	var refused: GameplayEffectApplicationResult = Factory.apply_result(
		target.asc, doomed, source.owner
	)
	assert_false(refused.is_ok(), "the cleanser itself was refused")

	assert_eq(_bindings(), 1, "the binding is still there, and once")
	assert_eq(_cues_on_screen(), 1, "and so is the cue")
	assert_eq(target.asc.effects.active_count(), 1, "and the effect is still running")
	assert_true(active.state_attached, "with its receipts still attached")
#endregion
