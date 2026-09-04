## Every gesture that changes a wire, and the one door they all go through.
##
## The canvas reports what somebody did; this turns it into a call on
## `ComposerConnectionController` and says whether the file moved. Nothing else
## sits between them, which is the point: the screen used to hold a handler per
## gesture, and each one was a chance for a new gesture to reach the document by
## a slightly different route with a slightly different idea of what to do
## afterwards.
##
## It listens to the canvas itself rather than being wired up signal by signal.
## A gesture added to the canvas is connected here, beside the others, instead of
## in a list somewhere else that has to be remembered.
##
## Nothing here draws. It says `changed` and the screen decides what to redraw,
## because only the screen knows what else is on the screen.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerWiringRoutes extends RefCounted

## The file moved. Everything drawn from it is now out of date.
signal changed()

## Why a gesture did nothing. Passed on from the controller unchanged: a refusal
## a person cannot read is a tool that ignored them.
signal refused(message: String)

var _wires: ComposerConnectionController = ComposerConnectionController.new()
var _document: ComposerDocument = null


func _init() -> void:
	_wires.refused.connect(func _said(message: String) -> void: refused.emit(message))


func bind(document: ComposerDocument) -> void:
	_document = document
	_wires.bind(document)


## Hear every wiring gesture the canvas reports.
func listen_to(canvas: ComposerCanvas) -> void:
	canvas.connection_requested.connect(_on_connection_requested)
	canvas.disconnection_requested.connect(_on_disconnection_requested)
	canvas.break_all_requested.connect(break_pin)
	canvas.move_connections_requested.connect(move_pin)


#region What each gesture means
func _on_connection_requested(edge: ComposerGraph.Connection) -> void:
	_announce(_wires.connect_edge(edge))


func _on_disconnection_requested(edge: ComposerGraph.Connection) -> void:
	_announce(_wires.disconnect_edge(edge))


## Alt-click on a pin, or Break all from its menu: everything on it comes off as
## one step, so one undo puts all of it back.
func break_pin(node_id: StringName, port_id: StringName) -> bool:
	return _announce(_wires.break_all(node_id, port_id))


## Ctrl-drag from one pin to another: all of it moves, or none of it does.
func move_pin(
	from_node_id: StringName,
	from_port_id: StringName,
	to_node_id: StringName,
	to_port_id: StringName
) -> bool:
	return _announce(
		_wires.move_connections(from_node_id, from_port_id, to_node_id, to_port_id)
	)


## Make a call and join it to whatever the drag came out of, as one change.
##
## The statement and the cable together: a person who dragged a wire into empty
## canvas and picked a call did one thing, so there is one thing to undo. A
## version that inserted the call and then connected it would leave a half-made
## node on screen whenever the second half was refused.
func create_and_connect(
	entry: ComposerCatalog.Entry, context: ComposerActionMenu.Context
) -> bool:
	if _document == null or not _document.may_write():
		refused.emit(ComposerDocument.NOTHING_OPEN)
		return false

	var made: ComposerCreation.Result = ComposerCreation.made(
		_document.printed(), _document.graph(), entry, context
	)
	if not made.is_ok():
		refused.emit(made.message)
		return false
	var refusal: ComposerGraph.Diagnostic = _document.commit(made.source)
	if refusal != null:
		refused.emit(refusal.message)
		return false
	return _announce(true)


## Text somebody typed into one argument, through the same door a cable uses.
func rewrite_field(node_id: StringName, position: int, written: String) -> bool:
	return _announce(_wires.rewrite_field(node_id, position, written))


## The Inspector asked for the cable on one argument to come off.
##
## An argument takes one cable, so there is one to find. Named by position
## because that is what a panel showing a list of arguments knows.
func unplug_argument(
	document: ComposerDocument, node_id: StringName, position: int
) -> bool:
	if not document.is_open():
		return false
	var wires: Array[ComposerGraph.Connection] = document.graph().connections_to(
		node_id, StringName(ComposerReader.ARGUMENT % position)
	)
	if wires.is_empty():
		return false
	return _announce(_wires.disconnect_edge(wires[0]))


func _announce(done: bool) -> bool:
	if done:
		changed.emit()
	return done
#endregion
