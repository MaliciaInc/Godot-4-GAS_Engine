## Fire at a fixed interval, runtime-driven - never a SceneTreeTimer, which
## would answer to a different clock than the one `advance_time` already
## drives every other task and effect from.
##
## Owed repetitions are derived from elapsed time, the same shape
## GameplayEffectScheduler already uses for periodic ticks: a frame long
## enough to span three intervals owes three, capped and carried as backlog
## rather than dropped or run unbounded in one frame.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskRepeat extends GameplayAbilityTask

## Same cap as GameplayEffectScheduler.MAX_PERIODIC_CATCH_UP_TICKS_PER_FRAME -
## one enormous delta must not run thousands of repetitions in one update.
const MAX_CATCH_UP_REPETITIONS_PER_UPDATE: int = 64

signal repeated(index: int)

var interval: float = 0.0
## 0 means indefinite - never finishes on its own, only on cancel.
var repetitions: int = 0

var elapsed: float = 0.0
var completed_count: int = 0


static func create(
	ability: GameplayAbility, interval_seconds: float, repeat_count: int = 0
) -> AbilityTaskRepeat:
	var task: AbilityTaskRepeat = AbilityTaskRepeat.new()
	task.owner_ability = ability
	task.interval = maxf(interval_seconds, 0.0)
	task.repetitions = maxi(repeat_count, 0)
	return task


## Whether the interval can ever come round. Zero would owe an unbounded
## number of repetitions in any frame at all, and a non-finite one owes none
## ever; neither is a slow repeat, both are a repetition that is never due.
func _interval_is_usable() -> bool:
	return is_finite(interval) and interval > 0.0


## The same refusal AbilityTaskPlayAnimationAndWait makes when its player
## cannot play what it was asked for: a task whose configuration can never be
## satisfied ends itself, so a caller awaiting it is released rather than
## stopping for good. An exported float defaults to 0.0, which is exactly how
## an interval nobody set in the inspector arrives here - and before this it
## produced a task that fired nothing and ended nothing, forever.
func _on_start() -> void:
	if not _interval_is_usable():
		cancel(GameplayAbilityTask.CancelReason.MANUAL)


func advance_time(delta: float) -> void:
	# Asked again rather than trusted from `_on_start()`: `interval` is public,
	# and a running task assigned a fresh one must not divide by it either.
	if not _interval_is_usable():
		return
	elapsed += maxf(delta, 0.0)
	# Nudged by the same epsilon ActiveGameplayEffect ticks against, so a
	# repetition due at exactly `interval` is never judged a frame late by
	# accumulated float error.
	var due: int = floori((elapsed + ActiveGameplayEffect.TICK_EPSILON_SECONDS) / interval)
	var owed: int = maxi(due - completed_count, 0)
	var payable: int = mini(owed, MAX_CATCH_UP_REPETITIONS_PER_UPDATE)
	for _tick: int in payable:
		completed_count += 1
		repeated.emit(completed_count - 1)
		if is_finished():
			return
		if repetitions > 0 and completed_count >= repetitions:
			succeed()
			return
