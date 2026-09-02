## The graph surface: grid, glow, cards, wires, zoom.
##
## Draw order is held by four layers rather than by the order things happen to
## be created in. Wires have to sit behind the cards and beads in front of them,
## but neither can be positioned until the cards have measured themselves - so
## anything that depends on creation order ends up drawing a cable across a card
## or burying a bead underneath one. With layers, each pass fills its own and
## the stacking is a fact of the tree.
##
## Nothing here decides where a node goes. `ComposerLayout` does, in grid
## coordinates, and this is the only place those become pixels - which is what
## lets a card's own measured height push its lane apart without the layout
## knowing anything about geometry.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerCanvas extends Control

const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.1

## Where a card's first port sits, measured down from its top edge. Level with
## the title, so a wire arrives pointing at the node's name.
const PORT_INSET: float = 33.0
const PORT_PITCH: float = 28.0

signal zoom_changed(zoom: float)

var _zoom: float = 1.0
var _graph: ComposerGraph = null
var _placements: Dictionary[StringName, Vector2i] = {}
var _cards: Dictionary[StringName, ComposerCard] = {}

var _grid: ColorRect = null
var _world: Control = null
var _bloom_layer: Control = null
var _wire_layer: Control = null
var _card_layer: Control = null
var _bead_layer: Control = null
var _blooms: Dictionary[StringName, TextureRect] = {}


func _ready() -> void:
	clip_contents = true
	_grid = ColorRect.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.material = ComposerShaders.grid_material(_zoom)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)

	# The chrome never scales, so the world is the only thing zoom touches.
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)

	_bloom_layer = _layer()
	_wire_layer = _layer()
	_card_layer = _layer()
	_bead_layer = _layer()


func _layer() -> Control:
	var layer: Control = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(layer)
	return layer


#region Showing a graph
## Draw `graph`. Positions come from the layout; sizes from the cards.
func show_graph(graph: ComposerGraph) -> void:
	_graph = graph
	_clear()
	if graph == null:
		return

	_placements = ComposerLayout.arrange(graph)
	for node: ComposerNode in graph.nodes:
		_add_card(node)

	# Cards have no measured height until a frame has passed, and every wire
	# endpoint depends on where a card's edges ended up.
	await get_tree().process_frame
	_fit_cards()
	_draw_wires()


func _add_card(node: ComposerNode) -> void:
	var bloom: TextureRect = ComposerTheme.glow_rect(
		ComposerTheme.glow(ComposerTheme.ACCENT, ComposerTheme.BLOOM_STRENGTH)
	)
	_bloom_layer.add_child(bloom)
	_blooms[node.id] = bloom

	var card: ComposerCard = ComposerCard.new()
	card.position = _origin_of(node.id)
	_card_layer.add_child(card)
	card.build(node)
	_cards[node.id] = card


## Grid coordinates become pixels here and nowhere else.
func _origin_of(id: StringName) -> Vector2:
	var at: Vector2i = _placements.get(id, Vector2i.ZERO)
	return Vector2(
		float(at.x) * ComposerTheme.COLUMN_STEP, float(at.y) * ComposerTheme.LANE_STEP
	)


## Trim every card to its content, then hang its glow on the result.
##
## The glow is an ellipse taking the card's own proportions. A circle around a
## short wide card spills far above and below it and stops looking like that
## card's light.
func _fit_cards() -> void:
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		card.fit()
		var bloom: TextureRect = _blooms[id]
		var reach: Vector2 = card.size * ComposerTheme.BLOOM_SCALE
		bloom.position = card.position + card.size * 0.5 - reach * 0.5
		bloom.size = reach
#endregion


#region Wires
func _draw_wires() -> void:
	var wired: Dictionary[String, bool] = {}
	for wire: ComposerGraph.Connection in _graph.connections:
		var from: Vector2 = _port_point(wire.from_node, wire.from_port)
		var to: Vector2 = _port_point(wire.to_node, wire.to_port)
		ComposerWire.draw_into(_wire_layer, from, to)
		ComposerWire.bead_into(_bead_layer, from)
		ComposerWire.bead_into(_bead_layer, to)
		wired[_key(wire.from_node, wire.from_port)] = true
		wired[_key(wire.to_node, wire.to_port)] = true

	# Every remaining port still gets drawn, as an outline. A card showing only
	# its wired ports looks like a node that takes nothing.
	for node: ComposerNode in _graph.nodes:
		for port: ComposerNode.Port in node.ports:
			if wired.has(_key(node.id, port.id)):
				continue
			ComposerWire.ring_into(_bead_layer, _port_point(node.id, port.id))


static func _key(node_id: StringName, port_id: StringName) -> String:
	return "%s/%s" % [node_id, port_id]


## Where a port sits on its card's edge.
##
## Inputs on the left, outputs on the right: flow is horizontal, and execution
## and data are told apart by the shape drawn for them rather than by which side
## they arrive on. Splitting them across sides would make a graph that has to be
## read in two directions at once.
func _port_point(node_id: StringName, port_id: StringName) -> Vector2:
	var card: ComposerCard = _cards.get(node_id)
	var node: ComposerNode = _graph.find_node(node_id) if _graph != null else null
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
#endregion


#region Zoom
## Scroll to zoom, anchored at the pointer.
##
## Anchoring at the centre instead drags whatever you were looking at out of the
## view as you pull back, which is the difference between a zoom that feels
## right and one that fights.
func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(_zoom * ZOOM_STEP, button.position)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(_zoom / ZOOM_STEP, button.position)


func _apply_zoom(wanted: float, anchor: Vector2) -> void:
	var next: float = clampf(wanted, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(next, _zoom):
		return

	# Keep the point under the pointer where it is: convert it to world space at
	# the old scale, then move the world so it lands there again at the new one.
	var world_point: Vector2 = (anchor - _world.position) / _zoom
	_zoom = next
	_world.scale = Vector2(_zoom, _zoom)
	_world.position = anchor - world_point * _zoom

	# The grid is not inside the world. Scaling it would fatten the dots until
	# they are smudges, so its pitch follows the zoom and the dots keep their
	# size at every level.
	_grid.material = ComposerShaders.grid_material(_zoom)
	zoom_changed.emit(_zoom)


func zoom() -> float:
	return _zoom
#endregion


func _clear() -> void:
	_cards.clear()
	_blooms.clear()
	for layer: Control in [_bloom_layer, _wire_layer, _card_layer, _bead_layer]:
		for child: Node in layer.get_children():
			child.queue_free()
