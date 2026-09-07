## The editor's side of the debugger: the door a running game speaks through.
##
## A real `EditorDebuggerPlugin`, which is the only thing that can hear a
## running game. The distinction it exists to hold: selecting an ASC in a scene
## being edited shows what somebody authored, and this shows what is happening -
## tags that are on, effects ticking, an ability half way through. Those are
## different questions, and a tool that answered the first while somebody was
## asking the second is worse than one that answered neither.
##
## Almost nothing lives here. `_capture()` runs on whatever thread the debugger
## hands it and is the one place a mistake takes the editor down with it, so
## what happens there is: hand the message to the log, and announce what the log
## made of it. Everything that decides anything is `GasRuntimeDebuggerLog`,
## which can be constructed and therefore proven - this cannot, because an
## `EditorDebuggerPlugin` refuses to exist outside the editor.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GasRuntimeDebuggerPlugin extends EditorDebuggerPlugin

## What makes a message ours. Read from the vocabulary rather than spelled
## again here, for the reason the vocabulary itself gives.
const PREFIX: String = GasDebugMessage.CAPTURE

signal snapshot_arrived(snapshot: GasRuntimeSnapshot)
signal trace_arrived(event: GasTraceEvent)

## What the game has said. See GasRuntimeDebuggerLog for why it is not here.
var log: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()


## Whether this plugin wants a message.
##
## Answered by the prefix rather than by listing the two names: a message this
## addon sends and this does not claim is one the debugger reports as unhandled,
## which reads as a broken editor rather than as a new message.
func _has_capture(capture: String) -> bool:
	return capture == PREFIX


func _capture(message: String, data: Array, _session_id: int) -> bool:
	if not log.take(message, data):
		return false

	if message == GasDebugMessage.SNAPSHOT:
		snapshot_arrived.emit(log.last_snapshot())
	else:
		trace_arrived.emit(log.last_event())
	return true

