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
## @meta_license: MIT
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


## One wire. Execution order comes from the order of statements, never from
## here: a data wire says what depends on what, and nothing about when.
class Connection extends RefCounted:
	var from_node: StringName = &""
	var from_port: StringName = &""
	var to_node: StringName = &""
	var to_port: StringName = &""

	func touches(node_id: StringName) -> bool:
		return from_node == node_id or to_node == node_id


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


func find_node(node_id: StringName) -> ComposerNode:
	for node: ComposerNode in nodes:
		if node.id == node_id:
			return node
	return null


## The node whose lines contain `line`, for putting a caret back on a card.
func node_at_line(line: int) -> ComposerNode:
	for node: ComposerNode in nodes:
		if node.span.contains(line):
			return node
	return null


func connections_for(node_id: StringName) -> Array[Connection]:
	var found: Array[Connection] = []
	for wire: Connection in connections:
		if wire.touches(node_id):
			found.append(wire)
	return found


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
