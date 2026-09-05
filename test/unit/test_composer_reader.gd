## Reading a `.gd` into a graph.
##
## The tests that carry weight are the ones about what must not be lost: every
## line of the body belongs to exactly one node, and a file the subset refuses
## comes back with no nodes rather than with some of them. A partial graph is
## the dangerous outcome, because it looks complete.
##
## @meta_license: GAS_Engine Community Use License 1.0
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
		for node: ComposerNode in ComposerProjection.statements(graph):
			if node.span.contains(line):
				owners += 1
		assert_eq(owners, 1, "line %d has exactly one owner" % line)


## A comment belongs to the statement below it, which is how a person reads it
## and what lets the writer put it back where it was.
func test_a_comment_is_carried_by_the_statement_it_precedes() -> void:
	var graph: ComposerGraph = _read(["# aim first", "commit_ability()"])

	assert_eq(ComposerProjection.statements(graph).size(), 1, "a comment is not a node of its own")
	assert_eq(ComposerProjection.statements(graph)[0].span.first_line, 5, "but the node's span reaches up to it")
	assert_eq(ComposerProjection.statements(graph)[0].span.last_line, 6, "through its own line")
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

	assert_eq(ComposerProjection.statements(graph).size(), 0, "not one statement, not some of them")
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

	assert_eq(ComposerProjection.statements(graph)[0].title, "Apply Gameplay Effect", "spelled out, not snake_case")
	assert_eq(ComposerProjection.statements(graph)[0].type_id, &"apply_gameplay_effect", "and the call is remembered")


## Positional until the catalog names them. Inventing a parameter name here
## would put a word on the card the engine's API never used.
func test_arguments_become_fields_in_order() -> void:
	var graph: ComposerGraph = _read(["apply_gameplay_effect(burning, 1.0)"])
	var fields: Array[ComposerNode.Field] = ComposerProjection.statements(graph)[0].fields

	assert_eq(fields.size(), 2, "one field per argument")
	assert_eq(fields[0].display, "burning", "the first, as written")
	assert_eq(fields[1].display, "1.0", "and the second")


func test_a_call_with_no_arguments_has_no_fields() -> void:
	assert_eq(
		ComposerProjection.statements(_read(["commit_ability()"]))[0].fields.size(), 0,
		"nothing to show"
	)


## The card says `await` because the statement suspends the ability. Every card
## is glass, so the treatment cannot carry that and the word has to.
func test_an_awaiting_statement_is_marked_as_one() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()", "commit_ability()"
	])

	assert_true(ComposerProjection.statements(graph)[0].awaits, "this one waits")
	assert_false(ComposerProjection.statements(graph)[1].awaits, "and this one does not")


## Only a local declaration produces something later lines can name, so it is
## the only shape that gets a value port.
func test_only_a_local_offers_a_value() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()", "commit_ability()"
	])

	assert_not_null(ComposerProjection.statements(graph)[0].find_port(ComposerReader.VALUE_OUT), "it declares one")
	assert_null(ComposerProjection.statements(graph)[1].find_port(ComposerReader.VALUE_OUT), "this one declares nothing")
#endregion


#region Wires
## Execution follows the statements, in the order they are written.
func test_statements_run_in_the_order_they_are_written() -> void:
	var graph: ComposerGraph = _read([
		"commit_ability()", "apply_gameplay_effect(burning, 1.0)", "end_ability()"
	])

	var flow: Array[ComposerGraph.Connection] = graph.execution_connections()
	assert_eq(flow.size(), 3, "Entry into the first, then two hops for three statements")
	assert_eq(flow[0].from_node, ComposerFlow.ENTRY_ID, "the method begins")
	assert_eq(flow[0].to_node, ComposerProjection.statements(graph)[0].id, "at the first statement")
	assert_eq(flow[1].to_node, ComposerProjection.statements(graph)[1].id, "which leads to the second")
	assert_eq(flow[2].to_node, ComposerProjection.statements(graph)[2].id, "and on to the third")


## A statement inside a branch runs on to the line after it, by its own way out.
##
## This asserted the opposite, on the reasoning that joining across indentation
## draws a path the code does not take. The code does take it: GDScript leaves
## the body of an `if` and carries on. What that reasoning was really guarding
## against is joining the *wrong* pins, and that is what is checked here - the
## tail leaves by its own execution output, and the branch reaches the same
## statement by its False side rather than through the body.
func test_a_branch_body_runs_on_to_the_statement_beside_it() -> void:
	var graph: ComposerGraph = _read([
		"if is_ready:", "\tcommit_ability()", "end_ability()"
	])

	var branch: ComposerNode = ComposerProjection.statements(graph)[0]
	var inside: ComposerNode = ComposerProjection.statements(graph)[1]
	var after: ComposerNode = ComposerProjection.statements(graph)[2]

	assert_true(
		graph.has_connection(
			ComposerReader.wire(
				inside.id, ComposerReader.EXEC_OUT, after.id, ComposerReader.EXEC_IN
			)
		),
		"the body leaves by its own output"
	)
	assert_true(
		graph.has_connection(
			ComposerReader.wire(
				branch.id, ComposerReader.FALSE_OUT, after.id, ComposerReader.EXEC_IN
			)
		),
		"and the branch reaches it by its False side"
	)
	assert_null(
		branch.find_port(ComposerReader.EXEC_OUT),
		"never by a generic way out, which a branch does not have"
	)


## A branch leads into its own body.
##
## Without this edge the body floats: nothing runs into it, so the layout reads
## it as another place the method begins and puts it at the left margin beside
## the first line of the ability. Every reference ability is full of branches,
## and every one of them drew that way.
func test_a_branch_leads_into_the_statement_it_opens() -> void:
	var graph: ComposerGraph = _read([
		"if not commit_ability().is_ok():",
		"	return false",
		"end_ability()",
	])

	assert_true(
		graph.is_port_connected(ComposerProjection.statements(graph)[1].id, ComposerReader.EXEC_IN),
		"the body of the branch is reached"
	)
	var from_branch: int = 0
	for wire: ComposerGraph.Connection in graph.connections:
		if wire.from_node == ComposerProjection.statements(graph)[0].id:
			from_branch += 1
	assert_eq(from_branch, 2, "the branch leads both into its body and past it")


## Nothing but the first line of a body is left without a way in.
##
## The check that the last one generalises: a node nothing leads to is a card
## with no cable arriving, and the canvas has no way to say why.
func test_every_statement_but_the_first_is_reached() -> void:
	var graph: ComposerGraph = _read([
		"if ready:",
		"	commit_ability()",
		"	if armed:",
		"		execute_cue(fire)",
		"end_ability()",
	])

	for index: int in range(1, ComposerProjection.statements(graph).size()):
		assert_true(
			graph.is_port_connected(ComposerProjection.statements(graph)[index].id, ComposerReader.EXEC_IN),
			"%s is reached" % ComposerProjection.statements(graph)[index].title
		)


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
		assert_eq(wire.to_node, ComposerProjection.statements(graph)[1].id, "to the statement that names it")
	assert_eq(data, 1, "and to no other")


## A value lands on the argument that uses it, not on the run of control.
##
## The wire and the slot are two halves of the same fact - a value goes into a
## particular argument - and nothing else compares them. Without this the reader
## can point a cable at a port that was never built and every check downstream
## quietly skips it, which is how a type system ends up agreeing with everything.
func test_every_wire_lands_on_a_port_that_exists() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
		"end_ability()",
	])

	for wire: ComposerGraph.Connection in graph.connections:
		var leaves: ComposerNode = graph.find_node(wire.from_node)
		var lands: ComposerNode = graph.find_node(wire.to_node)
		assert_not_null(leaves.find_port(wire.from_port), "leaves %s" % wire.from_port)
		assert_not_null(lands.find_port(wire.to_port), "lands on %s" % wire.to_port)


func test_a_value_lands_on_the_argument_that_names_it() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
	])

	for wire: ComposerGraph.Connection in graph.connections:
		if wire.from_port != ComposerReader.VALUE_OUT:
			continue
		var slot: ComposerNode.Port = ComposerProjection.statements(graph)[1].find_port(wire.to_port)
		assert_eq(slot.label, "Source Asc", "the second argument, where it was written")
		assert_eq(slot.kind, ComposerNode.PortKind.DATA, "and a value port, not a run")
#endregion


## A field fed by a cable is marked as one.
##
## The card draws a chevron for it instead of the text, because the value is not
## typed there - it comes from the statement above. The mark existed and nothing
## ever set it, so every argument looked hand-written whether it was or not.
func test_an_argument_a_cable_arrives_at_is_marked_as_wired() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
	])

	var fed: ComposerNode = ComposerProjection.statements(graph)[1]
	assert_eq(
		fed.fields[1].source, ComposerNode.ValueSource.WIRED,
		"the argument the cable lands on"
	)
	assert_eq(
		fed.fields[0].source, ComposerNode.ValueSource.LITERAL,
		"and the one beside it was typed"
	)
	assert_true(fed.fields[1].is_satisfied(), "a wired value is a value")


## A statement that reaches into a local is not cabled to it.
##
## This test said the opposite until Composer 3.2, and the old answer was the
## more tempting one: `pick.target_data` plainly needs `pick`, so why not draw
## the dependency? Because a cable on this canvas is something a person can take
## hold of, and that one could not be. Unplugging it and dropping it on another
## local would have had to rewrite `pick.target_data` into `other.target_data`,
## which is not what a wire means anywhere else, and re-pointing it at a whole
## value would have thrown away the `.target_data` they wrote.
##
## So the dependency is still visible - it is the argument text, on the card,
## where it can be edited - and the cable is reserved for the case where the
## argument *is* the local and moving it is honest.
func test_a_statement_that_reaches_into_a_local_is_not_cabled_to_it() -> void:
	var graph: ComposerGraph = _read([
		"var pick: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, pick.target_data)",
	])

	assert_eq(graph.data_connections().size(), 0, "no cable for an expression")
	assert_eq(
		ComposerProjection.statements(graph)[1].fields[1].display, "pick.target_data",
		"and the dependency is on the card, in the words the file uses"
	)


## Depending on a local and being one are two different things.
##
## One table, because they are the same statement with one character's
## difference and opposite answers. Passed whole, the argument *is* the local
## and can be swapped for another name. Reached into, it is an expression
## somebody wrote, and offering to swap the whole thing would throw away the
## `.target_data` they meant - so it stays text they can type over.
const FED: Array[Array] = [
	[
		"apply_gameplay_effect(burning, target)", ComposerNode.ValueSource.WIRED,
		false, "passed whole, so it is the local",
	],
	[
		"apply_gameplay_effect(burning, target.data)", ComposerNode.ValueSource.LITERAL,
		true, "reached into, so it is an expression",
	],
]


func test_being_fed_by_a_local_is_not_the_same_as_being_it() -> void:
	for row: Array in FED:
		var written: String = row[0]
		var expected: ComposerNode.ValueSource = row[1]
		var typable: bool = row[2]
		var described: String = row[3]

		var graph: ComposerGraph = _read([
			"var target: Node = await wait_target_data()", written,
		])
		var fed: ComposerNode = ComposerProjection.statements(graph)[1]

		assert_eq(fed.fields[1].source, expected, described)
		assert_eq(fed.may_type(fed.fields[1]), typable, "%s: typable" % described)


## A name inside a longer one is a coincidence of spelling, not a dependency.
func test_a_longer_name_is_not_a_dependency() -> void:
	var graph: ComposerGraph = _read([
		"var pick: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, picked_earlier)",
	])

	for wire: ComposerGraph.Connection in graph.connections:
		assert_ne(wire.from_port, ComposerReader.VALUE_OUT, "no cable was invented")


#region What a pin can hold
## Only a local's output fans out. Everything else takes one wire.
##
## The count is the difference between a value that can feed three statements
## and an argument that holds one thing, and the canvas asks this before it lets
## a drag land. Read off a real projection rather than asserted about the enum:
## a field nobody assigns defaults to SINGLE and agrees with every rule anyone
## writes down, which is how it sat unassigned in the first place.
func test_only_a_value_output_carries_more_than_one_wire() -> void:
	var graph: ComposerGraph = _read([
		"var target: Node = await wait_target_data()",
		"apply_gameplay_effect(burning, target)",
	])

	var fanning: int = 0
	for node: ComposerNode in graph.nodes:
		for pin: ComposerNode.Port in node.ports:
			var many: bool = pin.multiplicity == ComposerNode.PortMultiplicity.MULTIPLE
			var produces_a_value: bool = (
				pin.kind == ComposerNode.PortKind.DATA
				and pin.direction == ComposerNode.PortDirection.OUTPUT
			)
			assert_eq(many, produces_a_value, "%s on %s" % [pin.id, node.title])
			fanning += 1 if many else 0

	assert_eq(fanning, 1, "exactly the one local, so the rule was exercised")
#endregion
