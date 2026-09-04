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

var _graph: ComposerGraph = null
var _cards: Dictionary[StringName, ComposerCard] = {}
var _port_types: ComposerPortTypes = ComposerPortTypes.new()

## Where the selected cards were when a move began. Held only between
## `begin_node_move` and `end_node_move`, so there is nothing to keep in step.
var _moving_from: Dictionary[StringName, Vector2] = {}

## The detail level the cards were last drawn at.
var _detail: ComposerCard.Detail = ComposerCard.Detail.FULL

## Set while `reveal()` is moving the selection itself, so the several
## announcements that takes are reported as the one change it is.
var _revealing: bool = false


func _ready() -> void:
	right_disconnects = true
	minimap_enabled = false
	show_grid = true
	zoom_min = ZOOM_MIN
	zoom_max = ZOOM_MAX
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	node_selected.connect(_on_node_selected)
	node_deselected.connect(_on_node_selected)
	begin_node_move.connect(_on_move_begun)
	end_node_move.connect(_on_move_ended)
	popup_request.connect(_on_popup_request)


#region Showing a graph
## Draw `graph`, cards and cables alike.
##
## The pins are typed before any card is built, because a card asks the type
## table what number and colour each of its pins is. Cables are connected last,
## once every card exists to connect to.
func show_graph(graph: ComposerGraph) -> void:
	_graph = graph
	_clear()
	if graph == null:
		return

	_port_types.register_into(self, graph)
	var placements: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(graph)
	var placed: Dictionary[StringName, Vector2] = ComposerLayout.origins(placements)
	for node: ComposerNode in graph.visible_nodes():
		_add_card(node, node.layout_position if node.has_layout_position else placed[node.id])

	# A card has no measured size until a frame has passed, and the layout's
	# second pass needs those sizes: a column is only as wide as what it holds.
	await get_tree().process_frame
	# A redraw that arrived while this one was waiting owns the canvas now. Its
	# `_clear()` already freed the cards this continuation was about to place and
	# connect, and `_graph` is whatever it set - possibly null.
	if _graph != graph:
		return
	_place(placements)
	_connect_all()
	_apply_detail()


func _add_card(node: ComposerNode, at: Vector2) -> void:
	var card: ComposerCard = ComposerCard.new()
	add_child(card)
	card.build(node, _port_types)
	card.position_offset = at
	card.value_edited.connect(_on_value_edited)
	_cards[node.id] = card


## Put every card where the layout wants it, now that they have been measured.
##
## A card the person has moved themselves keeps where they put it. Overruling
## that on every redraw would move somebody's graph back under them each time
## they edited a field.
func _place(placements: Dictionary[StringName, Vector2i]) -> void:
	var widths: Dictionary[StringName, float] = {}
	var heights: Dictionary[StringName, float] = {}
	for id: StringName in _cards:
		widths[id] = _cards[id].size.x
		heights[id] = _cards[id].size.y

	var placed: Dictionary[StringName, Vector2] = ComposerLayout.origins(
		placements, widths, heights
	)
	for id: StringName in _cards:
		var model: ComposerNode = _graph.find_node(id)
		if model != null and not model.has_layout_position and placed.has(id):
			_cards[id].position_offset = placed[id]


## Draw every cable the graph holds, translated into the widget's numbering.
##
## A connection the cards cannot express is skipped rather than approximated:
## the alternative is a cable drawn to whichever pin happened to be at that
## index, which looks exactly like a real one.
func _connect_all() -> void:
	clear_connections()
	for wire: ComposerGraph.Connection in _graph.connections:
		if not _cards.has(wire.from_node) or not _cards.has(wire.to_node):
			continue
		var out: int = _cards[wire.from_node].right_index_for_port(wire.from_port)
		var into: int = _cards[wire.to_node].left_index_for_port(wire.to_port)
		if out < 0 or into < 0:
			continue
		connect_node(StringName(wire.from_node), out, StringName(wire.to_node), into)


func _clear() -> void:
	clear_connections()
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		remove_child(card)
		card.queue_free()
	_cards.clear()
	_moving_from.clear()
#endregion


#region Turning a gesture into a request
## A dropped wire, in the graph's own words.
func _on_connection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	var edge: ComposerGraph.Connection = _edge(from_node, from_port, to_node, to_port)
	if edge != null:
		connection_requested.emit(edge)


func _on_disconnection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	var edge: ComposerGraph.Connection = _edge(from_node, from_port, to_node, to_port)
	if edge != null:
		disconnection_requested.emit(edge)


## Translate two drawn pin numbers into the two ports they stand for.
##
## Nothing is emitted when either end cannot be named. The widget's numbering is
## its own, and a request carrying a port id nobody recognises would be answered
## by the controller with a refusal about a pin the person never touched.
func _edge(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> ComposerGraph.Connection:
	if not _cards.has(from_node) or not _cards.has(to_node):
		return null
	var out: StringName = _cards[from_node].right_port_of_drawn(from_port)
	var into: StringName = _cards[to_node].left_port_of_drawn(to_port)
	if out.is_empty() or into.is_empty():
		return null
	return ComposerReader.wire(from_node, out, to_node, into)


func _on_node_selected(_node: Object) -> void:
	if _revealing:
		return
	selection_changed.emit(picked())


## Remember where everything selected started out.
func _on_move_begun() -> void:
	_moving_from.clear()
	for id: StringName in _cards:
		if _cards[id].selected:
			_moving_from[id] = _cards[id].position_offset


## Say what actually moved, once.
##
## Only the cards whose position changed, and nothing at all when none did: a
## click that happens to be a one-pixel drag is not somebody rearranging their
## graph, and recording it would put an undo in front of the edit they meant.
func _on_move_ended() -> void:
	var moved: Dictionary[StringName, Vector2] = {}
	for id: StringName in _moving_from:
		if not _cards.has(id):
			continue
		var now: Vector2 = _cards[id].position_offset
		if now != _moving_from[id]:
			moved[id] = now
	_moving_from.clear()
	if not moved.is_empty():
		nodes_positioned.emit(moved)


## Which card was right-clicked, and where to put the menu.
##
## The pointer is asked for directly in both spaces rather than derived from
## `at_position`, whose space is not something to be guessed at: the card is
## found in this control's own coordinates and the menu is placed in the
## viewport's. The version this replaced passed one point to both and had the
## screen add the canvas offset again, so the menu opened as far from the
## pointer as the palette is wide.
func _on_popup_request(_at_position: Vector2) -> void:
	menu_requested.emit(_card_at(get_local_mouse_position()), get_global_mouse_position())


func _on_value_edited(
	node_id: StringName, position: int, source_text: String
) -> void:
	value_edited.emit(node_id, position, source_text)
#endregion


#region Answering questions about it
func picked() -> Array[StringName]:
	var found: Array[StringName] = []
	# Read in the order the graph holds, not the order they were clicked: a
	# selection that reads back shuffled makes every operation over it arbitrary.
	for id: StringName in _cards:
		if _cards[id].selected:
			found.append(id)
	return found


## Bring one node into view and make it the selection.
func reveal(node_id: StringName) -> void:
	if not _cards.has(node_id):
		return
	# Selecting each card in turn makes the widget announce each one, including
	# the moment in the middle when nothing is selected at all. A listener that
	# redraws on every announcement would clear the Inspector and fill it again
	# for one reveal.
	_revealing = true
	for id: StringName in _cards:
		_cards[id].selected = id == node_id
	_revealing = false
	var card: ComposerCard = _cards[node_id]
	scroll_offset = card.position_offset * zoom - size * 0.5 + card.size * 0.5 * zoom
	selection_changed.emit(picked())


func card_for(node_id: StringName) -> ComposerCard:
	return _cards.get(node_id)


## Which card is under a point in this canvas's own coordinates, or nothing.
func _card_at(at: Vector2) -> StringName:
	var point: Vector2 = (at + scroll_offset) / zoom
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
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
	for id: StringName in _cards:
		_cards[id].show_detail(_detail)
#endregion


#region Taking a call from the palette
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if _graph == null or not _graph.is_editable() or typeof(data) != TYPE_DICTIONARY:
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
	node_requested.emit(call_id, (at + scroll_offset) / zoom)
#endregion
