## Where execution goes, asked of the projection rather than of the file.
##
## `ComposerFlow` answers questions the canvas and the editing operations both
## need - what runs first, what runs after this, where a new statement would go
## so that it runs before the method returns. They used to be answered by
## reading indentation at the call site, which is how the same question got
## three slightly different answers.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/probe.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"


func _read(statements: Array) -> ComposerGraph:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return ComposerReader.read(HEAD + body, PATH)


#region Entry
## Entry is in the graph, is drawn, and is in no line of the file.
##
## All three matter and they are separate promises: the canvas needs it to start
## a wire from, a person needs to see where the method begins, and the writer
## must never look for it on disk - printing it would put a card into the source.
func test_entry_is_a_drawn_node_that_no_line_backs() -> void:
	var graph: ComposerGraph = _read(["return true"])
	var entry: ComposerNode = graph.find_node(ComposerFlow.ENTRY_ID)

	assert_not_null(entry, "the graph has a beginning")
	assert_false(entry.source_backed, "which the file does not contain")
	assert_true(entry.visible_in_graph, "and a person can see")
	assert_eq(
		entry.projection_kind, ComposerNode.ProjectionKind.ENTRY, "and it says what it is"
	)


## Entry leads somewhere and nothing leads into it.
func test_entry_only_leaves() -> void:
	var graph: ComposerGraph = _read(["commit_ability()", "return true"])
	var entry: ComposerNode = graph.find_node(ComposerFlow.ENTRY_ID)

	assert_not_null(entry.find_port(ComposerReader.EXEC_OUT), "it leads out")
	assert_null(entry.find_port(ComposerReader.EXEC_IN), "and nothing arrives at it")
	assert_null(
		ComposerFlow.predecessor_of(graph, ComposerFlow.ENTRY_ID),
		"so it has no predecessor"
	)
#endregion


#region Asking the flow
func test_the_first_statement_is_what_entry_leads_to() -> void:
	var graph: ComposerGraph = _read(["commit_ability()", "return true"])
	var after: Array[ComposerNode] = ComposerFlow.successors_of(
		graph, ComposerFlow.ENTRY_ID
	)

	assert_eq(after.size(), 1, "one way out of the beginning")
	assert_eq(after[0].id, ComposerProjection.statements(graph)[0].id, "into the first statement")


func test_a_statement_knows_what_ran_before_it() -> void:
	var graph: ComposerGraph = _read([
		"commit_ability()", "apply_gameplay_effect(burning, 1.0)", "return true"
	])
	var second: ComposerNode = ComposerProjection.statements(graph)[1]
	var before: ComposerNode = ComposerFlow.predecessor_of(graph, second.id)

	assert_not_null(before, "something ran before it")
	assert_eq(before.id, ComposerProjection.statements(graph)[0].id, "and it was the statement above")


## The last `return`, not the first, because early returns live inside branches
## and the End a person means is the one at the bottom of the method.
func test_main_end_is_the_last_return() -> void:
	var graph: ComposerGraph = _read([
		"if ready:", "\treturn false", "return true"
	])
	var ends: Array[ComposerNode] = []
	for node: ComposerNode in ComposerProjection.statements(graph):
		if node.terminal:
			ends.append(node)

	assert_eq(ends.size(), 2, "the body returns twice")
	assert_eq(
		ComposerFlow.main_end(graph).id, ends[1].id, "and the method's End is the later one"
	)


func test_source_region_of_entry_is_no_region_at_all() -> void:
	var graph: ComposerGraph = _read(["return true"])

	assert_false(
		ComposerFlow.source_region(graph, ComposerFlow.ENTRY_ID).is_valid(),
		"a node the file does not contain owns no lines"
	)
	assert_true(
		ComposerFlow.source_region(graph, ComposerProjection.statements(graph)[0].id).is_valid(),
		"and a statement owns its own"
	)
#endregion


#region Where a new statement goes
## Before the return, because after it is a line that never runs.
##
## This is the whole reason the number exists. 3.1 inserted after the last
## statement, and when the last statement was the `return` the canvas drew
## `End -> Wait Delay` - a picture of code that cannot happen.
func test_a_new_statement_goes_in_before_the_method_returns() -> void:
	var graph: ComposerGraph = _read(["commit_ability()", "return true"])
	var end: ComposerNode = ComposerFlow.main_end(graph)

	assert_eq(
		ComposerFlow.insertion_before_main_end(graph), end.span.last_line - 1,
		"the line above End, so what is written there still runs"
	)
#endregion
