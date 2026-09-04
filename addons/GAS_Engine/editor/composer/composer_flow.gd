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
	graph.nodes.insert(0, entry_node())
	_wire_execution(graph, lines)


## The virtual node the method starts at.
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
		if node.terminal:
			found = node
	return found


## The node execution arrives from, or null when nothing leads here.
static func predecessor_of(graph: ComposerGraph, node_id: StringName) -> ComposerNode:
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if wire.to_node == node_id:
			return graph.find_node(wire.from_node)
	return null


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


## Execution, in the order the statements are written, and never out of a
## terminal.
static func _wire_execution(graph: ComposerGraph, lines: PackedStringArray) -> void:
	var previous: Dictionary[int, StringName] = {}
	var started: bool = false

	for node: ComposerNode in graph.nodes:
		if not node.source_backed or not node.span.is_valid():
			continue
		var depth: int = ComposerSubset.indent_of(lines[node.span.last_line - 1])

		if not started:
			graph.connections.append(
				ComposerReader.wire(ENTRY_ID, ComposerReader.EXEC_OUT, node.id, ComposerReader.EXEC_IN)
			)
			started = true
		elif previous.has(depth):
			_join(graph, previous[depth], node.id)
		else:
			var opener: StringName = _opener(previous, depth)
			if not opener.is_empty():
				_join(graph, opener, node.id)

		previous[depth] = node.id
		for open_depth: int in previous.keys():
			if open_depth > depth:
				previous.erase(open_depth)

	if not started:
		var end: ComposerNode = main_end(graph)
		if end != null:
			graph.connections.append(
				ComposerReader.wire(ENTRY_ID, ComposerReader.EXEC_OUT, end.id, ComposerReader.EXEC_IN)
			)


## Join two statements, unless the first one ends the method.
static func _join(graph: ComposerGraph, from_id: StringName, to_id: StringName) -> void:
	var from: ComposerNode = graph.find_node(from_id)
	if from == null or from.terminal:
		return
	graph.connections.append(
		ComposerReader.wire(from_id, ComposerReader.EXEC_OUT, to_id, ComposerReader.EXEC_IN)
	)


## The statement that opened the block `depth` is inside.
static func _opener(previous: Dictionary[int, StringName], depth: int) -> StringName:
	var nearest: int = -1
	for open_depth: int in previous.keys():
		if open_depth < depth and open_depth > nearest:
			nearest = open_depth
	return previous[nearest] if nearest >= 0 else &""
