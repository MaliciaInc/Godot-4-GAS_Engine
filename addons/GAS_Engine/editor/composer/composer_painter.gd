## Putting a graph on a canvas: the cards, where they sit, and the cables.
##
## Drawing and reading input are two jobs, and the canvas was doing both. This is
## the first: it owns the cards, builds them, places them and connects them, and
## knows nothing about what anybody does with a mouse afterwards.
##
## It draws only what the file says. Nothing here decides anything about an
## ability - a cable appears because the graph holds one, and a cable the cards
## cannot express is left undrawn rather than approximated, because a cable drawn
## to whichever pin happened to be at that index looks exactly like a real one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPainter extends RefCounted

## Somebody finished editing a value in one of the cards. Passed straight up: a
## painter does not decide what happens to a file.
signal value_edited(node_id: StringName, position: int, source_text: String)

var _cards: Dictionary[StringName, ComposerCard] = {}
var _port_types: ComposerPortTypes = ComposerPortTypes.new()
var _graph: ComposerGraph = null


func cards() -> Dictionary[StringName, ComposerCard]:
	return _cards


func graph() -> ComposerGraph:
	return _graph


func port_types() -> ComposerPortTypes:
	return _port_types


## Draw `graph` onto `edit`, cards and cables alike.
##
## The pins are typed before any card is built, because a card asks the type
## table what number and colour each of its pins is. Cables are connected last,
## once every card exists to connect to.
func paint(edit: GraphEdit, graph: ComposerGraph) -> void:
	_graph = graph
	clear(edit)
	if graph == null:
		return

	_port_types.register_into(edit, graph)
	var placements: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(graph)
	var placed: Dictionary[StringName, Vector2] = ComposerLayout.origins(placements)
	for node: ComposerNode in graph.visible_nodes():
		_add_card(
			edit, node, node.layout_position if node.has_layout_position else placed[node.id]
		)

	# A card has no measured size until a frame has passed, and the layout's
	# second pass needs those sizes: a column is only as wide as what it holds.
	await edit.get_tree().process_frame
	# A redraw that arrived while this one was waiting owns the canvas now. Its
	# own `clear()` already freed the cards this continuation was about to place
	# and connect, and `_graph` is whatever it set - possibly null.
	if _graph != graph:
		return
	ComposerLayout.settle(_cards, placements, _graph)
	_connect_all(edit)


func _add_card(edit: GraphEdit, node: ComposerNode, at: Vector2) -> void:
	var card: ComposerCard = ComposerCard.new()
	edit.add_child(card)
	card.build(node, _port_types)
	card.position_offset = at
	card.value_edited.connect(
		func _typed(node_id: StringName, position: int, written: String) -> void:
			value_edited.emit(node_id, position, written)
	)
	_cards[node.id] = card


func _connect_all(edit: GraphEdit) -> void:
	edit.clear_connections()
	for wire: ComposerGraph.Connection in _graph.connections:
		var out: int = ComposerPins.drawn_index(_cards, wire.from_node, wire.from_port, true)
		var into: int = ComposerPins.drawn_index(_cards, wire.to_node, wire.to_port, false)
		if out < 0 or into < 0:
			continue
		edit.connect_node(
			StringName(wire.from_node), out, StringName(wire.to_node), into
		)


func clear(edit: GraphEdit) -> void:
	edit.clear_connections()
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		edit.remove_child(card)
		card.queue_free()
	_cards.clear()


## Draw as much of each card as is worth reading at this zoom.
func show_detail(level: ComposerCard.Detail) -> void:
	for id: StringName in _cards:
		_cards[id].show_detail(level)
