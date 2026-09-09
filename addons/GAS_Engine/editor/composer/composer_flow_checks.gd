## What a reading of a changed file owes before anybody may commit it.
##
## Every flow transformation ends the same way: read the text back and ask
## whether it says what was asked for and nothing worse. Written once because the
## questions are the same for a cut, a join and a move - and two files asking
## them slightly differently would let one operation through that another would
## have stopped.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowChecks extends RefCounted

## Read the changed text back, or nothing when it is not readable.
##
## The whole point of the module. A transformation that produced text nobody
## read is a guess, and a guess that reaches disk is how a person loses a file
## they could see a moment ago.
##
## What is checked afterwards is never an id. A node is named after the line it
## was read from, so every id moves when the source does - comparing them across
## a transformation would compare two different files' numbering and call the
## answer a verification.
static func read_back(
	original: String, changed: String, graph: ComposerGraph
) -> ComposerGraph:
	if changed == original:
		return null
	var read: ComposerGraph = ComposerReader.read(changed, graph.source_path)
	return read if read.is_editable() else null


## How many drawn statements execution still arrives at.
static func live_count(graph: ComposerGraph) -> int:
	var seen: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = [ComposerFlow.ENTRY_ID]
	while not pending.is_empty():
		var at: StringName = pending.pop_back()
		if seen.has(at):
			continue
		seen[at] = true
		for wire: ComposerGraph.Connection in graph.execution_connections():
			if wire.from_node == at:
				pending.append(wire.to_node)

	var live: int = 0
	for node: ComposerNode in graph.nodes:
		if node.visible_in_graph and node.source_backed and seen.has(node.id):
			live += 1
	return live


## Whether the result leaves a statement nothing reaches and nothing marks.
##
## The invariant the island machinery exists for. A statement that stops running
## must be *shown* to have stopped - wrapped, drawn apart, still editable. One
## that merely ends up written after a `return` is worse than a deleted one: it
## is still on the canvas, still in the file, and no longer does anything.
##
## Found by putting an island back in front of a live statement, which pushed
## that statement past the island's own `return`. The counts either side agreed,
## the reader read it back happily, and the person's cue silently stopped
## firing.
static func strands_anything(graph: ComposerGraph) -> bool:
	for node: ComposerNode in graph.nodes:
		if not node.source_backed or not node.visible_in_graph:
			continue
		if node.id == ComposerFlow.ENTRY_ID:
			continue
		if graph.is_reachable_from_entry(node.id):
			continue
		if ComposerFlowChecks.island_of(graph, node).is_empty():
			return true
	return false


## The islands a text holds.
static func islands_in(source: String) -> Dictionary[String, bool]:
	var found: Dictionary[String, bool] = {}
	for line: String in source.split(ComposerFlowText.NEWLINE):
		var island: String = ComposerFlow.island_name(line)
		if not island.is_empty():
			found[island] = true
	return found


static func has_edge(graph: ComposerGraph, edge: ComposerGraph.Connection) -> bool:
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if wire.from_node == edge.from_node and wire.to_node == edge.to_node:
			return true
	return false


## Which island a node is inside, or "" when it is in the live path.
static func island_of(graph: ComposerGraph, node: ComposerNode) -> String:
	for other: ComposerNode in graph.nodes:
		if other.projection_kind != ComposerNode.ProjectionKind.SUPPORT:
			continue
		var island: String = ComposerFlow.island_name(other.text)
		if island.is_empty():
			continue
		if other.span.first_line < node.span.first_line and other.indent < node.indent:
			return island
	return ""


## Whether any link in a reading arrives at or leaves a header nobody is shown.
static func touches_support(graph: ComposerGraph) -> bool:
	for wire: ComposerGraph.Connection in graph.execution_connections():
		for node_id: StringName in [wire.from_node, wire.to_node]:
			var node: ComposerNode = graph.find_node(node_id)
			if node != null and node.source_backed and not node.visible_in_graph:
				return true
	return false


## Whether every link in a reading runs down the file.
##
## A file cannot say "runs after" backwards: a statement runs after the one
## above it. So a link pointing up the file would mean the projection had begun
## saying something the text does not, and a circle is exactly what that would
## look like. Cheaper than a walk, and it says more.
static func runs_forward(graph: ComposerGraph) -> bool:
	for wire: ComposerGraph.Connection in graph.execution_connections():
		var from: ComposerNode = graph.find_node(wire.from_node)
		var to: ComposerNode = graph.find_node(wire.to_node)
		if from == null or to == null:
			return false
		if not from.span.is_valid():
			continue
		if to.span.first_line <= from.span.first_line:
			return false
	return true
