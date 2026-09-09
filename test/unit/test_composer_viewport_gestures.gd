## What every modifier gesture does when a real hand makes it.
##
## The harness is `composer_viewport_case.gd`: a canvas in a `SubViewport`, and
## the arithmetic that finds where a pin is actually drawn. What is asked here
## is what each gesture then means - which pin was read, at which zoom, and in
## the last region, what the file says afterwards.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends "res://test/fixtures/composer_viewport_case.gd"

const WIRED: Array = [
	"var caster: AbilitySystemComponent = owner_asc",
	"var other: AbilitySystemComponent = target_asc",
	"apply_gameplay_effect(burning, caster, 1.0)",
	"apply_effect_to_target_data(burning, caster)",
	"return true",
]

const CONSUMER: String = "apply_gameplay_effect"
const OTHER: String = "apply_effect_to_target_data"


#region Alt-click clears a pin
## Far enough to put a port dot inside a row rather than on the card's edge, and
## no further: it is the mechanism that matters, not the number.
##
## `port_h_offset` is a GraphNode theme constant a host game is entitled to set.
## What it does is move the dot off the card's outer edge and onto one of the
## card's own rows - and a row is `MOUSE_FILTER_STOP`, because a value editor
## has to get its clicks. So the press stops there, and every modifier gesture
## on every pin of every card silently does nothing.
##
## Found while chasing something else, and worth saying which: the sandbox
## finding this was written for turned out to be that harness aiming at a card
## that was off its canvas, with nothing at all receiving the press. This case
## is real and is reached by a theme rather than by that, and it is proved here
## rather than assumed - which is the part the finding skipped.
const INSIDE_THE_CARD: int = 24

## Every pin a person can clear, at every zoom they can be looking at, wherever
## the theme draws the dot.
##
## The zooms are here because the point pushed in is a viewport point: an
## arithmetic that forgot the scale would land on the right pin at 1.0 and on
## nothing at all at 2.0. The offset is here because where the dot is drawn is
## the theme's decision and not the Composer's, and the whole family - the run
## of control in, the way out, and a value's argument - went deaf under one.
##
##     [what it is called, the zoom, how far the dots are pushed in, the pin, out]
const CLEARING: Array = [
	["the run of control, at half zoom", 0.5, 0, ComposerReader.EXEC_IN, false],
	["a value's argument, at half zoom", 0.5, 0, StringName(ComposerReader.ARGUMENT % 1), false],
	["the run of control", 1.0, 0, ComposerReader.EXEC_IN, false],
	["a value's argument", 1.0, 0, StringName(ComposerReader.ARGUMENT % 1), false],
	["the way out", 1.0, 0, ComposerReader.EXEC_OUT, true],
	["the run of control, at double zoom", 2.0, 0, ComposerReader.EXEC_IN, false],
	["a value's argument, at double zoom", 2.0, 0, StringName(ComposerReader.ARGUMENT % 1), false],
	["the run of control, drawn inside the card", 1.0, INSIDE_THE_CARD, ComposerReader.EXEC_IN, false],
	["a value's argument, drawn inside the card", 1.0, INSIDE_THE_CARD, StringName(ComposerReader.ARGUMENT % 1), false],
	["the way out, drawn inside the card", 1.0, INSIDE_THE_CARD, ComposerReader.EXEC_OUT, true],
]


func test_alt_clicking_a_pin_through_the_viewport_asks_to_clear_it() -> void:
	var checked: int = 0
	for row: Array in CLEARING:
		var described: String = row[0]
		var at_zoom: float = row[1]
		var pushed_in: int = row[2]
		var port_id: StringName = row[3]
		var outgoing: bool = row[4]

		await _draw(WIRED, at_zoom)
		await _bring_into_view(CONSUMER)
		if pushed_in > 0:
			await _offset_ports(pushed_in)
		_broken.clear()
		var at: Vector2 = _pin_point(CONSUMER, port_id, outgoing)

		await _push(at, true, KEY_ALT)

		assert_eq(
			_broken.size(), 1, "%s: one pin was asked about: %s" % [described, _broken]
		)
		assert_true(
			_broken.size() == 1 and _broken[0].ends_with(".%s" % port_id),
			"%s: and it is the one under the pointer: %s" % [described, _broken]
		)
		checked += 1
	assert_eq(checked, CLEARING.size(), "every pin, zoom and theme was clicked")
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


#region A pin the host's theme draws inside the card
## And the drag between two of them, which is the other half of the family.
func test_ctrl_dragging_between_pins_drawn_inside_the_cards_still_moves_them() -> void:
	await _draw(WIRED)
	await _bring_into_view(CONSUMER)
	await _offset_ports(INSIDE_THE_CARD)
	var from: Vector2 = _pin_point(CONSUMER, StringName(ComposerReader.ARGUMENT % 1), false)
	var to: Vector2 = _pin_point(CONSUMER, StringName(ComposerReader.ARGUMENT % 2), false)

	await _push(from, true, KEY_CTRL)
	await _push_motion(from, to - from)
	await _push(to, false)

	assert_eq(_moved.size(), 1, "one move was asked for: %s" % [_moved])
	assert_true(
		_moved.size() == 1 and _moved[0].ends_with(".%s" % (ComposerReader.ARGUMENT % 2)),
		"onto the pin it was let go over: %s" % [_moved]
	)


## An ordinary press on a row is still the row's.
##
## The half that stops the fix from being a different defect: a value editor
## lives in one of these rows, and a Composer that swallowed plain clicks on the
## way to fixing the modified ones would be unusable for typing a number.
func test_an_ordinary_press_on_a_row_is_left_alone() -> void:
	await _draw(WIRED)
	await _bring_into_view(CONSUMER)
	await _offset_ports(INSIDE_THE_CARD)
	_broken.clear()
	var at: Vector2 = _pin_point(CONSUMER, StringName(ComposerReader.ARGUMENT % 1), false)

	await _push(at, true)
	await _push(at, false)

	assert_eq(_broken.size(), 0, "nothing was cleared: %s" % [_broken])
	assert_eq(_moved.size(), 0, "and nothing was moved: %s" % [_moved])
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
