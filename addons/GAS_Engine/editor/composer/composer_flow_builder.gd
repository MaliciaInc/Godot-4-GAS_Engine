## Where execution goes, worked out block by block instead of line by line.
##
## The builder this replaces walked the statements in order keeping a table of
## "the last statement seen at each depth". That reads a straight body correctly
## and a branch wrongly, in two ways that matter:
##
## - the tail of a true body was never joined back to the statement after the
##   `if`, so the canvas drew a run of statements as a dead end while the file
##   plainly carried on through it;
## - a branch had one generic way out, so nothing on the canvas could say which
##   of the two paths a statement was on.
##
## Both are the projection saying something the GDScript does not. What replaces
## the table is the shape the language already has: a sequence of statements
## returns the outputs execution can still leave by, and a block asks its own
## body for those before deciding what the next statement is joined to.
##
## Nothing here edits source, and nothing here decides whether a file is
## drawable. It is handed a graph whose nodes are already read and adds the
## execution projection to it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowBuilder extends RefCounted

## What the two sides of a branch and the fallthrough of a switch are called.
##
## The words a person reads on the card. A case is labelled by its own pattern
## instead, because the file already says what it is.
const TRUE_LABEL: String = "True"
const FALSE_LABEL: String = "False"
const NO_MATCH_LABEL: String = "No Match"

## The one pattern that catches everything, so a `match` carrying it needs no
## separate way out.
const WILDCARD: String = "_"


## One place execution can leave from: a node and one of its output pins.
##
## Carried instead of a bare node id because a branch has two ways out and the
## whole point is which one this is.
class Endpoint extends RefCounted:
	var node_id: StringName = &""
	var port_id: StringName = &""


## What a run of statements came to: where the caller carries on reading, and
## the outputs execution can still leave by.
##
## `exits` is empty when every path through the run ended - a `return` in a true
## body, a marked flow stop - and that is the difference between "joins the next
## statement" and "does not", which is the fact the old table could not hold.
class SequenceResult extends RefCounted:
	var next_index: int = 0
	var exits: Array[Endpoint] = []


## Add the execution projection to a graph whose nodes are already read.
##
## The lines are taken and not read: every node already carries the indentation
## it was classified at, and asking the text again would be a second answer to a
## question that is already settled - which is exactly how the depth table and
## the reader came to disagree about a wrapped statement.
static func build(graph: ComposerGraph, _lines: PackedStringArray) -> void:
	var ordered: Array[ComposerNode] = _ordered(graph)
	if ordered.is_empty():
		return
	var start: Array[Endpoint] = _one(
		_at(ComposerFlow.ENTRY_ID, ComposerReader.EXEC_OUT)
	)
	_sequence(graph, ordered, 0, ordered[0].indent, start)


## The statements a line of the file backs, in the order the file has them.
##
## Support headers are here: an `else:` delimits a block and the walk has to see
## it. Entry is not, because it backs no line and is where the walk starts.
static func _ordered(graph: ComposerGraph) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in graph.nodes:
		if node.source_backed and node.span.is_valid():
			found.append(node)
	found.sort_custom(
		func _by_line(first: ComposerNode, second: ComposerNode) -> bool:
			return first.span.first_line < second.span.first_line
	)
	return found


#region Walking a block
## Join a run of statements at one depth, and say what execution leaves by.
##
## Only statements at exactly `indent` belong to this run. Anything deeper is a
## block's body and is walked by whoever opened it; anything shallower ended
## this run. Depth is compared, never guessed at by adding one: GDScript indents
## with tabs or spaces and a body is simply deeper than its header.
static func _sequence(
	graph: ComposerGraph,
	ordered: Array[ComposerNode],
	from_index: int,
	indent: int,
	incoming: Array[Endpoint]
) -> SequenceResult:
	var index: int = from_index
	var open: Array[Endpoint] = incoming

	while index < ordered.size():
		var node: ComposerNode = ordered[index]
		if node.indent != indent:
			break

		var kind: ComposerSubset.Kind = ComposerSubset.classify(node.text).kind
		if kind == ComposerSubset.Kind.DETACHED:
			# An island is drawn, and drawn apart. Its statements are joined to
			# each other so a person can still read them, and nothing joins them
			# to the live path - which is what "unplugged" means here.
			index = _island(graph, ordered, index)
			continue
		if kind == ComposerSubset.Kind.FLOW_STOP:
			# A stop the Composer wrote to end a path it cut. It draws no card,
			# and nothing after it in this block runs.
			open = _none()
			index += 1
			break

		if node.projection_kind == ComposerNode.ProjectionKind.BRANCH:
			var branched: SequenceResult = _branch(graph, ordered, index, open)
			open = branched.exits
			index = branched.next_index
			continue
		if node.projection_kind == ComposerNode.ProjectionKind.SWITCH:
			var switched: SequenceResult = _switch(graph, ordered, index, open)
			open = switched.exits
			index = switched.next_index
			continue
		if node.projection_kind == ComposerNode.ProjectionKind.SUPPORT:
			# A header whose block nobody opened - an `else:` with no `if` above
			# it, which the file can only hold while somebody is mid-edit. Its
			# body is stepped over rather than joined to anything, because a
			# connection to a card nobody is shown is a connection nobody can see.
			index = _after_subtree(ordered, index)
			continue

		_connect_all(graph, open, node)
		open = (
			_none() if node.terminal
			else _one(_at(node.id, ComposerReader.EXEC_OUT))
		)
		index += 1

	return _result(index, open)


## Walk a detached island's body on its own, joined to nothing outside it.
static func _island(
	graph: ComposerGraph, ordered: Array[ComposerNode], index: int
) -> int:
	var body: int = index + 1
	var after: int = _after_subtree(ordered, index)
	if body < after:
		_sequence(graph, ordered, body, ordered[body].indent, _none())
	return after


## The index after this statement and everything nested inside it.
static func _after_subtree(ordered: Array[ComposerNode], index: int) -> int:
	var depth: int = ordered[index].indent
	var at: int = index + 1
	while at < ordered.size() and ordered[at].indent > depth:
		at += 1
	return at
#endregion


#region Branches
## A branch: its two ways out, its body, and whatever answers its false side.
##
## The exits are what makes the merge right. A true body that runs to its end
## leaves by its own last statement, a true body that returns leaves by nothing,
## and the false side leaves by the branch itself unless an `else` or an `elif`
## answers it. Whatever comes back is joined to the next statement by the caller,
## which is how one continuation ends up reached from both sides.
static func _branch(
	graph: ComposerGraph,
	ordered: Array[ComposerNode],
	index: int,
	incoming: Array[Endpoint]
) -> SequenceResult:
	var branch: ComposerNode = ordered[index]
	_connect_all(graph, incoming, branch)
	_ensure_output(branch, ComposerReader.TRUE_OUT, TRUE_LABEL)
	_ensure_output(branch, ComposerReader.FALSE_OUT, FALSE_LABEL)

	var after: int = _after_subtree(ordered, index)
	var exits: Array[Endpoint] = []
	var body: int = index + 1
	if body < after:
		var taken: SequenceResult = _sequence(
			graph, ordered, body, ordered[body].indent,
			_one(_at(branch.id, ComposerReader.TRUE_OUT))
		)
		exits.append_array(taken.exits)

	var otherwise: Array[Endpoint] = _one(_at(branch.id, ComposerReader.FALSE_OUT))
	if after < ordered.size() and ordered[after].indent == branch.indent:
		var sibling: ComposerNode = ordered[after]
		if is_elif(sibling):
			# `elif` is the false side asking a second question. It is a Branch a
			# person can see, and its own exits join this one's.
			var chained: SequenceResult = _branch(graph, ordered, after, otherwise)
			exits.append_array(chained.exits)
			return _result(chained.next_index, exits)
		if is_else(sibling):
			exits.append_array(_block(graph, ordered, after, otherwise))
			return _result(_after_subtree(ordered, after), exits)

	# Nothing answers the false side, so it falls through to whatever the caller
	# joins next.
	exits.append_array(otherwise)
	return _result(after, exits)


## Walk the body a header opens, or hand the header's own output back when the
## body is empty.
static func _block(
	graph: ComposerGraph,
	ordered: Array[ComposerNode],
	header_index: int,
	incoming: Array[Endpoint]
) -> Array[Endpoint]:
	var body: int = header_index + 1
	var after: int = _after_subtree(ordered, header_index)
	if body >= after:
		return incoming
	return _sequence(graph, ordered, body, ordered[body].indent, incoming).exits


static func is_elif(node: ComposerNode) -> bool:
	return (
		node.projection_kind == ComposerNode.ProjectionKind.BRANCH
		and node.text.strip_edges().begins_with(ComposerSubset.ELIF_OPENER)
	)


## An `else:`, whether a person wrote it or Composer did to hold a cut path.
## Public: moving a path has to find the same `else` the projection drew, and
## two opinions about what an else is would be two different graphs.
static func is_else(node: ComposerNode) -> bool:
	return (
		node.projection_kind == ComposerNode.ProjectionKind.SUPPORT
		and node.text.strip_edges().begins_with(ComposerSubset.ELSE_OPENER)
	)
#endregion


#region Switches
## A switch: one output per case the file writes, and one for no case at all.
##
## The unmatched output exists because GDScript carries on after a `match` that
## nothing caught. A wildcard is that path already written down, so a `match`
## carrying one gets no second way out - which would be two pins standing for
## one thing.
static func _switch(
	graph: ComposerGraph,
	ordered: Array[ComposerNode],
	index: int,
	incoming: Array[Endpoint]
) -> SequenceResult:
	var switch: ComposerNode = ordered[index]
	_connect_all(graph, incoming, switch)

	var after: int = _after_subtree(ordered, index)
	var exits: Array[Endpoint] = []
	var case_indent: int = -1
	var number: int = 0
	var wildcard: bool = false

	var at: int = index + 1
	while at < after:
		var header: ComposerNode = ordered[at]
		if case_indent < 0:
			case_indent = header.indent
		# Only this match's own arms. A nested `match` inside a case body is the
		# body's, and its cases belong to it.
		if header.indent != case_indent or not is_case(header):
			at = _after_subtree(ordered, at)
			continue

		var port_id: StringName = StringName(ComposerReader.CASE_OUT % number)
		_ensure_output(switch, port_id, case_label(header))
		wildcard = wildcard or case_label(header) == WILDCARD
		exits.append_array(
			_block(graph, ordered, at, _one(_at(switch.id, port_id)))
		)
		number += 1
		at = _after_subtree(ordered, at)

	if not wildcard:
		_ensure_output(switch, ComposerReader.UNMATCHED_OUT, NO_MATCH_LABEL)
		exits.append(_at(switch.id, ComposerReader.UNMATCHED_OUT))
	return _result(after, exits)


static func is_case(node: ComposerNode) -> bool:
	return (
		node.projection_kind == ComposerNode.ProjectionKind.SUPPORT
		and ComposerSubset.classify(node.text).kind == ComposerSubset.Kind.MATCH_CASE
	)


## The pattern as the file writes it, without the colon that ends it.
##
## The code only: a catch-all this tool wrote carries a marker after the colon,
## and reading that as part of the pattern is a wildcard nothing recognises.
##
## Not capitalised and not tidied. `State.CASTING` is what the person typed and
## what they will look for on the card.
static func case_label(node: ComposerNode) -> String:
	return ComposerLine.code_of(node.text).strip_edges().trim_suffix(":").strip_edges()
#endregion


#region Joining
## Join every open exit to one statement's execution input.
##
## Silent about ends it cannot use: a support header has no pins at all, and an
## endpoint naming a pin that is no longer there belongs to a graph that has
## already moved on. Neither is a connection worth inventing.
static func _connect_all(
	graph: ComposerGraph, endpoints: Array[Endpoint], to: ComposerNode
) -> void:
	if to.find_port(ComposerReader.EXEC_IN) == null:
		return
	for endpoint: Endpoint in endpoints:
		var from: ComposerNode = graph.find_node(endpoint.node_id)
		if from == null or from.find_port(endpoint.port_id) == null:
			continue
		var edge: ComposerGraph.Connection = ComposerReader.wire(
			endpoint.node_id, endpoint.port_id, to.id, ComposerReader.EXEC_IN
		)
		if graph.has_connection(edge):
			continue
		graph.connections.append(edge)


## Give a node one of the execution outputs only this builder creates.
##
## The reader creates every input and every data pin; the outputs a branch and a
## switch fan out by are made here, where the shape of the block is known. Two
## modules creating the same pin is two answers about how many a card has.
static func _ensure_output(node: ComposerNode, port_id: StringName, label: String) -> void:
	if node.find_port(port_id) != null:
		return
	var made: ComposerNode.Port = ComposerReader.port(
		port_id, ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT
	)
	made.label = label
	node.ports.append(made)


## One endpoint, as the list a sequence takes.
##
## Built rather than written as `[endpoint]`: an array literal is untyped, and
## assigning one to `Array[Endpoint]` is refused at runtime rather than at parse
## time - which is a whole suite failing on a line that reads correctly.
## No endpoints at all: every path through a run ended.
static func _none() -> Array[Endpoint]:
	var found: Array[Endpoint] = []
	return found


static func _one(endpoint: Endpoint) -> Array[Endpoint]:
	var found: Array[Endpoint] = []
	found.append(endpoint)
	return found


static func _at(node_id: StringName, port_id: StringName) -> Endpoint:
	var made: Endpoint = Endpoint.new()
	made.node_id = node_id
	made.port_id = port_id
	return made


static func _result(next_index: int, exits: Array[Endpoint]) -> SequenceResult:
	var made: SequenceResult = SequenceResult.new()
	made.next_index = next_index
	made.exits = exits
	return made
#endregion
