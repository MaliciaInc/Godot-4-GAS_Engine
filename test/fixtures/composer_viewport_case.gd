## A canvas in a viewport, and real events pushed at the pins as drawn.
##
## Everything else about gestures is tested by handing the parser an event and
## asking what it meant. That is worth having and it is not this: it cannot see
## whether the event ever *arrives*. It did not. A press over a card is the
## card's event, and the canvas - which is where the reading lives - never saw
## one, so every modifier gesture on a pin drawn on a card did nothing at all
## while `ComposerPins.at()` sat there answering correctly about a coordinate
## nobody was asking it about.
##
## So a battery standing on this pushes real `InputEventMouseButton`s into a
## `SubViewport` holding a real canvas, at the point the pin is actually drawn
## at, and lets Godot route them. Nothing private is called. A `SubViewport`
## rather than the display because the suite runs headless and there is no
## window to aim at; the routing - hit test, control, `gui_input` - is the
## engine's own either way.
##
## Nothing here asserts about behaviour. What it offers is the arrangement and
## the coordinates, so that two batteries asking different questions about the
## same routing ask them of one harness rather than of two copies that drift.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

## How far down a card its title bar is, which is what a person grabs to move
## it. Anything below this is a row, and a row is not a handle.
const TITLE_BAR: float = 6.0

var _window: SubViewport = null
var _canvas: ComposerCanvas = null
var _graph: ComposerGraph = null
var _broken: Array[String] = []
var _moved: Array[String] = []
var _joined: Array[String] = []


func before_each() -> void:
	_broken = []
	_moved = []
	_joined = []


#region Getting there
## A canvas drawing that ability inside a viewport of its own.
func _draw(statements: Array, at_zoom: float = 1.0) -> void:
	_window = SubViewport.new()
	_window.size = Vector2i(3200, 1800)
	_window.handle_input_locally = true
	add_child_autofree(_window)

	_canvas = ComposerCanvas.new()
	_canvas.size = Vector2(3200, 1800)
	_window.add_child(_canvas)
	_canvas.break_all_requested.connect(
		func _broke(node_id: StringName, port_id: StringName) -> void:
			_broken.append("%s.%s" % [node_id, port_id])
	)
	_canvas.move_connections_requested.connect(
		func _move(
			from_node: StringName,
			from_port: StringName,
			to_node: StringName,
			to_port: StringName
		) -> void:
			_moved.append("%s.%s>%s.%s" % [from_node, from_port, to_node, to_port])
	)
	_canvas.connection_requested.connect(
		func _joining(edge: ComposerGraph.Connection) -> void:
			_joined.append("%s.%s>%s.%s" % [
				edge.from_node, edge.from_port, edge.to_node, edge.to_port
			])
	)

	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	_graph = ComposerReader.read(HEAD + body, PATH)
	await _canvas.show_graph(_graph)
	_canvas.zoom = at_zoom
	await get_tree().process_frame
	await get_tree().process_frame


## Draw the port dots further into the cards, the way a host theme can.
##
## `port_h_offset` is a GraphNode theme constant and a game is entitled to set
## it. What it does here is put the dot on top of one of the card's own rows,
## and a row is `MOUSE_FILTER_STOP` so that a value editor gets its clicks -
## which means the press stops there and the canvas never hears it. That is
## GAS-009, and it is a theme constant rather than anything contrived: the game
## this was found in has a theme, and the dots are drawn inside the card in it.
func _offset_ports(by: int) -> void:
	for node: ComposerNode in _graph.nodes:
		var card: ComposerCard = _canvas.card_for(node.id)
		if card != null:
			card.add_theme_constant_override("port_h_offset", by)
	await get_tree().process_frame
	await get_tree().process_frame


func _card(said: String) -> ComposerCard:
	var node: ComposerNode = ComposerFlowProbe.at(_graph, said)
	assert_not_null(node, "there is a statement saying `%s`" % said)
	return _canvas.card_for(node.id)


## Scroll until that card is somewhere a pointer can reach it.
##
## Zooming in keeps the view where it was, so a card that was on screen at 1.0
## can be above the top of it at 2.0 - and an event pushed at a point outside
## the viewport is routed to nothing at all, which looks exactly like a gesture
## the code failed to read.
func _bring_into_view(said: String) -> void:
	var card: ComposerCard = _card(said)
	_canvas.scroll_offset += card.position - Vector2(200.0, 200.0)
	await get_tree().process_frame


## Where a pin of that statement is, in the viewport's own coordinates.
##
## Through the card's own transform, which is what carries the scroll and the
## zoom. Working it out from the numbers instead would be this test agreeing
## with the code about arithmetic they had both got wrong.
func _pin_point(said: String, port_id: StringName, outgoing: bool) -> Vector2:
	var card: ComposerCard = _card(said)
	var index: int = (
		card.right_index_for_port(port_id) if outgoing
		else card.left_index_for_port(port_id)
	)
	assert_gte(index, 0, "`%s` is drawn on that card" % port_id)
	var local: Vector2 = (
		card.get_output_port_position(index) if outgoing
		else card.get_input_port_position(index)
	)
	return card.get_global_transform() * local


## Push one mouse button through the viewport, and let Godot route it.
func _push(at: Vector2, pressed: bool, modifier: Key = KEY_NONE) -> void:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	button.global_position = at
	button.alt_pressed = modifier == KEY_ALT
	button.ctrl_pressed = modifier == KEY_CTRL
	_window.push_input(button, true)
	await get_tree().process_frame


func _push_motion(at: Vector2, by: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at + by
	motion.global_position = at + by
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_window.push_input(motion, true)
	await get_tree().process_frame
#endregion
