## The projection model: a file described, never a second copy of it.
##
## Nothing here executes. The value of these tests is not that the getters work,
## it is that the three decisions the whole Composer rests on cannot be undone
## quietly: editability is read from the diagnostics, a missing value is its own
## state, and a node knows the lines it came from.
##
## @meta_license: MIT
extends GutTest

const NODE_ID: StringName = &"n1"
const OTHER_ID: StringName = &"n2"
const PORT_IN: StringName = &"in"
const PORT_OUT: StringName = &"out"
const FIELD_LEVEL: String = "Level"
const FIELD_MAGNITUDE: String = "Magnitude"


## The model carries no constructors: the reader will build these from one
## place once it exists, and three near-identical `_init` bodies written ahead
## of it would be speculative code. Tests assemble what they need here.
func _field(
	label: String, shown: String,
	from: ComposerNode.ValueSource = ComposerNode.ValueSource.LITERAL
) -> ComposerNode.Field:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.label = label
	field.display = shown
	field.source = from
	return field


func _diagnostic(
	level: ComposerGraph.Severity, text: String, first: int
) -> ComposerGraph.Diagnostic:
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = level
	found.message = text
	found.span = ComposerSpan.new(first, first)
	return found


func _wire(source: StringName, target: StringName) -> ComposerGraph.Connection:
	var wire: ComposerGraph.Connection = ComposerGraph.Connection.new()
	wire.from_node = source
	wire.from_port = PORT_OUT
	wire.to_node = target
	wire.to_port = PORT_IN
	return wire


func _node(id: StringName, first: int, last: int) -> ComposerNode:
	var node: ComposerNode = ComposerNode.new()
	node.id = id
	node.span = ComposerSpan.new(first, last)
	return node


#region Span
## An empty span and a one-line span are different things.
##
## Reading "empty" as `first == last` would make line 7 of a file
## indistinguishable from a node that came from nowhere, and every caller would
## have to remember which it was holding.
func test_an_empty_span_is_not_a_one_line_span() -> void:
	var nowhere: ComposerSpan = ComposerSpan.new()
	var one_line: ComposerSpan = ComposerSpan.new(7, 7)

	assert_false(nowhere.is_valid(), "nothing was read from it")
	assert_true(one_line.is_valid(), "line 7 is a real place")
	assert_eq(nowhere.line_count(), 0, "and covers no lines")
	assert_eq(one_line.line_count(), 1, "while this one covers exactly one")


func test_a_span_includes_both_of_its_ends() -> void:
	var span: ComposerSpan = ComposerSpan.new(10, 12)

	assert_true(span.contains(10), "the first line is inside it")
	assert_true(span.contains(12), "and so is the last")
	assert_false(span.contains(9), "one before is not")
	assert_false(span.contains(13), "and neither is one after")
	assert_eq(span.line_count(), 3, "three lines, counted the way a person does")


func test_an_invalid_span_contains_nothing() -> void:
	assert_false(ComposerSpan.new().contains(1), "not even line 1")
#endregion


#region Fields
## A missing value is a third state, not an empty literal.
##
## This is what keeps the card and the Output panel from contradicting each
## other. Both read this: the field draws "not connected" and the diagnostic
## says the same thing, because neither is deciding it independently.
func test_a_missing_field_is_not_a_literal_with_no_text() -> void:
	var empty_text: ComposerNode.Field = _field(FIELD_LEVEL, "")
	var absent: ComposerNode.Field = _field(FIELD_MAGNITUDE, "", ComposerNode.ValueSource.MISSING)

	assert_eq(
		empty_text.source, ComposerNode.ValueSource.LITERAL,
		"an author may write an empty string on purpose"
	)
	assert_true(empty_text.is_satisfied(), "so it is satisfied")
	assert_eq(absent.source, ComposerNode.ValueSource.MISSING, "this one has nothing at all")
	assert_false(absent.is_satisfied(), "and says so")


func test_a_node_is_unsatisfied_while_any_field_is_missing() -> void:
	var node: ComposerNode = _node(NODE_ID, 1, 2)
	node.fields = [_field(FIELD_LEVEL, "1.0")] as Array[ComposerNode.Field]
	assert_true(node.is_satisfied(), "everything it needs is there")

	node.fields.append(
		_field(FIELD_MAGNITUDE, "", ComposerNode.ValueSource.MISSING)
	)
	assert_false(node.is_satisfied(), "and now one of them is not")
#endregion


#region Editability
## Whether a file can be edited is read from the diagnostics, never stored.
##
## A flag beside the list is a second place to look and a second thing to keep
## true. The first time the two disagreed, the canvas and the Output panel would
## say different things about the same file.
func test_a_graph_with_no_diagnostics_is_editable() -> void:
	assert_true(ComposerGraph.new().is_editable(), "nothing said it was not")
	assert_eq(ComposerGraph.new().blocked_reason(), "", "and there is no reason to give")


func test_errors_and_warnings_do_not_make_a_file_unreadable() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.diagnostics = [
		_diagnostic(ComposerGraph.Severity.ERROR, "port not connected", 4),
		_diagnostic(ComposerGraph.Severity.WARNING, "value never read", 9),
	] as Array[ComposerGraph.Diagnostic]

	assert_true(
		graph.is_editable(),
		"a wrong graph is still a graph; only an unreadable file is refused"
	)


func test_not_representable_blocks_editing_and_says_why() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.diagnostics = [
		_diagnostic(
			ComposerGraph.Severity.NOT_REPRESENTABLE, "uses for - line 42", 42
		),
	] as Array[ComposerGraph.Diagnostic]

	assert_false(graph.is_editable(), "the file is fine; this tool cannot draw it")
	assert_eq(
		graph.blocked_reason(), "uses for - line 42",
		"and hands over the reason rather than an empty canvas"
	)
#endregion


#region Lines back to nodes
## The round trip that makes the Source panel possible.
func test_a_line_finds_the_node_it_belongs_to() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.nodes = [_node(NODE_ID, 10, 12), _node(OTHER_ID, 14, 20)] as Array[ComposerNode]

	assert_eq(graph.node_at_line(11).id, NODE_ID, "inside the first")
	assert_eq(graph.node_at_line(14).id, OTHER_ID, "on the second's first line")
	assert_null(graph.node_at_line(13), "the gap between them belongs to neither")
#endregion


#region Ports and wires
## A port with no wire still exists, and the view needs to know which is which:
## drawing only the connected ones makes a node look like it takes nothing.
func test_a_port_reports_whether_anything_is_attached() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.nodes = [_node(NODE_ID, 1, 1), _node(OTHER_ID, 2, 2)] as Array[ComposerNode]
	graph.connections = [
		_wire(NODE_ID, OTHER_ID),
	] as Array[ComposerGraph.Connection]

	assert_true(graph.is_port_connected(NODE_ID, PORT_OUT), "the wire leaves here")
	assert_true(graph.is_port_connected(OTHER_ID, PORT_IN), "and lands here")
	assert_false(graph.is_port_connected(NODE_ID, PORT_IN), "nothing arrives at this one")


func test_connections_are_found_from_either_end() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.connections = [
		_wire(NODE_ID, OTHER_ID),
	] as Array[ComposerGraph.Connection]

	assert_eq(graph.connections_for(NODE_ID).size(), 1, "the source sees it")
	assert_eq(graph.connections_for(OTHER_ID).size(), 1, "and so does the target")
	assert_eq(graph.connections_for(&"absent").size(), 0, "a stranger sees nothing")
#endregion
