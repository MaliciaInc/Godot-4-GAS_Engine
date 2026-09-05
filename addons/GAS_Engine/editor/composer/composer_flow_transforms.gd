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
			# Nothing to put in it when the caller only wanted the chain written
			# out: a cut needs the `else` to exist before it can be stopped.
			if not written.strip_edges().is_empty():
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


#region Cutting one path
## Wrap the statements on one path and end the path where they were.
##
## What section 62 asks for, said once: the body of a true branch, of an else, or
## of a case comes out of the live path into an island - still visible, still
## editable, still in the file - and a marked stop takes its place so the path
## ends there instead of running on into whatever the block was followed by.
##
## The stop is written at the body's own depth, which is what keeps it inside the
## block rather than after it.
static func stopped_path(
	source: String, region: ComposerSpan, indent: int
) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	if not region.is_valid() or region.last_line > lines.size():
		return ""
	var wrapped: PackedStringArray = detached(lines, region)
	var stop: String = TAB.repeat(indent) + _stop(lines)
	# After the island, not before it: the path reaches the wrapper, finds a
	# block that never runs, and then ends.
	return ComposerEdits.insert_after(
		NEWLINE.join(wrapped), region.last_line + 1, stop
	)


## Put `if false:` around a run of lines, one indent deeper, marked as ours.
##
## The same wrapper the disconnect of an ordinary link uses. Kept here rather
## than reached for through `ComposerFlowText` so that one module owns writing a
## path down and another owns reading the file.
static func detached(
	lines: PackedStringArray, region: ComposerSpan
) -> PackedStringArray:
	return ComposerFlowText.detached(lines, region)
#endregion


#region Putting one path back
## Take an island's statements out of their wrapper and write them at `anchor`.
##
## The other half of cutting a path: the block that was set aside goes back into
## the live file at the depth the pin it is being joined to requires - inside a
## true body, inside a case, or straight after a statement.
##
## Re-indented whether or not it moves. A block released where it already stands
## is the commonest case of all - plugging a link straight back in - and one that
## kept the wrapper's depth would leave every statement in it one tab too deep,
## which is a different ability.
static func released_into(
	source: String, island: String, anchor: ComposerFlowPlaces.Anchor
) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var opened: int = -1
	for number: int in lines.size():
		if ComposerFlow.island_name(lines[number]) == island:
			opened = number
			break
	if opened < 0 or not anchor.is_ok():
		return ""

	var depth: int = ComposerSubset.indent_of(lines[opened])
	var last: int = opened
	for number: int in range(opened + 1, lines.size()):
		var line: String = lines[number]
		if not line.strip_edges().is_empty() and ComposerSubset.indent_of(line) <= depth:
			break
		last = number
	if last == opened:
		return ""

	var carried: PackedStringArray = PackedStringArray()
	var body_indent: int = ComposerSubset.indent_of(lines[opened + 1])
	for number: int in range(opened + 1, last + 1):
		carried.append(_redented(lines[number], anchor.indent - body_indent))

	# Where it goes, once the wrapper and its body are out of the way. A line
	# above the wrapper keeps its number; one below moves up by everything taken.
	var taken: int = last - opened + 1
	var at: int = anchor.line
	if anchor.line > opened + 1:
		at = maxi(anchor.line - taken, opened + 1)

	var kept: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		if number >= opened and number <= last:
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


## Take the marker off a boundary this tool wrote, leaving what a person now
## means by it.
##
## A generated `else` or `_:` that has been reconnected is no longer machinery -
## it holds behaviour somebody asked for - so the mark comes off and the header
## stays. Section 65 and section 66: what is left is theirs, and nothing removes
## it later.
static func unmarked(source: String, mark: String) -> String:
	var written: PackedStringArray = PackedStringArray()
	for line: String in source.split(NEWLINE):
		written.append(line.replace(" " + mark, "") if line.contains(mark) else line)
	return NEWLINE.join(written)


## Take out a boundary this tool wrote that is no longer holding anything.
##
## Only a marked one, and only when its body is nothing but the stop that came
## with it. A person's own `else` or `_:` is never touched, however empty it
## looks: section 65 and section 66 both say so, and the mark is the only thing
## that tells them apart.
static func spent_boundaries_removed(source: String, mark: String) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var gone: Dictionary[int, bool] = {}
	for number: int in lines.size():
		if not lines[number].contains(mark):
			continue
		var depth: int = ComposerSubset.indent_of(lines[number])
		var last: int = number
		var only_a_stop: bool = true
		for below: int in range(number + 1, lines.size()):
			var line: String = lines[below]
			if line.strip_edges().is_empty():
				continue
			if ComposerSubset.indent_of(line) <= depth:
				break
			last = below
			only_a_stop = (
				only_a_stop and line.contains(ComposerSubset.FLOW_STOP_MARK)
			)
		if not only_a_stop:
			continue
		for at: int in range(number, last + 1):
			gone[at] = true

	if gone.is_empty():
		return source
	var kept: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		if not gone.has(number):
			kept.append(lines[number])
	return NEWLINE.join(kept)
#endregion
