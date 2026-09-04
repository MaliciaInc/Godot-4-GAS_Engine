## Alt-click, Ctrl-drag and right-click on a pin.
##
## The gestures Blueprint taught people to expect, and the arithmetic that finds
## the pin they aimed at. That arithmetic is the part worth guarding: a pin found
## one row off looks exactly like a pin found correctly, right up until somebody
## watches their cable move to an argument they did not touch.
##
## Nothing here writes to a file. The canvas reports what a gesture meant and the
## routes decide whether the document can say it - so a cancelled drag has to
## leave no trace at all, which is the other half of what these check.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

var canvas: ComposerCanvas = null


func before_each() -> void:
	canvas = ComposerCanvas.new()
	canvas.size = Vector2(1280.0, 720.0)
	add_child_autofree(canvas)


func after_each() -> void:
	canvas = null


#region Getting there
func _shown() -> ComposerGraph:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)
	return graph


## Where a pin is drawn, in the canvas's own coordinates.
func _at_pin(node_id: StringName, port_id: StringName, outgoing: bool) -> Vector2:
	var card: ComposerCard = canvas.card_for(node_id)
	var index: int = (
		card.right_index_for_port(port_id) if outgoing
		else card.left_index_for_port(port_id)
	)
	var local: Vector2 = (
		card.get_output_port_position(index) if outgoing
		else card.get_input_port_position(index)
	)
	return card.position + local * canvas.zoom


func _click(at: Vector2, pressed: bool, alt: bool = false, ctrl: bool = false) -> void:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	button.alt_pressed = alt
	button.ctrl_pressed = ctrl
	canvas._on_gui_input(button)
#endregion


#region Finding the pin that was aimed at
## Every pin on a card answers at the place it is drawn.
##
## Checked pin by pin rather than on a chosen one, because the failure that
## matters is an off-by-one in the numbering - and that is exactly the pin
## nobody thought to name.
func test_every_pin_is_found_where_it_is_drawn() -> void:
	await _shown()
	var card: ComposerCard = canvas.card_for(Sample.APPLY)

	var checked: int = 0
	for index: int in card.get_input_port_count():
		var named: StringName = card.left_port_of_drawn(index)
		var at: Vector2 = card.position + card.get_input_port_position(index) * canvas.zoom

		var found: ComposerPins.Pin = ComposerPins.at(
			{Sample.APPLY: card} as Dictionary[StringName, ComposerCard], canvas.zoom, at
		)

		assert_eq(found.port_id, named, "input %d is the pin drawn there" % index)
		assert_false(found.is_output, "and it is an input")
		checked += 1
	assert_gt(checked, 1, "there was more than one pin to confuse")


## A point nowhere near a pin finds none, rather than the nearest one anywhere.
func test_a_point_away_from_every_pin_finds_none() -> void:
	await _shown()

	var found: ComposerPins.Pin = ComposerPins.at(
		{Sample.APPLY: canvas.card_for(Sample.APPLY)} as Dictionary[StringName, ComposerCard],
		canvas.zoom,
		Vector2(-4000.0, -4000.0)
	)

	assert_false(found.is_found(), "nothing is there")
#endregion


#region Alt-click
## Alt-clicking a pin asks for everything on it to come off.
func test_alt_clicking_a_pin_asks_to_break_it() -> void:
	await _shown()
	watch_signals(canvas)

	_click(_at_pin(Sample.APPLY, ComposerReader.EXEC_IN, false), true, true)

	var asked: Array = get_signal_parameters(canvas, "break_all_requested")
	var node_id: StringName = asked[0]
	var port_id: StringName = asked[1]
	assert_eq(node_id, Sample.APPLY, "on that card")
	assert_eq(port_id, ComposerReader.EXEC_IN, "and that pin")


## Alt-clicking away from every pin asks for nothing.
func test_alt_clicking_nothing_asks_for_nothing() -> void:
	await _shown()
	watch_signals(canvas)

	_click(Vector2(-4000.0, -4000.0), true, true)

	assert_signal_not_emitted(canvas, "break_all_requested")
#endregion


#region Ctrl-drag
## Ctrl-dragging between two pins that face the same way asks for a move.
func test_ctrl_dragging_between_two_inputs_asks_for_a_move() -> void:
	await _shown()
	watch_signals(canvas)

	_click(_at_pin(Sample.APPLY, ComposerReader.EXEC_IN, false), true, false, true)
	_click(_at_pin(Sample.CUE, ComposerReader.EXEC_IN, false), false)

	var asked: Array = get_signal_parameters(canvas, "move_connections_requested")
	var from_node: StringName = asked[0]
	var from_port: StringName = asked[1]
	var to_node: StringName = asked[2]
	var to_port: StringName = asked[3]
	assert_eq(from_node, Sample.APPLY, "from that card")
	assert_eq(to_node, Sample.CUE, "to that one")
	assert_eq(from_port, ComposerReader.EXEC_IN, "between two pins facing the same way")
	assert_eq(to_port, ComposerReader.EXEC_IN)


## A drag that ends on a pin facing the other way is not a move.
##
## Moving what is on an output onto an input is a different wire, and the drag
## that means that one is the ordinary one the widget already draws.
func test_ctrl_dragging_onto_a_pin_facing_the_other_way_asks_for_nothing() -> void:
	await _shown()
	watch_signals(canvas)

	_click(_at_pin(Sample.APPLY, ComposerReader.EXEC_IN, false), true, false, true)
	_click(_at_pin(Sample.CUE, ComposerReader.EXEC_OUT, true), false)

	assert_signal_not_emitted(canvas, "move_connections_requested")


## A drag let go over nothing is cancelled, and asks for nothing.
func test_ctrl_dragging_into_empty_space_is_cancelled() -> void:
	await _shown()
	watch_signals(canvas)

	_click(_at_pin(Sample.APPLY, ComposerReader.EXEC_IN, false), true, false, true)
	_click(Vector2(-4000.0, -4000.0), false)

	assert_signal_not_emitted(canvas, "move_connections_requested", "nothing was asked")

	# And the drag is over: an ordinary release afterwards must not resume it.
	_click(_at_pin(Sample.CUE, ComposerReader.EXEC_IN, false), false)
	assert_signal_not_emitted(canvas, "move_connections_requested", "nor afterwards")


## A drag that ends where it started is not a move.
func test_ctrl_dragging_onto_the_same_pin_asks_for_nothing() -> void:
	await _shown()
	watch_signals(canvas)
	var at: Vector2 = _at_pin(Sample.APPLY, ComposerReader.EXEC_IN, false)

	_click(at, true, false, true)
	_click(at, false)

	assert_signal_not_emitted(canvas, "move_connections_requested")
#endregion


#region What the widget is not allowed to decide
## GraphEdit's own right-disconnect is off.
##
## It is a second policy about what a right-click on a wire means, and this
## editor already has one: right-click opens what can be done here, and
## disconnecting is one of the things it offers. Two policies for one button is a
## button that does different things depending on where in it you clicked.
func test_the_widget_does_not_disconnect_on_its_own() -> void:
	assert_false(canvas.right_disconnects, "the Composer owns that gesture")


## Dropping a wire does not connect it. The file decides, and the canvas is
## redrawn from what the file then says.
func test_dropping_a_wire_does_not_connect_it_on_the_canvas() -> void:
	await _shown()
	var before: int = canvas.get_connection_list().size()
	var from: ComposerCard = canvas.card_for(Sample.CUE)
	var to: ComposerCard = canvas.card_for(Sample.COMMIT)

	canvas.connection_request.emit(
		from.name,
		from.right_index_for_port(ComposerReader.EXEC_OUT),
		to.name,
		to.left_index_for_port(ComposerReader.EXEC_IN)
	)

	assert_eq(
		canvas.get_connection_list().size(),
		before,
		"the canvas drew nothing it was not told the file says"
	)
#endregion
