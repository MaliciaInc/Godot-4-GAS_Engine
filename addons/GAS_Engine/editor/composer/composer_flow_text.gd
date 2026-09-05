## The line surgery a change of flow comes down to.
##
## Everything here takes text and hands text back. Nothing decides whether a
## rewiring is allowed - that is a question, and this is the answer being
## written down. Kept apart because a module that both judges and rewrites is
## one where a rule can be enforced in the middle of an edit, with half of
## somebody's file already changed.
##
## Reading is allowed, and needed: a line cannot be taken out without knowing
## which line it is. What never happens here is refusing.
##
## The shapes are three: wrapping a run of statements in a marked `if false:`
## so they stay readable and stop running, taking that wrapper off again, and
## putting a marked `return` at the end of a body whose own return has just
## been wrapped away.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowText extends RefCounted

const NEWLINE: String = "\n"
const TAB: String = "\t"


#region Wrapping and unwrapping
## The lines those nodes cover, from the first to the last.
static func region_of(nodes: Array[ComposerNode]) -> ComposerSpan:
	var first: int = 0
	var last: int = 0
	for node: ComposerNode in nodes:
		if not node.span.is_valid():
			continue
		if first == 0 or node.span.first_line < first:
			first = node.span.first_line
		if node.span.last_line > last:
			last = node.span.last_line
	return ComposerSpan.new(first, last)


## Whether those nodes are the whole of that run of lines and nothing else.
##
## A gap means the wrapper would swallow a statement that is still supposed to
## run, so the transformation is refused rather than approximated.
static func is_contiguous(nodes: Array[ComposerNode], region: ComposerSpan) -> bool:
	if not region.is_valid():
		return false
	var covered: int = 0
	for node: ComposerNode in nodes:
		if node.span.is_valid():
			covered += node.span.last_line - node.span.first_line + 1
	return covered == region.last_line - region.first_line + 1


## Put `if false:` around a run of lines, one indent deeper, marked as ours.
static func detached(
	lines: PackedStringArray, region: ComposerSpan
) -> PackedStringArray:
	var indent: String = _indent_of(lines[region.first_line - 1])
	var opener: String = "%s%s%s%s" % [
		indent,
		ComposerSubset.DETACHED_OPENER,
		ComposerSubset.DETACHED_MARK,
		ComposerFlow.free_island_name(lines),
	]

	var made: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		var line: String = lines[number]
		var at: int = number + 1
		if at == region.first_line:
			made.append(opener)
		if at >= region.first_line and at <= region.last_line:
			made.append(TAB + line if not line.strip_edges().is_empty() else line)
			continue
		made.append(line)
	return made


## Take the wrapper off an island and put its lines back where they run.
static func released(
	source: String, graph: ComposerGraph, island: String, after: ComposerNode
) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var opened: int = -1
	for number: int in lines.size():
		if ComposerFlow.island_name(lines[number]) == island:
			opened = number
			break
	if opened < 0:
		return source

	var depth: int = ComposerSubset.indent_of(lines[opened])
	var body: PackedStringArray = PackedStringArray()
	var last: int = opened
	for number: int in range(opened + 1, lines.size()):
		var line: String = lines[number]
		if not line.strip_edges().is_empty() and ComposerSubset.indent_of(line) <= depth:
			break
		body.append(_undented(line))
		last = number

	var kept: PackedStringArray = PackedStringArray()
	for number: int in lines.size():
		if number >= opened and number <= last:
			continue
		kept.append(lines[number])
		if number + 1 == after.span.last_line:
			kept.append_array(body)
	return NEWLINE.join(kept)


static func _indent_of(line: String) -> String:
	return line.substr(0, line.length() - line.lstrip(" \t").length())


static func _undented(line: String) -> String:
	if line.begins_with(TAB):
		return line.substr(1)
	return line


#endregion


#region Ending and tidying
## Take out the machinery returns the live path no longer reaches.
##
## A cut puts a `return` at the end so the shortened method does not fall off
## it. Putting the statements back makes that return unreachable, and leaving it
## there means every unplug-and-replug cycle deposits another dead line in
## somebody's file. Only marked ones are touched: an unreachable `return` the
## person wrote is theirs to keep, and telling the two apart is the entire
## reason the mark exists.
static func spent_stops_removed(source: String, path: String) -> String:
	var read: ComposerGraph = ComposerReader.read(source, path)
	if not read.is_editable():
		return source

	var spent: Dictionary[int, bool] = {}
	for node: ComposerNode in read.nodes:
		if not node.source_backed:
			continue
		if not node.text.contains(ComposerSubset.FLOW_STOP_MARK):
			continue
		if read.is_reachable_from_entry(node.id):
			continue
		if _holds_a_block_open(source.split(NEWLINE), node.span.first_line):
			# It is the only thing inside a header, so taking it out would leave
			# a block with nothing in it - which is not a file. The path still
			# ends there; the stop is what says so.
			continue
		for line: int in range(node.span.first_line, node.span.last_line + 1):
			spent[line] = true
	if spent.is_empty():
		return source

	var kept: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = source.split(NEWLINE)
	for number: int in lines.size():
		if not spent.has(number + 1):
			kept.append(lines[number])
	return NEWLINE.join(kept)


## Whether the statement at `at` is the only thing inside the header above it.
static func _holds_a_block_open(lines: PackedStringArray, at: int) -> bool:
	var depth: int = ComposerSubset.indent_of(lines[at - 1])
	var above: int = at - 2
	while above >= 0 and lines[above].strip_edges().is_empty():
		above -= 1
	if above < 0 or ComposerSubset.indent_of(lines[above]) != depth - 1:
		return false
	if not ComposerLine.code_of(lines[above]).strip_edges().ends_with(":"):
		return false
	for below: int in range(at, lines.size()):
		if lines[below].strip_edges().is_empty():
			continue
		return ComposerSubset.indent_of(lines[below]) < depth
	return true


## Give the live path somewhere to end, when unplugging took its return away.
##
## A method typed `-> bool` that falls off the end is a file the person cannot
## run, so the transformation that stranded the return puts one back - marked,
## so a later reconnect knows it was machinery rather than something they wrote.
static func ended(source: String, wrapped_at: int) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	for number: int in range(wrapped_at - 1, lines.size()):
		var line: String = lines[number]
		if line.strip_edges().is_empty():
			continue
		if ComposerSubset.indent_of(line) == 0:
			break
		var verdict: ComposerSubset.Verdict = ComposerSubset.classify(line)
		if verdict.indent != 1:
			continue
		# A stop this tool wrote ends the path as surely as a return somebody
		# else did. Read as an ordinary return it would be, but it is classified
		# by its mark first - so a second cut used to leave two of them.
		if (
			verdict.kind == ComposerSubset.Kind.RETURN
			or verdict.kind == ComposerSubset.Kind.FLOW_STOP
		):
			return source

	var written: String = ComposerTypes.default_expression(
		StringName(_returns(lines))
	)
	var stop: String = "%sreturn %s %s" % [TAB, written, ComposerSubset.FLOW_STOP_MARK]
	lines.insert(_after_body(lines, wrapped_at), stop)
	return NEWLINE.join(lines)


## The type the method says it hands back, or "" when it says nothing.
static func _returns(lines: PackedStringArray) -> String:
	for line: String in lines:
		if not line.begins_with("func "):
			continue
		var arrow: int = line.find("->")
		if arrow < 0:
			return ""
		return line.substr(arrow + 2).rstrip(":").strip_edges()
	return ""


## The line after the last one belonging to the body.
static func _after_body(lines: PackedStringArray, from: int) -> int:
	var last: int = from
	for number: int in range(from - 1, lines.size()):
		var line: String = lines[number]
		if line.strip_edges().is_empty():
			continue
		if ComposerSubset.indent_of(line) == 0:
			break
		last = number + 1
	return last
#endregion
