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

## Held down to drag the graph about. The middle button because the left one
## is drawing a selection box and the right one is a menu everywhere else.
const PAN_BUTTON: int = MOUSE_BUTTON_MIDDLE

## Room left around a graph when it is framed, so the outermost cards are not
## flush against the edge of a panel.
const FRAME_MARGIN: float = 48.0

## The zoom at which a card stops being worth reading in full, and the one at
## which it stops being worth reading at all.
const DETAIL_FULL: float = 0.75
const DETAIL_TITLE: float = 0.40

const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.1

## Where a card's first port sits, measured down from its top edge. Level with
## the title, so a wire arrives pointing at the node's name.
const PORT_INSET: float = 33.0
const PORT_PITCH: float = 28.0

## Which cards are being worked on. Empty when none are.
signal selection_changed(picked: Array[StringName])

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

var _picked: Dictionary[StringName, bool] = {}
var _panning: bool = false
var _boxing: bool = false
var _box_from: Vector2 = Vector2.ZERO
var _box: ColorRect = null


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

	# Outside the world, because a box is drawn where the pointer is and not
	# where the graph is - it must not move or scale while it is being dragged.
	_box = ComposerPanel.backdrop(ComposerTheme.SELECTION_FILL)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	add_child(_box)


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


#region Driving it
## Every pointer gesture the canvas answers, in one place.
##
## Hit-testing here rather than letting each card answer for itself: the cards
## sit inside a scaled world and pass the mouse straight through, and a graph
## where some clicks are the canvas's and some are a card's is a graph where
## the two disagree about what was clicked.
func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_on_button(button)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)


func _on_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
		_apply_zoom(_zoom * ZOOM_STEP, button.position)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
		_apply_zoom(_zoom / ZOOM_STEP, button.position)
	elif button.button_index == PAN_BUTTON:
		_panning = button.pressed
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press(button)
		else:
			_release(button)


func _on_motion(motion: InputEventMouseMotion) -> void:
	if _panning:
		_world.position += motion.relative
		return
	if not _boxing:
		return
	# Built from the two corners rather than from a running total, so dragging
	# back past where the drag started sweeps the other way instead of
	# collapsing the box to nothing.
	var corner: Vector2 = motion.position
	_box.position = Vector2(minf(_box_from.x, corner.x), minf(_box_from.y, corner.y))
	_box.size = (corner - _box_from).abs()


func _press(button: InputEventMouseButton) -> void:
	var hit: StringName = _card_at(button.position)
	if hit.is_empty():
		_boxing = true
		_box_from = button.position
		_box.position = _box_from
		_box.size = Vector2.ZERO
		_box.visible = true
		if not _adding(button):
			_pick([])
		return

	if _adding(button):
		_pick(_with(hit))
	elif not _picked.has(hit):
		# A card already in the selection is left alone: clicking one of several
		# to drag them all should not throw the others away first.
		_pick([hit] as Array[StringName])


func _release(button: InputEventMouseButton) -> void:
	if not _boxing:
		return
	_boxing = false
	_box.visible = false
	var swept: Array[StringName] = _inside(Rect2(_box.position, _box.size))
	if swept.is_empty():
		return
	_pick(_joined(swept) if _adding(button) else swept)


## Whether this click adds to the selection rather than replacing it.
static func _adding(button: InputEventMouseButton) -> bool:
	return button.shift_pressed or button.ctrl_pressed
#endregion


#region What is picked
## Replace the selection, and say so once.
func _pick(ids: Array[StringName]) -> void:
	_picked.clear()
	for id: StringName in ids:
		_picked[id] = true
	for card_id: StringName in _cards:
		var card: ComposerCard = _cards[card_id]
		card.pick(_picked.has(card_id))
	selection_changed.emit(picked())


## The selection with `id` added, or taken out if it was already in it.
func _with(id: StringName) -> Array[StringName]:
	var next: Array[StringName] = picked()
	if next.has(id):
		next.erase(id)
	else:
		next.append(id)
	return next


func _joined(swept: Array[StringName]) -> Array[StringName]:
	var next: Array[StringName] = picked()
	for id: StringName in swept:
		if not next.has(id):
			next.append(id)
	return next


func picked() -> Array[StringName]:
	var found: Array[StringName] = []
	# Read off the cards rather than off the dictionary, so the order is the
	# order of the graph and not whatever order they happened to be clicked in.
	for id: StringName in _cards:
		if _picked.has(id):
			found.append(id)
	return found


## Which card is under a point on screen, or nothing.
func _card_at(at: Vector2) -> StringName:
	var world_point: Vector2 = (at - _world.position) / _zoom
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		if Rect2(card.position, card.size).has_point(world_point):
			return id
	return &""


## Every card the box on screen covers any part of.
func _inside(box: Rect2) -> Array[StringName]:
	var swept: Rect2 = Rect2((box.position - _world.position) / _zoom, box.size / _zoom)
	var found: Array[StringName] = []
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		if swept.intersects(Rect2(card.position, card.size)):
			found.append(id)
	return found
#endregion


#region Finding your way around
## Put the whole graph on screen.
func frame_all() -> void:
	_frame(_bounds(_cards.keys()))


## Put what is picked on screen, or everything when nothing is.
func frame_picked() -> void:
	var ids: Array[StringName] = picked()
	_frame(_bounds(ids) if not ids.is_empty() else _bounds(_cards.keys()))


## Pick one card and bring it into view.
##
## What a person clicking a row in the Output panel is asking for: not the line
## number, the node. Told where to look and then left to find it themselves is
## the panel doing half a job.
func reveal(node_id: StringName) -> void:
	if not _cards.has(node_id):
		return
	_pick([node_id] as Array[StringName])
	frame_picked()


func _bounds(ids: Array) -> Rect2:
	var found: Rect2 = Rect2()
	var started: bool = false
	for id: StringName in ids:
		var card: ComposerCard = _cards[id]
		var box: Rect2 = Rect2(card.position, card.size)
		found = box if not started else found.merge(box)
		started = true
	return found


func _frame(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var room: Vector2 = bounds.size + Vector2(FRAME_MARGIN, FRAME_MARGIN) * 2.0
	_set_scale(clampf(minf(size.x / room.x, size.y / room.y), ZOOM_MIN, ZOOM_MAX))
	_world.position = size * 0.5 - bounds.get_center() * _zoom
#endregion


#region Zoom
## Scroll to zoom, anchored at the pointer.
##
## Anchoring at the centre instead drags whatever you were looking at out of the
## view as you pull back, which is the difference between a zoom that feels
## right and one that fights.


func _apply_zoom(wanted: float, anchor: Vector2) -> void:
	var next: float = clampf(wanted, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(next, _zoom):
		return

	# Keep the point under the pointer where it is: convert it to world space at
	# the old scale, then move the world so it lands there again at the new one.
	var world_point: Vector2 = (anchor - _world.position) / _zoom
	_set_scale(next)
	_world.position = anchor - world_point * _zoom


## Take the world to `next`, and tell the cards how much of themselves to draw.
static func detail_at(zoom: float) -> ComposerCard.Detail:
	if zoom >= DETAIL_FULL:
		return ComposerCard.Detail.FULL
	return ComposerCard.Detail.TITLE if zoom >= DETAIL_TITLE else ComposerCard.Detail.BLOCK


func _set_scale(next: float) -> void:
	_zoom = next
	_world.scale = Vector2(_zoom, _zoom)

	# The grid is not inside the world. Scaling it would fatten the dots until
	# they are smudges, so its pitch follows the zoom and the dots keep their
	# size at every level.
	_grid.material = ComposerShaders.grid_material(_zoom)
	var level: ComposerCard.Detail = detail_at(_zoom)
	for id: StringName in _cards:
		_cards[id].show_detail(level)


func zoom() -> float:
	return _zoom
#endregion


func _clear() -> void:
	_cards.clear()
	_blooms.clear()
	for layer: Control in [_bloom_layer, _wire_layer, _card_layer, _bead_layer]:
		for child: Node in layer.get_children():
			child.queue_free()
