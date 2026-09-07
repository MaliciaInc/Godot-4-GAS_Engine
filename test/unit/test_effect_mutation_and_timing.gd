## Changing an effect that is already running, and timing that is not a constant.
##
## Mutating a live effect meant reaching in and writing a field. That works
## right up to the moment the write should have been refused, and then nothing
## says so: a level of NaN, a stack count of zero, a handle whose effect ended a
## frame ago. Each is a different mistake and a caller that got `false` for all
## three could not tell which, so each says which now.
##
## And how long an effect lasts can be a magnitude rather than a number - a
## poison whose duration is the caster's intellect - resolved at the moment the
## application knows who it came from, which is the only moment it can be.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const POTENCY: StringName = &"Data.Potency"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Target")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	asc.set_attribute_base(ATTACK, 100.0)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _buff(magnitude: float = 10.0) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(ATTACK, magnitude)]
	return Factory.infinite(modifiers)


func _running(effect: GameplayEffect) -> GameplayEffectHandle:
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_not_null(active, "the effect was applied")
	return active.handle


## A handle to nothing: an effect that has already been removed.
func _stale() -> GameplayEffectHandle:
	var handle: GameplayEffectHandle = _running(_buff())
	asc.remove_active_effect_by_handle(handle)
	return handle
#endregion


#region Refusing, by name
## Every mutation refuses a handle that names nothing, and says which refusal.
##
## One table because the answer is the same for all five, and writing it five
## times is five places for one of them to start answering differently.
func test_every_mutation_refuses_a_handle_that_names_nothing() -> void:
	var stale: GameplayEffectHandle = _stale()
	var answers: Array[GameplayEffectMutationResult] = [
		asc.set_active_effect_level(stale, 2.0),
		asc.set_active_effect_stack_count(stale, 2),
		asc.remove_active_effect_stacks(stale, 1),
		asc.update_active_effect_set_by_caller(stale, POTENCY, 1.0),
		asc.set_active_effect_duration(stale, 5.0),
	]

	for answer: GameplayEffectMutationResult in answers:
		assert_eq(
			answer.status,
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND,
			"a handle to nothing is a handle to nothing"
		)


## A value that is not a value is refused rather than stored.
##
##     [what it is, the mutation, expected status]
func _bad_values() -> Array:
	return [
		["a level that is not a number", "level", NAN],
		["a negative level", "level", -1.0],
		["no stacks at all", "stacks", 0.0],
		["a negative stack count", "stacks", -3.0],
		["a duration of nothing", "duration", 0.0],
	]


func test_a_value_that_is_not_a_value_is_refused() -> void:
	var rows: Array = _bad_values()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var which: String = row[1]
		var value: float = row[2]

		before_each()
		var handle: GameplayEffectHandle = _running(_buff())
		var answer: GameplayEffectMutationResult = null
		match which:
			"level":
				answer = asc.set_active_effect_level(handle, value)
			"stacks":
				answer = asc.set_active_effect_stack_count(handle, int(value))
			_:
				answer = asc.set_active_effect_duration(handle, value)

		assert_eq(
			answer.status,
			GameplayEffectMutationResult.Status.INVALID_VALUE,
			"%s: refused as a value" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every bad value was offered")


## Setting a duration on something that has none is the wrong operation, not a
## wrong value.
##
## An INFINITE effect has no end to move and an INSTANT has already happened.
## Reported apart from INVALID_VALUE because a caller can fix a bad number and
## cannot fix asking the wrong question.
func test_setting_a_duration_on_an_effect_that_has_none_says_which_mistake() -> void:
	var handle: GameplayEffectHandle = _running(_buff())

	var answer: GameplayEffectMutationResult = asc.set_active_effect_duration(handle, 5.0)

	assert_eq(
		answer.status,
		GameplayEffectMutationResult.Status.INVALID_OPERATION,
		"an infinite effect has no end to move"
	)
#endregion


#region Changing what is running
## Stacks go up, and the aggregate goes with them.
##
## The second half is the point: a stack count that changed and never reached
## the aggregate is a change nobody in the game can see.
func test_changing_the_stack_count_changes_what_the_effect_is_worth() -> void:
	var stacking: GameplayEffect = Factory.stacked(
		_buff(10.0), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE, 5, true
	)
	var handle: GameplayEffectHandle = _running(stacking)
	assert_almost_eq(asc.get_attribute_current(ATTACK), 110.0, TOLERANCE, "one stack")

	var answer: GameplayEffectMutationResult = asc.set_active_effect_stack_count(handle, 3)

	assert_true(answer.is_ok(), "it took")
	assert_almost_eq(asc.get_attribute_current(ATTACK), 130.0, TOLERANCE, "three stacks")


## Taking off fewer stacks than there are leaves the rest running.
func test_removing_some_stacks_leaves_the_rest() -> void:
	var stacking: GameplayEffect = Factory.stacked(
		_buff(10.0), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE, 5, true
	)
	var handle: GameplayEffectHandle = _running(stacking)
	asc.set_active_effect_stack_count(handle, 3)

	assert_true(asc.remove_active_effect_stacks(handle, 1).is_ok(), "one came off")

	assert_almost_eq(asc.get_attribute_current(ATTACK), 120.0, TOLERANCE, "two are left")
	assert_eq(asc.effects.active_count(), 1, "and it is still running")


## Taking off the last stack takes the effect with it.
##
## Otherwise an effect sits registered at zero stacks, contributing nothing and
## answering every query as though it were there.
func test_removing_the_last_stack_removes_the_effect() -> void:
	var handle: GameplayEffectHandle = _running(_buff(10.0))

	assert_true(asc.remove_active_effect_stacks(handle, 1).is_ok(), "the last one")

	assert_eq(asc.effects.active_count(), 0, "and the effect went with it")
	assert_almost_eq(asc.get_attribute_current(ATTACK), 100.0, TOLERANCE, "unbuffed")


## A running effect's remaining time can be moved.
func test_a_running_effect_can_be_given_longer() -> void:
	var timed: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 10.0)]
	var handle: GameplayEffectHandle = _running(Factory.duration(timed, 5.0))

	assert_true(asc.set_active_effect_duration(handle, 30.0).is_ok(), "extended")

	assert_almost_eq(
		asc.get_effect_duration_remaining(handle), 30.0, TOLERANCE, "and it says so"
	)
#endregion


#region Timing that is not a constant
## A duration authored as a magnitude is resolved when the application is made.
##
## Both halves: the resolved number is used, and an effect that authored no
## magnitude keeps the plain number it was built with - which is every effect
## written before there were magnitudes to author.
func test_a_duration_authored_as_a_magnitude_is_what_the_effect_lasts() -> void:
	var timed: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 10.0)]
	var effect: GameplayEffect = Factory.duration(timed, 5.0)
	effect.duration_magnitude = Factory.scalable_magnitude(42.0)

	var handle: GameplayEffectHandle = _running(effect)

	assert_almost_eq(
		asc.get_effect_duration_remaining(handle),
		42.0,
		TOLERANCE,
		"the magnitude decided, not the number beside it"
	)


func test_an_effect_with_no_magnitude_keeps_the_number_it_was_authored_with() -> void:
	var timed: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 10.0)]

	var handle: GameplayEffectHandle = _running(Factory.duration(timed, 7.0))

	assert_almost_eq(
		asc.get_effect_duration_remaining(handle), 7.0, TOLERANCE, "as authored"
	)
#endregion


## A periodic effect can tick the moment it lands.
##
## Off by default, which is what this engine has always done - the first tick
## comes one period later. Both rows, because "it ticked" is also true of an
## effect whose period simply elapsed, and what separates them is that nothing
## has advanced any clock yet.
func test_a_periodic_effect_ticks_on_application_only_if_it_says_so() -> void:
	var checked: int = 0
	for on_application: bool in [false, true]:
		before_each()
		asc.set_attribute_base(ATTACK, 0.0)
		var ticking: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 1.0)]
		var effect: GameplayEffect = Factory.periodic(ticking, 10.0, 5.0)
		effect.execute_periodic_on_application = on_application

		Factory.apply(asc, effect)

		assert_almost_eq(
			asc.get_attribute_base(ATTACK),
			1.0 if on_application else 0.0,
			TOLERANCE,
			"execute_periodic_on_application=%s, before any clock moved" % on_application
		)
		checked += 1
	assert_eq(checked, 2, "both answers were asked for")


#region What a copy carries
## An application copy keeps the stack count the input carried.
##
## An area effect built at three stacks applies three stacks to everything it
## touches; a copy that reset to one would give every target a third of what was
## aimed at them.
func test_an_application_copy_keeps_the_stack_count_it_came_with() -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		_buff(), GameplayEffectContext.new(fixture.owner), 1.0
	)
	spec.stack_count = 3

	var copy: GameplayEffectSpec = spec.create_application_copy()

	assert_eq(copy.stack_count, 3, "three stacks were aimed, three arrive")


## A magnitude that declares nothing watches nothing, and says so.
##
## The default has to be empty rather than absent: a custom magnitude that reads
## something and declares nothing is resolved once and never again, which is
## correct for a constant and silently wrong for anything else.
func test_a_magnitude_declares_what_it_watches() -> void:
	var constant: GameplayScalableMagnitude = Factory.scalable_magnitude(1.0)

	assert_eq(constant.required_captures().size(), 0, "it reads no attribute")
	assert_eq(constant.external_dependencies().size(), 0, "and nothing outside either")
#endregion
