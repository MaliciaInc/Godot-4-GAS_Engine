## What is wrong with a graph, and where.
##
## Fills the Output panel and the dot on every card from one pass, so the two can
## never describe the same graph differently. A card marked clean beside a row
## complaining about it is the contradiction that costs a person their trust in
## the whole tool.
##
## Every finding carries the line it applies to. A message without a place sends
## someone hunting through a file for something they have to find themselves.
##
## Errors say the ability is wrong. Warnings say it is odd. Neither says the file
## is unreadable - that is `NOT_REPRESENTABLE`, decided by the subset before any
## of this runs, and it means something else entirely: the file is fine and this
## tool cannot draw it.
##
## The bar for a warning is that it is true. A mark on correct code teaches
## people to ignore the panel, and a panel nobody reads is worse than none.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerValidator extends RefCounted

const MISSING_ARGUMENT: String = "%s needs %s"
const WRONG_TYPE: String = "%s: %s"
const UNREAD_VALUE: String = "%s is never read"


## Inspect `graph`, replace its findings, and mark every card to match.
##
## Both in one call on purpose. Two entry points would be two chances to run one
## and not the other, and a dot that disagrees with the panel is worse than no
## dot at all.
##
## Safe to run again. Re-reading a file someone just edited comes through here,
## and a second pass that doubled the findings would report one gap twice.
static func apply(graph: ComposerGraph) -> void:
	if graph == null or not graph.is_editable():
		return

	for node: ComposerNode in graph.nodes:
		node.state = ComposerNode.State.CLEAN
		_forget_gaps(node)

	var found: Array[ComposerGraph.Diagnostic] = inspect(graph)
	graph.diagnostics.assign(found)
	for entry: ComposerGraph.Diagnostic in found:
		var node: ComposerNode = graph.find_node(entry.node_id)
		if node != null:
			node.state = _worse(node.state, entry.severity)


## Everything wrong with `graph`, in the order a person reads it.
static func inspect(graph: ComposerGraph) -> Array[ComposerGraph.Diagnostic]:
	var found: Array[ComposerGraph.Diagnostic] = []
	if graph == null:
		return found
	for node: ComposerNode in graph.nodes:
		_check_arguments(node, found)
		_check_wires(graph, node, found)
		_check_unread(graph, node, found)
	return found


#region Checks
## A required argument the statement never passed.
##
## Optional ones are left alone. A default is not a gap - a call that leaves one
## out has said everything it needed to - and marking them would put an error on
## most correct statements in a file.
##
## The gap becomes a field as well as a row, so the card shows the same words the
## panel does instead of looking complete while the panel disagrees.
static func _check_arguments(
	node: ComposerNode, found: Array[ComposerGraph.Diagnostic]
) -> void:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(node.type_id)
	if entry == null:
		return

	for position: int in range(node.fields.size(), entry.required):
		var declared: ComposerNode.Field = entry.parameter(position)
		if declared == null:
			continue
		node.fields.append(_gap(declared))
		found.append(
			_at(
				ComposerGraph.Severity.ERROR,
				MISSING_ARGUMENT % [node.title, declared.label],
				node
			)
		)


## A wire whose ends do not fit. The type system decides; this only reports.
##
## Blamed on the node the value lands in, because that is the statement that will
## not compile and the one someone has to open.
static func _check_wires(
	graph: ComposerGraph, node: ComposerNode, found: Array[ComposerGraph.Diagnostic]
) -> void:
	for edge: ComposerGraph.Connection in graph.connections:
		if edge.from_node != node.id:
			continue
		var target: ComposerNode = graph.find_node(edge.to_node)
		if target == null:
			continue
		var leaves: ComposerNode.Port = node.find_port(edge.from_port)
		var lands: ComposerNode.Port = target.find_port(edge.to_port)
		if leaves == null or lands == null:
			continue
		if ComposerTypes.ports_match(leaves, lands):
			continue
		found.append(
			_at(
				ComposerGraph.Severity.ERROR,
				WRONG_TYPE % [
					target.title, ComposerTypes.refusal(lands.type_name, leaves.type_name)
				],
				target
			)
		)


## A local nobody names again.
##
## Read off the text of the later statements rather than off the wires. The
## reader only draws a cable when an argument is exactly the name of the local,
## so a value used inside an expression - level plus one, a negation - has no
## wire and would be called dead while the file reads it perfectly well. Warning
## about correct code is how a panel earns being ignored.
##
## A warning and not an error: the code runs. But a value computed and dropped is
## usually a rename that half happened, and saying so costs nothing.
static func _check_unread(
	graph: ComposerGraph, node: ComposerNode, found: Array[ComposerGraph.Diagnostic]
) -> void:
	var value: ComposerNode.Port = node.find_port(ComposerReader.VALUE_OUT)
	if value == null or value.label.is_empty():
		return
	if _named_after(graph, node, value.label):
		return
	found.append(_at(ComposerGraph.Severity.WARNING, UNREAD_VALUE % value.label, node))
#endregion


#region Reading the text
## Whether any statement below `node` names `word`.
static func _named_after(graph: ComposerGraph, node: ComposerNode, word: String) -> bool:
	for other: ComposerNode in graph.nodes:
		if other.span.first_line <= node.span.last_line:
			continue
		for line: String in other.source_text:
			if _names(line, word):
				return true
	return false


## Whether `line` uses `word` as a whole name.
##
## A name does not appear inside a longer one, which is the difference between a
## check and a coincidence.
static func _names(line: String, word: String) -> bool:
	var at: int = line.find(word)
	while at >= 0:
		var after: int = at + word.length()
		if not _inside_a_name(line, at - 1) and not _inside_a_name(line, after):
			return true
		at = line.find(word, at + 1)
	return false


static func _inside_a_name(line: String, at: int) -> bool:
	if at < 0 or at >= line.length():
		return false
	var character: String = line[at]
	return character.is_valid_identifier() or character.is_valid_int()
#endregion


static func _gap(declared: ComposerNode.Field) -> ComposerNode.Field:
	var absent: ComposerNode.Field = ComposerNode.Field.new()
	absent.label = declared.label
	absent.type_name = declared.type_name
	absent.source = ComposerNode.ValueSource.MISSING
	return absent


## Drop the gaps a previous pass added, so running again reports what is wrong
## now rather than everything that was ever wrong.
static func _forget_gaps(node: ComposerNode) -> void:
	var kept: Array[ComposerNode.Field] = []
	for field: ComposerNode.Field in node.fields:
		if field.source != ComposerNode.ValueSource.MISSING:
			kept.append(field)
	node.fields.assign(kept)


static func _at(
	severity: ComposerGraph.Severity, message: String, node: ComposerNode
) -> ComposerGraph.Diagnostic:
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = severity
	found.message = message
	found.node_id = node.id
	found.span = node.span
	return found


## The louder of the two, so a card carrying an error and a warning shows the
## error rather than whichever happened to be found last.
static func _worse(
	state: ComposerNode.State, severity: ComposerGraph.Severity
) -> ComposerNode.State:
	if state == ComposerNode.State.ERROR:
		return state
	if severity == ComposerGraph.Severity.ERROR:
		return ComposerNode.State.ERROR
	return ComposerNode.State.WARNING
