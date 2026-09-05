## Execution drawn the way GDScript runs it, block by block.
##
## The builder this replaces walked the statements keeping a table of "the last
## statement at each depth". That reads a straight body correctly and a branch
## wrongly: the tail of a true body was never joined back to the statement after
## the `if`, so the canvas drew a run of statements as a dead end while the file
## carried on through it - and a branch had one generic way out, so nothing on
## the canvas could say which path a statement was on.
##
## Every case here is a real body read back, and every assertion is about an
## edge between semantic pins. Never about a node id: an id is derived from the
## line a statement was read from, so asserting on one is asserting on line
## numbers.
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


## The statement whose text contains `written`. Two statements never contain the
## same fragment in any body here.
func _at(graph: ComposerGraph, written: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(graph):
		if node.text.contains(written):
			return node
	return null


## Whether execution runs out of one node's pin into another's input.
func _runs(
	graph: ComposerGraph, from: ComposerNode, port: StringName, to: ComposerNode
) -> bool:
	if from == null or to == null:
		return false
	return graph.has_connection(
		ComposerReader.wire(from.id, port, to.id, ComposerReader.EXEC_IN)
	)


## Every execution edge, written as `Title.pin -> Title`, so a failure says what
## the graph actually holds instead of leaving somebody to print it.
func _drawn(graph: ComposerGraph) -> String:
	var said: PackedStringArray = PackedStringArray()
	for wire: ComposerGraph.Connection in graph.execution_connections():
		var from: ComposerNode = graph.find_node(wire.from_node)
		var to: ComposerNode = graph.find_node(wire.to_node)
		said.append("%s.%s -> %s" % [
			from.title if from != null else wire.from_node,
			wire.from_port,
			to.title if to != null else wire.to_node,
		])
	said.sort()
	return ", ".join(said)


func _entry(graph: ComposerGraph) -> ComposerNode:
	return graph.find_node(ComposerFlow.ENTRY_ID)


#region A branch with no else
## The four edges of an `if` with nothing answering it, and no others.
##
## The false side falls through to the continuation, and so does the tail of the
## true body. Both are what the file does, and the second is the one the old
## builder never drew.
func test_a_branch_with_no_else_joins_both_sides_to_the_continuation() -> void:
	var graph: ComposerGraph = _read([
		"if ready:", "\tfire()", "after()", "return true"
	])
	var branch: ComposerNode = _at(graph, "if ready:")
	var fire: ComposerNode = _at(graph, "fire()")
	var after: ComposerNode = _at(graph, "after()")
	var end: ComposerNode = _at(graph, "return true")

	assert_true(_runs(graph, _entry(graph), ComposerReader.EXEC_OUT, branch), "Entry -> Branch")
	assert_true(_runs(graph, branch, ComposerReader.TRUE_OUT, fire), "True -> Fire")
	assert_true(_runs(graph, fire, ComposerReader.EXEC_OUT, after), "Fire -> After")
	assert_true(_runs(graph, branch, ComposerReader.FALSE_OUT, after), "False -> After")
	assert_true(_runs(graph, after, ComposerReader.EXEC_OUT, end), "After -> End")
	assert_eq(graph.execution_connections().size(), 5, "and nothing else: %s" % _drawn(graph))


## A branch fans out by its own two pins and by no generic one.
func test_a_branch_has_true_and_false_and_no_generic_output() -> void:
	var branch: ComposerNode = _at(
		_read(["if ready:", "\tfire()", "return true"]), "if ready:"
	)

	assert_not_null(branch.find_port(ComposerReader.TRUE_OUT), "a True pin")
	assert_not_null(branch.find_port(ComposerReader.FALSE_OUT), "a False pin")
	assert_null(branch.find_port(ComposerReader.EXEC_OUT), "and no third way out")
	assert_eq(
		branch.find_port(ComposerReader.TRUE_OUT).label,
		ComposerFlowBuilder.TRUE_LABEL,
		"named for a person to read"
	)
	assert_eq(branch.find_port(ComposerReader.FALSE_OUT).label, ComposerFlowBuilder.FALSE_LABEL)


## A true body that returns leaves by nothing, so the End is not joined onward.
func test_a_terminal_true_body_does_not_reach_the_continuation() -> void:
	var graph: ComposerGraph = _read([
		"if invalid:", "\treturn false", "after()", "return true"
	])
	var branch: ComposerNode = _at(graph, "if invalid:")
	var refused: ComposerNode = _at(graph, "return false")
	var after: ComposerNode = _at(graph, "after()")

	assert_true(_runs(graph, branch, ComposerReader.TRUE_OUT, refused), "True -> End(false)")
	assert_true(_runs(graph, branch, ComposerReader.FALSE_OUT, after), "False -> After")
	assert_false(
		_runs(graph, refused, ComposerReader.EXEC_OUT, after),
		"and nothing runs after a return: %s" % _drawn(graph)
	)
	assert_null(refused.find_port(ComposerReader.EXEC_OUT), "which has no way out at all")
#endregion


#region Chains
## `if` / `elif` / `else`, with the false side of each asking the next question.
func test_an_elif_chain_runs_down_the_false_sides() -> void:
	var graph: ComposerGraph = _read([
		"if a:", "\tone()",
		"elif b:", "\ttwo()",
		"else:", "\tthree()",
		"after()", "return true",
	])
	var first: ComposerNode = _at(graph, "if a:")
	var second: ComposerNode = _at(graph, "elif b:")
	var one: ComposerNode = _at(graph, "one()")
	var two: ComposerNode = _at(graph, "two()")
	var three: ComposerNode = _at(graph, "three()")
	var after: ComposerNode = _at(graph, "after()")

	assert_true(_runs(graph, first, ComposerReader.TRUE_OUT, one), "a True -> One")
	assert_true(_runs(graph, first, ComposerReader.FALSE_OUT, second), "a False -> Branch(b)")
	assert_true(_runs(graph, second, ComposerReader.TRUE_OUT, two), "b True -> Two")
	assert_true(_runs(graph, second, ComposerReader.FALSE_OUT, three), "b False -> Three")
	for tail: ComposerNode in [one, two, three]:
		assert_true(
			_runs(graph, tail, ComposerReader.EXEC_OUT, after),
			"every arm reaches the continuation: %s" % _drawn(graph)
		)


## The inner branch's continuation is the outer body's next statement.
func test_a_nested_branch_merges_into_its_own_continuation_first() -> void:
	var graph: ComposerGraph = _read([
		"if outer:",
		"\tif inner:",
		"\t\tdeep()",
		"\tstill_inside()",
		"outside()",
		"return true",
	])
	var outer: ComposerNode = _at(graph, "if outer:")
	var inner: ComposerNode = _at(graph, "if inner:")
	var deep: ComposerNode = _at(graph, "deep()")
	var inside: ComposerNode = _at(graph, "still_inside()")
	var outside: ComposerNode = _at(graph, "outside()")

	assert_true(_runs(graph, outer, ComposerReader.TRUE_OUT, inner), "outer True -> inner")
	assert_true(_runs(graph, inner, ComposerReader.TRUE_OUT, deep), "inner True -> deep")
	assert_true(_runs(graph, deep, ComposerReader.EXEC_OUT, inside), "deep -> still inside")
	assert_true(_runs(graph, inner, ComposerReader.FALSE_OUT, inside), "inner False -> still inside")
	assert_true(_runs(graph, inside, ComposerReader.EXEC_OUT, outside), "and on out")
	assert_true(_runs(graph, outer, ComposerReader.FALSE_OUT, outside), "outer False -> outside")
	assert_false(
		_runs(graph, inner, ComposerReader.FALSE_OUT, outside),
		"the inner false side stops at its own continuation: %s" % _drawn(graph)
	)
#endregion


#region Switches
## Every case reaches its body, and every body reaches the continuation.
func test_a_switch_gives_each_case_its_own_output() -> void:
	var graph: ComposerGraph = _read([
		"match state:",
		"\tState.A:", "\t\tone()",
		"\tState.B:", "\t\ttwo()",
		"after()", "return true",
	])
	var switch: ComposerNode = _at(graph, "match state:")
	var one: ComposerNode = _at(graph, "one()")
	var two: ComposerNode = _at(graph, "two()")
	var after: ComposerNode = _at(graph, "after()")

	assert_null(switch.find_port(ComposerReader.EXEC_OUT), "no generic way out")
	assert_true(_runs(graph, switch, &"case_0", one), "the first case runs its body")
	assert_true(_runs(graph, switch, &"case_1", two), "and so does the second")
	assert_eq(switch.find_port(&"case_0").label, "State.A", "labelled as the file writes it")
	assert_eq(switch.find_port(&"case_1").label, "State.B")
	assert_true(_runs(graph, one, ComposerReader.EXEC_OUT, after), "One -> After")
	assert_true(_runs(graph, two, ComposerReader.EXEC_OUT, after), "Two -> After")


## With no wildcard the language carries on past the match, so the graph says so.
func test_a_switch_without_a_wildcard_has_a_no_match_path() -> void:
	var graph: ComposerGraph = _read([
		"match state:", "\tState.A:", "\t\tone()", "after()", "return true"
	])
	var switch: ComposerNode = _at(graph, "match state:")
	var after: ComposerNode = _at(graph, "after()")

	var unmatched: ComposerNode.Port = switch.find_port(ComposerReader.UNMATCHED_OUT)
	assert_not_null(unmatched, "there is a way out for no case at all")
	assert_eq(unmatched.label, ComposerFlowBuilder.NO_MATCH_LABEL)
	assert_true(
		_runs(graph, switch, ComposerReader.UNMATCHED_OUT, after), "which reaches the continuation"
	)


## A wildcard is that path already written down, so there is not a second one.
func test_a_wildcard_case_replaces_the_no_match_path() -> void:
	var graph: ComposerGraph = _read([
		"match state:",
		"\tState.A:", "\t\tone()",
		"\t_:", "\t\ttwo()",
		"after()", "return true",
	])
	var switch: ComposerNode = _at(graph, "match state:")

	assert_null(
		switch.find_port(ComposerReader.UNMATCHED_OUT),
		"no second pin for a path the file already has: %s" % _drawn(graph)
	)
	assert_eq(switch.find_port(&"case_1").label, "_", "the wildcard is a case like any other")
	assert_true(_runs(graph, switch, &"case_1", _at(graph, "two()")), "and it runs its body")


#endregion


#region Islands
## A path that ends does not reach the continuation, and its neighbour does.
##
## Two ways for a path to stop - a case whose body returns, and a stop the
## Composer wrote when it cut one - said once, because the fact is one fact. The
## row names what stops and what carries on, and both are checked every time so
## a body that stopped everything would fail rather than half-pass.
const ENDINGS: Array = [
	[
		"a case that returns",
		[
			"match state:",
			"\tState.A:", "\t\treturn false",
			"\tState.B:", "\t\ttwo()",
			"after()", "return true",
		],
		"return false",
	],
	[
		"a marked flow stop",
		[
			"if ready:",
			"\tfire()",
			"\treturn false # @composer-flow-stop",
			"after()", "return true",
		],
		"fire()",
	],
]


func test_a_path_that_ends_does_not_reach_the_continuation() -> void:
	var checked: int = 0
	for row: Array in ENDINGS:
		var described: String = row[0]
		var body: Array = row[1]
		var stops: String = row[2]

		var graph: ComposerGraph = _read(body)
		var after: ComposerNode = _at(graph, "after()")

		assert_false(
			_runs(graph, _at(graph, stops), ComposerReader.EXEC_OUT, after),
			"%s: stops there - %s" % [described, _drawn(graph)]
		)
		assert_true(
			graph.is_port_connected(after.id, ComposerReader.EXEC_IN),
			"%s: and the continuation is still reached" % described
		)
		checked += 1
	assert_eq(checked, ENDINGS.size(), "every ending was tried")
	assert_gt(checked, 0, "and there were endings to try")


## The stop itself is machinery, not a card.
func test_a_flow_stop_draws_no_card() -> void:
	var graph: ComposerGraph = _read([
		"if ready:",
		"\tfire()",
		"\treturn false # @composer-flow-stop",
		"after()", "return true",
	])

	assert_false(_at(graph, "@composer-flow-stop").visible_in_graph, "no card for it")
	assert_true(
		_runs(graph, _at(graph, "if ready:"), ComposerReader.FALSE_OUT, _at(graph, "after()")),
		"and the false side still reaches the continuation"
	)


## An unplugged island is joined to itself and to nothing else.
func test_a_detached_island_is_wired_inside_and_reaches_nothing_live() -> void:
	var graph: ComposerGraph = _read([
		"commit_ability()",
		"if false: # @composer-detached detached_1",
		"\tone()",
		"\ttwo()",
		"after()",
		"return true",
	])
	var one: ComposerNode = _at(graph, "one()")
	var two: ComposerNode = _at(graph, "two()")
	var commit: ComposerNode = _at(graph, "commit_ability()")
	var after: ComposerNode = _at(graph, "after()")

	assert_true(_runs(graph, one, ComposerReader.EXEC_OUT, two), "the island runs inside itself")
	assert_false(graph.is_port_connected(one.id, ComposerReader.EXEC_IN), "nothing runs into it")
	assert_false(
		_runs(graph, two, ComposerReader.EXEC_OUT, after), "and nothing runs out of it"
	)
	assert_true(
		_runs(graph, commit, ComposerReader.EXEC_OUT, after),
		"the live path steps over it: %s" % _drawn(graph)
	)


#endregion


#region What no connection may touch
## Every end of every wire is Entry or a card somebody is shown.
##
## The invariant the whole projection rests on. A support header - an `else:`, a
## case, the wrapper round an island - is a line the reader accounts for and
## nobody sees, so a wire ending on one is a wire ending nowhere: the painter
## silently drops it and the canvas quietly disagrees with the graph.
const EVERY_SHAPE: Array = [
	["a branch", ["if ready:", "\tfire()", "after()", "return true"]],
	["a chain", ["if a:", "\tone()", "elif b:", "\ttwo()", "else:", "\tthree()", "return true"]],
	["a switch", ["match state:", "\tState.A:", "\t\tone()", "\t_:", "\t\ttwo()", "return true"]],
	["an island", [
		"if false: # @composer-detached detached_1", "\tone()", "after()", "return true"
	]],
]


func test_no_connection_touches_a_node_nobody_is_shown() -> void:
	var checked: int = 0
	for row: Array in EVERY_SHAPE:
		var described: String = row[0]
		# Typed out of the row before it is passed on: a row of an untyped table
		# is a Variant, and handing one straight to a typed parameter is refused.
		var body: Array = row[1]
		var graph: ComposerGraph = _read(body)
		assert_true(graph.is_editable(), "%s: %s" % [described, graph.blocked_reason()])

		for wire: ComposerGraph.Connection in graph.connections:
			var from: ComposerNode = graph.find_node(wire.from_node)
			var to: ComposerNode = graph.find_node(wire.to_node)
			assert_not_null(from, "%s: %s is a node" % [described, wire.from_node])
			assert_not_null(to, "%s: %s is a node" % [described, wire.to_node])
			assert_true(
				from.visible_in_graph, "%s: %s is drawn" % [described, from.title]
			)
			assert_true(to.visible_in_graph, "%s: %s is drawn" % [described, to.title])
			checked += 1
	assert_gt(checked, 0, "there were wires to check")


## And a support header offers nothing to end on in the first place.
func test_a_support_header_has_no_pins_at_all() -> void:
	var graph: ComposerGraph = _read([
		"if a:", "\tone()", "else:", "\ttwo()", "return true"
	])
	var otherwise: ComposerNode = _at(graph, "else:")

	assert_false(otherwise.visible_in_graph, "the else is not a card")
	assert_eq(otherwise.ports.size(), 0, "so it has nowhere to plug anything in")
#endregion


#region Asking what ran before
## A merge has several predecessors, and saying "the one" would pick at random.
func test_a_merge_reports_every_predecessor_and_no_single_one() -> void:
	var graph: ComposerGraph = _read([
		"if ready:", "\tfire()", "after()", "return true"
	])
	var after: ComposerNode = _at(graph, "after()")
	var fire: ComposerNode = _at(graph, "fire()")

	var before: Array[ComposerNode] = ComposerFlow.predecessors_of(graph, after.id)
	assert_eq(before.size(), 2, "reached from the body and from the false side")
	assert_null(
		ComposerFlow.predecessor_of(graph, after.id),
		"so there is no single statement it runs after"
	)
	assert_eq(
		ComposerFlow.predecessor_of(graph, fire.id).title, "Branch",
		"where there is exactly one, it is still answered"
	)
#endregion
