## Where execution goes, worked out from statements that are already read.
##
## The reader's job is to say what each line is. This one's is to say what runs
## after what, which is a different question and was previously answered by the
## same loop - so a `return` grew a way out of itself and a new ability drew as
## a single card floating in an empty canvas with nothing leading into it.
##
## Two rules do most of the work. A method begins, so there is an Entry, and it
## is the one node with no line behind it. A `return` ends, so it is terminal
## and never grows an execution output: the file cannot run anything after it,
## and a port offering to is an offer the language will not honour.
##
## Where the walk itself lives is `ComposerFlowBuilder`. This is the facade: it
## puts Entry in front of the body, hands the walk the graph, and answers the
## questions the canvas and the editing operations ask afterwards.
##
## Nothing here edits source. It reads a graph and adds the projection of flow
## to it; changing the flow is `ComposerFlowEdits`, which writes GDScript.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlow extends RefCounted

## The one node that is not a line of the file.
const ENTRY_ID: StringName = &"__composer_entry"
const ENTRY_TITLE: String = "Entry"


## Add the flow projection to a graph whose nodes are already read.
##
## Entry first, so it is what a layout starting at the top of the list draws
## first, and so `visible_nodes()` hands it over in the order a person reads.
static func build(graph: ComposerGraph, lines: PackedStringArray) -> void:
	if graph.nodes.is_empty() and graph.source_path.is_empty():
		return
	graph.nodes.insert(0, _entry_placed(lines))
	ComposerFlowBuilder.build(graph, lines)


## The virtual node the method starts at.
## Entry, with wherever somebody last left it.
##
## Its place is written against its id rather than above a line, because Entry is
## drawn and is not a statement - there is no line of its own for a comment to
## travel with.
static func _entry_placed(lines: PackedStringArray) -> ComposerNode:
	var node: ComposerNode = entry_node()
	var saved: Variant = ComposerLayoutMetadata.virtual_position(
		"
".join(lines), ENTRY_ID
	)
	if saved is Vector2:
		node.has_layout_position = true
		node.layout_position = saved
	return node


static func entry_node() -> ComposerNode:
	var node: ComposerNode = ComposerNode.new()
	node.id = ENTRY_ID
	node.title = ENTRY_TITLE
	node.projection_kind = ComposerNode.ProjectionKind.ENTRY
	node.source_backed = false
	node.visible_in_graph = true
	node.terminal = false
	node.ports = [
		ComposerReader.port(
			ComposerReader.EXEC_OUT,
			ComposerNode.PortKind.EXECUTION,
			ComposerNode.PortDirection.OUTPUT
		),
	] as Array[ComposerNode.Port]
	return node


## The `return` the method ends at, or null when the body has none.
##
## The last one, not the first: a body may return early inside a branch, and the
## End a person means when they say "before the end" is the one at the bottom.
static func main_end(graph: ComposerGraph) -> ComposerNode:
	var found: ComposerNode = null
	for node: ComposerNode in graph.nodes:
		# The one a person can see. A support return put in to end a live path
		# after something was unplugged is terminal too, and is not the End they
		# mean when they ask for the end of the method.
		if node.terminal and node.visible_in_graph:
			found = node
	return found


## Every node execution can arrive from.
##
## More than one is ordinary now rather than a sign of something wrong: the
## statement after an `if` is reached from the true body and from the false
## side, which is what the file does.
static func predecessors_of(
	graph: ComposerGraph, node_id: StringName
) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if wire.to_node != node_id:
			continue
		var from: ComposerNode = graph.find_node(wire.from_node)
		if from != null and not found.has(from):
			found.append(from)
	return found


## The node execution arrives from when there is exactly one, and null when
## there are none or several.
##
## Null for a merge on purpose. This used to hand back whichever edge came
## first, which is an answer that depends on the order the wires happen to be
## in - and a caller inserting a statement 'before its predecessor' would put it
## on one arbitrary path of two. Ask `predecessors_of()` when several is a
## sensible answer.
static func predecessor_of(graph: ComposerGraph, node_id: StringName) -> ComposerNode:
	var found: Array[ComposerNode] = predecessors_of(graph, node_id)
	return found[0] if found.size() == 1 else null


## The nodes execution goes to, from one port or from all of them.
static func successors_of(
	graph: ComposerGraph, node_id: StringName, port_id: StringName = &""
) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if wire.from_node != node_id:
			continue
		if not port_id.is_empty() and wire.from_port != port_id:
			continue
		var node: ComposerNode = graph.find_node(wire.to_node)
		if node != null:
			found.append(node)
	return found


## The lines one node owns, or an invalid span for a node the file never held.
static func source_region(graph: ComposerGraph, node_id: StringName) -> ComposerSpan:
	var node: ComposerNode = graph.find_node(node_id)
	if node == null or not node.source_backed:
		return ComposerSpan.new()
	return node.span


## The line a new statement goes on to run before the method returns.
##
## The first line of End, not the line after it: a statement inserted after the
## `return` is a statement that never runs, which is exactly the shape 3.1 could
## produce and a person could see on the canvas as `End -> Wait Delay`.
static func insertion_before_main_end(graph: ComposerGraph) -> int:
	var end: ComposerNode = main_end(graph)
	if end == null or not end.span.is_valid():
		return 0
	return end.span.last_line - 1


## The island name a detached marker carries, or "" when the line carries none.
static func island_name(line: String) -> String:
	var at: int = line.find(ComposerSubset.DETACHED_MARK)
	if at < 0:
		return ""
	return line.substr(at + ComposerSubset.DETACHED_MARK.length()).strip_edges()


## The first island number nothing in these lines is using.
##
## Counted rather than made unique by chance: a file that is read, changed and
## written back has to produce the same names, or every save is a diff.
static func free_island_name(lines: PackedStringArray) -> String:
	var taken: Dictionary[String, bool] = {}
	for line: String in lines:
		var found: String = island_name(line)
		if not found.is_empty():
			taken[found] = true
	var number: int = 1
	while taken.has("detached_%d" % number):
		number += 1
	return "detached_%d" % number
