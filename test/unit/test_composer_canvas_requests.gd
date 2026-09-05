## What the canvas says a gesture meant.
##
## Split from the drawing tests because they are two jobs: one is a graph going
## in and cards coming out, this one is a hand moving and a request coming out.
## The translation is the half only this project can get wrong - which pin a
## drawn index stands for, and which of the two positions a released wire is
## reported at - and GraphEdit already knows how to drag a curve.
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


func _shown() -> ComposerGraph:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)
	return graph


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


#region A wire let go over nothing
## Where the cable was let go is reported twice, because it is two questions.
##
## One is where on the graph the new card belongs - a point in a space that
## scrolls and zooms. The other is where on the window the menu asking about it
## opens. The canvas is the only place that knows the scroll and the zoom, so it
## is the only place that can tell them apart, and it used to report one value
## for both: the menu opened at a graph coordinate, and the card that came out
## of it landed wherever the layout felt like putting it.
##
## Both directions, in one table, because they are one rule said twice.
const LET_GO: Array = [
	["connection_to_empty_requested", true, "dragged out of a pin"],
	["connection_from_empty_requested", false, "dragged into one"],
]


func test_a_wire_let_go_over_nothing_reports_both_of_its_positions() -> void:
	var checked: int = 0
	for row: Array in LET_GO:
		var reported: String = row[0]
		var outgoing: bool = row[1]
		var described: String = row[2]
		await _shown()
		canvas.scroll_offset = Vector2(400.0, 250.0)
		canvas.zoom = 2.0
		watch_signals(canvas)
		var released: Vector2 = Vector2(120.0, 90.0)

		if outgoing:
			canvas._on_connection_to_empty(Sample.APPLY, 0, released)
		else:
			canvas._on_connection_from_empty(Sample.APPLY, 0, released)

		assert_signal_emitted(canvas, reported, described)
		var said: Array = get_signal_parameters(canvas, reported)
		var on_the_graph: Vector2 = said[2]
		var on_the_window: Vector2 = said[3]
		assert_eq(
			on_the_graph, canvas.graph_point_of(released),
			"%s: the graph point carries the scroll and the zoom" % described
		)
		assert_eq(
			on_the_window, released + canvas.global_position,
			"%s: and the screen point does not" % described
		)
		assert_ne(on_the_graph, on_the_window, "%s: which is why both are said" % described)
		checked += 1
	assert_eq(checked, LET_GO.size(), "both directions were tried")
	assert_gt(checked, 0, "and there were directions to try")
#endregion
