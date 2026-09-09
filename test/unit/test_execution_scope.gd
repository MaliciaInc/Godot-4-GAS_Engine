## What an execution is handed, what it may keep, and what it may adjust.
##
## Split from test_typed_execution_output.gd, which is about what a calculation
## can say. This is about the other side: the arguments the application carried
## in, the scratch space that must not outlive one run, the adjustments that
## hold only while the calculation is running, and the one factor the engine
## applies to what it decided.
##
## The property under test in three of the four is a negative - that something
## did NOT escape - so each of them looks afterwards at the place it would have
## escaped to, rather than only at what the calculation returned.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const CRITICAL: StringName = &"Hit.Critical"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


## A calculation that records everything it was handed, and leaves a number in
## its own scratch space on the way past.
class Recording extends GameplayExecutionCalculation:
	## Static because the calculation the engine runs is the Resource the effect
	## holds, and a test reading an instance field would be reading whichever
	## copy it happened to keep.
	static var heard_tags: Array[StringName] = []
	static var scratch_after: float = 0.0
	## Whether a run ever started with somebody else's number still in it.
	static var saw_stale: bool = false
	static var read_attack: float = 0.0

	func execute_in(context: GameplayExecutionContext) -> GameplayExecutionOutput:
		heard_tags = context.passed_in_tags.duplicate()
		saw_stale = saw_stale or context.transient.has(&"partial")
		context.transient[&"partial"] = 41.0
		context.transient[&"partial"] = context.transient[&"partial"] + 1.0
		scratch_after = context.transient[&"partial"]
		read_attack = context.adjust(ATTACK, context.target_asc.get_attribute_current(ATTACK))
		var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
		output.modifiers.append(GameplayExecutionOutput.adding(HEALTH, -read_attack))
		return output


## The same, with one adjustment in force while it runs.
class Scoped extends Recording:
	static var adjustment: GameplayExecutionScopedModifier = null

	func scoped_modifiers() -> Array[GameplayExecutionScopedModifier]:
		return [adjustment] as Array[GameplayExecutionScopedModifier]


## A calculation that counted the stack itself and says so.
class CountedItsOwnStack extends GameplayExecutionCalculation:
	static var manual: bool = true

	func execute_typed(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> GameplayExecutionOutput:
		var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
		output.stack_count_handled_manually = manual
		output.modifiers.append(GameplayExecutionOutput.adding(HEALTH, -10.0))
		return output


func before_each() -> void:
	fixture = Fixture.create("Executed")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	fixture.set_base(ATTACK, 20.0)
	fixture.set_base(HEALTH, 100.0)
	Recording.heard_tags = [] as Array[StringName]
	Recording.scratch_after = 0.0
	Recording.read_attack = 0.0
	Recording.saw_stale = false
	Scoped.adjustment = null


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## An instant effect whose only content is one calculation.
func _with(execution: GameplayExecutionCalculation) -> GameplayEffect:
	var effect: GameplayEffect = Factory.instant([] as Array[GameplayEffectModifier])
	effect.executions = [execution] as Array[GameplayExecutionCalculation]
	return effect


## Apply `effect`, having told the application what it was carrying.
func _apply_carrying(effect: GameplayEffect, tags: Array[StringName]) -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(fixture.owner)
	)
	spec.passed_in_tags = tags
	asc.apply_effect_spec(spec)


func _add_adjustment(amount: float) -> GameplayExecutionScopedModifier:
	var modifier: GameplayExecutionScopedModifier = GameplayExecutionScopedModifier.new()
	modifier.attribute = GameplayAttributeRef.new()
	modifier.attribute.attribute_name = ATTACK
	modifier.magnitude = Factory.scalable_magnitude(amount)
	return modifier
#endregion


## The arguments an application carried reach the calculation, and only it.
##
## `passed_in_tags` is deliberately not `dynamic_tags`: those are granted,
## queried and matched against by the whole runtime, and a hit that said it was
## a critical must not leave the target permanently critical.
func test_execution_receives_passed_in_tags() -> void:
	_apply_carrying(_with(Recording.new()), [CRITICAL] as Array[StringName])

	assert_true(Recording.heard_tags.has(CRITICAL), "the calculation was told")
	assert_false(asc.has_tag(CRITICAL), "and the target was not tagged by being told")


## Scratch space lives for one run and is then gone.
##
## Checked from both sides: the calculation could read back what it wrote while
## it was running - a scratch space that lost values would be useless - and
## nothing of it survives on the spec afterwards.
func test_transient_aggregators_do_not_escape_the_execution() -> void:
	var effect: GameplayEffect = _with(Recording.new())
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(fixture.owner)
	)
	asc.apply_effect_spec(spec)

	assert_almost_eq(
		Recording.scratch_after, 42.0, TOLERANCE, "it could read back what it wrote"
	)
	# And a second application of the same effect starts empty. This is the
	# half that would actually break: a context kept on the calculation or on
	# the spec would hand the second hit the first hit's working number.
	asc.apply_effect_spec(
		GameplayEffectSpec.new(effect, GameplayEffectContext.new(fixture.owner))
	)
	assert_false(Recording.saw_stale, "no run began holding another run's number")


## An adjustment changes what the execution reads and nothing else.
##
## Attack is 20 and the adjustment is +30, so the calculation must see 50 - and
## the target's attack must still be 20 afterwards, with no contribution
## registered against it. Both halves, because a scoped modifier that failed to
## apply and one that applied permanently are the two ways to get this wrong.
func test_scoped_modifiers_only_affect_the_execution() -> void:
	Scoped.adjustment = _add_adjustment(30.0)
	_apply_carrying(_with(Scoped.new()), [] as Array[StringName])

	assert_almost_eq(Recording.read_attack, 50.0, TOLERANCE, "the execution saw the adjustment")
	assert_almost_eq(
		fixture.current_of(ATTACK), 20.0, TOLERANCE, "and the attribute never moved"
	)
	assert_almost_eq(
		fixture.current_of(HEALTH), 50.0, TOLERANCE, "the number it decided on landed"
	)


## The stack is applied to an execution's numbers once, or not at all.
##
## Under Unreal's contracts the engine multiplies by the stack count, and a
## calculation that counted them itself says so. Both arms, because the flag
## only means anything against the behaviour it turns off.
##
##     [what the calculation says, what health is left]
func _manual_stack_cases() -> Array:
	return [["it counted them itself", true, 90.0], ["it left it to the engine", false, 80.0]]


func test_manual_stack_count_flag_prevents_the_automatic_second_factor(
	case: Array = use_parameters(_manual_stack_cases())
) -> void:
	var described: String = case[0]
	var manual: bool = case[1]
	var expected: float = case[2]

	asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	CountedItsOwnStack.manual = manual

	var effect: GameplayEffect = _with(CountedItsOwnStack.new())
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(fixture.owner)
	)
	spec.stack_count = 2
	asc.apply_effect_spec(spec)

	assert_almost_eq(fixture.current_of(HEALTH), expected, TOLERANCE, described)
