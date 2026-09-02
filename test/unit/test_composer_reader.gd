## Reading a `.gd` into a graph.
##
## The tests that carry weight are the ones about what must not be lost: every
## line of the body belongs to exactly one node, and a file the subset refuses
## comes back with no nodes rather than with some of them. A partial graph is
## the dangerous outcome, because it looks complete.
##
## @meta_license: MIT
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"


func _script(statements: Array) -> String:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return HEAD + body


func _read(statements: Array) -> ComposerGraph:
	return ComposerReader.read(_script(statements), PATH)


#region Nothing is lost
## Every line of the body is inside exactly one node's span.
##
## This is the invariant the whole design rests on. A line no node claims is a
## line the writer will not reprint, and the statement disappears from the file
## on the first save - found when the ability stops working in the game.
func test_every_line_of_the_body_belongs_to_exactly_one_node() -> void:
	var statements: Array = [
		"commit_ability()",
		"",
		"# aim before firing",
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
	]
	var graph: ComposerGraph = _read(statements)
	var span: ComposerSpan = ComposerSubset.body_span(_script(statements).split("\n"))

	for line: int in range(span.first_line, span.last_line + 1):
		var owners: int = 0
		for node: ComposerNode in graph.nodes:
			if node.span.contains(line):
				owners += 1
		assert_eq(owners, 1, "line %d has exactly one owner" % line)


## A comment belongs to the statement below it, which is how a person reads it
## and what lets the writer put it back where it was.
func test_a_comment_is_carried_by_the_statement_it_precedes() -> void:
	var graph: ComposerGraph = _read(["# aim first", "commit_ability()"])

	assert_eq(graph.nodes.size(), 1, "a comment is not a node of its own")
	assert_eq(graph.nodes[0].span.first_line, 5, "but the node's span reaches up to it")
	assert_eq(graph.nodes[0].span.last_line, 6, "through its own line")
#endregion


#region Refusing rather than half-reading
## One line outside the subset ends the read. Returning the statements it did
## understand would be worse than returning nothing: the graph would look whole.
func test_an_unreadable_file_comes_back_with_no_nodes_at_all() -> void:
	var graph: ComposerGraph = _read([
		"commit_ability()",
		"for target in targets:",
		"\tapply_gameplay_effect(burning, target)",
	])

	assert_eq(graph.nodes.size(), 0, "not one statement, not some of them")
	assert_false(graph.is_editable(), "and the file is read-only")
	assert_true(graph.blocked_reason().contains("loop"), "with the reason named")


func test_a_script_with_no_entry_point_is_refused_rather_than_empty() -> void:
	var graph: ComposerGraph = ComposerReader.read("extends GameplayAbility\n", PATH)

	assert_false(graph.is_editable(), "an empty canvas would not say which it was")
	assert_ne(graph.blocked_reason(), "", "so it says")
#endregion


#region What a statement becomes
func test_a_call_is_named_the_way_a_person_would_say_it() -> void:
	var graph: ComposerGraph = _read(["apply_gameplay_effect(burning, 1.0)"])

	assert_eq(graph.nodes[0].title, "Apply Gameplay Effect", "spelled out, not snake_case")
	assert_eq(graph.nodes[0].type_id, &"apply_gameplay_effect", "and the call is remembered")


## Positional until the catalog names them. Inventing a parameter name here
## would put a word on the card the engine's API never used.
func test_arguments_become_fields_in_order() -> void:
	var graph: ComposerGraph = _read(["apply_gameplay_effect(burning, 1.0)"])
	var fields: Array[ComposerNode.Field] = graph.nodes[0].fields

	assert_eq(fields.size(), 2, "one field per argument")
	assert_eq(fields[0].display, "burning", "the first, as written")
	assert_eq(fields[1].display, "1.0", "and the second")


func test_a_call_with_no_arguments_has_no_fields() -> void:
	assert_eq(_read(["commit_ability()"]).nodes[0].fields.size(), 0, "nothing to show")


## The card says `await` because the statement suspends the ability. Every card
## is glass, so the treatment cannot carry that and the word has to.
func test_an_awaiting_statement_is_marked_as_one() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()", "commit_ability()"
	])

	assert_true(graph.nodes[0].awaits, "this one waits")
	assert_false(graph.nodes[1].awaits, "and this one does not")


## Only a local declaration produces something later lines can name, so it is
## the only shape that gets a value port.
func test_only_a_local_offers_a_value() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()", "commit_ability()"
	])

	assert_not_null(graph.nodes[0].find_port(ComposerReader.VALUE_OUT), "it declares one")
	assert_null(graph.nodes[1].find_port(ComposerReader.VALUE_OUT), "this one declares nothing")
#endregion


#region Wires
## Execution follows the statements, in the order they are written.
func test_statements_run_in_the_order_they_are_written() -> void:
	var graph: ComposerGraph = _read([
		"commit_ability()", "apply_gameplay_effect(burning, 1.0)", "end_ability()"
	])

	assert_eq(graph.connections.size(), 2, "two hops for three statements")
	assert_eq(graph.connections[0].from_node, graph.nodes[0].id, "the first leads")
	assert_eq(graph.connections[0].to_node, graph.nodes[1].id, "to the second")
	assert_eq(graph.connections[1].to_node, graph.nodes[2].id, "and on to the third")


## A statement inside a branch belongs to that branch. Joining across
## indentation would draw a path the code does not take.
func test_a_branch_does_not_run_into_the_statement_beside_it() -> void:
	var graph: ComposerGraph = _read([
		"if is_ready:", "\tcommit_ability()", "end_ability()"
	])

	var inside: ComposerNode = graph.nodes[1]
	var after: ComposerNode = graph.nodes[2]
	for wire: ComposerGraph.Connection in graph.connections:
		var crosses: bool = wire.from_node == inside.id and wire.to_node == after.id
		assert_false(crosses, "the branch's body does not lead to the line after it")


## A local reaches the later statements that name it, and only those.
func test_a_value_reaches_the_statement_that_uses_it() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
		"end_ability()",
	])

	var data: int = 0
	for wire: ComposerGraph.Connection in graph.connections:
		if wire.from_port != ComposerReader.VALUE_OUT:
			continue
		data += 1
		assert_eq(wire.to_node, graph.nodes[1].id, "to the statement that names it")
	assert_eq(data, 1, "and to no other")
#endregion
