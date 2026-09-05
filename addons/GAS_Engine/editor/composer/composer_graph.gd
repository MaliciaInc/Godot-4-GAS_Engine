## A `.gd` file, read as a graph. In memory and nowhere else.
##
## There is no graph resource, no `.tres`, no serialization and no save path.
## Opening an ability is reading its script; saving is writing that same script.
## A stored graph would be a second copy of the ability, free to drift from the
## file, and the first time they disagreed a person would have to guess which
## one the engine actually runs.
##
## Produced by the reader, consumed by the view. Neither one owns it and nothing
## executes it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerGraph extends RefCounted

## How loudly a diagnostic speaks.
##
## NOT_REPRESENTABLE is not a louder ERROR. An error means the graph is wrong;
## not-representable means the file is fine and this tool cannot draw it. The
## file is opened read-only and left untouched, which is the honest outcome and
## the one that keeps the Composer trustworthy: a tool that says "I cannot read
## this" survives; one that guesses and rewrites the file is used once.
enum Severity { NOTE, WARNING, ERROR, NOT_REPRESENTABLE }


## Something the tooling has to say, and where in the file it applies.
class Diagnostic extends RefCounted:
	var severity: ComposerGraph.Severity = ComposerGraph.Severity.NOTE
	var message: String = ""
	var node_id: StringName = &""
	var span: ComposerSpan = ComposerSpan.new()


## One wire, of either family.
##
## Both are held here. Execution order is written in the file and read back out
## of it, so an execution wire in this list is a projection of that order rather
## than the place it is decided: changing one means rewriting statements, and
## nothing that changes this list changes what runs. A data wire says what
## depends on what, and nothing about when.
class Connection extends RefCounted:
	var from_node: StringName = &""
	var from_port: StringName = &""
	var to_node: StringName = &""
	var to_port: StringName = &""

	func touches(node_id: StringName) -> bool:
		return from_node == node_id or to_node == node_id

	## Whether this is the same wire as `other`: both ends, both pins.
	##
	## Asked here so nothing has to compare three of the four and call it a
	## match. A branch has two outputs, so two edges between the same pair of
	## cards are two different claims about which path runs.
	func is_same_as(other: ComposerGraph.Connection) -> bool:
		return (
			other != null
			and from_node == other.from_node
			and from_port == other.from_port
			and to_node == other.to_node
			and to_port == other.to_port
		)


var source_path: String = ""
var nodes: Array[ComposerNode] = []
var connections: Array[Connection] = []
var diagnostics: Array[Diagnostic] = []


## Whether this file can be edited here.
##
## Asked of the diagnostics rather than stored beside them. A separate flag is a
## second place to look and a second thing to keep true; the first time it
## disagreed with the list, the panel and the canvas would say different things
## about the same file.
func is_editable() -> bool:
	for found: Diagnostic in diagnostics:
		if found.severity == Severity.NOT_REPRESENTABLE:
			return false
	return true


## Why it cannot be edited, in the words a person needs. Empty when it can.
func blocked_reason() -> String:
	for found: Diagnostic in diagnostics:
		if found.severity == Severity.NOT_REPRESENTABLE:
			return found.message
	return ""


## Whether this graph already holds that exact wire.
func has_connection(edge: Connection) -> bool:
	for wire: Connection in connections:
		if wire.is_same_as(edge):
			return true
	return false


func find_node(node_id: StringName) -> ComposerNode:
	for node: ComposerNode in nodes:
		if node.id == node_id:
			return node
	return null


## The node whose lines contain `line`, for putting a caret back on a card.
## The locals declared above `node` that would fit `wanted`.
##
## What a cable into that argument could be attached to instead. Read off the
## graph rather than kept anywhere: a local is a statement that declares one, and
## which of them are in scope is which of them are above.
func locals_reaching(node: ComposerNode, wanted: StringName) -> Array[ComposerNode.Port]:
	var found: Array[ComposerNode.Port] = []
	for other: ComposerNode in nodes:
		if other.span.last_line >= node.span.first_line:
			continue
		var value: ComposerNode.Port = other.find_port(ComposerReader.VALUE_OUT)
		if value == null or value.label.is_empty():
			continue
		if ComposerTypes.accepts(wanted, value.type_name):
			found.append(value)
	return found


func node_at_line(line: int) -> ComposerNode:
	for node: ComposerNode in nodes:
		if node.span.contains(line):
			return node
	return null


## Every wire on this node, or on one port of it when a port is named.
##
## The port is optional so that the older question - "what touches this node at
## all" - stays askable. Both are needed: a card is redrawn from the first and a
## pin is judged by the second.
func connections_for(node_id: StringName, port_id: StringName = &"") -> Array[Connection]:
	var found: Array[Connection] = []
	for wire: Connection in connections:
		if not wire.touches(node_id):
			continue
		if port_id.is_empty():
			found.append(wire)
			continue
		if wire.from_node == node_id and wire.from_port == port_id:
			found.append(wire)
		elif wire.to_node == node_id and wire.to_port == port_id:
			found.append(wire)
	return found


## The wires leaving one port.
func connections_from(node_id: StringName, port_id: StringName) -> Array[Connection]:
	var found: Array[Connection] = []
	for wire: Connection in connections:
		if wire.from_node == node_id and wire.from_port == port_id:
			found.append(wire)
	return found


## The wires arriving at one port.
func connections_to(node_id: StringName, port_id: StringName) -> Array[Connection]:
	var found: Array[Connection] = []
	for wire: Connection in connections:
		if wire.to_node == node_id and wire.to_port == port_id:
			found.append(wire)
	return found


## The nodes a person is meant to see.
##
## Entry is here and support headers are not: an `else:` is a real line that the
## reader has to account for, and a card for it would be a card for punctuation.
func visible_nodes() -> Array[ComposerNode]:
	var drawn: Array[ComposerNode] = []
	for node: ComposerNode in nodes:
		if node.visible_in_graph:
			drawn.append(node)
	return drawn


## The wires that carry execution, and the ones that carry values.
##
## Split by asking the port rather than by a flag on the wire: the port already
## knows which family it belongs to, and a second answer stored on the wire is a
## second answer that can disagree.
func execution_connections() -> Array[Connection]:
	return _connections_of_kind(ComposerNode.PortKind.EXECUTION)


func data_connections() -> Array[Connection]:
	return _connections_of_kind(ComposerNode.PortKind.DATA)


func _connections_of_kind(kind: ComposerNode.PortKind) -> Array[Connection]:
	var found: Array[Connection] = []
	for wire: Connection in connections:
		var from: ComposerNode = find_node(wire.from_node)
		if from == null:
			continue
		var port: ComposerNode.Port = from.find_port(wire.from_port)
		if port != null and port.kind == kind:
			found.append(wire)
	return found


## Whether execution can arrive here at all, starting where the method starts.
##
## Execution only, and with a visited set, because a projection read from a file
## somebody is still editing can hold a shape that leads back on itself - and a
## walk that trusts the graph not to is a walk that hangs the editor.
func is_reachable_from_entry(node_id: StringName) -> bool:
	var seen: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = [ComposerFlow.ENTRY_ID]
	while not pending.is_empty():
		var at: StringName = pending.pop_back()
		if at == node_id:
			return true
		if seen.has(at):
			continue
		seen[at] = true
		for wire: Connection in execution_connections():
			if wire.from_node == at:
				pending.append(wire.to_node)
	return false


## Whether a port already has a wire on it, which is what tells the view to draw
## a bead rather than an empty ring.
func is_port_connected(node_id: StringName, port_id: StringName) -> bool:
	for wire: Connection in connections:
		if wire.from_node == node_id and wire.from_port == port_id:
			return true
		if wire.to_node == node_id and wire.to_port == port_id:
			return true
	return false


func count_of(level: ComposerGraph.Severity) -> int:
	var total: int = 0
	for found: Diagnostic in diagnostics:
		if found.severity == level:
			total += 1
	return total
