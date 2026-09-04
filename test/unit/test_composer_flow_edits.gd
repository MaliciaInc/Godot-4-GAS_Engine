## Unplugging a wire, and what happens to the file when you do.
##
## Execution is written in the source, so a broken link has to be written too.
## The statements that can no longer be reached stay exactly where they are,
## wrapped in `if false:` and marked as Composer's - readable, editable, and no
## longer running. That is the only honest way to draw an island: the alternative
## is a canvas that shows a node nothing leads to while the file still runs it.
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


func _read(source: String) -> ComposerGraph:
	return ComposerReader.read(source, PATH)


func _edge(from_id: StringName, to_id: StringName) -> ComposerGraph.Connection:
	var made: ComposerGraph.Connection = ComposerGraph.Connection.new()
	made.from_node = from_id
	made.from_port = ComposerReader.EXEC_OUT
	made.to_node = to_id
	made.to_port = ComposerReader.EXEC_IN
	return made


func _first_flow(graph: ComposerGraph) -> ComposerGraph.Connection:
	return graph.execution_connections()[0]


#region Unplugging
## Everything the link was carrying becomes an island, and the method still ends.
##
## Both halves matter. Wrapping the statements is what makes the drawing true;
## leaving the live path without a return would leave a method that falls off
## the end, which is a file the person cannot run.
func test_unplugging_entry_strands_the_body_and_leaves_it_readable() -> void:
	var source: String = _script(["await wait_delay(1.0)", "return true"])
	var graph: ComposerGraph = _read(source)

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_flow(
		source, graph, _first_flow(graph)
	)

	assert_true(done.ok, done.message)
	assert_true(
		done.source.contains(ComposerSubset.DETACHED_MARK),
		"the stranded statements are marked as Composer's"
	)
	assert_true(done.source.contains("wait_delay(1.0)"), "and are still in the file")

	var after: ComposerGraph = _read(done.source)
	assert_true(after.is_editable(), after.blocked_reason())


## The island is invisible machinery, not a card.
##
## `if false:` is a line the reader has to account for and a person must never
## be shown: a card called "If false" would be Composer explaining its own
## bookkeeping to somebody who asked about their ability.
func test_the_wrapper_is_read_kept_and_never_drawn() -> void:
	var source: String = _script(["await wait_delay(1.0)", "return true"])
	var graph: ComposerGraph = _read(source)
	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_flow(
		source, graph, _first_flow(graph)
	)
	var after: ComposerGraph = _read(done.source)

	var wrappers: int = 0
	for node: ComposerNode in after.nodes:
		if node.projection_kind == ComposerNode.ProjectionKind.SUPPORT:
			wrappers += 1
			assert_true(node.source_backed, "the file contains it")
			assert_false(node.visible_in_graph, "and nobody is shown it")

	assert_gt(wrappers, 0, "the wrapper was read")
	for node: ComposerNode in after.visible_nodes():
		assert_false(
			node.title.to_lower().contains("false"),
			"no card is named after the bookkeeping"
		)
#endregion


#region A line that only looks like ours
## `if false:` a person wrote is their branch, not Composer's wrapper.
##
## The marker is what makes a line machinery. Reading any `if false:` as a
## wrapper would take somebody's own disabled code off the canvas and then
## unwrap it the first time they touched a nearby wire.
func test_an_unmarked_if_false_is_an_ordinary_branch() -> void:
	var graph: ComposerGraph = _read(_script([
		"if false:", "\tawait wait_delay(1.0)", "return true"
	]))

	var drawn: PackedStringArray = PackedStringArray()
	for node: ComposerNode in graph.visible_nodes():
		drawn.append(node.title)

	assert_true(graph.is_editable(), graph.blocked_reason())
	var branches: int = 0
	for node: ComposerNode in graph.nodes:
		if node.projection_kind == ComposerNode.ProjectionKind.BRANCH:
			branches += 1
	assert_eq(branches, 1, "their branch is a branch: %s" % drawn)


## And a plain `return` is still End, marker or no marker.
func test_an_unmarked_return_is_still_the_end() -> void:
	var graph: ComposerGraph = _read(_script(["return true"]))
	var end: ComposerNode = ComposerFlow.main_end(graph)

	assert_not_null(end, "there is an End")
	assert_true(end.visible_in_graph, "and it is drawn")
#endregion


#region Refusing
## A link that is not there cannot be broken.
func test_breaking_a_link_that_does_not_exist_changes_nothing() -> void:
	var source: String = _script(["await wait_delay(1.0)", "return true"])
	var graph: ComposerGraph = _read(source)

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_flow(
		source, graph, _edge(&"nowhere", &"nothing")
	)

	assert_false(done.ok, "refused")
	assert_eq(done.source, "", "and produced no source to commit")


## Nothing may be joined so that it runs before itself.
##
## A cycle drawn as a cable would be a `goto` hidden in a picture: the file
## cannot express it, so the canvas must not offer it.
func test_a_connection_that_would_loop_is_refused() -> void:
	var source: String = _script([
		"commit_ability()", "await wait_delay(1.0)", "return true"
	])
	var graph: ComposerGraph = _read(source)
	var statements: Array[ComposerNode] = ComposerProjection.statements(graph)

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.connect_flow(
		source, graph, _edge(statements[1].id, statements[0].id)
	)

	assert_false(done.ok, "refused")
	assert_eq(done.message, ComposerFlowEdits.WOULD_LOOP, "and said why")


## Nothing leaves End, so nothing can be joined to its output.
func test_nothing_can_be_run_after_the_end() -> void:
	var source: String = _script(["commit_ability()", "return true"])
	var graph: ComposerGraph = _read(source)
	var end: ComposerNode = ComposerFlow.main_end(graph)
	var first: ComposerNode = ComposerProjection.statements(graph)[0]

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.connect_flow(
		source, graph, _edge(end.id, first.id)
	)

	assert_false(done.ok, "refused")
#endregion


#region The file has to compile, not just parse
## The bodies a cut has to leave loadable.
##
## GDScript is compiled here rather than read back, because reading is not
## compiling: the reader answers whether Composer can draw the result, and a
## file it draws happily can still be one Godot refuses to load. Nothing else
## in the chain asks that question.
const SHORTENED: Array = [
	[
		["await wait_delay(1.0)", "end_ability()"],
		"a linear body loses its tail",
	],
	[
		["var pick: AbilityTaskWaitTargetData = wait_target_data()", "end_ability()"],
		"the tail that goes is the one using a local",
	],
	[
		["await wait_delay(1.0)", "end_ability()", "return true"],
		"a body that already ends in a return keeps that one",
	],
]


func test_a_shortened_method_still_compiles() -> void:
	for row: Array in SHORTENED:
		var statements: Array = row[0]
		var described: String = row[1]
		var source: String = _script(statements)
		var graph: ComposerGraph = _read(source)

		var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_flow(
			source, graph, _first_flow(graph)
		)

		assert_true(done.ok, "%s: %s" % [described, done.message])
		var built: GDScript = GDScript.new()
		built.source_code = done.source
		assert_eq(built.reload(), OK, "%s: the result compiles" % described)
#endregion
