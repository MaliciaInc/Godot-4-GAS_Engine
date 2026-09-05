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

const NO_SUCH_PIN: String = "that pin is not one this tool can write a path for"
const CHAIN_LEFT_BEHIND: String = (
	"moving that branch would leave the rest of its chain behind"
)
const NO_ELSE_TO_FILL: String = "that branch has no else for a path to be written into"
const NO_WILDCARD_TO_FILL: String = "that match has no catch-all for a path to be written into"


## Where a successor has to be written for one pin to reach it.
##
## A line to write before, and the indentation it has to be written at. Both are
## needed: the same statement means different things at different depths, which
## is the whole reason a branch has two paths.
class Anchor extends RefCounted:
	var line: int = ComposerSpan.NO_LINE
	var indent: int = 1
	var refusal: String = ""

	func is_ok() -> bool:
		return refusal.is_empty() and line != ComposerSpan.NO_LINE

	static func at(line: int, indent: int) -> Anchor:
		var made: Anchor = Anchor.new()
		made.line = line
		made.indent = indent
		return made

	static func refused(message: String) -> Anchor:
		var made: Anchor = Anchor.new()
		made.refusal = message
		return made


#region Where a path goes
## The line a successor of `port_id` has to be written before.
static func anchor_for(
	graph: ComposerGraph, node: ComposerNode, port_id: StringName
) -> Anchor:
	if port_id == ComposerReader.EXEC_IN:
		# Taking a statement's place: written where it starts, so whatever ran
		# before it now runs into this instead.
		return Anchor.at(node.span.first_line, node.indent)
	if port_id == ComposerReader.EXEC_OUT:
		if node.terminal:
			return Anchor.refused(NO_SUCH_PIN)
		return Anchor.at(block_of(graph, node).last_line + 1, node.indent)
	if port_id == ComposerReader.TRUE_OUT:
		return _inside(graph, node, node)
	if port_id == ComposerReader.FALSE_OUT:
		return _false_path(graph, node)
	if port_id == ComposerReader.UNMATCHED_OUT:
		var wildcard: ComposerNode = _wildcard_of(graph, node)
		if wildcard == null:
			return Anchor.refused(NO_WILDCARD_TO_FILL)
		return _inside(graph, node, wildcard)
	var arm: ComposerNode = _case_of(graph, node, port_id)
	if arm == null:
		return Anchor.refused(NO_SUCH_PIN)
	return _inside(graph, node, arm)


## The first line of `header`'s body, one indent deeper than `header`.
##
## `owner` is the statement whose block the header belongs to, so a case is
## looked for inside its own match rather than anywhere below it in the file.
static func _inside(
	graph: ComposerGraph, owner: ComposerNode, header: ComposerNode
) -> Anchor:
	var block: ComposerSpan = block_of(graph, owner)
	for other: ComposerNode in _ordered(graph):
		if other.span.first_line <= header.span.last_line:
			continue
		if other.span.first_line > block.last_line:
			break
		if other.indent > header.indent:
			return Anchor.at(other.span.first_line, other.indent)
		break
	# A header with nothing under it does not parse, so this is a header the
	# reader would already have refused. Written straight after it anyway, at the
	# depth its body would have had.
	return Anchor.at(header.span.last_line + 1, header.indent + 1)


## Where the false path of `branch` is written: into its `else`, or after it.
static func _false_path(graph: ComposerGraph, branch: ComposerNode) -> Anchor:
	var otherwise: ComposerNode = else_of(graph, branch)
	if otherwise != null:
		return _inside(graph, branch, otherwise)
	if _elif_of(graph, branch) != null:
		# An `elif` is the false path, and writing into it would mean rewriting
		# the chain as nested blocks. Section 16.9 allows that only for an
		# operation that needs it; nothing asks for it yet, so this says no
		# rather than guessing.
		return Anchor.refused(NO_ELSE_TO_FILL)
	return Anchor.at(block_of(graph, branch).last_line + 1, branch.indent)
#endregion


#region What a statement owns
## The lines a statement owns: itself, what it carried in, and its body.
static func block_of(graph: ComposerGraph, node: ComposerNode) -> ComposerSpan:
	var last: int = node.span.last_line
	for other: ComposerNode in _ordered(graph):
		if other.span.first_line <= node.span.last_line:
			continue
		if other.indent <= node.indent:
			break
		last = maxi(last, other.span.last_line)
	return ComposerSpan.new(node.span.first_line, last)


## The `else:` belonging to `branch`, or nothing.
static func else_of(graph: ComposerGraph, branch: ComposerNode) -> ComposerNode:
	var next: ComposerNode = _next_at_indent(graph, branch)
	return next if next != null and ComposerFlowBuilder.is_else(next) else null


static func _elif_of(graph: ComposerGraph, branch: ComposerNode) -> ComposerNode:
	var next: ComposerNode = _next_at_indent(graph, branch)
	return next if next != null and ComposerFlowBuilder.is_elif(next) else null


## Whether moving `node` would leave the rest of an `if` chain behind.
static func chains_on(graph: ComposerGraph, node: ComposerNode) -> bool:
	return else_of(graph, node) != null or _elif_of(graph, node) != null


## The statement written after `node`'s block, at `node`'s own depth.
static func _next_at_indent(graph: ComposerGraph, node: ComposerNode) -> ComposerNode:
	var block: ComposerSpan = block_of(graph, node)
	for other: ComposerNode in _ordered(graph):
		if other.span.first_line <= block.last_line:
			continue
		return other if other.indent == node.indent else null
	return null


## The arm of `switch` that `port_id` stands for, counted the way it was drawn.
static func _case_of(
	graph: ComposerGraph, switch: ComposerNode, port_id: StringName
) -> ComposerNode:
	var number: int = 0
	for arm: ComposerNode in _arms_of(graph, switch):
		if StringName(ComposerReader.CASE_OUT % number) == port_id:
			return arm
		number += 1
	return null


static func _wildcard_of(graph: ComposerGraph, switch: ComposerNode) -> ComposerNode:
	for arm: ComposerNode in _arms_of(graph, switch):
		if ComposerFlowBuilder.case_label(arm) == ComposerFlowBuilder.WILDCARD:
			return arm
	return null


## Every arm of one match, in the order the file writes them.
static func _arms_of(graph: ComposerGraph, switch: ComposerNode) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	var block: ComposerSpan = block_of(graph, switch)
	var depth: int = -1
	for other: ComposerNode in _ordered(graph):
		if other.span.first_line <= switch.span.last_line:
			continue
		if other.span.first_line > block.last_line:
			break
		if depth < 0:
			depth = other.indent
		if other.indent == depth and ComposerFlowBuilder.is_case(other):
			found.append(other)
	return found


## The statements of the file, in the order they are written.
static func _ordered(graph: ComposerGraph) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in graph.nodes:
		if node.source_backed and node.span.is_valid():
			found.append(node)
	return found
#endregion


#region Moving lines
## Take `block` out of `source` and put it back at `anchor`, re-indented.
##
## The lines keep their shape relative to one another - a branch moved with its
## body stays a branch with a body - and the whole run shifts by the difference
## between the depth it was written at and the depth it is going to.
static func moved(source: String, block: ComposerSpan, anchor: Anchor) -> String:
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
	return ComposerEdits.insert_after(source, block_of(graph, branch).last_line, written)


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
	return ComposerEdits.insert_after(source, block_of(graph, switch).last_line, written)


## The line a cut path ends on, typed by what the method hands back.
static func _stop(lines: PackedStringArray) -> String:
	return "return %s %s" % [
		ComposerTypes.default_expression(ComposerSubset.entry_return_type(lines)),
		ComposerSubset.FLOW_STOP_MARK,
	]


## Whether this line opens a block that has to have something under it.
static func _opens_a_block(line: String) -> bool:
	var code: String = ComposerSubset.code_of(line).strip_edges()
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
	if chains_on(graph, moving):
		return ""

	var anchor: Anchor = anchor_for(
		graph, producer, wanted.from_port
	)
	if not anchor.is_ok():
		return ""

	var block: ComposerSpan = block_of(graph, moving)
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
			and else_of(graph, from) == null
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
