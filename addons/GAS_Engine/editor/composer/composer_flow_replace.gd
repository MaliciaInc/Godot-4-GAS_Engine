## Moving a set of execution links, as one transaction over one copy of the text.
##
## The contract is two lists: the links that have to be gone afterwards, and the
## links that have to be there instead. Between them there is no shortcut - a run
## of control is not stored anywhere, so each link is written down or taken out
## by itself, and the file is read again after every one of them.
##
## The statements are found again by marks, not by ids. A node is named after the
## line it was read from, so the first transformation renames everything below
## it; the marks are comments this puts in before the surgery and takes out
## before handing anything back, and they are the only reason a transaction of
## several steps can talk about the same statement throughout.
##
## Nothing here commits and nothing here decides policy. `ComposerFlowEdits` owns
## the contract; `ComposerFlowPaths` owns what one link means on each pin.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowReplace extends RefCounted

## What a transaction produced, or why it produced nothing.
class Attempt extends RefCounted:
	var source: String = ""
	var message: String = ""

	static func refused(message: String) -> Attempt:
		var made: Attempt = Attempt.new()
		made.message = message
		return made

	static func written(source: String) -> Attempt:
		var made: Attempt = Attempt.new()
		made.source = source
		return made


## Why a transaction was refused, in the words the facade already uses.
const NOT_REPRESENTABLE: String = ComposerFlowEdits.NOT_REPRESENTABLE
const NOT_CONNECTED: String = ComposerFlowEdits.NOT_CONNECTED
const WOULD_LOOP: String = ComposerFlowEdits.WOULD_LOOP
const WOULD_STRAND: String = ComposerFlowEdits.WOULD_STRAND
const NO_SUCH_NODE: String = ComposerFlowEdits.NO_SUCH_NODE

## Move a set of execution links to other pins, or change nothing at all.
##
## This is what a Ctrl-drag on an execution pin means, and what the original 3.2
## left out. The two edge lists are the whole contract: `old_edges` are the links
## that have to be gone afterwards - the ones being moved, and the ones displaced
## from a destination that can only hold one - and `new_edges` are the links that
## have to be there instead.
##
## Nothing is stored. There is no list of wires in a file, so the only way to say
## "this runs after that" is to write it after that. The transaction is a run of
## single-link transformations over one anchored copy of the text: every removal
## first, then every addition, rereading between each one and finding the
## statements again by the marks rather than by ids that moved with the lines.
## The marks come off before anything is handed back.
static func run(
	source: String,
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> Attempt:
	var refusal: String = _unacceptable(graph, old_edges, new_edges)
	if not refusal.is_empty():
		return Attempt.refused(refusal)

	var anchored: ComposerFlowAnchors.Anchored = ComposerFlowAnchors.anchor(
		source, graph, _endpoints_of(old_edges, new_edges)
	)
	if not anchored.is_ok():
		return Attempt.refused(NOT_REPRESENTABLE)
	var read: ComposerGraph = ComposerReader.read(anchored.source, graph.source_path)
	if not read.is_editable():
		return Attempt.refused(NOT_REPRESENTABLE)

	var working: String = anchored.source
	for edge: ComposerGraph.Connection in _removals(old_edges, new_edges):
		var step: Array = _stepped(
			working, read, anchored, edge, true
		)
		if step.is_empty():
			return Attempt.refused(NOT_REPRESENTABLE)
		working = step[0]
		read = step[1]
	for edge: ComposerGraph.Connection in new_edges:
		var step: Array = _stepped(working, read, anchored, edge, false)
		if step.is_empty():
			return Attempt.refused(NOT_REPRESENTABLE)
		working = step[0]
		read = step[1]

	refusal = _unfinished(read, anchored, old_edges, new_edges)
	if not refusal.is_empty():
		return Attempt.refused(refusal)

	# The marks come off, and what is left has to be the same ability the checks
	# above were run against. They are comments, so a signature that noticed them
	# would be a signature that notices comments.
	var written: String = ComposerFlowAnchors.strip_anchors(working, anchored.prefix)
	var last: ComposerGraph = ComposerReader.read(written, graph.source_path)
	if not last.is_editable():
		return Attempt.refused(NOT_REPRESENTABLE)
	if ComposerWriter.signature(last) != ComposerWriter.signature(read):
		return Attempt.refused(NOT_REPRESENTABLE)
	if written == source:
		return Attempt.refused(NOT_REPRESENTABLE)
	return Attempt.written(written)


## Every reason to say no before a character is written, in the order of 61.1.
static func _unacceptable(
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> String:
	if new_edges.is_empty():
		return NOT_REPRESENTABLE
	for edge: ComposerGraph.Connection in old_edges:
		if not graph.has_connection(edge):
			return NOT_CONNECTED
	for edge: ComposerGraph.Connection in new_edges:
		var from: ComposerNode = graph.find_node(edge.from_node)
		var to: ComposerNode = graph.find_node(edge.to_node)
		if from == null or to == null:
			return NO_SUCH_NODE
		if edge.from_node == edge.to_node:
			return WOULD_LOOP
		var out: ComposerNode.Port = from.find_port(edge.from_port)
		var into: ComposerNode.Port = to.find_port(edge.to_port)
		if out == null or into == null:
			return NOT_REPRESENTABLE
		if not out.is_execution() or not into.is_execution():
			return NOT_REPRESENTABLE
		if (
			out.direction != ComposerNode.PortDirection.OUTPUT
			or into.direction != ComposerNode.PortDirection.INPUT
		):
			return NOT_REPRESENTABLE
	if _loops_in_desired(graph, old_edges, new_edges):
		return WOULD_LOOP
	return ""


## One link written down, and the reading that followed it.
##
## Empty when the step could not be taken. The endpoints are found again by the
## marks every time, because the last step moved lines and every id below the
## move is a different id now.
static func _stepped(
	source: String,
	read: ComposerGraph,
	anchored: ComposerFlowAnchors.Anchored,
	edge: ComposerGraph.Connection,
	cutting: bool
) -> Array:
	var here: ComposerGraph.Connection = _resolved(read, anchored, edge)
	if here == null:
		return []
	if cutting and not read.has_connection(here):
		# An earlier step already took it out - a displaced link whose statement
		# went into an island with the one before it. Asked for and already true
		# is not a failure.
		return [source, read]

	var written: String = (
		ComposerFlowPaths.disconnect_once(source, read, here) if cutting
		else ComposerFlowPaths.connect_once(source, read, here)
	)
	if written.is_empty() or written == source:
		return []
	var after: ComposerGraph = ComposerReader.read(written, read.source_path)
	if not after.is_editable():
		return []
	return [written, after]


## The same link, said in the numbering of `read`.
static func _resolved(
	read: ComposerGraph,
	anchored: ComposerFlowAnchors.Anchored,
	edge: ComposerGraph.Connection
) -> ComposerGraph.Connection:
	var from: ComposerNode = _by_mark(read, anchored, edge.from_node)
	var to: ComposerNode = _by_mark(read, anchored, edge.to_node)
	if from == null or to == null:
		return null
	return ComposerReader.wire(from.id, edge.from_port, to.id, edge.to_port)


## The statement that mark stands for, in this reading.
##
## Entry is the exception and the only one: it is not a line of the file, so it
## carries no mark and its id does not move.
static func _by_mark(
	read: ComposerGraph,
	anchored: ComposerFlowAnchors.Anchored,
	node_id: StringName
) -> ComposerNode:
	if node_id == ComposerFlow.ENTRY_ID:
		return read.find_node(ComposerFlow.ENTRY_ID)
	var token: String = anchored.token_of(node_id)
	if token.is_empty():
		return null
	return ComposerFlowAnchors.find_by_token(read, token)


## The links to take out, in the order they can be taken out in.
##
## Section 61.3 asks for the displaced link first, so that the destination pin is
## free before anything is added. Measured, that order cannot express its own
## example: islanding the destination's old target puts the moved link inside an
## island, where taking it out strands nothing and the step has nothing to write.
## The moved link goes first instead. Both orders free the destination before any
## addition - which is what that section says the order is for - and this one
## leaves each step something it can actually write.
static func _removals(
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> Array[ComposerGraph.Connection]:
	var moved: Array[ComposerGraph.Connection] = []
	var displaced: Array[ComposerGraph.Connection] = []
	for edge: ComposerGraph.Connection in old_edges:
		if _is_displaced(edge, new_edges):
			displaced.append(edge)
			continue
		moved.append(edge)
	var order: Array[ComposerGraph.Connection] = []
	order.append_array(moved)
	order.append_array(displaced)
	return order


## Whether that link is one the addition is taking the place of.
static func _is_displaced(
	edge: ComposerGraph.Connection, new_edges: Array[ComposerGraph.Connection]
) -> bool:
	for wanted: ComposerGraph.Connection in new_edges:
		if wanted.from_node == edge.from_node and wanted.from_port == edge.from_port:
			return true
	return false


## Every statement either list touches, so all of them are marked in one pass.
static func _endpoints_of(
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> Array[StringName]:
	var found: Array[StringName] = []
	for group: Array[ComposerGraph.Connection] in [old_edges, new_edges]:
		for edge: ComposerGraph.Connection in group:
			for node_id: StringName in [edge.from_node, edge.to_node]:
				if not found.has(node_id):
					found.append(node_id)
	return found


## What the finished transaction still owes, or nothing when it owes nothing.
##
## Checked while the marks are still in place, which is the only moment every
## statement can still be named.
static func _unfinished(
	read: ComposerGraph,
	anchored: ComposerFlowAnchors.Anchored,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> String:
	for edge: ComposerGraph.Connection in new_edges:
		var wanted: ComposerGraph.Connection = _resolved(read, anchored, edge)
		if wanted == null or not read.has_connection(wanted):
			return NOT_REPRESENTABLE
	for edge: ComposerGraph.Connection in old_edges:
		var gone: ComposerGraph.Connection = _resolved(read, anchored, edge)
		if gone != null and read.has_connection(gone):
			return NOT_REPRESENTABLE
	if ComposerFlowChecks.strands_anything(read):
		return WOULD_STRAND
	if ComposerFlowChecks.touches_support(read):
		return NOT_REPRESENTABLE
	if not ComposerFlowChecks.runs_forward(read):
		return WOULD_LOOP
	return ""


## Whether the links asked for would make the ability run in a circle.
##
## Asked of an ephemeral set of edge keys rather than of the live graph, and
## before any surgery: a Move All takes links out and puts others in within the
## one operation, so judging it by what the file says now would refuse moves that
## are perfectly straight once both halves have happened.
static func _loops_in_desired(
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> bool:
	var desired: Array[ComposerGraph.Connection] = []
	for wire: ComposerGraph.Connection in graph.execution_connections():
		if _is_kept(wire, old_edges) or _leaves_a_moved_statement(graph, wire, new_edges):
			continue
		desired.append(wire)
	desired.append_array(new_edges)

	for edge: ComposerGraph.Connection in new_edges:
		var seen: Dictionary[StringName, bool] = {}
		var pending: Array[StringName] = [edge.to_node]
		while not pending.is_empty():
			var at: StringName = pending.pop_back()
			if at == edge.from_node:
				return true
			if seen.has(at):
				continue
			seen[at] = true
			for wire: ComposerGraph.Connection in desired:
				if wire.from_node == at:
					pending.append(wire.to_node)
	return false


## Whether that link only exists because of where a statement being moved is
## standing now.
##
## A statement carries its way out with it. Judging the desired set with those
## links still in it says a move is a circle whenever the statement being moved
## currently runs into the one it is being joined after - which is most moves,
## and none of them is a circle. Measured on the true path of a branch: the body
## runs into the continuation, the continuation is what it is being joined to,
## and the two links together looked like a loop that the file cannot even
## express.
static func _leaves_a_moved_statement(
	graph: ComposerGraph,
	wire: ComposerGraph.Connection,
	new_edges: Array[ComposerGraph.Connection]
) -> bool:
	for wanted: ComposerGraph.Connection in new_edges:
		var moving: ComposerNode = graph.find_node(wanted.to_node)
		if moving == null:
			continue
		var block: ComposerSpan = ComposerFlowPlaces.block_of(graph, moving)
		var from: ComposerNode = graph.find_node(wire.from_node)
		if from != null and block.contains(from.span.first_line):
			return true
	return false


static func _is_kept(
	edge: ComposerGraph.Connection, group: Array[ComposerGraph.Connection]
) -> bool:
	for other: ComposerGraph.Connection in group:
		if other.is_same_as(edge):
			return true
	return false
