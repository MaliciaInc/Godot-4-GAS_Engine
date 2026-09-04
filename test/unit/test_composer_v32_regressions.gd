## What Composer 3.2 fixed about the projection, pinned so it cannot come back.
##
## Every case here is something the 3.1 reader got wrong in a way a person could
## see on the canvas: a `return` that offered somewhere to go next, a graph with
## no beginning, and cables between statements that looked draggable and were
## not. The file is the authority in all three - what changed is that the
## drawing now says the same thing the file does.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/probe.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"


func _script(statements: Array) -> String:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return HEAD + body


func _read(statements: Array) -> ComposerGraph:
	return ComposerReader.read(_script(statements), PATH)


func _titles_of(nodes: Array[ComposerNode]) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for node: ComposerNode in nodes:
		found.append(node.title)
	return found


#region Entry and End
## A blank ability is not an empty canvas: it is a beginning and an end.
##
## `func _activate_ability(): return true` drew exactly one card before, which
## told a person opening a new ability that there was nothing there. There is:
## the method runs, and it returns. Entry is where it starts.
func test_blank_ability_projects_entry_to_end() -> void:
	var graph: ComposerGraph = _read(["return true"])
	var drawn: Array[ComposerNode] = graph.visible_nodes()

	assert_eq(drawn.size(), 2, "Entry and End, and nothing else: %s" % _titles_of(drawn))
	assert_not_null(graph.find_node(ComposerFlow.ENTRY_ID), "the graph begins somewhere")

	var edges: Array[ComposerGraph.Connection] = graph.execution_connections()
	assert_eq(edges.size(), 1, "one execution edge")
	assert_eq(edges[0].from_node, ComposerFlow.ENTRY_ID, "which leaves Entry")
	assert_eq(
		edges[0].to_node, ComposerFlow.main_end(graph).id, "and arrives at End"
	)


## End is terminal, and a terminal node offers nowhere to go next.
##
## The exec output was the whole bug: a person could drag a wire out of `return`
## and the canvas would accept it, which is a promise the language cannot keep.
func test_end_has_exec_input_and_no_exec_output() -> void:
	var graph: ComposerGraph = _read(["return true"])
	var end: ComposerNode = ComposerFlow.main_end(graph)

	assert_not_null(end, "there is an End")
	assert_true(end.terminal, "and it says so")
	assert_not_null(
		end.find_port(ComposerReader.EXEC_IN), "something can arrive at it"
	)
	assert_null(
		end.find_port(ComposerReader.EXEC_OUT), "and nothing can leave it"
	)


## Nothing runs after a return, so nothing is drawn as running after it.
##
## Unreachable code is legal to write and the reader has to read it; what it
## must not do is draw an execution edge into it, because that edge is a claim
## about what happens at runtime and the claim is false.
func test_return_never_connects_to_following_statement() -> void:
	var graph: ComposerGraph = _read(["return true", "await wait_delay(1.0)"])
	var end: ComposerNode = ComposerFlow.main_end(graph)

	for edge: ComposerGraph.Connection in graph.execution_connections():
		assert_ne(
			edge.from_node, end.id,
			"nothing leaves End, but %s -> %s does" % [edge.from_node, edge.to_node]
		)
#endregion


#region A cable is something you can move
## Reaching into a local is a dependency, not a wire.
##
## `consume(data.target_data)` plainly needs `data`, and the old reader drew a
## cable for it. The cable was a lie in the only way that matters: a person
## could not unplug it and plug it somewhere else, because the argument is not
## the local - it is an expression that mentions it.
func test_expression_dependency_is_not_a_data_wire() -> void:
	var graph: ComposerGraph = _read([
		"var pick: GameplayAbilityTargetData = await wait_target_data()",
		"apply_gameplay_effect(burning, pick.target_data)",
	])

	assert_eq(
		graph.data_connections().size(), 0,
		"an expression that mentions a local is not a wire out of it"
	)


## Passing the local whole is a wire, because that one can be re-pointed.
func test_exact_local_argument_is_a_data_wire() -> void:
	var graph: ComposerGraph = _read([
		"var pick: GameplayAbilityTargetData = await wait_target_data()",
		"apply_gameplay_effect(burning, pick)",
	])

	assert_eq(graph.data_connections().size(), 1, "exactly the local, so exactly a wire")
#endregion
