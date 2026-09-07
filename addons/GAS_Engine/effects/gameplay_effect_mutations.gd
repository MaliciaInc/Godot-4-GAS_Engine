## Changing an effect that is already running.
##
## Separate from the component because it is a different job: the component is
## the surface a game talks to, and this is the five things that can be done to
## something already registered - its level, how many of it there are, what its
## caller-supplied values are worth, and how much longer it lasts.
##
## Every one of them answers with which refusal it was rather than with false. A
## level of NaN, a stack count of zero, a handle whose effect ended a frame ago
## and an operation that does not apply to this kind of effect are four
## different mistakes, and a caller told only that it failed can act on none of
## them.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectMutations extends RefCounted


## Change what a running effect is worth, by handle.
##
## Five doors, one shape. Reaching into an ActiveGameplayEffect and writing a
## field works right until the write should have been refused, and then nothing
## says so: a level of NaN, a stack count below one, a handle whose effect ended
## a frame ago. Each is a different mistake and each now says which.
##
## Every one of them recomposes afterwards, because a value that changed and did
## not reach the aggregate is a change nobody can see.
static func set_level(
	runtime: GameplayEffectRuntime, handle: GameplayEffectHandle, level: float
) -> GameplayEffectMutationResult:
	var active: ActiveGameplayEffect = runtime.handles.resolve(handle)
	if active == null:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND
		)
	if not is_finite(level) or level < 0.0:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_VALUE
		)

	active.spec.level = level
	runtime.recompose_and_emit(active.spec)
	return GameplayEffectMutationResult.ok(active)


static func set_stack_count(
	runtime: GameplayEffectRuntime, handle: GameplayEffectHandle, count: int
) -> GameplayEffectMutationResult:
	var active: ActiveGameplayEffect = runtime.handles.resolve(handle)
	if active == null:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND
		)
	if count < 1:
		# Zero stacks is not a stack count, it is a removal, and doing one
		# through the other would leave an effect registered at nothing.
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_VALUE
		)

	return _restacked(runtime, active, count)


## Take stacks off, and remove the effect when the last one goes.
static func remove_stacks(
	runtime: GameplayEffectRuntime, handle: GameplayEffectHandle, count: int
) -> GameplayEffectMutationResult:
	var active: ActiveGameplayEffect = runtime.handles.resolve(handle)
	if active == null:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND
		)
	if count < 1:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_VALUE
		)

	if count >= active.spec.stack_count:
		runtime.remove(active)
		return GameplayEffectMutationResult.ok(active)

	return _restacked(runtime, active, active.spec.stack_count - count)


static func update_set_by_caller(
	runtime: GameplayEffectRuntime, handle: GameplayEffectHandle, tag: StringName, value: float
) -> GameplayEffectMutationResult:
	var active: ActiveGameplayEffect = runtime.handles.resolve(handle)
	if active == null:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND
		)
	if not active.spec.update_set_by_caller(tag, value):
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_VALUE
		)

	runtime.recompose_and_emit(active.spec)
	return GameplayEffectMutationResult.ok(active)


## Change how much longer a running effect lasts.
##
## Only for one that has a duration to change: an INSTANT has already happened
## and an INFINITE has no end to move, and setting one on either would be
## writing a number nothing reads.
static func set_duration(
	runtime: GameplayEffectRuntime, handle: GameplayEffectHandle, seconds: float
) -> GameplayEffectMutationResult:
	var active: ActiveGameplayEffect = runtime.handles.resolve(handle)
	if active == null:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.HANDLE_NOT_FOUND
		)
	if not is_finite(seconds) or seconds <= 0.0:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_VALUE
		)
	if active.get_effect_def().policy != GameplayEffect.DurationPolicy.DURATION:
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.INVALID_OPERATION
		)

	active.spec.duration = seconds
	active.time_remaining = seconds
	return GameplayEffectMutationResult.ok(active)


## Put an effect on a different number of stacks, for real.
##
## Writing `stack_count` and recomposing is not enough and looks like it is: the
## contributions were resolved with the old count, so the aggregate recomposes
## the same numbers it already had. What a stack change means is a
## re-evaluation, which is what a second application of a stacking effect does -
## so this goes the same way, through the same swap.
static func _restacked(
	runtime: GameplayEffectRuntime, active: ActiveGameplayEffect, count: int
) -> GameplayEffectMutationResult:
	active.spec.stack_count = count
	var evaluation: GameplayEffectEvaluationResult = runtime.evaluate_spec(
		active.spec, active.application_order, active.handle
	)
	if not evaluation.is_ok():
		return GameplayEffectMutationResult.refused(
			GameplayEffectMutationResult.Status.EVALUATION_FAILED
		)

	runtime.stacking.replace_stack_state(active, active.spec, evaluation, count)
	runtime.recompose_and_emit(active.spec)
	return GameplayEffectMutationResult.ok(active)
