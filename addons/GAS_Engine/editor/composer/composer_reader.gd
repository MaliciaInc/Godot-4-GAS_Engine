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
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerReader extends RefCounted

const EXEC_IN: StringName = &"exec_in"
const EXEC_OUT: StringName = &"exec_out"
const VALUE_OUT: StringName = &"value_out"

## An argument slot. One per field, so a value lands where it is actually used
## rather than on the node's run of control.
const ARGUMENT: String = "arg_%d"

const OPEN_BRACKET: String = "("

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

	_build_nodes(graph, lines, span, path)
	_wire_execution(graph, lines)
	_wire_data(graph, lines)

	# The findings come back with the graph rather than being asked for later.
	# A caller that forgot to validate would draw a file with every card clean
	# and an empty Output panel, which reads as "nothing is wrong" rather than
	# as "nobody looked".
	ComposerValidator.apply(graph)
	return graph


#region Nodes
static func _build_nodes(
	graph: ComposerGraph, lines: PackedStringArray, span: ComposerSpan, path: String
) -> void:
	var carried: int = ComposerSpan.NO_LINE
	# What each local was declared to be, gathered on the way down. A receiver
	# is very often a local - `var data: GameplayAbilityTargetData = ...` and
	# then `data.get_target_nodes()` - and without this every call on one is a
	# call the catalog cannot place.
	var locals: Dictionary[String, StringName] = {}
	for made: ComposerSubset.Statement in ComposerSubset.statements(lines, span):
		if not made.verdict.is_drawn():
			# A comment or a blank belongs to whatever comes next, so remember
			# where the run started and let the statement claim it.
			if carried == ComposerSpan.NO_LINE:
				carried = made.first
			continue

		var first: int = carried if carried != ComposerSpan.NO_LINE else made.first
		carried = ComposerSpan.NO_LINE
		var node: ComposerNode = _node(made, first, path, locals)
		var declared: String = _local_name(made.text)
		if not declared.is_empty():
			locals[declared] = StringName(_local_type(made.text))
		# The node keeps the text it came from, so a save can reprint it rather
		# than rebuild it. The comments it picked up on the way are kept apart:
		# nothing in the model stands for a comment, so a rebuilt statement that
		# carried them along would print itself and lose them.
		node.carried = PackedStringArray(lines.slice(first - 1, made.first - 1))
		node.source_text = PackedStringArray(lines.slice(made.first - 1, made.last))
		graph.nodes.append(node)


static func _node(
	made: ComposerSubset.Statement, first: int, path: String,
	locals: Dictionary[String, StringName]
) -> ComposerNode:
	var text: String = made.text.strip_edges()
	var verdict: ComposerSubset.Verdict = made.verdict
	var node: ComposerNode = ComposerNode.new()
	node.id = StringName("n%d" % made.last)
	node.span = ComposerSpan.new(first, made.last)
	node.awaits = text.contains(AWAIT_MARK)
	node.indent = verdict.indent
	node.text = text
	# Only a statement that is a call has one. Reading a name off a branch gives
	# `if not commit_ability`, which is not a call, is not in any catalog, and is
	# one lookup away from claiming a person's condition takes arguments.
	var called: String = _call_name(text) if _may_call(verdict.kind) else ""
	var dot: int = called.rfind(".")
	node.receiver = called.left(dot) if dot > 0 else ""
	node.type_id = StringName(called.substr(dot + 1))
	node.prefix = _prefix(text, called)

	node.entry = ComposerCatalog.entry_for(node.type_id, node.receiver, path, locals)
	node.title = _title(node, verdict)
	node.ports = _ports(verdict, text)
	node.fields.assign(_fields(text, node.entry))
	# After the fields, never before: there is one argument port per field, and
	# reading them while the list is still empty gives a node no value can land on.
	_add_argument_ports(node)
	return node


## The words on the card.
##
## A call is named by what it calls, spelled the way a person would say it:
## `apply_gameplay_effect` reads as `Apply Gameplay Effect`. The structural
## statements name themselves, because `if` is already the clearest word for
## what it does.
static func _title(node: ComposerNode, verdict: ComposerSubset.Verdict) -> String:
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
	if verdict.kind == ComposerSubset.Kind.NOTHING:
		return "Nothing"
	if node.entry != null:
		return node.entry.title
	if node.type_id.is_empty():
		return node.text.strip_edges()
	# The method, not the receiver: a card headed "Owner Asc.apply Gameplay
	# Effect" tells a person where the call went rather than what it does.
	return String(node.type_id).capitalize()


## The called identifier, or empty when the line calls nothing.
## What the statement says before the call, `await` excluded.
##
## Found by looking for the call in the line rather than by parsing the
## declaration: whatever is in front of it is the prefix, whether that is a
## `var` with a written type or nothing at all. The `await` is left out because
## the node carries that separately and the writer would otherwise print it
## twice.
static func _prefix(text: String, called: String) -> String:
	if called.is_empty():
		return ""
	var at: int = text.find(called + OPEN_BRACKET)
	if at <= 0:
		return ""
	return text.left(at).trim_suffix(AWAIT_MARK)


## Which statements can carry a call: the ones whose whole shape is one.
static func _may_call(kind: ComposerSubset.Kind) -> bool:
	return (
		kind == ComposerSubset.Kind.CALL
		or kind == ComposerSubset.Kind.LOCAL
		or kind == ComposerSubset.Kind.AWAIT
	)


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
static func _ports(
	verdict: ComposerSubset.Verdict, text: String
) -> Array[ComposerNode.Port]:
	var ports: Array[ComposerNode.Port] = [
		port(EXEC_IN, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.INPUT),
		port(EXEC_OUT, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT),
	]
	if verdict.kind == ComposerSubset.Kind.LOCAL:
		var value: ComposerNode.Port = port(
			VALUE_OUT, ComposerNode.PortKind.DATA, ComposerNode.PortDirection.OUTPUT
		)
		# The type the person wrote, carried onto the port. The subset refuses an
		# inferred local for exactly this reason: without a written type the port
		# would claim to carry nothing, and every wire out of it would be checked
		# against a promise the file never made.
		value.type_name = StringName(_local_type(text))
		value.label = _local_name(text)
		ports.append(value)
	return ports


## One data input per argument, typed by the catalog.
##
## Without these a value wire had nowhere to land and was joined to the node's
## execution input instead - a data cable plugged into a run of control. Nothing
## caught it until something compared the two ends, which is the whole reason
## the type system exists.
static func _add_argument_ports(node: ComposerNode) -> void:
	for position: int in node.fields.size():
		var slot: ComposerNode.Port = port(
			StringName(ARGUMENT % position),
			ComposerNode.PortKind.DATA,
			ComposerNode.PortDirection.INPUT
		)
		slot.label = node.fields[position].label
		slot.type_name = node.fields[position].type_name
		node.ports.append(slot)


## The type in `var name: Type = ...`, or empty when there is none.
static func _local_type(line: String) -> String:
	# Stripped here, the way `_local_name` strips: one of the two taking a raw
	# line and the other a trimmed one is an asymmetry nobody sees until a
	# caller hands both the same string and only one of them answers.
	var text: String = line.strip_edges()
	if not text.begins_with("var "):
		return ""
	var colon: int = text.find(":")
	var equals: int = text.find("=")
	if colon < 0 or equals < colon:
		return ""
	return text.substr(colon + 1, equals - colon - 1).strip_edges()


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


## One field per argument, named by the catalog where it knows the call.
##
## The label is the engine's own parameter name, read from the method rather
## than invented here. A call the catalog does not offer still draws - a person
## may write anything the subset admits - but its arguments fall back to their
## position, which says "this is the second thing you passed" and claims nothing
## more.
static func _fields(text: String, entry: ComposerCatalog.Entry) -> Array[ComposerNode.Field]:
	var fields: Array[ComposerNode.Field] = []
	var open: int = text.find("(")
	if open < 0 or not text.ends_with(")"):
		return fields

	var inside: String = text.substr(open + 1, text.length() - open - 2).strip_edges()
	if inside.is_empty():
		return fields

	var position: int = 0
	# Split on the call's own commas. Every comma would cut `build(x, y)` in
	# half and hand the card two arguments the file never passed.
	for argument: String in ComposerSubset.arguments_of(inside):
		var declared: ComposerNode.Field = (
			entry.parameter(position) if entry != null else null
		)
		var field: ComposerNode.Field = ComposerNode.Field.new()
		field.label = declared.label if declared != null else "#%d" % (position + 1)
		field.type_name = declared.type_name if declared != null else &""
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
		else:
			# The first statement of a block runs because the line above opened
			# it. Without this the body of every branch floats free of its own
			# condition: nothing leads into it, so the layout treats it as
			# another place the method starts and puts it at the left margin
			# beside the first line of the ability.
			var opener: StringName = _opener(previous, depth)
			if not opener.is_empty():
				graph.connections.append(wire(opener, EXEC_OUT, node.id, EXEC_IN))
		previous[depth] = node.id

		# A deeper block starts fresh: whatever ran at that depth belonged to an
		# earlier branch and must not reach into this one.
		for open_depth: int in previous.keys():
			if open_depth > depth:
				previous.erase(open_depth)


## The statement that opened the block `depth` is inside.
##
## The nearest shallower depth still open, not `depth - 1`: indentation is
## counted in characters, so a file written with spaces steps four at a time and
## subtracting one would find nothing.
static func _opener(previous: Dictionary[int, StringName], depth: int) -> StringName:
	var nearest: int = -1
	for open_depth: int in previous.keys():
		if open_depth < depth and open_depth > nearest:
			nearest = open_depth
	return previous[nearest] if nearest >= 0 else &""


## A local's value reaches every later statement that names it.
##
## Read by name rather than by scope analysis, which the subset makes safe: a
## body with no loops and no lambdas has one flat set of names, so a later line
## mentioning `target` means that `target`.
static func _wire_data(graph: ComposerGraph, lines: PackedStringArray) -> void:
	for node: ComposerNode in graph.nodes:
		var declared: String = _local_name(node.text)
		if declared.is_empty():
			continue
		for other: ComposerNode in graph.nodes:
			if other.span.first_line <= node.span.last_line:
				continue
			_wire_into(graph, node, other, declared)


## Join `node`'s value to whichever argument of `other` depends on it.
##
## Two different things used to be one. A cable says "this statement needs what
## that one produced", and that is true of `apply(damage, pick.target_data)` -
## the statement plainly depends on `pick`. It is separately true, and only
## sometimes, that the argument *is* the local and can be re-pointed at another
## one; that is the exact spelling, and only that spelling.
##
## Tying both to the exact spelling drew almost nothing on real code, because
## real code reaches into a local far more often than it passes one whole:
## nine locals across the reference abilities and two cables between them. The
## canvas was hiding dependencies the file states plainly, which is the one
## thing a view of a file may not do.
static func _wire_into(
	graph: ComposerGraph, node: ComposerNode, other: ComposerNode, declared: String
) -> void:
	var slot: int = _argument_naming(other.text, declared)
	var exact: bool = slot >= 0
	if not exact:
		slot = _argument_using(other.text, declared)
	if slot < 0:
		return

	graph.connections.append(
		wire(node.id, VALUE_OUT, other.id, StringName(ARGUMENT % slot))
	)
	# Marked as fed only when the argument is the local and nothing else. An
	# argument that merely reaches into it is an expression somebody wrote, and
	# offering to swap the whole thing for another name would throw away the
	# `.target_data` they meant.
	if exact and slot < other.fields.size():
		other.fields[slot].source = ComposerNode.ValueSource.WIRED


static func _local_name(line: String) -> String:
	var text: String = line.strip_edges()
	if not text.begins_with("var "):
		return ""
	var rest: String = text.substr(4)
	var stop: int = rest.find(":")
	if stop < 0:
		return ""
	return rest.substr(0, stop).strip_edges()


## Which argument of `line` depends on `word` without being it, or -1.
##
## `pick.target_data` uses `pick`; `picked` does not. Whole names only, which is
## the difference between a dependency and a coincidence of spelling.
static func _argument_using(line: String, word: String) -> int:
	var open: int = line.find(OPEN_BRACKET)
	if open < 0:
		return -1
	var position: int = 0
	for argument: String in ComposerSubset.arguments_of(line.substr(open + 1)):
		if ComposerValidator.names(argument, word):
			return position
		position += 1
	return -1


## Which argument of `line` is exactly `word`, or -1 when none is.
##
## Position matters: the wire has to land on the slot that uses the value, not
## just on the statement that mentions it somewhere.
static func _argument_naming(line: String, word: String) -> int:
	var open: int = line.find("(")
	if open < 0:
		return -1
	var position: int = 0
	for argument: String in ComposerSubset.arguments_of(line.substr(open + 1)):
		if argument.strip_edges().trim_suffix(")").strip_edges() == word:
			return position
		position += 1
	return -1


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
