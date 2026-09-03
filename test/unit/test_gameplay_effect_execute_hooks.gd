## Pre/Post GameplayEffect execute hooks: GameplayEffectExecuteData,
## AttributeSet.pre_gameplay_effect_execute/post_gameplay_effect_execute.
##
## These hooks exist for a narrower case than pre_attribute_change/
## post_attribute_change: only a base mutation an effect actually executes -
## INSTANT, a periodic tick, an ExecCalc output - reaches them. A plain
## DURATION/INFINITE contribution never does, because it never stages a base
## write at all.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const HEALTH: StringName = TestAttributeSet.HEALTH
const MANA: StringName = TestAttributeSet.MANA
const ATTACK: StringName = TestAttributeSet.ATTACK


## A calculation that returns a fixed delta - the ExecCalc path, distinct from
## a standard modifier, per the evaluator's own split.
class FlatDamage extends GameplayExecutionCalculation:
	var attribute: StringName = TestAttributeSet.HEALTH
	var delta: float = -10.0

	func execute(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var produced: Dictionary[StringName, float] = {}
		produced[attribute] = delta
		return produced


## Records every pre/post execute-hook call and every post_attribute_change
## call, and optionally rejects or rewrites a proposal - configured per test
## via Callables rather than one subclass per scenario. Keeps
## TestAttributeSet's real Health/MaxHealth clamp so the hooks are proven to
## compose with the pre-existing base clamp, not tested against a stub that
## has none.
class RecordingAttributeSet extends TestAttributeSet:
	var pre_calls: Array[GameplayEffectExecuteData] = []
	var post_calls: Array[GameplayEffectExecuteData] = []
	var post_attribute_change_names: Array[StringName] = []

	## Returning true rejects; called with the same data pre_calls recorded.
	var reject_when: Callable = Callable()
	## Called before returning true, so it can call data.set_proposed_base().
	var modify_proposal: Callable = Callable()
	## Called from inside post_gameplay_effect_execute, to observe state at
	## the exact moment a post hook runs - e.g. reading current_value there.
	var on_post: Callable = Callable()

	func pre_gameplay_effect_execute(data: GameplayEffectExecuteData) -> bool:
		pre_calls.append(data)
		if modify_proposal.is_valid():
			modify_proposal.call(data)
		if reject_when.is_valid() and reject_when.call(data):
			return false
		return true

	func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
		post_calls.append(data)
		if on_post.is_valid():
			on_post.call(data)

	func post_attribute_change(
		asc: Node, attribute_name: StringName, old_value: float, new_value: float
	) -> void:
		super.post_attribute_change(asc, attribute_name, old_value, new_value)
		post_attribute_change_names.append(attribute_name)


var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var recording: RecordingAttributeSet = null


func before_each() -> void:
	fixture = Fixture.create("ExecuteHookOwner", RecordingAttributeSet)
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	recording = fixture.attributes as RecordingAttributeSet
	# The suite drives periodic ticks itself, deterministically.
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null
	recording = null


func _tick(delta: float) -> void:
	asc.scheduler.advance_time(delta)


#region Which paths trigger the hooks
func test_instant_pre() -> void:
	fixture.set_base(HEALTH, 100.0)
	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	assert_eq(recording.pre_calls.size(), 1, "one base mutation, one pre call")
	assert_eq(recording.pre_calls[0].attribute_name, HEALTH)
	assert_almost_eq(recording.pre_calls[0].requested_base, 80.0, TOLERANCE)
	assert_null(recording.pre_calls[0].effect_handle, "INSTANT never gets a handle")


func test_periodic_pre() -> void:
	fixture.set_base(HEALTH, 50.0)
	var active: ActiveGameplayEffect = Factory.apply(
		asc, Factory.infinite_periodic([Factory.add(HEALTH, -1.0)], 1.0)
	)
	# Grant-time evaluation already ran once (and committed nothing, since a
	# periodic effect's first-application mutations are tick mutations) -
	# cleared here so the assertion below measures ticks alone.
	recording.pre_calls.clear()

	_tick(1.0)

	assert_eq(recording.pre_calls.size(), 1, "one tick, one pre call")
	assert_almost_eq(recording.pre_calls[0].requested_base, 49.0, TOLERANCE)
	assert_eq(recording.pre_calls[0].effect_handle, active.handle, "a tick carries its own effect's handle")


func test_execution_pre() -> void:
	fixture.set_base(HEALTH, 100.0)
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [FlatDamage.new()]
	Factory.apply(asc, effect)

	assert_eq(recording.pre_calls.size(), 1, "an ExecCalc output is still one base mutation")
	assert_eq(recording.pre_calls[0].attribute_name, HEALTH)
	assert_almost_eq(recording.pre_calls[0].requested_base, 90.0, TOLERANCE)


func test_duration_contribution_no_pre() -> void:
	Factory.apply(asc, Factory.duration([Factory.add(ATTACK, 5.0)], 10.0))
	assert_true(recording.pre_calls.is_empty(), "a plain DURATION contribution never stages a base write")
#endregion


#region Atomicity and rejection
func test_reject_atomic() -> void:
	fixture.set_base(HEALTH, 100.0)
	fixture.set_base(MANA, 50.0)
	recording.reject_when = func(data: GameplayEffectExecuteData) -> bool:
		return data.attribute_name == MANA

	var effect: GameplayEffect = Factory.instant([Factory.add(HEALTH, -20.0), Factory.add(MANA, -10.0)])
	var result: GameplayEffectApplicationResult = Factory.apply_result(asc, effect)

	assert_eq(result.status, GameplayEffectApplicationResult.Status.EVALUATION_FAILED)
	assert_eq(result.evaluation_status, AttributeEvaluationResult.Status.GAMEPLAY_EFFECT_EXECUTE_REJECTED)
	assert_eq(result.error_attribute_name, MANA)
	# The whole evaluation failed before anything committed - HEALTH, staged
	# and accepted before MANA was ever rejected, was never written either.
	assert_almost_eq(fixture.base_of(HEALTH), 100.0, TOLERANCE, "the first mutation never committed")
	assert_almost_eq(fixture.base_of(MANA), 50.0, TOLERANCE)


func test_modify_proposal() -> void:
	fixture.set_base(HEALTH, 100.0)
	recording.modify_proposal = func(data: GameplayEffectExecuteData) -> void:
		data.set_proposed_base(data.requested_base + 15.0)

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	# requested_base was 80.0; the hook raised the proposal to 95.0.
	assert_almost_eq(fixture.base_of(HEALTH), 95.0, TOLERANCE, "the modified proposal is what committed")


func test_nonfinite_modify_reject() -> void:
	fixture.set_base(HEALTH, 100.0)
	var setter_accepted: Array[bool] = [true]
	recording.modify_proposal = func(data: GameplayEffectExecuteData) -> void:
		setter_accepted[0] = data.set_proposed_base(NAN)

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	assert_false(setter_accepted[0], "set_proposed_base refuses a non-finite value")
	# A well-behaved hook that gets false back leaves proposed_base untouched,
	# so the original requested value is what commits.
	assert_almost_eq(fixture.base_of(HEALTH), 80.0, TOLERANCE)
#endregion


#region Post-commit ordering
func test_post_after_commit() -> void:
	fixture.set_base(HEALTH, 100.0)
	var seen_current_during_post: Array[float] = [-1.0]
	recording.on_post = func(_data: GameplayEffectExecuteData) -> void:
		seen_current_during_post[0] = fixture.current_of(HEALTH)

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	assert_eq(recording.post_calls.size(), 1)
	assert_almost_eq(seen_current_during_post[0], 80.0, TOLERANCE, "recompose already ran before post fires")


func test_post_sees_committed() -> void:
	fixture.set_base(HEALTH, 100.0)
	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	assert_eq(recording.post_calls.size(), 1)
	assert_almost_eq(recording.post_calls[0].committed_base, 80.0, TOLERANCE)


func test_multiattribute_post_order_deterministic() -> void:
	fixture.set_base(HEALTH, 100.0)
	fixture.set_base(MANA, 50.0)
	var effect: GameplayEffect = Factory.instant([Factory.add(HEALTH, -5.0), Factory.add(MANA, -5.0)])

	for _run: int in 3:
		recording.post_calls.clear()
		Factory.apply(asc, effect)
		assert_eq(recording.post_calls.size(), 2)
		assert_eq(recording.post_calls[0].attribute_name, HEALTH, "modifier declaration order, every run")
		assert_eq(recording.post_calls[1].attribute_name, MANA)


func test_no_duplicate_post_attribute_change_semantics() -> void:
	fixture.set_base(HEALTH, 100.0)
	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -20.0)]))

	assert_eq(recording.post_calls.size(), 1, "post_gameplay_effect_execute fires once")
	assert_eq(
		recording.post_attribute_change_names, [HEALTH] as Array[StringName],
		"post_attribute_change still fires exactly once too, neither hook duplicating the other"
	)
#endregion


#region Clamp metadata and the base-clamp regression the hooks must not break
func test_clamp_metadata() -> void:
	fixture.set_base(HEALTH, 100.0)
	var seen_committed: Array[float] = [-1.0]
	recording.on_post = func(data: GameplayEffectExecuteData) -> void:
		seen_committed[0] = data.committed_base

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -500.0)]))

	assert_almost_eq(recording.pre_calls[0].requested_base, -400.0, TOLERANCE, "the unclamped proposal")
	assert_almost_eq(seen_committed[0], 0.0, TOLERANCE, "pre_attribute_base_change still floors it at zero")


## The exact scenario AttributeSet's own doc comment describes: with only
## pre_attribute_change, 500 damage against 100 health leaves base=-400 and a
## later heal of 30 arrives at 0 instead of 30. The execute hooks must not
## reopen that: the base clamp they wrap around is unchanged.
func test_500_damage_heal_regression() -> void:
	fixture.set_base(HEALTH, 100.0)

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, -500.0)]))
	assert_almost_eq(fixture.base_of(HEALTH), 0.0, TOLERANCE, "clamped, not -400")
	assert_almost_eq(fixture.current_of(HEALTH), 0.0, TOLERANCE)

	Factory.apply(asc, Factory.instant([Factory.add(HEALTH, 30.0)]))
	assert_almost_eq(fixture.base_of(HEALTH), 30.0, TOLERANCE, "the heal landed on the floored base")
	assert_almost_eq(fixture.current_of(HEALTH), 30.0, TOLERANCE)
#endregion
