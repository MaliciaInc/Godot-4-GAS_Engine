## The graph surface: the cards, the cables between them, and the gestures.
##
## A GraphEdit rather than a Control that drew its own. Everything the old
## surface did by hand - hit-testing cards, tracking a drag, drawing cables from
## one card's edge to another's, panning and zooming a scaled world - is what
## the widget already does, and every hand-written version of it was a second
## opinion about where a port was. They disagreed, and a wire drawn to the wrong
## edge is a graph that lies about the file.
##
## Nothing here writes to the file. A gesture becomes a *request* - this wire,
## these positions, this call - and the screen decides what, if anything, that
## means for the source. The cards and cables then come back from the reread, so
## what is on screen is always something the file actually says. A canvas that
## drew a connection the moment it was dropped would be showing a wire that does
## not exist yet and may never.
##
## Support nodes are not drawn. An `if false:` wrapper and an `else:` are lines
## the reader must account for and a person must never be shown a card for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCanvas extends GraphEdit

## Above this, a card is worth reading. Below the second, it is worth seeing.
const DETAIL_FULL: float = 0.75
const DETAIL_TITLE: float = 0.40

const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0

## What is being worked on now.
signal selection_changed(picked: Array[StringName])

## Where cards ended up, once somebody stopped dragging them.
##
## Once, with everything that moved, rather than per frame: a person dragging a
## card across the canvas did one thing, and the file should record one thing.
signal nodes_positioned(positions: Dictionary[StringName, Vector2])

## Somebody dropped a wire between two pins, or pulled one off.
signal connection_requested(edge: ComposerGraph.Connection)
signal disconnection_requested(edge: ComposerGraph.Connection)

signal menu_requested(node_id: StringName, screen_position: Vector2)

## Somebody dragged a call out of the palette onto the canvas.
signal node_requested(call_id: StringName, graph_position: Vector2)

## What a card's row was set to. Passed straight through, because only the
## screen can say whether the file may be written.
signal value_edited(node_id: StringName, position: int, source_text: String)

## Alt-click on a pin: take everything off it, whatever is on it.
signal break_all_requested(node_id: StringName, port_id: StringName)

## Ctrl-drag from one pin to another: move what is on the first onto the second.
signal move_connections_requested(
	from_node_id: StringName,
	from_port_id: StringName,
	to_node_id: StringName,
	to_port_id: StringName
)

## Right-click on a pin, rather than on the card it belongs to.
signal pin_context_requested(
	node_id: StringName, port_id: StringName, screen_position: Vector2
)

## A wire dragged out of a pin and let go over empty canvas. Which pin it came
## out of decides what may be offered; the two positions are where on the graph
## the new card belongs and where on the window the menu opens, and they are
## different points.
signal connection_to_empty_requested(
	node_id: StringName,
	port_id: StringName,
	graph_position: Vector2,
	screen_position: Vector2
)
signal connection_from_empty_requested(
	node_id: StringName,
	port_id: StringName,
	graph_position: Vector2,
	screen_position: Vector2
)

## Right-click on the canvas itself, where there is neither pin nor card.
signal graph_menu_requested(graph_position: Vector2, screen_position: Vector2)

## The widget's own keyboard requests, passed on as intentions. What each one
## does to the file is the screen's, so that a menu item and a shortcut cannot
## end up meaning two different things.
signal delete_requested()
signal copy_requested()
signal cut_requested()
signal paste_requested()
signal duplicate_requested()


## What is drawn, and how. The canvas owns the surface and the gestures; the
## painter owns the cards on it.
var _painter: ComposerPainter = ComposerPainter.new()

## What moved during a drag, worked out from where everything was when it began.
var _drag: ComposerCardDrag = ComposerCardDrag.new()

## The detail level the cards were last drawn at.
var _detail: ComposerCard.Detail = ComposerCard.Detail.FULL

## Set while `reveal()` is moving the selection itself, so the several
## announcements that takes are reported as the one change it is.
var _revealing: bool = false

## What a mouse event on this canvas meant, if it meant anything.
var _gestures: ComposerCanvasGestures = ComposerCanvasGestures.new()


func _ready() -> void:
	# What kind of GraphEdit this is, and why, is written down beside the
	# settings themselves rather than here among the wiring.
	ComposerCanvasSettings.apply(self, ZOOM_MIN, ZOOM_MAX)
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	node_selected.connect(_on_node_selected)
	node_deselected.connect(_on_node_selected)
	begin_node_move.connect(_on_move_begun)
	end_node_move.connect(_on_move_ended)
	popup_request.connect(_on_popup_request)
	gui_input.connect(_on_gui_input)
	_painter.value_edited.connect(
		func _typed(node_id: StringName, position: int, written: String) -> void:
			value_edited.emit(node_id, position, written)
	)
	connection_to_empty.connect(_on_connection_to_empty)
	connection_from_empty.connect(_on_connection_from_empty)
	# The widget's own shortcuts, taken as the requests they are. Bound here
	# rather than in a chord table of this project's own, because two handlers
	# for one key is a key that does one thing sometimes.
	delete_nodes_request.connect(_on_delete_request)
	copy_nodes_request.connect(func _asked() -> void: copy_requested.emit())
	cut_nodes_request.connect(func _asked() -> void: cut_requested.emit())
	paste_nodes_request.connect(func _asked() -> void: paste_requested.emit())
	duplicate_nodes_request.connect(func _asked() -> void: duplicate_requested.emit())


#region Showing a graph
## Draw `graph`. What that means is the painter's; this owns the surface.
func show_graph(graph: ComposerGraph) -> void:
	await _painter.paint(self, graph)
	_apply_detail()
#endregion


#region Gestures on a pin
## Alt-click clears a pin; Ctrl-drag moves what is on it somewhere else.
##
## Watched through the `gui_input` signal rather than by overriding
## `_gui_input`. GraphEdit handles input in C++, so a GDScript override replaces
## that handling and cannot call it - dragging a card, drawing a wire,
## box-selecting and panning would all stop the moment this file existed. The
## signal is emitted first and the widget's own handler runs after it unless the
## event was accepted, which is exactly the "take these two, leave the rest"
## this needs.
func _on_gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_on_key(key)
		return

	_acted_on(_gestures.read(event, _painter.cards(), zoom))


## Say what the gesture asked for, and keep the event from the widget when it
## was one of ours.
##
## Only when it was one of ours: an ordinary click has to go on to GraphEdit, to
## pick a card up or to start a wire, and accepting it here would leave the
## canvas unusable.
func _acted_on(meant: ComposerCanvasGestures.Reading) -> void:
	if not meant.is_consumed():
		return
	accept_event()
	if meant.kind == ComposerCanvasGestures.Kind.BREAK:
		break_all_requested.emit(meant.from.node_id, meant.from.port_id)
		return
	if meant.kind == ComposerCanvasGestures.Kind.MOVE:
		move_connections_requested.emit(
			meant.from.node_id, meant.from.port_id, meant.to.node_id, meant.to.port_id
		)


## Arrows nudge what is picked; Home brings the graph back into view.
##
## Only reached when the canvas itself has focus, which is what keeps these off
## a person typing into a card: a value editor with the caret in it is the
## focused control, and the keys go there instead.
func _on_key(key: InputEventKey) -> void:
	var meant: ComposerCanvasGestures.Reading = ComposerCanvasGestures.read_key(key)
	if meant.kind == ComposerCanvasGestures.Kind.FRAME:
		frame_picked()
		accept_event()
		return
	if meant.kind != ComposerCanvasGestures.Kind.NUDGE:
		return

	# One press, one placement, one thing to undo - however many cards moved.
	var moved: Dictionary[StringName, Vector2] = {}
	for id: StringName in picked():
		moved[id] = _painter.cards()[id].position_offset + meant.by
	if not moved.is_empty():
		nodes_positioned.emit(moved)
	accept_event()


## Put everything picked on screen, or everything when nothing is.
func frame_picked() -> void:
	var shown: Array[StringName] = picked()
	if shown.is_empty():
		shown = _painter.cards().keys()
	if shown.is_empty():
		return

	var bounds: Rect2 = Rect2(_painter.cards()[shown[0]].position_offset, Vector2.ZERO)
	for id: StringName in shown:
		bounds = bounds.expand(_painter.cards()[id].position_offset)
		bounds = bounds.expand(_painter.cards()[id].position_offset + _painter.cards()[id].size)
	scroll_offset = bounds.get_center() * zoom - size * 0.5
#endregion


#region Turning a released wire into a question
## A wire let go over nothing. Which pin it left tells the screen what may be
## offered, and where it was let go is where the new card goes.
##
## The widget reports the release in its own coordinates, so it is turned into a
## point on the graph here - the one place that knows what the scroll and the
## zoom are.
func _on_connection_to_empty(from_node: StringName, from_port: int, at: Vector2) -> void:
	var port: StringName = ComposerPins.port_of(_painter.cards(), from_node, from_port, true)
	if not port.is_empty():
		connection_to_empty_requested.emit(
			from_node, port, graph_point_of(at), at + global_position
		)


func _on_connection_from_empty(to_node: StringName, to_port: int, at: Vector2) -> void:
	var port: StringName = ComposerPins.port_of(_painter.cards(), to_node, to_port, false)
	if not port.is_empty():
		connection_from_empty_requested.emit(
			to_node, port, graph_point_of(at), at + global_position
		)
#endregion


#region Turning a gesture into a request
## A wire dropped or pulled off, in the graph's own words.
##
## Both go through one translation and differ only in what is said afterwards.
## Written twice, the two would be two chances for one of them to be told about
## a change to the numbering and the other not.
func _on_connection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	_report(connection_requested, from_node, from_port, to_node, to_port)


func _on_disconnection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	_report(disconnection_requested, from_node, from_port, to_node, to_port)


func _report(
	asking: Signal,
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	var edge: ComposerGraph.Connection = ComposerPins.edge_of(
		_painter.cards(), from_node, from_port, to_node, to_port
	)
	if edge != null:
		asking.emit(edge)


## Delete arrives with the nodes it means, but the screen already works on what
## is picked - and the widget only ever sends what is selected. Passed on as the
## same intention the menu's Remove is, so both go one way to one place.
func _on_delete_request(_nodes: Array) -> void:
	delete_requested.emit()


func _on_node_selected(_node: Object) -> void:
	if _revealing:
		return
	selection_changed.emit(picked())


func _on_move_begun() -> void:
	_drag.begun(_painter.cards())


## Say what actually moved, once.
func _on_move_ended() -> void:
	var moved: Dictionary[StringName, Vector2] = _drag.ended(_painter.cards())
	if not moved.is_empty():
		nodes_positioned.emit(moved)


## Which card was right-clicked, and where to put the menu.
##
## The pointer is asked for directly in both spaces rather than derived from
## `at_position`, whose space is not something to be guessed at: the card is
## found in this control's own coordinates and the menu is placed in the
## viewport's.
func _on_popup_request(_at_position: Vector2) -> void:
	var here: Vector2 = get_local_mouse_position()
	var there: Vector2 = get_global_mouse_position()
	# A pin first, because a pin sits on a card and asking about the card would
	# answer for both. What can be done to a wire and what can be done to a
	# statement are different lists.
	var pin: ComposerPins.Pin = ComposerPins.at(_painter.cards(), zoom, here)
	if pin.is_found():
		pin_context_requested.emit(pin.node_id, pin.port_id, there)
		return
	var card: StringName = _card_at(here)
	if not card.is_empty():
		# Right-clicking a card selects it, the way it does in every other
		# editor. Without this the menu's items would act on whatever was picked
		# before - somebody right-clicks one node and removes another.
		if not picked().has(card):
			reveal(card)
		menu_requested.emit(card, there)
		return
	graph_menu_requested.emit(graph_point_of(here), there)
#endregion


#region Answering questions about it
func picked() -> Array[StringName]:
	var found: Array[StringName] = []
	# Read in the order the graph holds, not the order they were clicked: a
	# selection that reads back shuffled makes every operation over it arbitrary.
	for id: StringName in _painter.cards():
		if _painter.cards()[id].selected:
			found.append(id)
	return found


## Bring one node into view and make it the selection.
func reveal(node_id: StringName) -> void:
	if not _painter.cards().has(node_id):
		return
	# Selecting each card in turn makes the widget announce each one, including
	# the moment in the middle when nothing is selected at all. A listener that
	# redraws on every announcement would clear the Inspector and fill it again
	# for one reveal.
	_revealing = true
	for id: StringName in _painter.cards():
		_painter.cards()[id].selected = id == node_id
	_revealing = false
	var card: ComposerCard = _painter.cards()[node_id]
	scroll_offset = card.position_offset * zoom - size * 0.5 + card.size * 0.5 * zoom
	selection_changed.emit(picked())


func card_for(node_id: StringName) -> ComposerCard:
	return _painter.cards().get(node_id)


## Where a point in this canvas's own coordinates falls on the graph.
##
## The one place that turns the two apart, because the scroll and the zoom are
## the canvas's and nothing outside it should have to know them.
func graph_point_of(at: Vector2) -> Vector2:
	return (at + scroll_offset) / zoom


## Which card is under a point in this canvas's own coordinates, or nothing.
func _card_at(at: Vector2) -> StringName:
	var point: Vector2 = graph_point_of(at)
	for id: StringName in _painter.cards():
		var card: ComposerCard = _painter.cards()[id]
		if Rect2(card.position_offset, card.size).has_point(point):
			return id
	return &""
#endregion


#region Zoom
## How much of a card is worth drawing at this zoom.
static func detail_at(at_zoom: float) -> ComposerCard.Detail:
	if at_zoom >= DETAIL_FULL:
		return ComposerCard.Detail.FULL
	return ComposerCard.Detail.TITLE if at_zoom >= DETAIL_TITLE else ComposerCard.Detail.BLOCK


## Watched rather than listened for.
##
## GraphEdit has a `zoom` property and, in this engine version, no signal that
## says it changed: `ClassDB.class_get_signal_list("GraphEdit")` lists
## connection, selection, movement and scroll signals and nothing about zoom. So
## the value is read once a frame and acted on when it crosses a threshold -
## which is also the only version that reacts however the zoom was changed,
## wheel or toolbar alike.
func _process(_delta: float) -> void:
	if detail_at(zoom) != _detail:
		_apply_detail()


func _apply_detail() -> void:
	_detail = detail_at(zoom)
	_painter.show_detail(_detail)
#endregion


#region Taking a call from the palette
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var graph: ComposerGraph = _painter.graph()
	if graph == null or not graph.is_editable() or typeof(data) != TYPE_DICTIONARY:
		return false
	var carried: Dictionary = data
	return carried.has(ComposerCatalog.DRAGGED_CALL)


## Take it, and say where on the graph it landed.
##
## Where it landed, not what it landed on. The old surface looked for a card
## under the pointer and inserted after it, which meant a drop was two different
## operations depending on a pixel.
func _drop_data(at: Vector2, data: Variant) -> void:
	var carried: Dictionary = data
	var call_id: StringName = carried[ComposerCatalog.DRAGGED_CALL]
	node_requested.emit(call_id, graph_point_of(at))
#endregion
