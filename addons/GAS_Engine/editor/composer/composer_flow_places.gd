## Where each path of a statement is written in the file.
##
## There is no stored list of execution wires. A statement runs after another
## because it is written after it, and it is on a branch's true path because it
## is written indented under the `if` - so "where does this path go" is a
## question about lines, and this is where it is answered.
##
## Nothing here changes anything. Both the move and the creation ask these
## questions before they write, and the refusals that have to happen first -
## a pin with no path to write into, a branch whose chain would be left behind -
## are answered here too.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowPlaces extends RefCounted

const NO_SUCH_PIN: String = "that pin is not one this tool can write a path for"
const NO_ELSE_TO_FILL: String = "that branch has no else for a path to be written into"
const NO_WILDCARD_TO_FILL: String = (
	"that match has no catch-all for a path to be written into"
)


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
		var wildcard: ComposerNode = wildcard_of(graph, node)
		if wildcard == null:
			return Anchor.refused(NO_WILDCARD_TO_FILL)
		return _inside(graph, node, wildcard)
	var arm: ComposerNode = case_of(graph, node, port_id)
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
static func case_of(
	graph: ComposerGraph, switch: ComposerNode, port_id: StringName
) -> ComposerNode:
	var number: int = 0
	for arm: ComposerNode in _arms_of(graph, switch):
		if StringName(ComposerReader.CASE_OUT % number) == port_id:
			return arm
		number += 1
	return null


## Whether that match already takes whatever is left.
static func has_wildcard(graph: ComposerGraph, switch: ComposerNode) -> bool:
	return wildcard_of(graph, switch) != null


static func wildcard_of(graph: ComposerGraph, switch: ComposerNode) -> ComposerNode:
	for arm: ComposerNode in _arms_of(graph, switch):
		if ComposerFlowBuilder.case_label(arm) == ComposerFlowBuilder.WILDCARD:
			return arm
	return null


## The lines written inside `header`'s block: everything deeper than it.
##
## A branch's own block ends where its `else` begins, and an `else` block ends
## where the statement after the chain begins, so the same walk answers for the
## true side, for the else and for one arm of a match.
static func body_of(graph: ComposerGraph, header: ComposerNode) -> ComposerSpan:
	var block: ComposerSpan = block_of(graph, header)
	var first: int = ComposerSpan.NO_LINE
	var last: int = ComposerSpan.NO_LINE
	for other: ComposerNode in _ordered(graph):
		if other.span.first_line <= header.span.last_line:
			continue
		if other.span.first_line > block.last_line:
			break
		if other.indent <= header.indent:
			break
		if first == ComposerSpan.NO_LINE:
			first = other.span.first_line
		last = maxi(last, other.span.last_line)
	return ComposerSpan.new(first, last)


## The island a statement is standing in, or nothing when it is live.
##
## The one whose block actually covers it, not the first one written above it. A
## file can hold several islands - a move sets one aside per link it takes out -
## and answering with whichever came first releases somebody else's statements.
static func island_of(graph: ComposerGraph, node: ComposerNode) -> String:
	for other: ComposerNode in graph.nodes:
		if other.projection_kind != ComposerNode.ProjectionKind.SUPPORT:
			continue
		var island: String = ComposerFlow.island_name(other.text)
		if island.is_empty():
			continue
		if other.span.first_line >= node.span.first_line or other.indent >= node.indent:
			continue
		if block_of(graph, other).contains(node.span.first_line):
			return island
	return ""


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
