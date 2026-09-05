## The one door every wire change goes through.
##
## A canvas expresses an intention - somebody dragged from this pin to that one.
## Turning that into GDScript, proving the result reads back as what was asked
## for, and committing it exactly once is this. The canvas never edits anything
## itself, so there is no second path where a rule can be skipped.
##
## Refusals are loud and total. Every change is staged on a graph read fresh out
## of the current text, so a refused wire leaves the file *and* the graph the
## canvas is drawing byte-identical: half a rewiring is worse than none, because
## the person cannot see which half happened.
##
## Multiplicity is not a gate here, deliberately. In this projection every input
## takes one wire and only a local's output fans out, so the question a canvas
## really asks is not "may this pin hold another wire" but "what does joining it
## again mean" - and that answer differs by family, not by count: an argument is
## overwritten, a run of control is re-routed. Those are the two branches below.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerConnectionController extends RefCounted

## Why a wire was not made. Said out loud rather than logged: a drag that
## silently does nothing is a tool the person stops trusting.
signal refused(message: String)

const READ_ONLY: String = "this ability is open to be looked at, not changed"
const NO_SUCH_PORT: String = "that pin is no longer on the card"
const WRONG_FAMILY: String = "execution and values do not connect to each other"
const WRONG_WAY: String = "a wire runs from an output to an input"
const NOT_A_LOCAL: String = "only a named value can be sent along a wire"
const NOT_YET_DECLARED: String = (
	"%s is declared after this statement, so it does not exist here yet"
)

var _document: ComposerDocument = null


func bind(document: ComposerDocument) -> void:
	_document = document


#region Making and breaking
## Join two pins, by writing what the join means.
func connect_edge(edge: ComposerGraph.Connection) -> bool:
	var staged: ComposerGraph = _staged()
	if staged == null:
		return false
	var ends: Array = _checked(staged, edge, true)
	if ends.is_empty():
		return false

	var from: ComposerNode = ends[0]
	var to: ComposerNode = ends[1]
	var out: ComposerNode.Port = ends[2]
	if out.is_execution():
		return _flow(ComposerFlowEdits.connect_flow(_document.printed(), staged, edge))

	var named: String = out.label
	if named.is_empty():
		return _no(NOT_A_LOCAL)
	if not _in_scope(from, to):
		return _no(NOT_YET_DECLARED % named)
	# Whatever the argument held - a literal, an expression, another local - is
	# gone, not remembered. There is nowhere to remember it: the argument text is
	# the connection, so a kept copy would be a second opinion about the file.
	return _argument_becomes(staged, to, edge.to_port, named)


## Take a wire off, and leave something valid where it was.
##
## A data argument goes back to the value it would have been created holding. It
## cannot be left empty: the wire *was* the argument, and removing both would be
## a call that no longer compiles.
func disconnect_edge(edge: ComposerGraph.Connection) -> bool:
	var staged: ComposerGraph = _staged()
	if staged == null:
		return false
	var ends: Array = _checked(staged, edge, false)
	if ends.is_empty():
		return false

	var to: ComposerNode = ends[1]
	var out: ComposerNode.Port = ends[2]
	if out.is_execution():
		return _flow(ComposerFlowEdits.disconnect_flow(_document.printed(), staged, edge))

	var position: int = to.field_for(edge.to_port)
	if position < 0 or position >= to.fields.size():
		return _no(NO_SUCH_PORT)
	return _argument_becomes(staged, to, edge.to_port, _default_for(to, position))


## Break everything on one pin, in a single change.
##
## One commit, not one per wire: a local feeding four arguments is one thing a
## person did, and four entries in the history would take four undos to put
## back. A pin with nothing on it succeeds without committing - there is no
## change to record, and recording one would hand somebody an undo that does
## nothing.
func break_all(node_id: StringName, port_id: StringName) -> bool:
	var staged: ComposerGraph = _staged()
	if staged == null:
		return false

	var node: ComposerNode = staged.find_node(node_id)
	var port: ComposerNode.Port = node.find_port(port_id) if node != null else null
	if port == null:
		return _no(NO_SUCH_PORT)

	var wires: Array[ComposerGraph.Connection] = staged.connections_for(node_id, port_id)
	if wires.is_empty():
		return true
	if port.is_execution():
		return _flow(
			ComposerFlowEdits.disconnect_flow(_document.printed(), staged, wires[0])
		)

	var changes: Array[ComposerFieldEdits.Change] = []
	for wire: ComposerGraph.Connection in wires:
		var to: ComposerNode = staged.find_node(wire.to_node)
		var position: int = to.field_for(wire.to_port) if to != null else -1
		if to == null or position < 0 or position >= to.fields.size():
			return _no(NO_SUCH_PORT)
		changes.append(
			ComposerFieldEdits.Change.of(to.id, position, _default_for(to, position))
		)
	return _rewritten(staged, changes)


## Move every wire on one pin to another pin of the same kind.
##
## All of them or none. Every move is checked against the destination before
## anything is written, which is what makes a refused Ctrl-drag leave the file
## exactly as it was rather than half-transferred.
func move_connections(
	origin_node_id: StringName,
	origin_port_id: StringName,
	destination_node_id: StringName,
	destination_port_id: StringName
) -> bool:
	var staged: ComposerGraph = _staged()
	if staged == null:
		return false

	var origin: ComposerNode = staged.find_node(origin_node_id)
	var destination: ComposerNode = staged.find_node(destination_node_id)
	if origin == null or destination == null:
		return _no(NO_SUCH_PORT)
	var from_port: ComposerNode.Port = origin.find_port(origin_port_id)
	var to_port: ComposerNode.Port = destination.find_port(destination_port_id)
	if from_port == null or to_port == null:
		return _no(NO_SUCH_PORT)
	if from_port.kind != to_port.kind:
		return _no(WRONG_FAMILY)
	if from_port.direction != to_port.direction:
		return _no(WRONG_WAY)

	var wires: Array[ComposerGraph.Connection] = staged.connections_for(
		origin_node_id, origin_port_id
	)
	if wires.is_empty():
		return true
	if from_port.is_execution():
		# Moving a run of control means rewriting the order statements are
		# written in, which the flow transformations express as a disconnect and
		# a connect. Doing it as one motion is TASK 5's job, not a guess here.
		return _no(ComposerFlowEdits.NOT_REPRESENTABLE)

	var named: String = to_port.label
	if named.is_empty():
		return _no(NOT_A_LOCAL)
	var changes: Array[ComposerFieldEdits.Change] = []
	for wire: ComposerGraph.Connection in wires:
		var to: ComposerNode = staged.find_node(wire.to_node)
		var position: int = to.field_for(wire.to_port) if to != null else -1
		if to == null or position < 0 or position >= to.fields.size():
			return _no(NO_SUCH_PORT)
		var wanted: StringName = to.fields[position].type_name
		if not ComposerTypes.accepts(wanted, to_port.type_name):
			return _no(ComposerTypes.refusal(wanted, to_port.type_name))
		if not _in_scope(destination, to):
			return _no(NOT_YET_DECLARED % named)
		changes.append(ComposerFieldEdits.Change.of(to.id, position, named))
	return _rewritten(staged, changes)


## Put text somebody typed into one argument.
##
## The same door a dropped cable comes through, on purpose. A typed value and a
## wired one are the same edit to the same field, and the screen used to do this
## itself: it wrote straight into the document's live graph, so a refused edit
## left the canvas and the Inspector showing text the file did not contain until
## something else redrew them. Staged here, a refusal changes nothing at all.
func rewrite_field(node_id: StringName, position: int, written: String) -> bool:
	var staged: ComposerGraph = _staged()
	if staged == null:
		return false

	var changes: Array[ComposerFieldEdits.Change] = []
	changes.append(ComposerFieldEdits.Change.of(node_id, position, written))
	return _rewritten(staged, changes)
#endregion


#region Checking
## A graph to change, read out of the text as it stands, or nothing.
##
## Read fresh rather than handed out: the document's own graph is what the
## canvas is drawing, and staging edits on it would leave a refused operation
## visible on screen with none of it in the file.
func _staged() -> ComposerGraph:
	if _document == null or not _document.is_open():
		# The document's own words for it. Two spellings of the same refusal is
		# two things to keep in step, and nobody notices when they stop being.
		_no(ComposerDocument.NOTHING_OPEN)
		return null
	if not _document.may_write():
		_no(READ_ONLY)
		return null
	return ComposerReader.read(_document.printed(), _document.path())


## The two ends and the output port, or nothing when a rule says no.
##
## Everything a wire has to satisfy before a single character is written: both
## cards are still there, both pins are still on them, they are the same family,
## and they face opposite ways. Execution self-loops and longer circles are
## refused further in, by the transformation that would have to write them.
##
## The types are asked about only when `typed`, which means only when making a
## wire. A file can already hold an argument whose type does not fit - the
## reader draws what the person wrote, and judging it is the validator's job -
## and a shared check would then refuse to take that cable off. Somebody left
## staring at a cable the tool will not unplug is worse off than somebody
## looking at one it warned them about.
func _checked(graph: ComposerGraph, edge: ComposerGraph.Connection, typed: bool) -> Array:
	var from: ComposerNode = graph.find_node(edge.from_node)
	var to: ComposerNode = graph.find_node(edge.to_node)
	if from == null or to == null:
		_no(NO_SUCH_PORT)
		return []

	var out: ComposerNode.Port = from.find_port(edge.from_port)
	var into: ComposerNode.Port = to.find_port(edge.to_port)
	if out == null or into == null:
		_no(NO_SUCH_PORT)
		return []
	if out.kind != into.kind:
		_no(WRONG_FAMILY)
		return []
	if (
		out.direction != ComposerNode.PortDirection.OUTPUT
		or into.direction != ComposerNode.PortDirection.INPUT
	):
		_no(WRONG_WAY)
		return []
	if typed and not out.is_execution() and not ComposerTypes.ports_match(out, into):
		_no(ComposerTypes.refusal(into.type_name, out.type_name))
		return []
	return [from, to, out]


## Whether the local `producer` declares is in scope where `consumer` runs.
##
## A value wire is a name written into an argument, and a name written above
## its own `var` is a file that parses and does not compile. The reader will
## not draw such a wire, so nothing downstream would notice: the canvas would
## show the drag failing while the file quietly stopped building.
static func _in_scope(producer: ComposerNode, consumer: ComposerNode) -> bool:
	return producer.span.last_line < consumer.span.first_line


## Say why, and answer false so a caller can `return _no(...)`.
func _no(message: String) -> bool:
	refused.emit(message)
	return false
#endregion


#region Writing
## Put `written` in one argument and commit, as one change.
func _argument_becomes(
	graph: ComposerGraph, node: ComposerNode, port_id: StringName, written: String
) -> bool:
	var position: int = node.field_for(port_id)
	if position < 0 or position >= node.fields.size():
		return _no(NO_SUCH_PORT)
	var changes: Array[ComposerFieldEdits.Change] = []
	changes.append(ComposerFieldEdits.Change.of(node.id, position, written))
	return _rewritten(graph, changes)


## Ask for those values to be written, and commit whatever comes back.
##
## The argument text is the whole truth about a data wire. There is no stored
## "this was connected" anywhere: the wire exists because the argument is
## exactly a local's name, so writing that name IS connecting and writing a
## value back IS disconnecting. Nothing can fall out of step because there is
## nothing else to keep in step.
##
## Every change of every gesture goes in at once. A pin feeding four arguments
## is one thing a person did, and four commits would take four undos to put
## back; a refusal on the fourth would leave the first three written.
func _rewritten(
	graph: ComposerGraph, changes: Array[ComposerFieldEdits.Change]
) -> bool:
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite_many(
		_document.printed(), graph, changes
	)
	if not done.ok:
		return _no(done.message)
	return _accepted(_document.commit(done.source))


## What an unconnected argument holds: what the method declares, or the zero.
static func _default_for(node: ComposerNode, position: int) -> String:
	var field: ComposerNode.Field = node.fields[position]
	if not field.default_expression.is_empty():
		return field.default_expression
	return ComposerTypes.default_expression(field.type_name, field.variant_type)


## Hand a flow transformation to the document, or say why there was none.
func _flow(done: ComposerFlowEdits.Result) -> bool:
	if not done.ok:
		return _no(done.message)
	return _accepted(_document.commit(done.source))


func _accepted(refusal: ComposerGraph.Diagnostic) -> bool:
	if refusal != null:
		return _no(refusal.message)
	return true
#endregion
