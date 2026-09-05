## Making a new statement, and joining it to whatever asked for it.
##
## Dragging a wire into empty canvas and picking a call from the menu is one
## thing a person did, so it is one change to the file and one step to undo. The
## statement and the cable are written together; a version that inserted the call
## and then connected it would leave a half-made node on screen whenever the
## second half was refused.
##
## Which way the drag went decides where the statement goes. Out of a value, and
## the new call goes *after* the one that produces it, taking that value as an
## argument. Into an argument, and the new call goes *before* the statement that
## needs it, because a local has to be declared above the line that names it.
## Both are the same rule stated twice: a value is written before it is read.
##
## Nothing is inserted and then fixed up. The text is built, read back, finished,
## and only then handed over - so a creation that cannot be expressed leaves the
## file exactly as it was.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCreation extends RefCounted

const NOTHING_TO_MAKE: String = "there is no such call to make"
const NO_ROOM: String = "there is nowhere in this ability to put that"
const NOT_A_VALUE: String = "that call hands nothing back to hold"

## Why a statement cannot be put on an execution input that several paths
## arrive at. Said in full because the way out of it is not obvious: the
## person has to start the drag from the path they meant.
const AMBIGUOUS_MERGE: String = (
	"This execution input has more than one source path; insert from the path "
	+ "output instead."
)


## What was made, or why nothing was.
class Result extends RefCounted:
	var source: String = ""
	var message: String = ""

	## The line the new statement was written on, so a caller can find the node
	## it stands for without guessing which of the two is new. Node ids are
	## derived from line numbers, so every id after an insertion is a different
	## id than it was - "the one that was not there before" cannot be asked.
	var at_line: int = ComposerSpan.NO_LINE

	func is_ok() -> bool:
		return message.is_empty()


static func _refuse(message: String) -> ComposerCreation.Result:
	var made: ComposerCreation.Result = ComposerCreation.Result.new()
	made.message = message
	return made


static func _accept(source: String, at_line: int) -> ComposerCreation.Result:
	var made: ComposerCreation.Result = ComposerCreation.Result.new()
	made.source = source
	made.at_line = at_line
	return made


#region Making one
## The text this ability becomes when `entry` is added for `context`.
static func made(
	source: String,
	graph: ComposerGraph,
	entry: ComposerCatalog.Entry,
	context: ComposerActionMenu.Context
) -> ComposerCreation.Result:
	if entry == null:
		return _refuse(NOTHING_TO_MAKE)
	if context.mode == ComposerActionMenu.Context.Mode.ALL:
		return _plain(source, graph, entry)
	var from_pin: bool = context.mode == ComposerActionMenu.Context.Mode.FROM_PIN
	if context.is_execution():
		# A run of control asked for this, so the statement goes on that run -
		# not at the end of the ability, which is where every execution drag used
		# to put it, whichever pin it started from.
		return (
			_execution_from(source, graph, entry, context) if from_pin
			else _execution_to(source, graph, entry, context)
		)
	if from_pin:
		return _consuming(source, graph, entry, context)
	return _producing(source, graph, entry, context)


## A statement with nothing attached, put where the ability ends.
##
## Before the End rather than at the bottom of the file: everything after the
## return is unreachable, and a call written there is one somebody has to notice
## never ran.
static func _plain(
	source: String, graph: ComposerGraph, entry: ComposerCatalog.Entry
) -> ComposerCreation.Result:
	var written: String = ComposerStatementFactory.call_statement(entry, graph.source_path)
	if written.is_empty():
		return _refuse(NOTHING_TO_MAKE)
	var at: int = ComposerFlow.insertion_before_main_end(graph)
	if at < 0:
		return _refuse(NO_ROOM)
	return _accept(ComposerEdits.insert_after(source, at, written), at + 1)


## Dragged out of an execution pin: the new statement runs on that path.
##
## Where that is depends on the pin, and the projection already answers it -
## the same answer that says where a moved statement has to be written. The two
## paths that do not exist yet are written out here: a branch with no `else` and
## a match with no catch-all get a real one, holding the new statement, with no
## mark on it. A path somebody asked for is theirs, not machinery.
static func _execution_from(
	source: String,
	graph: ComposerGraph,
	entry: ComposerCatalog.Entry,
	context: ComposerActionMenu.Context
) -> ComposerCreation.Result:
	var node: ComposerNode = graph.find_node(context.node_id)
	var written: String = ComposerStatementFactory.call_statement(entry, graph.source_path)
	if node == null:
		return _refuse(NO_ROOM)
	if written.is_empty():
		return _refuse(NOTHING_TO_MAKE)

	var opened: String = _opened_path(source, graph, node, context.port_id, written)
	if not opened.is_empty():
		return _accept(opened, _line_holding(opened, graph.source_path, written))

	var anchor: ComposerFlowPlaces.Anchor = ComposerFlowPlaces.anchor_for(
		graph, node, context.port_id
	)
	if not anchor.is_ok():
		return _refuse(anchor.refusal if not anchor.refusal.is_empty() else NO_ROOM)
	return _accept(
		ComposerEdits.insert_after(
			source,
			anchor.line - 1,
			ComposerEdits.TAB.repeat(anchor.indent) + written.strip_edges()
		),
		anchor.line
	)


## The text with a path written that was not there before, or nothing when the
## pin already has one.
static func _opened_path(
	source: String,
	graph: ComposerGraph,
	node: ComposerNode,
	port_id: StringName,
	written: String
) -> String:
	if port_id == ComposerReader.FALSE_OUT:
		if ComposerFlowPlaces.else_of(graph, node) != null:
			return ""
		if ComposerFlowPlaces.chains_on(graph, node):
			return ComposerFlowTransforms.with_nested_else(source, graph, node, written)
		return ComposerFlowTransforms.with_else(source, graph, node, written)
	if port_id == ComposerReader.UNMATCHED_OUT and not ComposerFlowPlaces.has_wildcard(
		graph, node
	):
		return ComposerFlowTransforms.with_case(source, graph, node, written)
	return ""


## Which line of `changed` the new statement ended up on.
##
## Asked of the text rather than counted, because the transformations that
## open a path write two lines and not one, and a caller that guessed would
## put the card's position on the `else` instead of on the statement.
static func _line_holding(changed: String, path: String, written: String) -> int:
	var wanted: String = written.strip_edges()
	var read: ComposerGraph = ComposerReader.read(changed, path)
	for node: ComposerNode in read.nodes:
		if node.source_backed and node.text.strip_edges() == wanted:
			return node.span.last_line
	return ComposerSpan.NO_LINE


## Dragged into an execution input: the new statement runs before that one.
##
## Only when one path arrives there. A statement several paths reach - the one
## after an `if`, say - has no single place "before it" that means what the
## drag meant, and picking one of them would quietly put the new call on one
## branch of two.
static func _execution_to(
	source: String,
	graph: ComposerGraph,
	entry: ComposerCatalog.Entry,
	context: ComposerActionMenu.Context
) -> ComposerCreation.Result:
	var node: ComposerNode = graph.find_node(context.node_id)
	var written: String = ComposerStatementFactory.call_statement(entry, graph.source_path)
	if node == null:
		return _refuse(NO_ROOM)
	if written.is_empty():
		return _refuse(NOTHING_TO_MAKE)
	if ComposerFlow.predecessors_of(graph, node.id).size() > 1:
		return _refuse(AMBIGUOUS_MERGE)

	var anchor: ComposerFlowPlaces.Anchor = ComposerFlowPlaces.anchor_for(
		graph, node, ComposerReader.EXEC_IN
	)
	return _accept(
		ComposerEdits.insert_after(
			source,
			anchor.line - 1,
			ComposerEdits.TAB.repeat(anchor.indent) + written.strip_edges()
		),
		anchor.line
	)


## Dragged out of a value: the new call goes after the one producing it, with
## that value in the first argument that accepts it.
static func _consuming(
	source: String,
	graph: ComposerGraph,
	entry: ComposerCatalog.Entry,
	context: ComposerActionMenu.Context
) -> ComposerCreation.Result:
	var producer: ComposerNode = graph.find_node(context.node_id)
	if producer == null:
		return _refuse(NO_ROOM)
	var slot: int = ComposerActionMenu.first_argument_for(context, entry)
	if slot < 0:
		return _refuse(NOTHING_TO_MAKE)
	var written: String = ComposerStatementFactory.call_statement(entry, graph.source_path)
	if written.is_empty():
		return _refuse(NOTHING_TO_MAKE)

	var named: String = _local_of(producer)
	if named.is_empty():
		return _refuse(NOT_A_VALUE)
	return _argument_set(
		ComposerEdits.insert_after(source, producer.span.last_line, written),
		graph.source_path,
		producer.span.last_line + 1,
		slot,
		named
	)


## Dragged out of an argument: the new call goes before the statement that needs
## it, keeping what it hands back in a local that argument then names.
static func _producing(
	source: String,
	graph: ComposerGraph,
	entry: ComposerCatalog.Entry,
	context: ComposerActionMenu.Context
) -> ComposerCreation.Result:
	var consumer: ComposerNode = graph.find_node(context.node_id)
	var slot: int = _argument_index(context.port_id)
	if consumer == null or slot < 0:
		return _refuse(NO_ROOM)

	var used: PackedStringArray = _locals_in(graph)
	# Asked twice on purpose, and safe because both answers come from the same
	# entry and the same list of names in use. The factory writes the line and
	# does not hand the name back; reading it out of the line afterwards would be
	# a second parser for something already decided.
	var named: String = ComposerStatementFactory.unique_local_name(entry, used)
	var written: String = ComposerStatementFactory.local_call(entry, graph.source_path, used)
	if written.is_empty():
		return _refuse(NOT_A_VALUE)

	return _argument_set(
		ComposerEdits.insert_after(source, consumer.span.first_line - 1, written),
		graph.source_path,
		consumer.span.first_line + 1,
		slot,
		named
	)
#endregion


#region Finishing the join
## Put `named` into one argument of the statement now at `line`.
##
## Read back first rather than edited as text. The statement is found by the line
## it must be on - one was inserted above or below it, and by exactly one - so
## there is no searching for it by what it says, which would pick the wrong one
## of two identical calls.
static func _argument_set(
	source: String, path: String, line: int, slot: int, named: String
) -> ComposerCreation.Result:
	var read: ComposerGraph = ComposerReader.read(source, path)
	if not read.is_editable():
		return _refuse(read.blocked_reason())

	var node: ComposerNode = read.node_at_line(line)
	if node == null or slot < 0 or slot >= node.fields.size():
		return _refuse(NO_ROOM)

	node.fields[slot].display = named
	node.fields[slot].source = ComposerNode.ValueSource.LITERAL
	node.dirty = true
	var printed: ComposerWriter.Result = ComposerWriter.apply(read, source, false)
	if not printed.is_ok():
		return _refuse(printed.refusal.message)
	# The new statement is the one the caller asked about, not the one just
	# edited: writing an argument into an existing call moves no lines.
	return _accept(printed.text, line)


## The local a statement declares, or nothing.
static func _local_of(node: ComposerNode) -> String:
	var produced: ComposerNode.Port = node.find_port(ComposerReader.VALUE_OUT)
	return produced.label if produced != null else ""


## Every local name the body already uses, so a new one does not shadow them.
static func _locals_in(graph: ComposerGraph) -> PackedStringArray:
	var used: PackedStringArray = PackedStringArray()
	for node: ComposerNode in graph.nodes:
		var named: String = _local_of(node)
		if not named.is_empty():
			used.append(named)
	return used


static func _argument_index(port_id: StringName) -> int:
	var spelled: String = String(port_id)
	var mark: int = spelled.rfind("_")
	if mark < 0:
		return -1
	var number: String = spelled.substr(mark + 1)
	return number.to_int() if number.is_valid_int() else -1
#endregion
