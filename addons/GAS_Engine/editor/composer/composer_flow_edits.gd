## Changing what runs after what, by changing the GDScript that says so.
##
## A wire on the canvas is a claim about execution, and execution is written in
## the file. So unplugging one is not a change to a list of connections - it is
## a source transformation: the statements that can no longer be reached get
## wrapped in `if false:` and stay exactly where they were, still readable,
## still editable, no longer running. Plugging one back in unwraps them.
##
## Nothing here half-succeeds. Every operation works on a copy, reads the copy
## back, checks that the edges it promised are the edges that exist, and only
## then hands the text over for a single commit. A transformation that cannot be
## verified leaves the original untouched and says so.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowEdits extends RefCounted


## What every refusal says when the shape asked for is outside the subset.
const NOT_REPRESENTABLE: String = (
	"Connection cannot be represented by Composer's structured GDScript subset."
)
const NOT_CONNECTED: String = "those two are not connected"
const WOULD_LOOP: String = "that would make the ability run in a circle"
const WOULD_STRAND: String = (
	"that would leave statements written but never run, and not shown as such"
)
const NO_SUCH_NODE: String = "one end of that connection is no longer in the ability"


## What a transformation produced, or why it produced nothing.
class Result extends RefCounted:
	var ok: bool = false
	var source: String = ""
	var message: String = ""


#region Answers
static func _refuse(message: String) -> Result:
	var made: Result = Result.new()
	made.message = message
	return made


static func _accept(source: String) -> Result:
	var made: Result = Result.new()
	made.ok = true
	made.source = source
	return made
#endregion


#region Connecting
## Join one statement's execution output to another's input.
##
## Only ever by putting the target back into the live path: a detached island is
## unwrapped and moved to run after its new predecessor. There is no way to
## write "runs after" other than "is written after", so that is what happens.
static func connect_flow(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> Result:
	var from: ComposerNode = graph.find_node(edge.from_node)
	var to: ComposerNode = graph.find_node(edge.to_node)
	if from == null or to == null:
		return _refuse(NO_SUCH_NODE)
	if from.terminal:
		return _refuse(NOT_REPRESENTABLE)
	if _would_loop(graph, edge):
		return _refuse(WOULD_LOOP)

	var island: String = _island_of(graph, to)
	if island.is_empty():
		return _refuse(NOT_REPRESENTABLE)

	var changed: String = ComposerFlowText.spent_stops_removed(
		ComposerFlowText.released(source, graph, island, from), graph.source_path
	)
	var read: ComposerGraph = _read_back(source, changed, graph)
	if read == null:
		return _refuse(NOT_REPRESENTABLE)
	if _islands_in(changed).has(island):
		return _refuse(NOT_REPRESENTABLE)
	if _live_count(read) <= _live_count(graph):
		return _refuse(NOT_REPRESENTABLE)
	if _strands_anything(read):
		return _refuse(WOULD_STRAND)
	return _accept(changed)


## Whether following execution from `to` gets back to `from`.
static func _would_loop(
	graph: ComposerGraph, edge: ComposerGraph.Connection
) -> bool:
	var seen: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = [edge.to_node]
	while not pending.is_empty():
		var at: StringName = pending.pop_back()
		if at == edge.from_node:
			return true
		if seen.has(at):
			continue
		seen[at] = true
		for wire: ComposerGraph.Connection in graph.execution_connections():
			if wire.from_node == at:
				pending.append(wire.to_node)
	return false
#endregion


#region Disconnecting
## Break one execution link, and keep the file compiling.
##
## What gets wrapped is decided by reachability, not by the edge: taking a link
## out can strand a whole run of statements, and leaving half of them live would
## be a lie about which ones happen.
static func disconnect_flow(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> Result:
	if not _has_edge(graph, edge):
		return _refuse(NOT_CONNECTED)

	var stranded: Array[ComposerNode] = _stranded_by(graph, edge)
	if stranded.is_empty():
		return _refuse(NOT_REPRESENTABLE)

	var lines: PackedStringArray = source.split(ComposerFlowText.NEWLINE)
	var region: ComposerSpan = ComposerFlowText.region_of(stranded)
	if not ComposerFlowText.is_contiguous(stranded, region):
		return _refuse(NOT_REPRESENTABLE)

	var wrapped: PackedStringArray = ComposerFlowText.detached(lines, region)
	var changed: String = ComposerFlowText.ended(
		ComposerFlowText.NEWLINE.join(wrapped), region.first_line
	)
	var read: ComposerGraph = _read_back(source, changed, graph)
	if read == null:
		return _refuse(NOT_REPRESENTABLE)
	if _live_count(read) >= _live_count(graph):
		return _refuse(NOT_REPRESENTABLE)
	if _strands_anything(read):
		return _refuse(WOULD_STRAND)
	return _accept(changed)


## The visible nodes that could be reached before and cannot be after.
static func _stranded_by(
	graph: ComposerGraph, edge: ComposerGraph.Connection
) -> Array[ComposerNode]:
	var reachable_now: Dictionary[StringName, bool] = _reachable(graph, edge)
	var stranded: Array[ComposerNode] = []
	for node: ComposerNode in graph.nodes:
		if not node.source_backed or not node.visible_in_graph:
			continue
		if node.id == ComposerFlow.ENTRY_ID:
			continue
		if not reachable_now.has(node.id):
			stranded.append(node)
	return stranded


## Everything execution still arrives at once `without` is gone.
static func _reachable(
	graph: ComposerGraph, without: ComposerGraph.Connection
) -> Dictionary[StringName, bool]:
	var seen: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = [ComposerFlow.ENTRY_ID]
	while not pending.is_empty():
		var at: StringName = pending.pop_back()
		if seen.has(at):
			continue
		seen[at] = true
		for wire: ComposerGraph.Connection in graph.execution_connections():
			if wire.from_node != at:
				continue
			if wire.from_node == without.from_node and wire.to_node == without.to_node:
				continue
			pending.append(wire.to_node)
	return seen
#endregion


#region Verifying
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
static func _read_back(
	original: String, changed: String, graph: ComposerGraph
) -> ComposerGraph:
	if changed == original:
		return null
	var read: ComposerGraph = ComposerReader.read(changed, graph.source_path)
	return read if read.is_editable() else null


## How many drawn statements execution still arrives at.
static func _live_count(graph: ComposerGraph) -> int:
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
static func _strands_anything(graph: ComposerGraph) -> bool:
	for node: ComposerNode in graph.nodes:
		if not node.source_backed or not node.visible_in_graph:
			continue
		if node.id == ComposerFlow.ENTRY_ID:
			continue
		if graph.is_reachable_from_entry(node.id):
			continue
		if _island_of(graph, node).is_empty():
			return true
	return false


## The islands a text holds.
static func _islands_in(source: String) -> Dictionary[String, bool]:
	var found: Dictionary[String, bool] = {}
	for line: String in source.split(ComposerFlowText.NEWLINE):
		var island: String = ComposerFlow.island_name(line)
		if not island.is_empty():
			found[island] = true
	return found


static func _has_edge(graph: ComposerGraph, edge: ComposerGraph.Connection) -> bool:
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if wire.from_node == edge.from_node and wire.to_node == edge.to_node:
			return true
	return false


## Which island a node is inside, or "" when it is in the live path.
static func _island_of(graph: ComposerGraph, node: ComposerNode) -> String:
	for other: ComposerNode in graph.nodes:
		if other.projection_kind != ComposerNode.ProjectionKind.SUPPORT:
			continue
		var island: String = ComposerFlow.island_name(other.text)
		if island.is_empty():
			continue
		if other.span.first_line < node.span.first_line and other.indent < node.indent:
			return island
	return ""
#endregion
