## What can be done to the cables on one pin, offered where the pointer is.
##
## Breaking one exact cable is a Blueprint gesture people arrive expecting, and
## the Composer had only "break everything on this pin" - which on a value
## feeding four statements is three cables somebody did not ask to lose. There is
## no hit-testing of curves here and no second wire renderer: the menu was opened
## on a known pin, and the graph already knows which cables touch it. That is
## enough to name each one.
##
## It offers and nothing more. What each entry does to the file is the screen's,
## which is what lets this list grow without any of that growth landing there.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPinMenu extends PopupMenu

## What each entry says, with the far end of the cable filled in.
const BREAK_ONE: String = "Break Link to %s"
const BREAK_ALL: String = "Break All Connections"

## What a pin the person can see, feeding nothing, offers instead of a list of
## nothing: a menu that opens empty reads as a menu that failed.
const NOTHING_ON_IT: String = "Nothing connected"


## One exact cable is to come off.
signal break_link_requested(edge: ComposerGraph.Connection)

## Every cable on that pin is to come off, in one change.
signal break_all_requested(node_id: StringName, port_id: StringName)

## The cables this menu is offering, by the item index that names each one.
##
## Held here and nowhere else, and rebuilt on every open: an index is only
## meaningful against the list it was built from, and a menu that kept the list
## it was opened with last time would break whichever cable happens to sit at
## that number now.
var _edges: Array[ComposerGraph.Connection] = []
var _node_id: StringName = &""
var _port_id: StringName = &""


## Offer what is on that pin, at a point in the viewport.
func open_for(
	graph: ComposerGraph,
	node_id: StringName,
	port_id: StringName,
	screen_position: Vector2
) -> void:
	_node_id = node_id
	_port_id = port_id
	_edges = _cables_of(graph, node_id, port_id)

	clear()
	for edge: ComposerGraph.Connection in _edges:
		add_item(BREAK_ONE % _far_end_of(graph, edge, node_id, port_id))
	if _edges.is_empty():
		add_item(NOTHING_ON_IT)
		set_item_disabled(item_count - 1, true)
	add_separator()
	add_item(BREAK_ALL)

	if not id_pressed.is_connected(_on_id_pressed):
		id_pressed.connect(_on_id_pressed)
	# A popup reused from an earlier open keeps the size it had, so a menu that
	# once held four cables opens with empty space under one.
	reset_size()
	position = Vector2i(screen_position)
	popup()


## The cables on that pin, in the order the statements they reach are written.
##
## By source order rather than by whatever order the graph holds them in: the
## list a person reads has to be the list they see on the canvas, top to bottom,
## or the second entry is the first cable and nobody can tell.
static func _cables_of(
	graph: ComposerGraph, node_id: StringName, port_id: StringName
) -> Array[ComposerGraph.Connection]:
	var found: Array[ComposerGraph.Connection] = graph.connections_for(node_id, port_id)
	found.sort_custom(
		func _by_line(one: ComposerGraph.Connection, other: ComposerGraph.Connection) -> bool:
			return _line_of(graph, one, node_id) < _line_of(graph, other, node_id)
	)
	return found


## Where the statement at the far end of that cable is written.
static func _line_of(
	graph: ComposerGraph, edge: ComposerGraph.Connection, node_id: StringName
) -> int:
	var far: ComposerNode = graph.find_node(
		edge.to_node if edge.from_node == node_id else edge.from_node
	)
	return far.span.first_line if far != null else 0


## What the far end of that cable is called, for a person to pick it out.
static func _far_end_of(
	graph: ComposerGraph,
	edge: ComposerGraph.Connection,
	node_id: StringName,
	port_id: StringName
) -> String:
	var here: bool = edge.from_node == node_id and edge.from_port == port_id
	var far: ComposerNode = graph.find_node(edge.to_node if here else edge.from_node)
	if far == null:
		return String(edge.to_node if here else edge.from_node)
	var pin: ComposerNode.Port = far.find_port(edge.to_port if here else edge.from_port)
	if pin == null or pin.label.is_empty():
		return far.title
	return "%s.%s" % [far.title, pin.label]


func _on_id_pressed(chosen: int) -> void:
	if chosen >= 0 and chosen < _edges.size():
		break_link_requested.emit(_edges[chosen])
		return
	# Everything past the cables is Break All: the separator has no index a
	# person can press, and the disabled line never arrives here.
	break_all_requested.emit(_node_id, _port_id)
