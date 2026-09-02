## GDScript in, a graph out. Nothing is stored and nothing is executed.
##
## Reads the body of one method through `ComposerSubset` and builds the
## projection the canvas draws. The subset decides what a line is; this decides
## what that line becomes.
##
## Fails early and loudly. One line outside the subset ends the read, and the
## file opens with the reason and the line rather than with a partial graph - a
## graph missing a statement looks complete, and the writer would then emit what
## it drew and delete the statement from the file.
##
## Comments and blank lines are carried by the statement below them. That is how
## a person reads them, and it is what lets the writer put them back where they
## were instead of dropping them on the first save.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerReader extends RefCounted

const EXEC_IN: StringName = &"exec_in"
const EXEC_OUT: StringName = &"exec_out"
const VALUE_OUT: StringName = &"value_out"

## Statements that suspend the ability, which the card says out loud.
const AWAIT_MARK: String = "await "


## Read `source` as a graph of `path`.
##
## Always returns a graph. An unreadable file comes back with no nodes and one
## NOT_REPRESENTABLE diagnostic, which is what the panel and the canvas both
## read - so neither has to decide on its own whether the file is drawable.
static func read(source: String, path: String) -> ComposerGraph:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.source_path = path

	var lines: PackedStringArray = source.split("\n")
	var span: ComposerSpan = ComposerSubset.body_span(lines)
	var refusal: ComposerGraph.Diagnostic = ComposerSubset.first_refusal(lines, span)
	if refusal != null:
		graph.diagnostics = [refusal] as Array[ComposerGraph.Diagnostic]
		return graph

	_build_nodes(graph, lines, span)
	_wire_execution(graph, lines)
	_wire_data(graph, lines)
	return graph


#region Nodes
static func _build_nodes(
	graph: ComposerGraph, lines: PackedStringArray, span: ComposerSpan
) -> void:
	var carried: int = ComposerSpan.NO_LINE
	for line: int in range(span.first_line, span.last_line + 1):
		var verdict: ComposerSubset.Verdict = ComposerSubset.classify(lines[line - 1])
		if not verdict.is_drawn():
			# A comment or a blank belongs to whatever comes next, so remember
			# where the run started and let the statement claim it.
			if carried == ComposerSpan.NO_LINE:
				carried = line
			continue

		var first: int = carried if carried != ComposerSpan.NO_LINE else line
		carried = ComposerSpan.NO_LINE
		graph.nodes.append(_node(lines[line - 1], verdict, first, line))


static func _node(
	line: String, verdict: ComposerSubset.Verdict, first: int, last: int
) -> ComposerNode:
	var text: String = line.strip_edges()
	var node: ComposerNode = ComposerNode.new()
	node.id = StringName("n%d" % last)
	node.span = ComposerSpan.new(first, last)
	node.awaits = text.contains(AWAIT_MARK)
	node.type_id = StringName(_call_name(text))
	node.title = _title(text, verdict)
	node.ports = _ports(verdict)
	node.fields.assign(_fields(text))
	return node


## The words on the card.
##
## A call is named by what it calls, spelled the way a person would say it:
## `apply_gameplay_effect` reads as `Apply Gameplay Effect`. The structural
## statements name themselves, because `if` is already the clearest word for
## what it does.
static func _title(text: String, verdict: ComposerSubset.Verdict) -> String:
	if verdict.kind == ComposerSubset.Kind.BRANCH:
		return "Branch"
	if verdict.kind == ComposerSubset.Kind.BRANCH_ELSE:
		return "Otherwise"
	if verdict.kind == ComposerSubset.Kind.MATCH:
		return "Match"
	if verdict.kind == ComposerSubset.Kind.MATCH_CASE:
		return "Case"
	if verdict.kind == ComposerSubset.Kind.RETURN:
		return "End"

	var name: String = _call_name(text)
	if name.is_empty():
		return text
	return name.get_file().capitalize()


## The called identifier, or empty when the line calls nothing.
static func _call_name(text: String) -> String:
	var body: String = text
	if body.begins_with("var "):
		var equals: int = body.find("=")
		if equals < 0:
			return ""
		body = body.substr(equals + 1).strip_edges()
	if body.begins_with(AWAIT_MARK):
		body = body.substr(AWAIT_MARK.length()).strip_edges()

	var open: int = body.find("(")
	if open <= 0:
		return ""
	return body.substr(0, open).strip_edges()


## What a node offers a wire.
##
## Execution on every drawn statement, because every one of them runs. A value
## port only where a local is declared: that is the one shape in the subset that
## produces something later lines can name.
static func _ports(verdict: ComposerSubset.Verdict) -> Array[ComposerNode.Port]:
	var ports: Array[ComposerNode.Port] = [
		port(EXEC_IN, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.INPUT),
		port(EXEC_OUT, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT),
	]
	if verdict.kind == ComposerSubset.Kind.LOCAL:
		ports.append(
			port(VALUE_OUT, ComposerNode.PortKind.DATA, ComposerNode.PortDirection.OUTPUT)
		)
	return ports


## Public: this is how a projection is assembled, and anything else building
## one - a fixture, a future importer - should assemble it the same way rather
## than growing a second opinion about what a port is.
static func port(
	id: StringName, kind: ComposerNode.PortKind, direction: ComposerNode.PortDirection
) -> ComposerNode.Port:
	var port: ComposerNode.Port = ComposerNode.Port.new()
	port.id = id
	port.kind = kind
	port.direction = direction
	return port


## One field per argument, labelled by position.
##
## Positional until the catalog names them: without it the reader knows the
## argument's text but not what the engine calls that parameter, and inventing a
## name here would put a word on the card the API never used.
static func _fields(text: String) -> Array[ComposerNode.Field]:
	var fields: Array[ComposerNode.Field] = []
	var open: int = text.find("(")
	if open < 0 or not text.ends_with(")"):
		return fields

	var inside: String = text.substr(open + 1, text.length() - open - 2).strip_edges()
	if inside.is_empty():
		return fields

	var position: int = 1
	for argument: String in inside.split(","):
		var field: ComposerNode.Field = ComposerNode.Field.new()
		field.label = "#%d" % position
		field.display = argument.strip_edges()
		fields.append(field)
		position += 1
	return fields
#endregion


#region Wires
## Execution follows the statements, in the order they are written.
##
## Only between siblings: a statement inside a branch belongs to that branch, and
## joining across indentation would draw a path the code does not take.
static func _wire_execution(graph: ComposerGraph, lines: PackedStringArray) -> void:
	var previous: Dictionary[int, StringName] = {}
	for node: ComposerNode in graph.nodes:
		var depth: int = ComposerSubset.indent_of(lines[node.span.last_line - 1])
		if previous.has(depth):
			graph.connections.append(wire(previous[depth], EXEC_OUT, node.id, EXEC_IN))
		previous[depth] = node.id

		# A deeper block starts fresh: whatever ran at that depth belonged to an
		# earlier branch and must not reach into this one.
		for open_depth: int in previous.keys():
			if open_depth > depth:
				previous.erase(open_depth)


## A local's value reaches every later statement that names it.
##
## Read by name rather than by scope analysis, which the subset makes safe: a
## body with no loops and no lambdas has one flat set of names, so a later line
## mentioning `target` means that `target`.
static func _wire_data(graph: ComposerGraph, lines: PackedStringArray) -> void:
	for node: ComposerNode in graph.nodes:
		var declared: String = _local_name(lines[node.span.last_line - 1])
		if declared.is_empty():
			continue
		for other: ComposerNode in graph.nodes:
			if other.span.first_line <= node.span.last_line:
				continue
			if not _mentions(lines[other.span.last_line - 1], declared):
				continue
			graph.connections.append(wire(node.id, VALUE_OUT, other.id, EXEC_IN))


static func _local_name(line: String) -> String:
	var text: String = line.strip_edges()
	if not text.begins_with("var "):
		return ""
	var rest: String = text.substr(4)
	var stop: int = rest.find(":")
	if stop < 0:
		return ""
	return rest.substr(0, stop).strip_edges()


## Whether a line names `word` as a word, not as part of a longer one.
static func _mentions(line: String, word: String) -> bool:
	var open: int = line.find("(")
	if open < 0:
		return false
	for argument: String in line.substr(open + 1).split(","):
		if argument.strip_edges().trim_suffix(")").strip_edges() == word:
			return true
	return false


## Public for the same reason `port()` is.
static func wire(
	source: StringName, source_port: StringName,
	target: StringName, target_port: StringName
) -> ComposerGraph.Connection:
	var wire: ComposerGraph.Connection = ComposerGraph.Connection.new()
	wire.from_node = source
	wire.from_port = source_port
	wire.to_node = target
	wire.to_port = target_port
	return wire
#endregion
