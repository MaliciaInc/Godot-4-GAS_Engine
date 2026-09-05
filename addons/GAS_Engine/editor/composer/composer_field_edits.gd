## Turning "this value now holds X" into the line the file will hold.
##
## One module for every field there is. A call's argument and a branch's
## condition are the same thing to the person editing them - a value on a card,
## typed into or fed by a cable - and they were two different things to the tool:
## an argument went through the writer, and a condition went nowhere at all,
## because the writer rebuilds a statement out of a call and a branch is not one.
## That is why a condition could be shown and never changed.
##
## What happens here is source surgery, not printing. Only the lines of the
## statements that changed are replaced; everything else in the file, inside the
## body and out of it, is the same bytes it was. The result is handed back rather
## than committed - the caller owns the transaction, so two fields moved in one
## gesture are one entry in the history and one refusal when either half is
## impossible.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFieldEdits extends RefCounted

const NO_SUCH_CARD: String = "that card is no longer here"
const NO_SUCH_FIELD: String = "that value is no longer on the card"
const NOT_EDITABLE: String = "%s is not something this tool may write"
const NOTHING_WRITTEN: String = "%s has to say something"
const NOT_IN_SOURCE: String = "%s is not written anywhere this tool can change"
const OVERLAPPING: String = "two of those values are on the same lines"
const UNREADABLE: String = "that change would leave a file this tool cannot read: %s"
const LOST: String = "that change did not come back as it was written: %s"
const HEADER_MARK: String = ":"


## One value, and what it should now say.
##
## The field is named by its place rather than by its label: two arguments of one
## call can be called the same thing, and position is what the language goes by.
class Change extends RefCounted:
	var node_id: StringName = &""
	var field_index: int = -1
	var written: String = ""

	static func of(node_id: StringName, field_index: int, written: String) -> Change:
		var made: Change = Change.new()
		made.node_id = node_id
		made.field_index = field_index
		made.written = written
		return made


## The file after the change, or why there is no such file.
class Result extends RefCounted:
	var ok: bool = false
	var source: String = ""
	var message: String = ""


## One statement to replace, and everything needed to find it again afterwards.
##
## Kept per node rather than per change, so two arguments of one call are one
## replacement. Rebuilding the same statement twice would apply the second
## rewrite to lines the first one already replaced.
class Planned extends RefCounted:
	var node: ComposerNode = null
	var first_line: int = ComposerSpan.NO_LINE
	var last_line: int = ComposerSpan.NO_LINE
	var lines: PackedStringArray = PackedStringArray()
	var written: Dictionary[int, String] = {}

	## How many lines this statement takes up in the file it came from.
	func read_length() -> int:
		return last_line - first_line + 1

	## What it will take up once it is replaced.
	func written_length() -> int:
		return lines.size()


#region Rewriting
## One field, changed. The whole file comes back, or nothing does.
static func rewrite(source: String, graph: ComposerGraph, change: Change) -> Result:
	var only: Array[Change] = []
	only.append(change)
	return rewrite_many(source, graph, only)


## Several fields, changed together or not at all.
##
## Bottom-up on purpose: a statement rebuilt onto fewer or more lines than it
## came on moves everything below it, and replacing the lowest one first means
## every line number gathered from the original graph is still true when its turn
## comes. Nothing here looks a statement up by what it says - two identical calls
## in one body are perfectly legal, and a search would rewrite whichever came
## first, twice.
static func rewrite_many(
	source: String, graph: ComposerGraph, changes: Array[Change]
) -> Result:
	if changes.is_empty():
		# Nothing asked for is not a failure. A gesture that turns out to change
		# no value hands back the file it was given, and the caller commits
		# nothing because nothing differs.
		return _done(source)

	var planned: Array[Planned] = []
	for change: Change in changes:
		var refusal: String = _plan(graph, planned, change)
		if not refusal.is_empty():
			return _refused(refusal)
	for edit: Planned in planned:
		var refusal: String = _render(edit)
		if not refusal.is_empty():
			return _refused(refusal)
	if _overlapping(planned):
		return _refused(OVERLAPPING)

	planned.sort_custom(_bottom_first)
	var next_source: String = source
	for edit: Planned in planned:
		next_source = ComposerWriter.spliced(
			next_source.split("\n"),
			ComposerSpan.new(edit.first_line, edit.last_line),
			edit.lines
		)

	var reread: ComposerGraph = ComposerReader.read(next_source, graph.source_path)
	if not reread.is_editable():
		return _refused(UNREADABLE % reread.blocked_reason())
	var missing: String = _unrepresented(reread, planned)
	if not missing.is_empty():
		return _refused(LOST % missing)
	return _done(next_source)
#endregion


#region Planning
## Judge one change and fold it into the statement it belongs to.
##
## Every reason to say no is here, before a single character is written, so a
## refusal is a file nobody touched rather than a file half rewritten.
static func _plan(
	graph: ComposerGraph, planned: Array[Planned], change: Change
) -> String:
	var node: ComposerNode = graph.find_node(change.node_id)
	if node == null:
		return NO_SUCH_CARD
	if change.field_index < 0 or change.field_index >= node.fields.size():
		return NO_SUCH_FIELD

	var field: ComposerNode.Field = node.fields[change.field_index]
	if not node.may_edit(field):
		return NOT_EDITABLE % field.label
	# An empty condition is `if :`, and an empty argument is `apply(, 1.0)`.
	# Neither is a statement, and both would be refused by the reread further
	# down - named here so the person is told which value was left blank.
	if change.written.strip_edges().is_empty():
		return NOTHING_WRITTEN % field.label
	if not node.source_backed or node.source_text.is_empty() or not node.span.is_valid():
		return NOT_IN_SOURCE % node.title

	var edit: Planned = _for_node(planned, node)
	edit.written[change.field_index] = change.written.strip_edges()
	return ""


## The replacement being built for `node`, started if this is the first change
## to land on it.
##
## The span is the statement's own lines and not the node's span: a node's span
## reaches back over the comments it carried in, and replacing those would take
## a person's note off the top of their statement.
static func _for_node(planned: Array[Planned], node: ComposerNode) -> Planned:
	for edit: Planned in planned:
		if edit.node.id == node.id:
			return edit
	var made: Planned = Planned.new()
	made.node = node
	made.last_line = node.span.last_line
	made.first_line = made.last_line - node.source_text.size() + 1
	planned.append(made)
	return made


## Build the lines this statement becomes, or say why it cannot be built.
static func _render(edit: Planned) -> String:
	if not edit.node.type_id.is_empty():
		edit.lines.append(
			ComposerWriter.render_with_field_overrides(edit.node, edit.written)
		)
		return ""

	# A structural statement carries exactly one value, so there is exactly one
	# thing the person could have changed.
	var carried: Array = edit.written.values()
	var written: String = carried[0]
	var rebuilt: String = _structural(edit.node, written)
	if rebuilt.is_empty():
		return NOT_IN_SOURCE % edit.node.title
	edit.lines.append(rebuilt)
	return ""


## An `if`, an `elif`, a `match` or a `return`, with its one value replaced.
##
## The keyword is taken off the line rather than guessed from the node's kind:
## the line already says which of them it is, and reading it back is one fewer
## thing to keep in step. The colon, the indentation and the note somebody left
## at the end of the line all survive, because none of them is what changed.
static func _structural(node: ComposerNode, written: String) -> String:
	var code: String = ComposerSubset.code_of(node.text)
	var note: String = node.text.substr(code.length()).strip_edges()
	var head: String = code.strip_edges()
	var rebuilt: String = ""

	if head.begins_with(ComposerSubset.RETURN_OPENER):
		rebuilt = "%s %s" % [ComposerSubset.RETURN_OPENER, written]
	else:
		var keyword: int = head.find(" ")
		if keyword < 0:
			return ""
		rebuilt = "%s %s%s" % [head.left(keyword), written, HEADER_MARK]

	if not note.is_empty():
		rebuilt += " " + note
	return ComposerWriter.TAB.repeat(maxi(node.indent, 1)) + rebuilt


## Whether two statements to be replaced share a line.
##
## They cannot, and a caller that asked for it has asked for one replacement to
## be written over another.
static func _overlapping(planned: Array[Planned]) -> bool:
	for edit: Planned in planned:
		for other: Planned in planned:
			if other == edit:
				continue
			if edit.first_line <= other.last_line and other.first_line <= edit.last_line:
				return true
	return false


static func _bottom_first(first: Planned, second: Planned) -> bool:
	return first.first_line > second.first_line
#endregion


#region Checking the result
## Whichever value did not come back saying what it was written as, or nothing.
##
## The statement is found by counting lines rather than by looking for what it
## says. Every replacement above this one moved it by the difference between the
## lines it took up and the lines it takes up now, and adding those up is exactly
## where it ended: no search, so two identical calls cannot be confused for one
## another, and no reliance on a node id, which is derived from a line number and
## is a different id the moment anything above it changes length.
static func _unrepresented(reread: ComposerGraph, planned: Array[Planned]) -> String:
	for edit: Planned in planned:
		var line: int = edit.first_line
		for other: Planned in planned:
			if other.first_line < edit.first_line:
				line += other.written_length() - other.read_length()

		var node: ComposerNode = reread.node_at_line(line)
		if node == null:
			return edit.node.title
		for position: int in edit.written:
			if position >= node.fields.size():
				return edit.written[position]
			if node.fields[position].display.strip_edges() != edit.written[position]:
				return edit.written[position]
	return ""
#endregion


#region Answers
static func _done(source: String) -> Result:
	var made: Result = Result.new()
	made.ok = true
	made.source = source
	return made


static func _refused(message: String) -> Result:
	var made: Result = Result.new()
	made.message = message
	return made
#endregion
