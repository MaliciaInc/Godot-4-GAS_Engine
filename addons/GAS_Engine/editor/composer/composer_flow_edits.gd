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
## Only ever by putting the target back into the live path: a block somebody set
## aside is unwrapped and written where the pin it is being joined to requires.
## There is no way to write "runs after" other than "is written after", so that
## is what happens. Which pin was used decides where that is, and deciding that
## is `ComposerFlowPaths`.
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

	var island: String = ComposerFlowPlaces.island_of(graph, to)
	if island.is_empty():
		return _refuse(NOT_REPRESENTABLE)

	var changed: String = ComposerFlowPaths.connect_once(source, graph, edge)
	if changed.is_empty():
		return _refuse(NOT_REPRESENTABLE)
	var read: ComposerGraph = ComposerFlowChecks.read_back(source, changed, graph)
	if read == null:
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.islands_in(changed).has(island):
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.live_count(read) <= ComposerFlowChecks.live_count(graph):
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.strands_anything(read):
		return _refuse(WOULD_STRAND)
	return _accept(changed)


## Whether following execution from `to` gets back to `from`.
static func _would_loop(graph: ComposerGraph, edge: ComposerGraph.Connection) -> bool:
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
## What that means depends on the pin it left, which is why there is a handler
## per pin rather than one rule: taking the link off an ordinary statement's way
## out sets aside the run below it, while taking it off a branch's True leaves
## that path leading nowhere and the false side exactly as it was.
static func disconnect_flow(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> Result:
	if not ComposerFlowChecks.has_edge(graph, edge):
		return _refuse(NOT_CONNECTED)

	var changed: String = ComposerFlowPaths.disconnect_once(source, graph, edge)
	if changed.is_empty():
		return _refuse(NOT_REPRESENTABLE)
	var read: ComposerGraph = ComposerFlowChecks.read_back(source, changed, graph)
	if read == null:
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.has_edge(read, edge):
		# The same link, still there. Asked by endpoint rather than by counting:
		# a cut that wrapped the wrong run of lines can leave the counts moving
		# in the right direction while the link it was asked about survives.
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.live_count(read) >= ComposerFlowChecks.live_count(graph):
		return _refuse(NOT_REPRESENTABLE)
	if ComposerFlowChecks.strands_anything(read):
		return _refuse(WOULD_STRAND)
	return _accept(changed)
#endregion


#region Replacing
## Move a set of execution links to other pins, or change nothing at all.
##
## This is what a Ctrl-drag on an execution pin means, and what the original 3.2
## left out. The two edge lists are the whole contract: `old_edges` are the links
## that have to be gone afterwards - the ones being moved, and the ones displaced
## from a destination that can only hold one - and `new_edges` are the links that
## have to be there instead.
##
## The transaction itself is `ComposerFlowReplace`. This is the door, and a door
## is where the shape of an answer is decided.
static func replace(
	source: String,
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> Result:
	var tried: ComposerFlowReplace.Attempt = ComposerFlowReplace.run(
		source, graph, old_edges, new_edges
	)
	if not tried.message.is_empty():
		return _refuse(tried.message)
	return _accept(tried.source)
#endregion
