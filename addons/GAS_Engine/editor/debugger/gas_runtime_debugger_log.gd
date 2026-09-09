## Everything the running game has said, kept and answerable.
##
## Held apart from the `EditorDebuggerPlugin` that receives it, and for a reason
## that is not tidiness: an `EditorDebuggerPlugin` refuses to be instantiated
## outside the editor - `new()` answers with nothing at all - so anything living
## on it is code no test can construct, let alone drive. The plugin is the door
## and this is what is behind it, so the deciding is the half that can be
## proven.
##
## Everything here is a value. Nothing draws, nothing reaches into the editor,
## and nothing assumes a thread: `_capture()` runs on whatever thread the
## debugger hands it, and the less that happens there the smaller the surface on
## which a mistake takes the editor down.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasRuntimeDebuggerLog extends RefCounted

## How much history is worth keeping.
##
## A trace of a busy entity is thousands of events a minute, and an editor that
## kept all of them would eventually be an editor that stops. The newest are
## what somebody is looking at; the oldest are what they scrolled past.
const KEPT_EVENTS: int = 500

## The last thing each watched entity said about itself, by its instance id.
var _snapshots: Dictionary[int, GasRuntimeSnapshot] = {}

## What has happened, oldest first.
var _events: Array[GasTraceEvent] = []


## Take one message from the running game, and say whether it was understood.
##
## A message that is not one is dropped rather than kept: a row for every
## malformed packet is a debugger showing somebody its own bugs, which is worse
## than showing them nothing.
func take(message: String, data: Array) -> bool:
	if data.is_empty():
		return false
	var said: Dictionary = data[0]

	if message == GasDebugMessage.SNAPSHOT:
		var snapshot: GasRuntimeSnapshot = GasRuntimeSnapshot.from_message(said)
		if snapshot == null:
			return false
		_snapshots[snapshot.asc_id] = snapshot
		return true

	if message == GasDebugMessage.TRACE:
		var event: GasTraceEvent = GasTraceEvent.from_message(said)
		if event == null:
			return false
		_events.append(event)
		if _events.size() > KEPT_EVENTS:
			_events = _events.slice(_events.size() - KEPT_EVENTS)
		return true

	return false


## The snapshot that arrived with a message, for a caller announcing it.
##
## Read after `take()` rather than returned by it, because `take()` answers a
## different question - was this understood - and one function answering two is
## one a caller has to check twice.
func last_snapshot() -> GasRuntimeSnapshot:
	return _snapshots.values().back() if not _snapshots.is_empty() else null


func last_event() -> GasTraceEvent:
	return _events.back() if not _events.is_empty() else null


#region What is known
## What that entity last said about itself, or null when it has said nothing.
func snapshot(asc_id: int) -> GasRuntimeSnapshot:
	return _snapshots.get(asc_id)


## Every entity being reported on.
func watched_ids() -> Array[int]:
	var found: Array[int] = []
	for asc_id: int in _snapshots:
		found.append(asc_id)
	return found


## Everything that has happened, oldest first.
func events() -> Array[GasTraceEvent]:
	return _events.duplicate()


## Everything that happened to one entity.
##
## By id rather than by object, for the reason the snapshot gives: the object is
## in another process.
func events_for(asc_id: int) -> Array[GasTraceEvent]:
	var found: Array[GasTraceEvent] = []
	for event: GasTraceEvent in _events:
		if event.asc_id == asc_id:
			found.append(event)
	return found


## Everything of one kind, for somebody hunting one sort of mistake.
func events_of(kind: GasDebugMessage.Kind) -> Array[GasTraceEvent]:
	var found: Array[GasTraceEvent] = []
	for event: GasTraceEvent in _events:
		if event.kind == kind:
			found.append(event)
	return found


## Forget everything. A new run of the game is a new subject, and history from
## the last one is history about something that is no longer there.
func forget() -> void:
	_snapshots.clear()
	_events.clear()
#endregion
