## Knowing which statement is which, across a transaction that moves them.
##
## A node's id is derived from the line it was read from, so the first
## transformation of a move renames everything below it. A move is several
## transformations, and each one has to talk about the same statements the last
## one did. Ids cannot do that, and a statement's text cannot either: a person is
## free to write the same call twice.
##
## So the transaction marks the statements it is going to touch, finds them again
## by those marks, and takes the marks out before anything is handed back. What
## is asked here is the whole contract: the marks work, they survive the surgery,
## they tell two identical statements apart, they leave a person's own comments
## alone, and they never reach the file.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

## Two statements that say exactly the same thing, which is the case the marks
## exist for.
const TWINS: Array = [
	"commit_ability()",
	"execute_cue(&\"boom\")",
	"end_ability()",
	"execute_cue(&\"boom\")",
	"return true",
]

const CUE: String = "execute_cue"


#region Getting there
func _script_of(statements: Array) -> String:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return HEAD + body


func _read(statements: Array) -> ComposerGraph:
	return ComposerReader.read(_script_of(statements), PATH)


## Every statement of the body, so a test can ask for the second of two twins.
func _statements(graph: ComposerGraph) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in graph.nodes:
		if node.source_backed and node.visible_in_graph:
			found.append(node)
	return found


func _ids_of(nodes: Array[ComposerNode]) -> Array[StringName]:
	var found: Array[StringName] = []
	for node: ComposerNode in nodes:
		found.append(node.id)
	return found
#endregion


#region What a mark is
## Every statement asked for gets one, above itself and below what it carried in.
##
## Below the comments a person wrote, because those belong to their statement and
## stay where they put them; above the statement, because that is where a reread
## will take the mark as part of the same run and hand it back on `carried`.
func test_a_mark_goes_between_the_comment_and_the_statement() -> void:
	var graph: ComposerGraph = _read([
		"# Aim first.", "execute_cue(&\"boom\")", "return true",
	])
	var cue: ComposerNode = ComposerFlowProbe.at(graph, CUE)

	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		_script_of(["# Aim first.", "execute_cue(&\"boom\")", "return true"]),
		graph,
		[cue.id] as Array[StringName]
	)

	assert_true(anchored.is_ok(), "it was marked")
	assert_true(
		anchored.source.contains(
			"\t# Aim first.\n\t%s\n\texecute_cue" % anchored.token_of(cue.id)
		),
		"the person's comment, then the mark, then the statement: %s"
		% [ComposerFlowProbe.body_of(anchored.source)]
	)


## The statement is found again by its mark, whatever the lines did.
func test_a_marked_statement_is_found_again_after_the_lines_move() -> void:
	var graph: ComposerGraph = _read(TWINS)
	var statements: Array[ComposerNode] = _statements(graph)
	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		_script_of(TWINS), graph, _ids_of(statements)
	)
	var wanted: String = anchored.token_of(statements[2].id)

	# Something above it is taken out, so every line below moves and every id
	# with them.
	var shorter: String = ComposerEdits.remove(
		anchored.source,
		[ComposerSpan.new(6, 6)] as Array[ComposerSpan]
	)
	var read: ComposerGraph = ComposerReader.read(shorter, PATH)

	var found: ComposerNode = ComposerFlowAnchors.find_by_token(read, wanted)
	assert_not_null(found, "the mark still names a statement")
	assert_eq(found.text, statements[2].text, "and it is the one it was put on")


## Two statements that say the same thing are told apart.
##
## The whole reason a mark exists rather than a name. `execute_cue(&"boom")`
## twice in one ability is ordinary code, and a transaction that found "the one
## that says that" would move whichever came first, twice.
func test_two_identical_statements_are_still_told_apart() -> void:
	var graph: ComposerGraph = _read(TWINS)
	var statements: Array[ComposerNode] = _statements(graph)
	var first: ComposerNode = statements[1]
	var second: ComposerNode = statements[3]
	assert_eq(first.text, second.text, "the two really do say the same thing")

	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		_script_of(TWINS), graph, _ids_of(statements)
	)
	var read: ComposerGraph = ComposerReader.read(anchored.source, PATH)

	var found_first: ComposerNode = ComposerFlowAnchors.find_by_token(
		read, anchored.token_of(first.id)
	)
	var found_second: ComposerNode = ComposerFlowAnchors.find_by_token(
		read, anchored.token_of(second.id)
	)
	assert_not_null(found_first, "the first was found")
	assert_not_null(found_second, "and the second")
	assert_ne(
		found_first.span.first_line,
		found_second.span.first_line,
		"and they are two different statements, not one found twice"
	)
	assert_lt(
		found_first.span.first_line,
		found_second.span.first_line,
		"in the order they were written"
	)


## A comment a person could have written themselves does not collide.
##
## The first free spelling is used, chosen the same way every time so that the
## same file always produces the same marks.
func test_a_mark_a_person_already_wrote_is_not_reused() -> void:
	var statements: Array = [
		"# @composer-transient-anchor 0", "execute_cue(&\"boom\")", "return true",
	]
	var graph: ComposerGraph = _read(statements)
	var cue: ComposerNode = ComposerFlowProbe.at(graph, CUE)

	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		_script_of(statements), graph, [cue.id] as Array[StringName]
	)

	assert_true(anchored.is_ok(), "it was still marked")
	assert_ne(
		anchored.prefix, ComposerFlowAnchors.PREFIX, "with a spelling of its own"
	)
	assert_true(
		anchored.token_of(cue.id).begins_with(anchored.prefix.strip_edges()),
		"and the mark is written in it"
	)


## Taking the marks out leaves the file the marks were put into.
func test_taking_the_marks_out_leaves_the_file_alone() -> void:
	var source: String = _script_of(TWINS)
	var graph: ComposerGraph = _read(TWINS)
	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		source, graph, _ids_of(_statements(graph))
	)

	var stripped: String = ComposerFlowAnchors.strip_anchors(
		anchored.source, anchored.prefix
	)

	assert_ne(anchored.source, source, "the marks were really put in")
	assert_eq(stripped, source, "and taking them out gives back what was there")
#endregion


#region What a transaction owes
## A move hands back a file with no marks in it.
func test_no_mark_ever_reaches_the_file_a_move_hands_back() -> void:
	var source: String = _script_of([
		"commit_ability()", "execute_cue(&\"boom\")", "end_ability()", "return true",
	])
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var cue: ComposerNode = ComposerFlowProbe.at(graph, CUE)
	var commit: ComposerNode = ComposerFlowProbe.at(graph, "commit_ability")

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.replace(
		source,
		graph,
		_edges(graph, [[cue.id, ComposerReader.EXEC_OUT], [commit.id, ComposerReader.EXEC_OUT]]),
		_wanted(graph, commit, cue)
	)

	assert_true(done.ok, "the move was written: %s" % done.message)
	assert_false(
		done.source.contains(ComposerFlowAnchors.PREFIX.strip_edges()),
		"and there is no mark left in it: %s" % [ComposerFlowProbe.body_of(done.source)]
	)


## A move that cannot be finished hands back nothing at all.
##
## Not the file half-changed, and not the file with marks in it: the caller
## commits what it is given, and what it is given here is nothing.
func test_a_move_that_cannot_be_finished_writes_nothing() -> void:
	var source: String = _script_of([
		"commit_ability()", "execute_cue(&\"boom\")", "return true",
	])
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var commit: ComposerNode = ComposerFlowProbe.at(graph, "commit_ability")
	var cue: ComposerNode = ComposerFlowProbe.at(graph, CUE)

	# Joining the cue's way out to its own way in: a statement that runs itself.
	var itself: Array[ComposerGraph.Connection] = []
	itself.append(
		ComposerReader.wire(
			cue.id, ComposerReader.EXEC_OUT, cue.id, ComposerReader.EXEC_IN
		)
	)
	var done: ComposerFlowEdits.Result = ComposerFlowEdits.replace(
		source, graph, _edges(graph, [[commit.id, ComposerReader.EXEC_OUT]]), itself
	)

	assert_false(done.ok, "it was refused")
	assert_eq(done.source, "", "and no file came back")
	assert_eq(done.message, ComposerFlowEdits.WOULD_LOOP, "saying which impossible it is")
#endregion


#region Getting the edges
## The links leaving those pins, as the graph holds them.
func _edges(graph: ComposerGraph, pins: Array) -> Array[ComposerGraph.Connection]:
	var found: Array[ComposerGraph.Connection] = []
	for pin: Array in pins:
		var node_id: StringName = pin[0]
		var port_id: StringName = pin[1]
		found.append_array(graph.connections_from(node_id, port_id))
	return found


## One link, from that statement's way out to whatever the other one runs into.
func _wanted(
	graph: ComposerGraph, from: ComposerNode, like: ComposerNode
) -> Array[ComposerGraph.Connection]:
	var found: Array[ComposerGraph.Connection] = []
	var carried: Array[ComposerGraph.Connection] = graph.connections_from(
		like.id, ComposerReader.EXEC_OUT
	)
	if carried.is_empty():
		return found
	found.append(
		ComposerReader.wire(
			from.id, ComposerReader.EXEC_OUT, carried[0].to_node, carried[0].to_port
		)
	)
	return found
#endregion
