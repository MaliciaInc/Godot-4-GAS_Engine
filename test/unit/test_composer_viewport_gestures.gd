## Mouse events pushed through a real viewport, onto the pins as drawn.
##
## Everything else about gestures is tested by handing the parser an event and
## asking what it meant. That is worth having and it is not this: it cannot see
## whether the event ever *arrives*. It did not. A press over a card is the
## card's event, and the canvas - which is where the reading lives - never saw
## one, so every modifier gesture on a pin drawn on a card did nothing at all
## while `ComposerPins.at()` sat there answering correctly about a coordinate
## nobody was asking it about.
##
## So these push real `InputEventMouseButton`s into a `SubViewport` holding a
## real canvas, at the point the pin is actually drawn at, and let Godot route
## them. Nothing private is called. A `SubViewport` rather than the display
## because the suite runs headless and there is no window to aim at; the routing
## - hit test, control, `gui_input` - is the engine's own either way.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

const WIRED: Array = [
	"var caster: AbilitySystemComponent = owner_asc",
	"var other: AbilitySystemComponent = target_asc",
	"apply_gameplay_effect(burning, caster, 1.0)",
	"apply_effect_to_target_data(burning, caster)",
	"return true",
]

const CONSUMER: String = "apply_gameplay_effect"
const OTHER: String = "apply_effect_to_target_data"

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


#region Alt-click clears a pin
## Every pin a person can clear, at every zoom they can be looking at.
##
## The data argument pin is the one GAS-009 was about, and the zooms are here
## because the point pushed in is a viewport point: an arithmetic that forgot
## the scale would land on the right pin at 1.0 and on nothing at all at 2.0.
const CLEARING: Array = [
	["the run of control, at half zoom", 0.5, ComposerReader.EXEC_IN, false],
	["a value's argument, at half zoom", 0.5, StringName(ComposerReader.ARGUMENT % 1), false],
	["the run of control", 1.0, ComposerReader.EXEC_IN, false],
	["a value's argument", 1.0, StringName(ComposerReader.ARGUMENT % 1), false],
	["the way out", 1.0, ComposerReader.EXEC_OUT, true],
	["the run of control, at double zoom", 2.0, ComposerReader.EXEC_IN, false],
	["a value's argument, at double zoom", 2.0, StringName(ComposerReader.ARGUMENT % 1), false],
]


func test_alt_clicking_a_pin_through_the_viewport_asks_to_clear_it() -> void:
	var checked: int = 0
	for row: Array in CLEARING:
		var described: String = row[0]
		var at_zoom: float = row[1]
		var port_id: StringName = row[2]
		var outgoing: bool = row[3]

		await _draw(WIRED, at_zoom)
		await _bring_into_view(CONSUMER)
		_broken.clear()
		var at: Vector2 = _pin_point(CONSUMER, port_id, outgoing)

		await _push(at, true, KEY_ALT)

		assert_eq(
			_broken.size(), 1, "%s: one pin was asked about: %s" % [described, _broken]
		)
		assert_true(
			_broken[0].ends_with(".%s" % port_id),
			"%s: and it is the one under the pointer: %s" % [described, _broken]
		)
		checked += 1
	assert_eq(checked, CLEARING.size(), "every pin and every zoom was clicked")
#endregion


#region Ctrl-drag moves what is on a pin
## Pressing on one pin and letting go on another asks for the move.
##
## Both directions, because they are two different requests: taking a value's
## cables to another value, and taking a run of control to another statement.
## The release carries no modifier on purpose - somebody who lets go of Ctrl
## before the mouse button has still made the gesture.
const MOVING: Array = [
	[
		"between two arguments",
		CONSUMER, StringName(ComposerReader.ARGUMENT % 1), false,
		OTHER, StringName(ComposerReader.ARGUMENT % 1), false,
	],
	[
		"between two ways out",
		CONSUMER, ComposerReader.EXEC_OUT, true,
		OTHER, ComposerReader.EXEC_OUT, true,
	],
]


func test_ctrl_dragging_between_two_pins_asks_for_a_move() -> void:
	var checked: int = 0
	for row: Array in MOVING:
		var described: String = row[0]
		var from_said: String = row[1]
		var from_port: StringName = row[2]
		var from_out: bool = row[3]
		var to_said: String = row[4]
		var to_port: StringName = row[5]
		var to_out: bool = row[6]

		await _draw(WIRED)
		await _bring_into_view(from_said)
		_moved.clear()
		var from: Vector2 = _pin_point(from_said, from_port, from_out)
		var to: Vector2 = _pin_point(to_said, to_port, to_out)

		await _push(from, true, KEY_CTRL)
		await _push(to, false)

		assert_eq(_moved.size(), 1, "%s: one move was asked for: %s" % [described, _moved])
		assert_true(
			_moved[0].contains(".%s>" % from_port) and _moved[0].ends_with(".%s" % to_port),
			"%s: from the one pressed to the one let go on: %s" % [described, _moved]
		)
		checked += 1
	assert_eq(checked, MOVING.size(), "both directions were dragged")
#endregion


#region What the widget must still get
## An ordinary press on a card still picks it up and moves it.
##
## The card reports its mouse buttons and accepts none of them. If it did, a
## graph would become a picture nobody could rearrange.
func test_an_ordinary_drag_still_moves_the_card() -> void:
	await _draw(WIRED)
	var card: ComposerCard = _card(CONSUMER)
	var before: Vector2 = card.position_offset
	var at: Vector2 = card.get_global_transform() * Vector2(card.size.x * 0.5, TITLE_BAR)

	await _push(at, true)
	await _push_motion(at, Vector2(64.0, 32.0))
	await _push(at + Vector2(64.0, 32.0), false)

	assert_ne(card.position_offset, before, "the card was dragged")
	assert_eq(_broken.size(), 0, "and nothing was asked about a pin")
	assert_eq(_moved.size(), 0, "and no cable was moved")


## An ordinary drag from pin to pin is still the widget's own wire gesture.
func test_an_ordinary_pin_drag_still_asks_to_connect() -> void:
	await _draw(WIRED)
	var from: Vector2 = _pin_point("var caster", ComposerReader.VALUE_OUT, true)
	var to: Vector2 = _pin_point(OTHER, StringName(ComposerReader.ARGUMENT % 0), false)

	await _push(from, true)
	await _push_motion(from, to - from)
	await _push(to, false)

	assert_eq(_broken.size(), 0, "no pin was cleared")
	assert_eq(_moved.size(), 0, "and nothing was moved")
	assert_eq(_joined.size(), 1, "the widget asked to connect them: %s" % [_joined])


## A click in a box somebody types into is theirs, not a gesture.
func test_a_click_in_a_value_editor_is_not_a_pin_gesture() -> void:
	await _draw(WIRED)
	var card: ComposerCard = _card(CONSUMER)
	var editors: Array[Node] = card.find_children("", "ComposerValueEditor", true, false)
	assert_gt(editors.size(), 0, "the card has something to type into")
	var editor: Control = editors[0] as Control
	var at: Vector2 = editor.get_global_transform() * (editor.size * 0.5)

	await _push(at, true, KEY_ALT)

	assert_eq(_broken.size(), 0, "nothing was cleared: %s" % [_broken])
	assert_eq(_moved.size(), 0, "and nothing was moved")
#endregion


#region All the way to the file
## The gate: a real Alt-click on a data pin changes the ability on disk.
##
## Everything above stops at a request. This one wires the canvas to the routes
## and the routes to a document, exactly the way the screen does, pushes one
## event through the viewport, and asks the file what it says afterwards. That
## is what "the gesture works" has to mean: not that a coordinate was found, and
## not that a signal was emitted, but that the person's ability changed.
func test_alt_clicking_a_data_pin_writes_the_file() -> void:
	var document: ComposerDocument = ComposerDocument.new()
	var body: String = ""
	for statement: String in WIRED:
		body += "	" + statement + "
"
	document.open(HEAD + body, PATH)

	var routes: ComposerWiringRoutes = ComposerWiringRoutes.new()
	routes.bind(document)
	await _draw(WIRED)
	routes.listen_to(_canvas)
	await _bring_into_view(CONSUMER)

	var at: Vector2 = _pin_point(CONSUMER, StringName(ComposerReader.ARGUMENT % 1), false)
	await _push(at, true, KEY_ALT)

	assert_false(
		document.printed().contains("apply_gameplay_effect(burning, caster, 1.0)"),
		"the cable is off the argument: %s" % [ComposerFlowProbe.body_of(document.printed())]
	)
	assert_true(
		document.printed().contains("apply_gameplay_effect(burning, null, 1.0)"),
		"and it holds what it would have been created holding"
	)
	assert_eq(document.history().depth(), 1, "as one step")
#endregion


#region The structural pins, through the same routing
## A branch, a match and an end drawn on one canvas.
const STRUCTURED: Array = [
	"var ready: bool = can_activate()",
	"if ready:",
	"\tfire()",
	"match state:",
	"\tState.A:",
	"\t\tone()",
	"after()",
	"return true",
]


## Every pin a structural statement offers, cleared by a real Alt-click.
##
## The four the closure phase added: a branch's two paths, one arm of a match,
## and the value an end hands back. They are drawn from `node.ports` and reached
## through the same routing as any other pin - which is the point of asking here
## rather than of the parser.
const STRUCTURAL_PINS: Array = [
	["a branch's True", "if ready:", ComposerReader.TRUE_OUT, true],
	["a branch's False", "if ready:", ComposerReader.FALSE_OUT, true],
	["one arm of a match", "match state:", StringName(ComposerReader.CASE_OUT % 0), true],
	["what an end hands back", "return true", ComposerReader.RETURN_VALUE_IN, false],
]


func test_alt_clicking_a_structural_pin_asks_to_clear_it() -> void:
	var checked: int = 0
	for row: Array in STRUCTURAL_PINS:
		var described: String = row[0]
		var said: String = row[1]
		var port_id: StringName = row[2]
		var outgoing: bool = row[3]

		await _draw(STRUCTURED)
		await _bring_into_view(said)
		_broken.clear()

		await _push(_pin_point(said, port_id, outgoing), true, KEY_ALT)

		assert_eq(_broken.size(), 1, "%s: one pin was asked about: %s" % [described, _broken])
		assert_true(
			_broken[0].ends_with(".%s" % port_id),
			"%s: and it is the one under the pointer: %s" % [described, _broken]
		)
		checked += 1
	assert_eq(checked, STRUCTURAL_PINS.size(), "every structural pin was clicked")
#endregion


#region Letting go over nothing
## A wire dragged off a pin and let go on empty canvas asks what to make there.
##
## The widget's own gesture, reported through the canvas: the Composer answers it
## with a menu of the calls that would fit. What matters here is that it arrives
## at all, and that it says which pin it left and where the pointer was.
func test_a_wire_let_go_over_nothing_asks_what_to_put_there() -> void:
	await _draw(WIRED)
	var asked: Array[String] = []
	_canvas.connection_to_empty_requested.connect(
		func _empty(
			node_id: StringName,
			port_id: StringName,
			_graph_position: Vector2,
			_screen_position: Vector2
		) -> void:
			asked.append("%s.%s" % [node_id, port_id])
	)
	var from: Vector2 = _pin_point("var caster", ComposerReader.VALUE_OUT, true)
	var nowhere: Vector2 = from + Vector2(0.0, 600.0)

	await _push(from, true)
	await _push_motion(from, nowhere - from)
	await _push(nowhere, false)

	assert_eq(asked.size(), 1, "one question was asked: %s" % [asked])
	assert_true(
		asked[0].ends_with(".%s" % ComposerReader.VALUE_OUT),
		"about the pin the wire left: %s" % [asked]
	)
	assert_eq(_broken.size(), 0, "and nothing was cleared on the way")


## A call dragged from the palette onto the origin lands on the origin.
##
## Through the widget's own drag and drop rather than by calling the handler:
## `(0, 0)` is a real place, and the whole reason the drop path takes a position
## of its own instead of a default argument.
func test_a_call_dropped_at_the_origin_is_asked_for_there() -> void:
	await _draw(WIRED)
	var asked: Array[Vector2] = []
	_canvas.node_requested.connect(
		func _made(_call_id: StringName, graph_position: Vector2) -> void:
			asked.append(graph_position)
	)
	var carried: Dictionary = {ComposerCatalog.DRAGGED_CALL: &"end_ability"}
	var origin: Vector2 = _canvas.get_global_transform() * Vector2.ZERO

	_canvas.force_drag(carried, Control.new())
	await _push_motion(origin, Vector2.ZERO)
	await _push(origin, false)

	assert_eq(asked.size(), 1, "the canvas took the call: %s" % [asked])
	assert_eq(
		asked[0], _canvas.graph_point_of(Vector2.ZERO), "at the point it was let go"
	)
#endregion
