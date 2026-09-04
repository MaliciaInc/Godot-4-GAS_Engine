## The canvas: a graph in, cards and cables out, gestures back as requests.
##
## Everything below runs headless. What is being tested is the translation, not
## the widget: GraphEdit already knows how to drag a node and draw a curve, and
## a test that checked those would be testing Godot. What only this project can
## get wrong is which pin a drawn index means, which nodes are worth drawing at
## all, and whether a gesture reaches the file more than once.
##
## Nothing here writes to a document. The canvas asks; the screen answers.
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
func _cards() -> Array[ComposerCard]:
	var found: Array[ComposerCard] = []
	for child: Node in canvas.get_children():
		if child is ComposerCard:
			found.append(child)
	return found


func _shown() -> ComposerGraph:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)
	return graph


## The sample with a support line in it, which must be read and never drawn.
func _shown_with_support() -> ComposerGraph:
	var graph: ComposerGraph = Sample.build()
	graph.nodes.append(Sample.support())
	await canvas.show_graph(graph)
	return graph
#endregion


#region Drawing a graph
## The canvas is the widget, not something wrapping one.
##
## Said plainly because everything else here depends on it: the pins, the
## cables, the dragging and the refusal of an impossible drop are all the
## widget's, and a canvas that merely contained one would have to forward every
## part of that by hand.
func test_the_canvas_is_a_graph_edit() -> void:
	assert_true(canvas is GraphEdit, "the surface is the widget itself")


## Every node a person is meant to see becomes exactly one card.
func test_every_visible_node_becomes_one_graph_node() -> void:
	var graph: ComposerGraph = await _shown()

	assert_eq(_cards().size(), graph.visible_nodes().size(), "one card each")
	for card: ComposerCard in _cards():
		assert_true(card is GraphNode, "%s is a real graph node" % card.node_id)
		assert_not_null(graph.find_node(card.node_id), "and it stands for a statement")


## Machinery is read and never drawn.
##
## An `if false:` wrapper is a line the reader must account for, and a card
## called "If False" would be Composer explaining its own bookkeeping to
## somebody who asked about their ability.
func test_a_support_line_becomes_no_card_at_all() -> void:
	var graph: ComposerGraph = await _shown_with_support()

	assert_eq(graph.nodes.size(), _cards().size() + 1, "one node is not drawn")
	for card: ComposerCard in _cards():
		assert_ne(card.node_id, &"wrapper", "and it is that one")


## Every cable the graph holds becomes one the widget knows about.
func test_graph_connections_become_native_connections() -> void:
	var graph: ComposerGraph = await _shown()

	assert_eq(
		canvas.get_connection_list().size(),
		graph.connections.size(),
		"one native connection per wire"
	)


## A cable lands on the pins it names, not on whichever index happened to match.
##
## The whole reason a card keeps two lists of port ids. GraphNode numbers the
## pins it draws rather than the rows, so a card whose second row has no left
## pin has an input at index 1 belonging to its third row - and a wire that
## trusted the row number would be drawn one row off, looking entirely correct.
func test_a_cable_lands_on_the_pins_its_wire_names() -> void:
	await _shown()

	assert_gt(canvas.get_connection_list().size(), 0, "there were cables to check")
	for native: Dictionary in canvas.get_connection_list():
		var leaves: StringName = native["from_node"]
		var lands: StringName = native["to_node"]
		var leaving: int = native["from_port"]
		var landing: int = native["to_port"]
		var out: StringName = canvas.card_for(leaves).right_port_of_drawn(leaving)
		var into: StringName = canvas.card_for(lands).left_port_of_drawn(landing)
		assert_eq(out, ComposerReader.EXEC_OUT, "leaves by the run of control")
		assert_eq(into, ComposerReader.EXEC_IN, "and arrives by one")


func test_showing_nothing_clears_the_canvas() -> void:
	await _shown()
	assert_gt(_cards().size(), 0, "there was something to clear")

	await canvas.show_graph(null)

	assert_eq(_cards().size(), 0, "no cards")
	assert_eq(canvas.get_connection_list().size(), 0, "and no cables")
#endregion


#region Turning a gesture into a request
## Drive one wire gesture the way the widget would, and hand back what the canvas
## asked for.
##
## Both gestures go through one translator in the canvas, so they are driven
## through one helper here: two copies of this would be two chances to prove the
## same translation twice and the other one never.
func _asked(
	gesture: Signal, answer: StringName, from_id: StringName, to_id: StringName
) -> ComposerGraph.Connection:
	var from: ComposerCard = canvas.card_for(from_id)
	var to: ComposerCard = canvas.card_for(to_id)
	gesture.emit(
		from.name,
		from.right_index_for_port(ComposerReader.EXEC_OUT),
		to.name,
		to.left_index_for_port(ComposerReader.EXEC_IN)
	)
	var reported: Array = get_signal_parameters(canvas, answer)
	assert_not_null(reported, "the canvas asked for something")
	var edge: ComposerGraph.Connection = reported[0]
	return edge


## Both wire gestures, and the ports each has to be reported with.
##
## One test rather than two: the canvas translates both through a single
## function, so proving it twice in two shapes proves one of them and reads like
## it proved both.
const GESTURES: Array = [
	[&"connection_requested", Sample.COMMIT, Sample.APPLY, "a wire dropped"],
	[&"disconnection_requested", Sample.APPLY, Sample.WAIT, "a wire pulled off"],
]


func test_a_wire_gesture_is_reported_with_semantic_port_ids() -> void:
	for row: Array in GESTURES:
		var answer: StringName = row[0]
		var from_id: StringName = row[1]
		var to_id: StringName = row[2]
		var described: String = row[3]

		await _shown()
		watch_signals(canvas)
		var gesture: Signal = (
			canvas.connection_request
			if answer == &"connection_requested"
			else canvas.disconnection_request
		)

		var edge: ComposerGraph.Connection = _asked(gesture, answer, from_id, to_id)

		assert_eq(edge.from_node, from_id, "%s: leaves the right card" % described)
		assert_eq(edge.to_node, to_id, "%s: lands on the right card" % described)
		assert_eq(
			edge.from_port, ComposerReader.EXEC_OUT, "%s: named, not numbered" % described
		)
		assert_eq(edge.to_port, ComposerReader.EXEC_IN, "%s: and so is the far end" % described)


## A pin number that means nothing is asked about at all.
##
## The alternative is a request carrying a port id nobody recognises, answered
## by the controller with a refusal about a pin the person never touched.
func test_a_pin_number_that_names_nothing_asks_for_nothing() -> void:
	await _shown()
	watch_signals(canvas)

	canvas.connection_request.emit(
		StringName(Sample.COMMIT), 97, StringName(Sample.APPLY), 0
	)

	assert_signal_not_emitted(canvas, "connection_requested", "nothing to ask about")
#endregion


#region Moving cards
## Dragging says where things ended up, once, when the drag ends.
func test_moving_cards_reports_once_at_the_end_of_the_drag() -> void:
	await _shown()
	watch_signals(canvas)
	var card: ComposerCard = canvas.card_for(Sample.APPLY)
	card.selected = true

	canvas.begin_node_move.emit()
	card.position_offset += Vector2(40.0, 20.0)
	assert_signal_not_emitted(canvas, "nodes_positioned", "nothing while it moves")
	canvas.end_node_move.emit()

	assert_signal_emit_count(canvas, "nodes_positioned", 1, "and once when it stops")
	var reported: Array = get_signal_parameters(canvas, "nodes_positioned")
	var moved: Dictionary = reported[0]
	assert_eq(moved.size(), 1, "only what moved")
	assert_true(moved.has(Sample.APPLY), "and it is the card that was dragged")


## A drag that moved nothing is not a change.
##
## A click is a one-pixel drag as far as the widget is concerned, and recording
## one would put an undo in front of the edit somebody meant to reach.
func test_a_drag_that_moved_nothing_reports_nothing() -> void:
	await _shown()
	watch_signals(canvas)
	canvas.card_for(Sample.APPLY).selected = true

	canvas.begin_node_move.emit()
	canvas.end_node_move.emit()

	assert_signal_not_emitted(canvas, "nodes_positioned")


## Dragging a card over another says nothing about running order.
##
## The surface this replaced took a card dropped onto another as an instruction
## to move that statement in the file, so somebody tidying their graph
## reordered their ability by accident. There is no such gesture now.
func test_dragging_a_card_over_another_never_asks_to_reorder() -> void:
	await _shown()
	watch_signals(canvas)
	var moved: ComposerCard = canvas.card_for(Sample.CUE)
	var onto: ComposerCard = canvas.card_for(Sample.COMMIT)
	moved.selected = true

	canvas.begin_node_move.emit()
	moved.position_offset = onto.position_offset
	canvas.end_node_move.emit()

	var said: Array = get_signal_parameters(canvas, "nodes_positioned")
	var reported: Dictionary = said[0]
	assert_eq(reported.size(), 1, "one card was placed")
	var landed: Vector2 = reported[Sample.CUE]
	assert_eq(landed, onto.position_offset, "where it was let go")
	# The point of the test: a placement is all that was reported. The surface
	# this replaced had a separate gesture that asked to move the STATEMENT, and
	# nothing on this canvas may ask for that any more.
	for named: String in ["node_dropped", "reorder_requested", "move_requested"]:
		assert_false(
			canvas.has_signal(named), "%s is not something this canvas can ask for" % named
		)
#endregion


#region Selection
## What is picked is what the widget says is selected.
func test_the_selection_is_whatever_the_widget_has_selected() -> void:
	await _shown()

	canvas.card_for(Sample.WAIT).selected = true

	assert_eq(canvas.picked(), [Sample.WAIT] as Array[StringName])


## Revealing a node picks it and nothing else.
func test_revealing_a_node_picks_it_alone() -> void:
	await _shown()
	canvas.card_for(Sample.COMMIT).selected = true
	watch_signals(canvas)

	canvas.reveal(Sample.CUE)

	assert_eq(canvas.picked(), [Sample.CUE] as Array[StringName], "just that one")
	assert_signal_emitted(canvas, "selection_changed", "and it is announced")


func test_revealing_a_node_that_is_not_drawn_does_nothing() -> void:
	await _shown()
	canvas.card_for(Sample.COMMIT).selected = true

	canvas.reveal(&"nobody")

	assert_eq(canvas.picked(), [Sample.COMMIT] as Array[StringName], "left as it was")
#endregion


#region Taking a call from the palette
## A dropped call says which call and where, and nothing about what it landed on.
##
## The surface this replaced looked for a card under the pointer and inserted
## after it, which made one drop two different operations depending on a pixel.
func test_a_dropped_call_reports_the_call_and_the_place() -> void:
	await _shown()
	watch_signals(canvas)

	canvas._drop_data(
		Vector2(200.0, 120.0), {ComposerCatalog.DRAGGED_CALL: &"gas.commit"}
	)

	var asked: Array = get_signal_parameters(canvas, "node_requested")
	var call_id: StringName = asked[0]
	var where: Vector2 = asked[1]
	assert_eq(call_id, &"gas.commit", "the call that was dragged")
	assert_eq(
		where,
		(Vector2(200.0, 120.0) + canvas.scroll_offset) / canvas.zoom,
		"and the place on the graph it landed on"
	)


func test_nothing_but_a_call_may_be_dropped() -> void:
	await _shown()

	assert_false(canvas._can_drop_data(Vector2.ZERO, "some text"), "not a call")
	assert_true(
		canvas._can_drop_data(
			Vector2.ZERO, {ComposerCatalog.DRAGGED_CALL: &"gas.commit"}
		),
		"but a call is"
	)
#endregion


#region How much of a card is worth drawing
## The detail follows the zoom, at the thresholds this project chose.
func test_the_detail_a_card_draws_follows_the_zoom() -> void:
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_FULL),
		ComposerCard.Detail.FULL,
		"close enough to read"
	)
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_TITLE),
		ComposerCard.Detail.TITLE,
		"far enough that only the name is worth it"
	)
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_TITLE - 0.01),
		ComposerCard.Detail.BLOCK,
		"and far enough that only the shape is"
	)


## Pulling back empties a card without moving anything on it.
##
## A card that shrank as its rows went away would take every pin with it, and
## the graph would appear to rearrange itself while somebody was only looking at
## it from further off.
func test_pulling_back_empties_a_card_without_resizing_it() -> void:
	await _shown()
	var card: ComposerCard = canvas.card_for(Sample.APPLY)
	card.show_detail(ComposerCard.Detail.FULL)
	await get_tree().process_frame
	var full: Vector2 = card.size

	card.show_detail(ComposerCard.Detail.BLOCK)
	await get_tree().process_frame

	assert_almost_eq(card.size.x, full.x, 1.0, "the card is the same width")
	assert_almost_eq(card.size.y, full.y, 1.0, "and the same height")
#endregion


#region Redrawing under itself
## A redraw that arrives mid-redraw does not place or connect the old cards.
##
## `show_graph` waits a frame for the cards to measure themselves. The version
## this replaced then carried on with the placements it had computed - against
## cards its own successor had already freed, and a `_graph` that could by then
## be null. Opening a second ability while the first was still settling crashed
## on exactly that.
func test_a_redraw_that_arrives_mid_redraw_leaves_the_newer_one_alone() -> void:
	var first: ComposerGraph = Sample.build()
	var second: ComposerGraph = Sample.build()
	second.nodes.resize(2)

	# Started without waiting, which is the whole situation: GDScript will not let
	# a coroutine's completion be held as a value, so it is launched the way the
	# editor launches it - and then superseded before it can finish.
	var start: Callable = Callable(canvas, "show_graph")
	start.call(first)
	await canvas.show_graph(second)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(
		_cards().size(), second.visible_nodes().size(), "the newer graph is what is drawn"
	)


## Showing nothing while a redraw is settling leaves nothing behind.
func test_clearing_the_canvas_mid_redraw_leaves_it_clear() -> void:
	var start: Callable = Callable(canvas, "show_graph")
	start.call(Sample.build())
	await canvas.show_graph(null)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_cards().size(), 0, "no cards")
	assert_eq(canvas.get_connection_list().size(), 0, "and no cables")
#endregion


#region Finding a card under a point
## A card is found where it actually is.
##
## The hit rectangle is in graph space, so it takes the card's position offset
## and the card's own size. Dividing the size by the zoom - as this did - shrinks
## every card's hit area as somebody zooms in, which is the opposite of what
## they see.
func test_the_card_under_a_point_is_the_one_drawn_there() -> void:
	await _shown()
	var card: ComposerCard = canvas.card_for(Sample.APPLY)
	var middle: Vector2 = card.position_offset + card.size * 0.5

	var at: Vector2 = middle * canvas.zoom - canvas.scroll_offset

	assert_eq(canvas._card_at(at), Sample.APPLY, "the card the point is inside")
	assert_eq(
		canvas._card_at(Vector2(-4000.0, -4000.0)), &"", "and nothing where there is none"
	)
#endregion
