## The editor's side of the debugger: the door a running game speaks through,
## and the tab in the Debugger dock it is drawn in.
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
## what happens there is: hand the message to the log, announce what the log
## made of it, and ask for a redraw on the main thread. Everything that decides
## anything is `GasRuntimeDebuggerLog`, and everything that draws is
## `GasRuntimeDebuggerPanel` - both can be constructed and therefore proven, and
## this cannot, because an `EditorDebuggerPlugin` refuses to exist outside the
## editor.
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

## What each running game has said, by debugger session.
##
## One log per session, because two games run side by side - an authority and a
## client - are two subjects, and an instance id in one means nothing in the
## other.
var _logs: Dictionary[int, GasRuntimeDebuggerLog] = {}

## Each session's tab, by instance id rather than by reference: the editor owns
## the tab and frees it when it likes, and a freed tab reaching a typed variable
## stops the editor rather than answering null.
var _panel_ids: Dictionary[int, int] = {}

var _refresh_queued: bool = false


## Whether this plugin wants a message.
##
## Answered by the prefix rather than by listing the two names: a message this
## addon sends and this does not claim is one the debugger reports as unhandled,
## which reads as a broken editor rather than as a new message.
func _has_capture(capture: String) -> bool:
	return capture == PREFIX


## A session is a game being run. It gets a tab of its own in the Debugger dock,
## and each new run starts that tab from nothing.
func _setup_session(session_id: int) -> void:
	var panel: GasRuntimeDebuggerPanel = GasRuntimeDebuggerPanel.new(log_for(session_id))
	_panel_ids[session_id] = panel.get_instance_id()
	var session: EditorDebuggerSession = get_session(session_id)
	session.started.connect(_on_session_started.bind(session_id))
	session.add_session_tab(panel)


func _capture(message: String, data: Array, session_id: int) -> bool:
	var session_log: GasRuntimeDebuggerLog = log_for(session_id)
	if not session_log.take(message, data):
		return false

	if message == GasDebugMessage.SNAPSHOT:
		snapshot_arrived.emit(session_log.last_snapshot())
	else:
		trace_arrived.emit(session_log.last_event())
	_queue_refresh()
	return true


## What one session's game has said.
func log_for(session_id: int) -> GasRuntimeDebuggerLog:
	if not _logs.has(session_id):
		_logs[session_id] = GasRuntimeDebuggerLog.new()
	return _logs[session_id]


## A new run of the game is a new subject, and what the last one said is about
## something that is no longer there.
func _on_session_started(session_id: int) -> void:
	log_for(session_id).forget()
	_queue_refresh()


## Redraw on the main thread, once for however many messages arrived before it.
##
## Deferred because a Control touched from the debugger's thread is an editor
## that crashes some of the time; once because a busy entity says hundreds of
## things a second, and a tab redrawn for each would be the load being debugged.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_panels.call_deferred()


func _refresh_panels() -> void:
	_refresh_queued = false
	for session_id: int in _panel_ids:
		var panel_id: int = _panel_ids[session_id]
		if not is_instance_id_valid(panel_id):
			continue
		var panel: GasRuntimeDebuggerPanel = instance_from_id(panel_id) as GasRuntimeDebuggerPanel
		if panel != null:
			panel.refresh()
