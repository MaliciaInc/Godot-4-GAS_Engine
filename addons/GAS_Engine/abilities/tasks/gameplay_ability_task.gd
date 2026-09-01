## One awaitable step inside an ability: a wait, a listen, a request for targets.
##
## An ability used to suspend on whatever was convenient - a bare `await`, a
## Timer it created and forgot, a signal it never disconnected. Nothing owned
## those waits, so ending an ability early left them running and a cancelled
## cast could still resume minutes later into an ability that no longer existed.
##
## A task is that wait with an owner and an ending. It finishes exactly once,
## and it finishes on cancellation too: `await task.finished` that only fired on
## success would hang forever the moment anything went wrong, which is precisely
## when the caller most needs to be woken up.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayAbilityTask extends RefCounted


## Where the task is in its one-way trip. Nothing returns to CREATED or RUNNING.
enum State {
	CREATED,
	RUNNING,
	SUCCEEDED,
	CANCELLED,
}


## Why a task ended, when it did not end by succeeding.
##
## Closed and specific: a UI that greys out a cast bar wants to know whether the
## player interrupted it or the ASC was torn down, and a string would make that
## a parsing problem.
enum CancelReason {
	NONE,
	ABILITY_ENDED,
	ABILITY_ABORTED,
	ABILITY_REMOVED,
	ASC_CLEANUP,
	CANCEL_TAG,
	MANUAL,
}


## Emitted exactly once, on success and on cancellation alike.
signal finished(task: GameplayAbilityTask, succeeded: bool, reason: CancelReason)

## The ability this task belongs to. Cancellation is addressed by ability, so a
## task without one cannot be reached and is refused at registration.
var owner_ability: GameplayAbility = null

var state: State = State.CREATED


## What this task is actually waiting for - a tag, an attribute, a handle -
## for the runtime debugger alone. The default, empty, costs nothing and
## every task written before this existed still works; override it in a
## subclass that has something worth naming.
func debug_description() -> String:
	return ""


#region Lifecycle
## Begin waiting. Only a CREATED task starts, and starting only moves it to
## RUNNING - it never reports a result.
func start() -> void:
	if state != State.CREATED:
		return
	state = State.RUNNING
	_on_start()


## End successfully. Only a RUNNING task can succeed: a cancelled task that
## later got what it was waiting for must not report success anyway.
func succeed() -> void:
	if state != State.RUNNING:
		return
	state = State.SUCCEEDED
	_on_finish()
	finished.emit(self, true, CancelReason.NONE)


## End without success. Legal from CREATED as well as RUNNING, because an ASC
## torn down between registration and start still has to release the task.
func cancel(reason: CancelReason) -> void:
	if state != State.CREATED and state != State.RUNNING:
		return
	state = State.CANCELLED
	_on_finish()
	finished.emit(self, false, reason)


func is_finished() -> bool:
	return state == State.SUCCEEDED or state == State.CANCELLED


## Wait for this task to end, whether or not it already has.
##
## `await task.finished` is the obvious spelling and it has a trap. A task can
## end inside `start()` - a threshold already crossed, an animation the player
## does not have - and `AbilityTaskRuntime.register()` starts it before the
## caller is handed the reference back. Awaiting a signal that has already
## fired waits for the next one, and a task fires exactly once, so the ability
## stops there and never resumes.
##
## This is the same wait without the trap, and it keeps the promise this class
## opens with: a caller is woken up however the task ended, including when it
## ended before the caller could ask.
func completed() -> void:
	if is_finished():
		return
	await finished
#endregion


#region Subclass hooks
## Override to begin whatever this task waits on.
##
## Finishing from here is allowed but is the awkward case: the runtime registers
## and connects before it starts a task, so the ending is not lost - but the
## caller does not hold the task yet, so `await task.finished` would wait for an
## emission that has already happened. Three tasks in this library can end
## during `start()` - a threshold already crossed, a tag query already at the
## result it was told to wait for, an animation the player does not have - which
## is why `completed()` exists and why callers should use it.
func _on_start() -> void:
	pass


## Override to release whatever `_on_start` acquired: a connected signal, a
## timer, a listener.
##
## Runs exactly once, on success and on cancellation alike. Putting the release
## here rather than in each ending is what stops a cancelled task from leaving a
## connection behind that fires into an ability that has already closed.
func _on_finish() -> void:
	pass
#endregion


#region Delivery
## The base handlers do nothing. A task hears only what it overrides, so a delay
## is not woken by an unrelated keypress.
func advance_time(_delta: float) -> void:
	pass


func handle_input_pressed(_input_id: int) -> void:
	pass


func handle_input_released(_input_id: int) -> void:
	pass


func handle_gameplay_event(_event: GameplayEventData) -> void:
	pass


func handle_target_data(_data: GameplayAbilityTargetData) -> void:
	pass
#endregion
