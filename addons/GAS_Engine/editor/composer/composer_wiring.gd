## Where every cable and every port lands on a card.
##
## Split out of the canvas because it is a different question. The canvas knows
## what is on screen and how big it is; this knows that an input sits on the
## left edge, an output on the right, and that they stack downwards from the
## title so a cable arrives pointing at the name of the node it reaches.
##
## Flow is horizontal, so execution and data arrive on the same sides and are
## told apart by the shape drawn for them. Splitting them across sides instead
## would make a graph that has to be read in two directions at once.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerWiring extends RefCounted

## Where a card's first port sits, measured down from its top edge. Level with
## the title, so a wire arrives pointing at the node's name.
const PORT_INSET: float = 33.0
const PORT_PITCH: float = 28.0


static func draw(
	graph: ComposerGraph, cards: Dictionary[StringName, ComposerCard],
	wires: Control, beads: Control
) -> void:
	var wired: Dictionary[String, bool] = {}
	for wire: ComposerGraph.Connection in graph.connections:
		var from: Vector2 = _port_point(graph, cards, wire.from_node, wire.from_port)
		var to: Vector2 = _port_point(graph, cards, wire.to_node, wire.to_port)
		ComposerWire.draw_into(wires, from, to)
		ComposerWire.bead_into(beads, from)
		ComposerWire.bead_into(beads, to)
		wired[_key(wire.from_node, wire.from_port)] = true
		wired[_key(wire.to_node, wire.to_port)] = true

	# Every remaining port still gets drawn, as an outline. A card showing only
	# its wired ports looks like a node that takes nothing.
	for node: ComposerNode in graph.nodes:
		for port: ComposerNode.Port in node.ports:
			if wired.has(_key(node.id, port.id)):
				continue
			ComposerWire.ring_into(beads, _port_point(graph, cards, node.id, port.id))


static func _key(node_id: StringName, port_id: StringName) -> String:
	return "%s/%s" % [node_id, port_id]


## Where a port sits on its card's edge.
##
## Inputs on the left, outputs on the right: flow is horizontal, and execution
## and data are told apart by the shape drawn for them rather than by which side
## they arrive on. Splitting them across sides would make a graph that has to be
## read in two directions at once.
static func _port_point(
	graph: ComposerGraph, cards: Dictionary[StringName, ComposerCard],
	node_id: StringName, port_id: StringName
) -> Vector2:
	var card: ComposerCard = cards.get(node_id)
	var node: ComposerNode = graph.find_node(node_id) if graph != null else null
	if card == null or node == null:
		return Vector2.ZERO

	var index: int = 0
	var port: ComposerNode.Port = node.find_port(port_id)
	var outgoing: bool = port != null and port.direction == ComposerNode.PortDirection.OUTPUT
	for other: ComposerNode.Port in node.ports:
		if other.id == port_id:
			break
		if (other.direction == ComposerNode.PortDirection.OUTPUT) == outgoing:
			index += 1

	var down: float = minf(
		PORT_INSET + float(index) * PORT_PITCH, maxf(card.size.y - ComposerTheme.PAD_Y, 0.0)
	)
	return card.position + Vector2(card.size.x if outgoing else 0.0, down)
