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

## The pins a structural statement offers. A branch is asked something and
## answers one of two ways; a switch is handed a value and takes one case, or
## none of them; an end is handed what the method returns.
const CONDITION_IN: StringName = &"condition_in"
const MATCH_VALUE_IN: StringName = &"match_value_in"
const RETURN_VALUE_IN: StringName = &"return_value_in"
const TRUE_OUT: StringName = &"true_out"
const FALSE_OUT: StringName = &"false_out"
const UNMATCHED_OUT: StringName = &"unmatched_out"
const CASE_OUT: String = "case_%d"

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
	var refusal: ComposerGraph.Diagnostic = ComposerStatements.first_refusal(lines, span)
	if refusal != null:
		graph.diagnostics = [refusal] as Array[ComposerGraph.Diagnostic]
		return graph

	_build_nodes(graph, lines, span, path, ComposerSubset.entry_return_type(lines))
	ComposerFlow.build(graph, lines)
	ComposerDataWires.apply(graph)

	# The findings come back with the graph rather than being asked for later.
	# A caller that forgot to validate would draw a file with every card clean
	# and an empty Output panel, which reads as "nothing is wrong" rather than
	# as "nobody looked".
	ComposerValidator.apply(graph)
	return graph


#region Nodes
static func _build_nodes(
	graph: ComposerGraph,
	lines: PackedStringArray,
	span: ComposerSpan,
	path: String,
	returns: StringName
) -> void:
	var carried: int = ComposerSpan.NO_LINE
	# What each local was declared to be, gathered on the way down. A receiver
	# is very often a local - `var data: GameplayAbilityTargetData = ...` and
	# then `data.get_target_nodes()` - and without this every call on one is a
	# call the catalog cannot place.
	var locals: Dictionary[String, StringName] = {}
	for made: ComposerStatements.Statement in ComposerStatements.of(lines, span):
		if not made.verdict.is_drawn():
			# A comment or a blank belongs to whatever comes next, so remember
			# where the run started and let the statement claim it.
			if carried == ComposerSpan.NO_LINE:
				carried = made.first
			continue

		var first: int = carried if carried != ComposerSpan.NO_LINE else made.first
		carried = ComposerSpan.NO_LINE
		var node: ComposerNode = _node(made, first, path, locals, returns)
		var declared: String = local_name(made.text)
		if not declared.is_empty():
			locals[declared] = StringName(_local_type(made.text))
		# The node keeps the text it came from, so a save can reprint it rather
		# than rebuild it. The comments it picked up on the way are kept apart:
		# nothing in the model stands for a comment, so a rebuilt statement that
		# carried them along would print itself and lose them.
		node.carried = PackedStringArray(lines.slice(first - 1, made.first - 1))
		node.source_text = PackedStringArray(lines.slice(made.first - 1, made.last))

		ComposerLayoutMetadata.read_onto(node)
		graph.nodes.append(node)


static func _node(
	made: ComposerStatements.Statement,
	first: int,
	path: String,
	locals: Dictionary[String, StringName],
	returns: StringName
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
	node.terminal = (
		verdict.kind == ComposerSubset.Kind.RETURN
		or verdict.kind == ComposerSubset.Kind.FLOW_STOP
	)
	node.projection_kind = _projection_of(verdict.kind, text)
	node.visible_in_graph = (
		node.projection_kind != ComposerNode.ProjectionKind.SUPPORT
	)
	# Fields before ports, never after: there is one data input per field, and
	# reading them while the list is still empty gives a node no value can land on.
	node.fields.assign(ComposerNodeFields.of(node, verdict, returns))
	node.ports = _ports(verdict, text)
	_add_data_ports(node, verdict)
	return node


## The words on the card.
##
## A call is named by what it calls, spelled the way a person would say it:
## `apply_gameplay_effect` reads as `Apply Gameplay Effect`. The structural
## statements name themselves, because `if` is already the clearest word for
## what it does.
static func _title(node: ComposerNode, verdict: ComposerSubset.Verdict) -> String:
	if verdict.kind == ComposerSubset.Kind.BRANCH or _is_elif(verdict.kind, node.text):
		return "Branch"
	if verdict.kind == ComposerSubset.Kind.MATCH:
		return "Switch"
	if verdict.kind == ComposerSubset.Kind.RETURN:
		return "End"
	if verdict.kind == ComposerSubset.Kind.NOTHING:
		return "Nothing"
	if node.entry != null:
		return node.entry.title
	# A support header - `else:`, a case - has no card, so its title is its own
	# line: what the signature of a graph names it by, and all it needs.
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


## What kind of card a verdict draws, or none at all.
##
## `elif` and `else:` classify alike - both continue a branch - and only the
## text tells them apart. An `elif` tests something and is drawn as the Branch it
## is; an `else:` tests nothing and is the one header nobody is shown.
static func _projection_of(
	kind: ComposerSubset.Kind, text: String
) -> ComposerNode.ProjectionKind:
	if kind == ComposerSubset.Kind.BRANCH or _is_elif(kind, text):
		return ComposerNode.ProjectionKind.BRANCH
	if kind == ComposerSubset.Kind.MATCH:
		return ComposerNode.ProjectionKind.SWITCH
	if (
		kind == ComposerSubset.Kind.BRANCH_ELSE
		or kind == ComposerSubset.Kind.MATCH_CASE
		or kind == ComposerSubset.Kind.DETACHED
		or kind == ComposerSubset.Kind.FLOW_STOP
		or ComposerSubset.is_a_boundary(kind)
	):
		return ComposerNode.ProjectionKind.SUPPORT
	return ComposerNode.ProjectionKind.STATEMENT


## Whether this statement leaves by more than one path.
static func _fans_out(verdict: ComposerSubset.Verdict, text: String) -> bool:
	var drawn: ComposerNode.ProjectionKind = _projection_of(verdict.kind, text)
	return (
		drawn == ComposerNode.ProjectionKind.BRANCH
		or drawn == ComposerNode.ProjectionKind.SWITCH
	)


static func _is_elif(kind: ComposerSubset.Kind, text: String) -> bool:
	return (
		kind == ComposerSubset.Kind.BRANCH_ELSE
		and text.strip_edges().begins_with(ComposerSubset.ELIF_OPENER)
	)


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
	# A support header - an `else:`, a case, the wrapper round an unplugged island
	# - is a line nobody is shown a card for, so it has nothing to plug a wire
	# into. A pin on it would be a pin on a card that does not exist.
	if _projection_of(verdict.kind, text) == ComposerNode.ProjectionKind.SUPPORT:
		return []
	var ports: Array[ComposerNode.Port] = [
		port(EXEC_IN, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.INPUT),
	]
	# A `return` ends the method, so it is not offered a way out. The port used
	# to be here for every statement alike, and a person could drag a wire from
	# `return` to the next card - a promise GDScript will not keep.
	#
	# A branch and a switch get none either, and for the opposite reason: they
	# have more than one way out. `ComposerFlowBuilder` gives them the pins the
	# block actually has - True and False, one per case - because it is what
	# reads the block. A generic output beside those would be a third path,
	# drawn on the card and taken by nothing.
	if verdict.kind != ComposerSubset.Kind.RETURN and not _fans_out(verdict, text):
		ports.append(
			port(EXEC_OUT, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT)
		)
	if verdict.kind == ComposerSubset.Kind.LOCAL:
		var value: ComposerNode.Port = port(
			VALUE_OUT, ComposerNode.PortKind.DATA, ComposerNode.PortDirection.OUTPUT
		)
		# The type the person wrote, carried onto the port. The subset refuses an
		# inferred local for exactly this reason: without a written type the port
		# would claim to carry nothing, and every wire out of it would be checked
		# against a promise the file never made.
		value.type_name = StringName(_local_type(text))
		value.label = local_name(text)
		# The one pin in this projection that carries more than one wire: a local
		# can be passed to every argument that wants it, while an argument holds
		# one value and a statement runs after exactly one other.
		value.multiplicity = ComposerNode.PortMultiplicity.MULTIPLE
		ports.append(value)
	return ports


## One data input per field, typed by the field and naming it back.
##
## Without these a value wire had nowhere to land and was joined to the node's
## execution input instead - a data cable plugged into a run of control. Nothing
## caught it until something compared the two ends, which is the whole reason
## the type system exists.
##
## A call's inputs are numbered by argument. A structural statement has one
## field and one pin for it, named for what it is - so a controller asks the
## pin which field it stands for rather than parsing a number off its name.
static func _add_data_ports(node: ComposerNode, verdict: ComposerSubset.Verdict) -> void:
	for position: int in node.fields.size():
		var slot: ComposerNode.Port = port(
			_data_port_id(node, verdict, position),
			ComposerNode.PortKind.DATA,
			ComposerNode.PortDirection.INPUT
		)
		slot.label = node.fields[position].label
		slot.type_name = node.fields[position].type_name
		slot.field_index = position
		node.ports.append(slot)


static func _data_port_id(
	node: ComposerNode, verdict: ComposerSubset.Verdict, position: int
) -> StringName:
	if node.projection_kind == ComposerNode.ProjectionKind.BRANCH:
		return CONDITION_IN
	if node.projection_kind == ComposerNode.ProjectionKind.SWITCH:
		return MATCH_VALUE_IN
	if verdict.kind == ComposerSubset.Kind.RETURN:
		return RETURN_VALUE_IN
	return StringName(ARGUMENT % position)


## The local a statement declares, or nothing.
##
## Public because the data wiring asks it too, and two parsers for one
## question is two chances to disagree about whether a cable belongs.
static func local_name(line: String) -> String:
	var text: String = line.strip_edges()
	if not text.begins_with("var "):
		return ""
	var rest: String = text.substr(4)
	var stop: int = rest.find(":")
	if stop < 0:
		return ""
	return rest.substr(0, stop).strip_edges()


## The type in `var name: Type = ...`, or empty when there is none.
static func _local_type(line: String) -> String:
	# Stripped here, the way `local_name` strips: one of the two taking a raw
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
#endregion


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
