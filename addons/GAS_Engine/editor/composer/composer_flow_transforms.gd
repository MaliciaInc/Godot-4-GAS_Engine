## The line surgery behind moving a run of control.
##
## There is no stored list of execution wires anywhere. A statement runs after
## another because it is written after it; a statement is inside a branch's true
## path because it is written indented under the `if`. So moving a wire is moving
## text, and this is the module that does it - where a pin's successor has to be
## written, which lines a statement owns, and what has to be put back so the file
## still parses once those lines are somewhere else.
##
## Nothing here judges. `ComposerFlowEdits` decides whether a move is allowed and
## proves afterwards that the file says what was asked for; this only produces
## the candidate text. That split is what lets a refusal cost nothing: the
## surgery happens on a string, and a string nobody commits is a file nobody
## changed.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowTransforms extends RefCounted

const NEWLINE: String = "\n"
const TAB: String = "\t"


## What a match arm ends with, and the arm that takes whatever is left.
const WILDCARD: String = ComposerFlowBuilder.WILDCARD
const CASE_END: String = ":"


#region Moving lines
## Take `block` out of `source` and put it back at `anchor`, re-indented.
##
## The lines keep their shape relative to one another - a branch moved with its
## body stays a branch with a body - and the whole run shifts by the difference
## between the depth it was written at and the depth it is going to.
static func moved(source: String, block: ComposerSpan, anchor: ComposerFlowPlaces.Anchor) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	if block.first_line <= anchor.line and anchor.line <= block.last_line + 1:
		# Already there: taking it out and putting it back in the same place is
		# not a change, and computing the shifted index for it is one off-by-one
		# nobody would ever see in a test.
		return source

	var carried: PackedStringArray = PackedStringArray()
	var depth: int = ComposerSubset.indent_of(lines[block.first_line - 1])
	for number: int in range(block.first_line - 1, block.last_line):
		carried.append(_redented(lines[number], anchor.indent - depth))

	var kept: PackedStringArray = PackedStringArray()
	var at: int = anchor.line
	if anchor.line > block.last_line:
		at -= block.last_line - block.first_line + 1
	for number: int in lines.size():
		if number >= block.first_line - 1 and number <= block.last_line - 1:
			continue
		kept.append(lines[number])
	var written: PackedStringArray = PackedStringArray()
	for number: int in kept.size():
		if number == at - 1:
			written.append_array(carried)
		written.append(kept[number])
	if at - 1 >= kept.size():
		written.append_array(carried)
	return NEWLINE.join(written)


## One line, `by` tabs deeper or shallower. A blank line stays blank.
static func _redented(line: String, by: int) -> String:
	if line.strip_edges().is_empty():
		return line
	if by >= 0:
		return TAB.repeat(by) + line
	return line.substr(mini(-by, ComposerSubset.indent_of(line)))
#endregion


#region Putting back what a move took away
## Give every header left with nothing under it a path that ends there.
##
## A block header with an empty body is not a file: GDScript will not parse it.
## The stop is marked, so reconnecting the path later can take it out again and
## a `return` somebody wrote themselves is never mistaken for machinery.
static func bodies_kept(source: String) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var written: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		written.append(lines[number])
		if not _opens_a_block(lines[number]):
			continue
		if _has_a_body(lines, number):
			continue
		written.append(
			TAB.repeat(ComposerSubset.indent_of(lines[number]) + 1) + _stop(lines)
		)
	return NEWLINE.join(written)


## Cut the false path of `branch` with an `else` this tool owns.
static func with_else_stop(
	source: String, graph: ComposerGraph, branch: ComposerNode
) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var indent: String = TAB.repeat(branch.indent)
	var written: String = "%s%s %s%s%s%s" % [
		indent,
		ComposerSubset.ELSE_OPENER,
		ComposerSubset.FLOW_ELSE_MARK,
		NEWLINE,
		indent + TAB,
		_stop(lines),
	]
	return ComposerEdits.insert_after(source, ComposerFlowPlaces.block_of(graph, branch).last_line, written)


## Cut the unmatched path of `switch` with a catch-all this tool owns.
static func with_default_stop(
	source: String, graph: ComposerGraph, switch: ComposerNode
) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var indent: String = TAB.repeat(switch.indent + 1)
	var written: String = "%s%s %s%s%s%s" % [
		indent,
		ComposerFlowBuilder.WILDCARD + ":",
		ComposerSubset.FLOW_DEFAULT_MARK,
		NEWLINE,
		indent + TAB,
		_stop(lines),
	]
	return ComposerEdits.insert_after(source, ComposerFlowPlaces.block_of(graph, switch).last_line, written)


## Write a path that was not there: an `else` for a branch that had none.
##
## No mark on it. A generated boundary is machinery that comes out again when
## the path is reconnected; this one is a path a person asked for, and taking
## it away later because it looked like machinery would delete their work.
static func with_else(
	source: String, graph: ComposerGraph, branch: ComposerNode, written: String
) -> String:
	var indent: String = TAB.repeat(branch.indent)
	var block: String = "%s%s%s%s%s" % [
		indent,
		ComposerSubset.ELSE_OPENER,
		NEWLINE,
		indent + TAB,
		written.strip_edges(),
	]
	return ComposerEdits.insert_after(source, ComposerFlowPlaces.block_of(graph, branch).last_line, block)


## Write a catch-all a match never had, with something in it.
static func with_case(
	source: String, graph: ComposerGraph, switch: ComposerNode, written: String
) -> String:
	var indent: String = TAB.repeat(switch.indent + 1)
	var block: String = "%s%s%s%s%s%s" % [
		indent,
		WILDCARD,
		CASE_END,
		NEWLINE,
		indent + TAB,
		written.strip_edges(),
	]
	return ComposerEdits.insert_after(source, ComposerFlowPlaces.block_of(graph, switch).last_line, block)


## Turn `elif` into a nested `else: if`, and open the else with `written`.
##
## `elif b:` *is* the false path of the branch above it, so there is nowhere to
## write a statement that runs on that path before `b` is asked. Written out
## long - `else:` holding the statement and then the same branch - the file
## says exactly what it said before plus the one new thing, and stays inside
## the subset. Only the chain being written into is rewritten; a chain nobody
## touched keeps the shape its author chose.
static func with_nested_else(
	source: String, graph: ComposerGraph, branch: ComposerNode, written: String
) -> String:
	var chained: ComposerNode = ComposerFlowPlaces._elif_of(graph, branch)
	if chained == null:
		return source
	var rest: ComposerSpan = ComposerSpan.new(
		chained.span.first_line, _chain_end(graph, chained)
	)
	var indent: String = TAB.repeat(branch.indent)

	var lines: PackedStringArray = source.split(NEWLINE)
	var made: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		var at: int = number + 1
		if at == rest.first_line:
			made.append(indent + ComposerSubset.ELSE_OPENER)
			made.append(indent + TAB + written.strip_edges())
		if at < rest.first_line or at > rest.last_line:
			made.append(lines[number])
			continue
		if lines[number].strip_edges().is_empty():
			made.append(lines[number])
			continue
		made.append(TAB + _unchained(lines[number], at == rest.first_line))
	return NEWLINE.join(made)


## The `elif` that opens a chain, written as the `if` it becomes.
static func _unchained(line: String, opening: bool) -> String:
	if not opening:
		return line
	var at: int = line.find(ComposerSubset.ELIF_OPENER)
	return line.substr(0, at) + ComposerSubset.IF_OPENER + line.substr(
		at + ComposerSubset.ELIF_OPENER.length()
	)


## The last line of everything hanging off one `elif`: its own block, and
## whatever continues the chain after it.
static func _chain_end(graph: ComposerGraph, chained: ComposerNode) -> int:
	var last: int = ComposerFlowPlaces.block_of(graph, chained).last_line
	var following: ComposerNode = ComposerFlowPlaces._next_at_indent(graph, chained)
	while following != null and (
		ComposerFlowBuilder.is_else(following) or ComposerFlowBuilder.is_elif(following)
	):
		last = ComposerFlowPlaces.block_of(graph, following).last_line
		following = ComposerFlowPlaces._next_at_indent(graph, following)
	return last


## The line a cut path ends on, typed by what the method hands back.
static func _stop(lines: PackedStringArray) -> String:
	return "return %s %s" % [
		ComposerTypes.default_expression(ComposerSubset.entry_return_type(lines)),
		ComposerSubset.FLOW_STOP_MARK,
	]


## Whether this line opens a block that has to have something under it.
static func _opens_a_block(line: String) -> bool:
	var code: String = ComposerLine.code_of(line).strip_edges()
	return not code.is_empty() and code.ends_with(":")


## Whether anything is written under the line at `number`, deeper than it.
static func _has_a_body(lines: PackedStringArray, number: int) -> bool:
	var depth: int = ComposerSubset.indent_of(lines[number])
	for below: int in range(number + 1, lines.size()):
		if lines[below].strip_edges().is_empty():
			continue
		return ComposerSubset.indent_of(lines[below]) > depth
	return false
#endregion


#region Writing a move down
## The text a move would produce, or nothing when it cannot be written.
##
## One relocation, not one per link. Every link asked for by a move shares
## either the statement it arrives at or the pin it leaves, so writing that one
## statement in the one right place is what makes all of them true at once -
## and asking for anything else is asking for a second, unrelated move.
static func written(
	source: String,
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> String:
	var wanted: ComposerGraph.Connection = new_edges[0]
	var producer: ComposerNode = graph.find_node(wanted.from_node)
	var moving: ComposerNode = graph.find_node(wanted.to_node)
	if producer == null or moving == null:
		return ""
	if ComposerFlowPlaces.chains_on(graph, moving):
		return ""

	var anchor: ComposerFlowPlaces.Anchor = ComposerFlowPlaces.anchor_for(
		graph, producer, wanted.from_port
	)
	if not anchor.is_ok():
		return ""

	var block: ComposerSpan = ComposerFlowPlaces.block_of(graph, moving)
	if block.contains(anchor.line) or block.contains(producer.span.first_line):
		# Writing a statement inside itself, or writing its own predecessor into
		# it. Either is a file that means nothing; both are refused here rather
		# than produced and then discovered by the reread.
		return ""

	var changed: String = moved(source, block, anchor)
	changed = _paths_cut(changed, graph, old_edges, new_edges)
	return bodies_kept(changed)


## Close the fallthroughs a move left open.
##
## A branch with no `else` reaches the statement after it, and a match with no
## catch-all reaches it too. Those are links like any other, so a move that takes
## one away has to write the boundary that stops it - otherwise the path silently
## finds whatever the move left sitting there next.
static func _paths_cut(
	source: String,
	graph: ComposerGraph,
	old_edges: Array[ComposerGraph.Connection],
	new_edges: Array[ComposerGraph.Connection]
) -> String:
	var changed: String = source
	for edge: ComposerGraph.Connection in old_edges:
		if _is_kept(edge, new_edges):
			continue
		var from: ComposerNode = graph.find_node(edge.from_node)
		if from == null:
			continue
		if (
			edge.from_port == ComposerReader.FALSE_OUT
			and ComposerFlowPlaces.else_of(graph, from) == null
		):
			changed = with_else_stop(changed, graph, from)
		elif edge.from_port == ComposerReader.UNMATCHED_OUT:
			changed = with_default_stop(changed, graph, from)
	return changed


static func _is_kept(
	edge: ComposerGraph.Connection, new_edges: Array[ComposerGraph.Connection]
) -> bool:
	for wanted: ComposerGraph.Connection in new_edges:
		if wanted.is_same_as(edge):
			return true
	return false
#endregion
