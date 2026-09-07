## What an execution calculation is allowed to say, and what happens to it.
##
## A calculation answered with a dictionary of attribute-to-float, and every
## entry meant one thing: add this much to that. So it could not say that its
## number multiplies, could not say which of two same-named attributes it meant,
## and could not say anything that was not a number at all - that the hit it
## just worked out should also set the target alight, or that it landed but
## should be silent because a hundred of them are landing this frame. It says
## all of it now, and one that only ever added numbers keeps working unchanged.
##
## The other half is the order. An attribute written by an execution AND by a
## standard modifier used to be refused for having no defined order. It has one:
## the execution decides the base, the modifiers compose over what it decided.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Evaluator = preload("res://addons/GAS_Engine/effects/gameplay_effect_evaluator.gd")
const Vehicle = preload("res://test/fixtures/vehicle_attribute_set.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const IMPACT: StringName = &"Cue.Execution.Impact"
const BURNING: StringName = &"Status.Burning"
const VEHICLE_SET: StringName = &"VehicleAttributeSet"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


## A calculation that only knows how to return deltas - which is every
## calculation written before an execution could say anything else.
class LegacyDelta extends GameplayExecutionCalculation:
	var attribute: StringName = &"attack"
	var delta: float = -10.0

	func execute(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var produced: Dictionary[StringName, float] = {}
		produced[attribute] = delta
		return produced


## A calculation that says what it decided, handed to it by the test.
class TypedCalculation extends GameplayExecutionCalculation:
	var output: GameplayExecutionOutput = null

	func execute_typed(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> GameplayExecutionOutput:
		return output


func before_each() -> void:
	fixture = Fixture.create("Calculated")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	fixture.set_base(ATTACK, 100.0)
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, IMPACT)


func after_each() -> void:
	CueProbe.uninstall(manager, IMPACT)
	fixture = null
	asc = null
	manager = null


#region Getting there
## One thing a calculation decided to do to one attribute.
func _write(
	attribute_name: StringName,
	operation: GameplayEffectModifier.Operation,
	magnitude: float,
	set_name: StringName = &""
) -> GameplayExecutionOutput.Modifier:
	var made: GameplayExecutionOutput.Modifier = GameplayExecutionOutput.Modifier.new()
	made.attribute = GameplayAttributeRef.new()
	made.attribute.set_name = set_name
	made.attribute.attribute_name = attribute_name
	made.operation = operation
	made.magnitude = magnitude
	return made


## A calculation saying exactly one thing, which is most of these tests.
func _saying_one(
	attribute_name: StringName,
	operation: GameplayEffectModifier.Operation,
	magnitude: float,
	set_name: StringName = &""
) -> GameplayExecutionOutput:
	var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
	output.modifiers.append(_write(attribute_name, operation, magnitude, set_name))
	return output


func _saying(output: GameplayExecutionOutput) -> TypedCalculation:
	var calculation: TypedCalculation = TypedCalculation.new()
	calculation.output = output
	return calculation


## An effect whose executions are these, and whose modifiers are those.
func _effect(
	executions: Array[GameplayExecutionCalculation],
	modifiers: Array[GameplayEffectModifier],
	lasting: bool = false
) -> GameplayEffect:
	var effect: GameplayEffect = (
		Factory.infinite(modifiers) if lasting else Factory.instant(modifiers)
	)
	effect.executions = executions
	return effect


## The instant effect of one calculation and nothing else.
func _effect_saying(output: GameplayExecutionOutput) -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return _effect([_saying(output)] as Array[GameplayExecutionCalculation], no_modifiers)


func _evaluate(effect: GameplayEffect, mode: int) -> GameplayEffectEvaluationResult:
	var request: GameplayEffectEvaluator.Request = Evaluator.Request.new()
	request.spec = GameplayEffectSpec.new(effect, GameplayEffectContext.new(fixture.owner))
	request.attributes = asc.attributes
	request.owner_asc = asc
	request.application_order = 0
	request.mode = mode
	return Evaluator.evaluate(request)


## Put a second set on the entity, so `health` means two things at once.
func _also_drive_a_vehicle() -> void:
	var both: Array[AttributeSet] = [fixture.attributes, Vehicle.new()]
	asc.share_attributes = true
	asc.attribute_sets = both


## An effect that grants a tag, for a calculation to decide to apply.
func _burn() -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(Factory.infinite(no_modifiers), [BURNING])


func _running_count(effect: GameplayEffect) -> int:
	var count: int = 0
	for active: ActiveGameplayEffect in asc.get_active_effects():
		if active.get_effect_def() == effect:
			count += 1
	return count
#endregion


#region What a calculation can say
## A calculation that only returns deltas lands exactly as it always did.
##
## The adapter is the whole compatibility story: every entry of the dictionary
## becomes one addition, because addition is what every entry meant.
func test_a_calculation_that_only_returns_deltas_lands_as_it_always_did() -> void:
	var legacy: Array[GameplayExecutionCalculation] = [LegacyDelta.new()]
	var no_modifiers: Array[GameplayEffectModifier] = []

	Factory.apply(asc, _effect(legacy, no_modifiers))

	assert_almost_eq(fixture.base_of(ATTACK), 90.0, TOLERANCE, "100 less the ten it took")


## A calculation says how, not only how much.
##
##     [what it decided, which operation, the magnitude, what attack becomes]
func _operations() -> Array:
	return [
		["adding, which is all a dictionary could say", "add", 5.0, 105.0],
		["multiplying", "multiply", 2.0, 200.0],
		["dividing", "divide", 4.0, 25.0],
		["replacing it outright", "override", 42.0, 42.0],
	]


func test_a_calculation_says_how_and_not_only_how_much() -> void:
	var rows: Array = _operations()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var which: String = row[1]
		var magnitude: float = row[2]
		var expected: float = row[3]
		var operation: GameplayEffectModifier.Operation = GameplayEffectModifier.Operation.OVERRIDE
		match which:
			"add":
				operation = GameplayEffectModifier.Operation.ADD
			"multiply":
				operation = GameplayEffectModifier.Operation.MULTIPLY
			"divide":
				operation = GameplayEffectModifier.Operation.DIVIDE

		before_each()
		Factory.apply(asc, _effect_saying(_saying_one(ATTACK, operation, magnitude)))

		assert_almost_eq(fixture.base_of(ATTACK), expected, TOLERANCE, described)
		checked += 1
	assert_eq(checked, rows.size(), "every operation was offered")


## Two writes from one calculation compose, rather than the last one winning.
func test_two_writes_from_one_calculation_both_land() -> void:
	var output: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, 5.0
	)
	output.modifiers.append(_write(ATTACK, GameplayEffectModifier.Operation.MULTIPLY, 2.0))

	Factory.apply(asc, _effect_saying(output))

	assert_almost_eq(fixture.base_of(ATTACK), 210.0, TOLERANCE, "(100 + 5) doubled")
#endregion


#region The order the two mechanisms compose in
## Forty off the top, for the tests that need something written by both.
func _taking_forty() -> Array[GameplayExecutionCalculation]:
	var output: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, -40.0
	)
	return [_saying(output)] as Array[GameplayExecutionCalculation]


## An attribute both mechanisms write is composed in a defined order.
##
## The execution decides the base and the modifier composes over what it
## decided: (100 - 40) doubled. The other order is 100 doubled less 40, which is
## 160 - and this combination used to be refused rather than answered at all.
func test_an_attribute_written_by_both_composes_in_a_defined_order() -> void:
	var effect: GameplayEffect = _effect(_taking_forty(), [Factory.multiply(ATTACK, 2.0)])

	Factory.apply(asc, effect)

	assert_almost_eq(fixture.base_of(ATTACK), 120.0, TOLERANCE, "the execution went first")


## And it is one write, not two: two staged writes would move the base twice and
## fire the execute hook twice for one application, which an AttributeSet
## counting hits, or refusing them, would see as two separate things.
func test_and_the_two_of_them_land_as_a_single_write() -> void:
	var effect: GameplayEffect = _effect(_taking_forty(), [Factory.multiply(ATTACK, 2.0)])

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)

	assert_true(result.is_ok(), "no longer refused")
	assert_eq(result.base_mutations.size(), 1, "one write for one attribute")


## The same order while the effect stays active, where the two mechanisms are
## not even doing the same kind of work: the execution writes the durable base,
## the modifier is a contribution composing over whatever the base is. Same
## rule, and here it is the aggregate's own construction rather than anything
## this pipeline had to arrange.
func test_the_same_order_holds_for_an_effect_that_stays_active() -> void:
	var effect: GameplayEffect = _effect(_taking_forty(), [Factory.multiply(ATTACK, 2.0)], true)

	Factory.apply(asc, effect)

	assert_almost_eq(fixture.base_of(ATTACK), 60.0, TOLERANCE, "the execution wrote the base")
	assert_almost_eq(fixture.current_of(ATTACK), 120.0, TOLERANCE, "and the buff doubled it")
#endregion


#region A write has to land somewhere
## A reference naming a set this entity has not got is refused.
##
## A calculation meaning the vehicle's `health` on somebody who is not driving
## anything must not quietly write the driver's.
func test_a_reference_naming_a_set_that_is_not_here_is_refused() -> void:
	var effect: GameplayEffect = _effect_saying(
		_saying_one(HEALTH, GameplayEffectModifier.Operation.ADD, -5.0, VEHICLE_SET)
	)

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)

	assert_eq(result.status, AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND)
	assert_eq(result.error_attribute_name, HEALTH, "and says which one")
	assert_eq(result.base_mutations.size(), 0, "nothing staged")


## A write the entity cannot aim is refused, and says which name is the problem.
##
## Two sets both declaring `health` make `health` two attributes with one name,
## and every write is addressed by that name. Sending it to whichever set was
## listed first is an answer that changes when somebody reorders the list, and
## reports nothing when it does. One table because the answer must be the same
## whichever mechanism is doing the writing.
##
##     [what is doing the writing, an execution, a standard modifier]
func _ambiguous_writers() -> Array:
	return [
		["an execution", true, false],
		["a standard modifier", false, true],
		["both of them at once", true, true],
	]


func test_a_write_the_entity_cannot_aim_is_refused() -> void:
	var rows: Array = _ambiguous_writers()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var by_execution: bool = row[1]
		var by_modifier: bool = row[2]

		before_each()
		_also_drive_a_vehicle()

		var executions: Array[GameplayExecutionCalculation] = []
		if by_execution:
			var output: GameplayExecutionOutput = _saying_one(
				HEALTH, GameplayEffectModifier.Operation.ADD, -5.0
			)
			executions = [_saying(output)] as Array[GameplayExecutionCalculation]
		var modifiers: Array[GameplayEffectModifier] = []
		if by_modifier:
			modifiers = [Factory.add(HEALTH, 5.0)]

		var result: GameplayEffectEvaluationResult = _evaluate(
			_effect(executions, modifiers), Evaluator.Mode.BASE_MUTATION
		)

		assert_eq(
			result.status,
			AttributeEvaluationResult.Status.AMBIGUOUS_ATTRIBUTE_WRITE,
			"%s: refused rather than aimed by list order" % described
		)
		assert_eq(result.error_attribute_name, HEALTH, "%s: names the attribute" % described)
		assert_eq(result.base_mutations.size(), 0, "%s: nothing staged" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every writer was offered")
#endregion


#region Everything that is not a number
## A calculation can ask for silence, and is otherwise as loud as it ever was.
func test_a_calculation_decides_whether_the_effect_makes_a_sound() -> void:
	var checked: int = 0
	for trigger_cues: bool in [true, false]:
		before_each()
		var output: GameplayExecutionOutput = _saying_one(
			ATTACK, GameplayEffectModifier.Operation.ADD, -1.0
		)
		output.trigger_cues = trigger_cues
		var effect: GameplayEffect = Factory.with_application_cues(
			_effect_saying(output), [IMPACT]
		)

		Factory.apply(asc, effect)

		assert_eq(
			CueProbe.executions(manager, fixture.owner, IMPACT),
			1 if trigger_cues else 0,
			"trigger_cues=%s" % trigger_cues
		)
		assert_almost_eq(fixture.base_of(ATTACK), 99.0, TOLERANCE, "the number landed either way")
		checked += 1
	assert_eq(checked, 2, "both answers were asked for")


## One calculation asking for silence silences the effect.
##
## The alternative is the loudest calculation in an effect deciding for every
## other one, which is not a decision anybody made.
func test_one_calculation_asking_for_silence_is_enough() -> void:
	var loud: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, -1.0
	)
	var quiet: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, -1.0
	)
	quiet.trigger_cues = false

	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.with_application_cues(
		_effect(
			[_saying(loud), _saying(quiet)] as Array[GameplayExecutionCalculation], no_modifiers
		),
		[IMPACT]
	)

	Factory.apply(asc, effect)

	assert_eq(CueProbe.executions(manager, fixture.owner, IMPACT), 0, "silent")
	assert_almost_eq(fixture.base_of(ATTACK), 98.0, TOLERANCE, "both calculations still landed")


## A calculation can apply an effect its own numbers decided on, and that child
## is held to the same recursion limit an authored one is.
##
## An authored chain is decided before the effect is evaluated, which is exactly
## when a calculation's numbers do not exist yet - so "burn them if that hit
## took more than half their health" cannot be authored, only computed. It goes
## through the same chain runtime either way, so a calculation cannot spawn a
## child that escapes the depth accounting an authored one has always been
## held to.
func test_a_calculation_can_apply_an_effect_its_numbers_decided_on() -> void:
	var burn: GameplayEffect = _burn()
	var output: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, -1.0
	)
	output.conditional_effects.append(burn)

	Factory.apply(asc, _effect_saying(output))

	assert_eq(_running_count(burn), 1, "the child was applied")
	assert_true(asc.tags.active_tags().has(BURNING), "and it granted what it grants")
	var depths: Array[int] = []
	for active: ActiveGameplayEffect in asc.get_active_effects():
		if active.get_effect_def() == burn:
			depths.append(active.spec.chain_depth)
	assert_eq(depths, [1] as Array[int], "one deeper than whatever applied it")


## A periodic effect applies them per tick, not once when it lands.
##
## An execution's children follow its numbers, and a periodic effect commits
## none of its numbers at application - its first tick is what does.
func test_a_periodic_effect_applies_them_per_tick_rather_than_at_application() -> void:
	var burn: GameplayEffect = _burn()
	var output: GameplayExecutionOutput = _saying_one(
		ATTACK, GameplayEffectModifier.Operation.ADD, -1.0
	)
	output.conditional_effects.append(burn)

	var no_modifiers: Array[GameplayEffectModifier] = []
	var ticking: GameplayEffect = Factory.infinite_periodic(no_modifiers, 5.0)
	ticking.executions = [_saying(output)] as Array[GameplayExecutionCalculation]
	var active: ActiveGameplayEffect = Factory.apply(asc, ticking)

	assert_eq(_running_count(burn), 0, "nothing of its landed yet, so nothing followed")

	asc.effects.run_periodic_tick(active)

	assert_eq(_running_count(burn), 1, "the tick is what applied it")
	assert_almost_eq(fixture.base_of(ATTACK), 99.0, TOLERANCE, "with the tick's own number")
#endregion
