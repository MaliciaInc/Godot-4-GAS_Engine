## The graph surface: grid, glow, cards, wires, zoom.
##
## Draw order is held by four layers rather than by the order things happen to
## be created in. Wires have to sit behind the cards and beads in front of them,
## but neither can be positioned until the cards have measured themselves - so
## anything that depends on creation order ends up drawing a cable across a card
## or burying a bead underneath one. With layers, each pass fills its own and
## the stacking is a fact of the tree.
##
## Nothing here decides where a node goes. `ComposerLayout` does, and it decides
## twice: once before the cards exist, from the minimum a card can be, and again
## once every card has been measured - which is what lets a card's own width and
## height push its column and its lane apart.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCanvas extends Control

## Held down to drag the graph about. The middle button because the left one
## is drawing a selection box and the right one is a menu everywhere else.
const PAN_BUTTON: int = MOUSE_BUTTON_MIDDLE

## Room left around a graph when it is framed, so the outermost cards are not
## flush against the edge of a panel.
const FRAME_MARGIN: float = 48.0

## How far the pointer has to travel before a click becomes a drag. Without it
## every click is a drag of nought pixels onto the card it started on.
const DRAG_SLACK: float = 6.0

## The zoom at which a card stops being worth reading in full, and the one at
## which it stops being worth reading at all.
const DETAIL_FULL: float = 0.75
const DETAIL_TITLE: float = 0.40

const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.1

## Which cards are being worked on. Empty when none are.
signal selection_changed(picked: Array[StringName])

## One card was dragged onto another. What that means is not the canvas's to
## decide - cards have no positions of their own here.
signal node_dropped(moved: StringName, onto: StringName)

## One card was left in empty space. Unlike node_dropped, this does not change
## source order; it records only presentation metadata in the same GDScript.
signal node_positioned(node_id: StringName, world_position: Vector2)

## Somebody asked a card what can be done to it.
signal menu_requested(node_id: StringName, at: Vector2)

## A call was dragged in from the palette and let go over the canvas.
signal node_requested(type_id: StringName)

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
var _dragging: StringName = &""
var _drag_from: Vector2 = Vector2.ZERO
var _drag_card_from: Vector2 = Vector2.ZERO
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
	var placed: Dictionary[StringName, Vector2] = ComposerLayout.origins(_placements)
	for node: ComposerNode in graph.nodes:
		var at: Vector2 = (
			node.layout_position
			if node.has_layout_position
			else placed[node.id]
		)
		_add_card(node, at)

	# Cards have no measured height until a frame has passed, and every wire
	# endpoint depends on where a card's edges ended up.
	await get_tree().process_frame
	_fit_cards()
	ComposerWiring.draw(_graph, _cards, _wire_layer, _bead_layer)


func _add_card(node: ComposerNode, at: Vector2) -> void:
	var bloom: TextureRect = ComposerTheme.glow_rect(
		ComposerTheme.glow(ComposerTheme.ACCENT, ComposerTheme.BLOOM_STRENGTH)
	)
	_bloom_layer.add_child(bloom)
	_blooms[node.id] = bloom

	var card: ComposerCard = ComposerCard.new()
	card.position = at
	_card_layer.add_child(card)
	card.build(node)
	_cards[node.id] = card


## Trim every card to its content, then hang its glow on the result.
##
## The glow is an ellipse taking the card's own proportions. A circle around a
## short wide card spills far above and below it and stops looking like that
## card's light.
func _fit_cards() -> void:
	var widths: Dictionary[StringName, float] = {}
	var heights: Dictionary[StringName, float] = {}
	for id: StringName in _cards:
		_cards[id].fit()
		widths[id] = _cards[id].size.x
		heights[id] = _cards[id].size.y

	# Placed again now that the cards have a size: the first pass could only
	# guess, and a column is only as wide as what it turned out to hold.
	var placed: Dictionary[StringName, Vector2] = ComposerLayout.origins(
		_placements, widths, heights
	)
	for id: StringName in _cards:
		var card: ComposerCard = _cards[id]
		var model: ComposerNode = _graph.find_node(id)
		if model == null or not model.has_layout_position:
			card.position = placed[id]
		_sync_bloom(id)


func _sync_bloom(id: StringName) -> void:
	if not _cards.has(id) or not _blooms.has(id):
		return
	var card: ComposerCard = _cards[id]
	var bloom: TextureRect = _blooms[id]
	var reach: Vector2 = card.size * ComposerTheme.BLOOM_SCALE
	bloom.position = card.position + card.size * 0.5 - reach * 0.5
	bloom.size = reach


func _redraw_wires() -> void:
	for layer: Control in [_wire_layer, _bead_layer]:
		for child: Node in layer.get_children():
			layer.remove_child(child)
			child.queue_free()
	if _graph != null:
		ComposerWiring.draw(_graph, _cards, _wire_layer, _bead_layer)
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
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var asked: StringName = _card_at(button.position)
		if not asked.is_empty():
			if not _picked.has(asked):
				_pick([asked] as Array[StringName])
			menu_requested.emit(asked, button.position)
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press(button)
		else:
			_release(button)


func _on_motion(motion: InputEventMouseMotion) -> void:
	if _panning:
		_world.position += motion.relative
		return

	if not _dragging.is_empty() and _cards.has(_dragging):
		var card: ComposerCard = _cards[_dragging]
		card.position += motion.relative / _zoom
		_sync_bloom(_dragging)
		_redraw_wires()
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
		if not ComposerSelection.adding(button):
			_pick([])
		return

	_dragging = hit
	_drag_from = button.position
	_drag_card_from = _cards[hit].position
	if ComposerSelection.adding(button):
		_pick(ComposerSelection.toggled(picked(), hit))
	elif not _picked.has(hit):
		# A card already in the selection is left alone: clicking one of several
		# to drag them all should not throw the others away first.
		_pick([hit] as Array[StringName])


func _release(button: InputEventMouseButton) -> void:
	if not _dragging.is_empty():
		var moved: StringName = _dragging
		_dragging = &""
		var travelled: float = button.position.distance_to(_drag_from)

		if travelled <= DRAG_SLACK:
			if _cards.has(moved):
				_cards[moved].position = _drag_card_from
				_sync_bloom(moved)
				_redraw_wires()
			return

		var onto: StringName = _card_at_except(button.position, moved)
		if not onto.is_empty():
			node_dropped.emit(moved, onto)
			return

		if _cards.has(moved):
			node_positioned.emit(moved, _cards[moved].position)
		return
	if not _boxing:
		return
	_boxing = false
	_box.visible = false
	var swept: Array[StringName] = _inside(Rect2(_box.position, _box.size))
	if swept.is_empty():
		return
	_pick(
		ComposerSelection.joined(picked(), swept) if ComposerSelection.adding(button)
		else swept
	)


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


## Whether what is being dragged is a call this canvas can take.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if _graph == null or not _graph.is_editable() or typeof(data) != TYPE_DICTIONARY:
		return false
	var carried: Dictionary = data
	return carried.has(ComposerCatalog.DRAGGED_CALL)


## Take it, and put the selection where it landed.
##
## Selecting the card under the pointer is the whole of what the drop has to
## say about position: the Composer already writes a new statement after
## whatever is selected, so a drop onto a card lands after that card and a drop
## onto empty canvas lands at the end. One insertion path, two ways in.
func _drop_data(at: Vector2, data: Variant) -> void:
	var carried: Dictionary = data
	var call_id: StringName = carried[ComposerCatalog.DRAGGED_CALL]
	var onto: StringName = _card_at(at)
	var landing: Array[StringName] = []
	if not onto.is_empty():
		landing.append(onto)
	_pick(landing)
	node_requested.emit(call_id)


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


func _card_at_except(at: Vector2, excluded: StringName) -> StringName:
	var world_point: Vector2 = (at - _world.position) / _zoom
	for id: StringName in _cards:
		if id == excluded:
			continue
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
	# Floored at DETAIL_FULL, not ZOOM_MIN: framing used to land below it, so
	# every card opened as a bare title and the graph knew less than the file.
	_set_scale(clampf(minf(size.x / room.x, size.y / room.y), DETAIL_FULL, ZOOM_MAX))
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
