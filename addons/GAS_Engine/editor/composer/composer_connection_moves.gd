## What dragging every cable off one pin onto another one means.
##
## Four kinds of pin, and the same gesture means something different on each.
## Taking a value output's cables to another output re-points every consumer at a
## new producer. Taking a value input's one cable to another input moves a single
## value between slots and leaves the slot it came from holding something valid.
## Taking an execution output's link, or an execution input's, moves a run of
## control, which is not written down anywhere and has to be moved by rewriting
## the order the statements are in.
##
## Nothing here writes. What comes back is a plan - some field changes, or the
## two lists of execution links a transaction has to make true - and the caller
## commits it once. That is what makes a refused drag cost nothing at all: every
## reason to say no is found before a character is written.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerConnectionMoves extends RefCounted

const NO_SUCH_PORT: String = "that pin is no longer on the card"
const WRONG_FAMILY: String = "execution and values do not connect to each other"
const WRONG_WAY: String = "a wire runs from an output to an input"
const NOT_A_LOCAL: String = "only a named value can be sent along a wire"
const TOO_MANY_CABLES: String = "that pin has more than one cable on it"
const NOT_YET_DECLARED: String = (
	"%s is not declared yet where that statement runs, so naming it there would "
	+ "not compile"
)


## What a drag turns into, or why it turns into nothing.
##
## Three answers in one shape: a refusal, nothing to do, or the work. A drag on a
## pin with nothing on it is the middle one - it is not a failure, and committing
## an empty change would hand somebody an undo that does nothing.
class Plan extends RefCounted:
	var message: String = ""
	var fields: Array[ComposerFieldEdits.Change] = []
	var gone: Array[ComposerGraph.Connection] = []
	var wanted: Array[ComposerGraph.Connection] = []

	func is_ok() -> bool:
		return message.is_empty()

	func is_nothing() -> bool:
		return message.is_empty() and fields.is_empty() and wanted.is_empty()


## Everything the drag has to satisfy, and then what it means.
static func planned(
	graph: ComposerGraph,
	origin: ComposerNode,
	from_port: ComposerNode.Port,
	destination: ComposerNode,
	to_port: ComposerNode.Port
) -> Plan:
	if from_port.kind != to_port.kind:
		return _refused(WRONG_FAMILY)
	if from_port.direction != to_port.direction:
		return _refused(WRONG_WAY)

	var leaving: bool = from_port.direction == ComposerNode.PortDirection.OUTPUT
	var cables: Array[ComposerGraph.Connection] = (
		graph.connections_from(origin.id, from_port.id) if leaving
		else graph.connections_to(origin.id, from_port.id)
	)
	if cables.is_empty():
		return Plan.new()

	if from_port.is_execution():
		return _execution(graph, cables, destination, to_port, leaving)
	if leaving:
		return _data_output(graph, cables, destination, to_port)
	if cables.size() != 1:
		return _refused(TOO_MANY_CABLES)
	return _data_input(graph, cables[0], origin, destination, to_port)


#region Execution
## Two lists: what has to be gone, and what has to be there instead.
##
## The displaced link is part of the same transaction because an execution pin
## holds one link: arriving at an occupied pin is replacing what was on it, and
## doing that as a second commit would be a second thing to undo.
static func _execution(
	graph: ComposerGraph,
	cables: Array[ComposerGraph.Connection],
	destination: ComposerNode,
	to_port: ComposerNode.Port,
	leaving: bool
) -> Plan:
	var made: Plan = Plan.new()
	for wire: ComposerGraph.Connection in cables:
		made.wanted.append(
			ComposerReader.wire(destination.id, to_port.id, wire.to_node, wire.to_port)
			if leaving
			else ComposerReader.wire(
				wire.from_node, wire.from_port, destination.id, to_port.id
			)
		)
	made.gone.append_array(cables)
	made.gone.append_array(
		graph.connections_from(destination.id, to_port.id) if leaving
		else graph.connections_to(destination.id, to_port.id)
	)
	return made
#endregion


#region Values
## Every consumer of one value is fed by another value instead.
##
## The destination keeps whatever it already fed: a value output carries as many
## cables as there are statements that want it. Every consumer is judged before
## anything is written, which is what makes a refused drag leave the file exactly
## as it was rather than half transferred.
static func _data_output(
	graph: ComposerGraph,
	cables: Array[ComposerGraph.Connection],
	destination: ComposerNode,
	to_port: ComposerNode.Port
) -> Plan:
	var named: String = to_port.label
	if named.is_empty():
		return _refused(NOT_A_LOCAL)

	var made: Plan = Plan.new()
	for wire: ComposerGraph.Connection in cables:
		var to: ComposerNode = graph.find_node(wire.to_node)
		var position: int = to.field_for(wire.to_port) if to != null else -1
		if to == null or position < 0 or position >= to.fields.size():
			return _refused(NO_SUCH_PORT)
		var refusal: String = _fits(to.fields[position], to_port, destination, to, named)
		if not refusal.is_empty():
			return _refused(refusal)
		made.fields.append(ComposerFieldEdits.Change.of(to.id, position, named))
	return made


## One value moves from the slot it was in to another slot.
##
## The producer is read off the cable that arrives, never off the destination
## pin's label: an input pin is named for the argument it is, so taking the name
## from there would write the argument's own name into it as if it were a local.
## The slot it leaves goes back to what it would have been created holding - a
## value input takes one cable and cannot be left empty, because the argument
## text is the cable.
static func _data_input(
	graph: ComposerGraph,
	arriving: ComposerGraph.Connection,
	origin: ComposerNode,
	destination: ComposerNode,
	to_port: ComposerNode.Port
) -> Plan:
	var producer: ComposerNode = graph.find_node(arriving.from_node)
	var out: ComposerNode.Port = (
		producer.find_port(arriving.from_port) if producer != null else null
	)
	if out == null:
		return _refused(NO_SUCH_PORT)
	if out.label.is_empty():
		return _refused(NOT_A_LOCAL)

	var leaves: int = origin.field_for(arriving.to_port)
	var into: int = destination.field_for(to_port.id)
	if leaves < 0 or leaves >= origin.fields.size():
		return _refused(NO_SUCH_PORT)
	if into < 0 or into >= destination.fields.size():
		return _refused(NO_SUCH_PORT)
	var refusal: String = _fits(
		destination.fields[into], out, producer, destination, out.label
	)
	if not refusal.is_empty():
		return _refused(refusal)

	var made: Plan = Plan.new()
	made.fields.append(
		ComposerFieldEdits.Change.of(
			origin.id, leaves, ComposerWriter.declared_default(origin.fields[leaves])
		)
	)
	made.fields.append(ComposerFieldEdits.Change.of(destination.id, into, out.label))
	return made


## Whether that value may be written into that slot, in words, or nothing.
static func _fits(
	field: ComposerNode.Field,
	out: ComposerNode.Port,
	producer: ComposerNode,
	consumer: ComposerNode,
	named: String
) -> String:
	if not ComposerTypes.accepts(field.type_name, out.type_name):
		return ComposerTypes.refusal(field.type_name, out.type_name)
	if not producer.runs_before(consumer):
		return NOT_YET_DECLARED % named
	return ""
#endregion


static func _refused(message: String) -> Plan:
	var made: Plan = Plan.new()
	made.message = message
	return made
