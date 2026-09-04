## Visual placement stored inside the ability source itself.
##
## The comment is presentation metadata only. It never changes execution order,
## never participates in ComposerWriter.signature(), and never becomes a second
## gameplay authority. Because the comment travels with the statement, moving
## that statement in source also moves its visual placement.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerLayoutMetadata extends RefCounted

const PREFIX: String = "# @composer-position "

## Where a card that is not a statement sits.
##
## Entry is drawn and has no line of its own to carry a comment, so its place
## is written against its id instead. Kept in the body like every other piece
## of this metadata, and just as inert: it names a card, never a statement.
const VIRTUAL_PREFIX: String = "# @composer-virtual-position "
const PRECISION: int = 2


static func position_in(lines: PackedStringArray) -> Variant:
	for line: String in lines:
		var stripped: String = line.strip_edges()
		if not stripped.begins_with(PREFIX):
			continue
		var payload: String = stripped.substr(PREFIX.length()).strip_edges()
		var parts: PackedStringArray = payload.split(" ", false)
		if parts.size() != 2:
			return null
		if not parts[0].is_valid_float() or not parts[1].is_valid_float():
			return null
		return Vector2(parts[0].to_float(), parts[1].to_float())
	return null


static func positioned(source: String, node: ComposerNode, position: Vector2) -> String:
	if node == null or not node.span.is_valid() or node.source_text.is_empty():
		return source

	var lines: PackedStringArray = source.split("\n")
	var statement_first: int = node.span.last_line - node.source_text.size() + 1
	var metadata_first: int = node.span.first_line
	var metadata_last: int = statement_first - 1
	var replacement: String = _line(node.indent, position)

	for line_number: int in range(metadata_first, metadata_last + 1):
		if line_number <= 0 or line_number > lines.size():
			continue
		if lines[line_number - 1].strip_edges().begins_with(PREFIX):
			lines[line_number - 1] = replacement
			return "\n".join(lines)

	var insert_at: int = clampi(statement_first - 1, 0, lines.size())
	lines.insert(insert_at, replacement)
	return "\n".join(lines)


## Take the saved position out of a node's carried comments and onto the node.
##
## Here rather than inline in ComposerReader because this is the only thing in
## the project that knows what the comment looks like, so this is where a change
## to its shape should have to be made.
static func read_onto(node: ComposerNode) -> void:
	if node == null:
		return
	var saved: Variant = position_in(node.carried)
	if saved is Vector2:
		node.has_layout_position = true
		node.layout_position = saved


static func without_layout_lines(lines: PackedStringArray) -> PackedStringArray:
	var clean: PackedStringArray = PackedStringArray()
	for line: String in lines:
		if line.strip_edges().begins_with(PREFIX):
			continue
		clean.append(line)
	return clean


static func without_layout_text(text: String) -> String:
	return "\n".join(without_layout_lines(text.split("\n")))


static func _line(indent: int, position: Vector2) -> String:
	var tabs: String = "\t".repeat(maxi(indent, 1))
	return tabs + PREFIX + ("%.*f %.*f" % [
		PRECISION,
		position.x,
		PRECISION,
		position.y,
	])


#region Placing several at once
## Every position written into one source, in one pass.
##
## Applied from the bottom of the file upwards. Writing a comment above a
## statement shifts every line below it, so a pass that went top-down would be
## working from spans that stopped being true after its first edit - and would
## put the second card's position against somebody else's statement.
##
## One string comes back, not one per card. The alternative is a commit per
## moved node, which turns dragging four selected cards into four things to undo.
static func positioned_many(
	source: String, graph: ComposerGraph, positions: Dictionary[StringName, Vector2]
) -> String:
	var wanted: Array[StringName] = []
	for id: StringName in positions:
		if _is_finite(positions[id]) and graph.find_node(id) != null:
			wanted.append(id)

	# Bottom-up: the node furthest down the file is written first, so no edit
	# moves a line another edit has not been applied to yet.
	wanted.sort_custom(
		func _lower_first(one: StringName, other: StringName) -> bool:
			return graph.find_node(one).span.first_line > graph.find_node(other).span.first_line
	)

	var written: String = source
	for id: StringName in wanted:
		var node: ComposerNode = graph.find_node(id)
		if node.source_backed:
			written = positioned(written, node, positions[id])
			continue
		written = position_virtual(written, id, positions[id])
	return written


## A position with a real x and y. Infinity and NaN are what a divide by a zoom
## of nought produces, and a card placed at one is a card nobody can find again.
static func _is_finite(position: Vector2) -> bool:
	return is_finite(position.x) and is_finite(position.y)
#endregion


#region Cards that are not statements
## Where `id` was left, or nothing.
##
## The first valid line wins. A file can end up with two through a hand edit, and
## picking the first makes the answer the same on every read; the duplicate is
## removed the next time that card is written.
static func virtual_position(source: String, id: StringName) -> Variant:
	for line: String in _body_of(source):
		var found: Variant = _virtual_in(line, id)
		if found != null:
			return found
	return null


## Write `id`'s place, leaving exactly one line for it.
##
## Every existing line for that id is taken out first, so a file that had picked
## up duplicates is normalised by the act of writing rather than by a repair
## nobody remembers to run.
static func position_virtual(
	source: String, id: StringName, position: Vector2
) -> String:
	var lines: PackedStringArray = source.split("
")
	var kept: PackedStringArray = PackedStringArray()
	var body: ComposerSpan = ComposerSubset.body_span(lines)
	for number: int in lines.size():
		var inside: bool = body.is_valid() and number + 1 >= body.first_line and number + 1 <= body.last_line
		if inside and _virtual_in(lines[number], id) != null:
			continue
		kept.append(lines[number])

	if not body.is_valid():
		return "
".join(kept)
	kept.insert(
		clampi(body.first_line - 1, 0, kept.size()),
		"	" + VIRTUAL_PREFIX + "%s %.*f %.*f" % [
			id, PRECISION, position.x, PRECISION, position.y
		]
	)
	return "
".join(kept)


## What that line says about `id`, or nothing.
static func _virtual_in(line: String, id: StringName) -> Variant:
	var stripped: String = line.strip_edges()
	if not stripped.begins_with(VIRTUAL_PREFIX):
		return null
	var parts: PackedStringArray = stripped.substr(VIRTUAL_PREFIX.length()).split(" ", false)
	if parts.size() != 3 or StringName(parts[0]) != id:
		return null
	if not parts[1].is_valid_float() or not parts[2].is_valid_float():
		return null
	return Vector2(parts[1].to_float(), parts[2].to_float())


## The lines of `_activate_ability()`, which is the only place this metadata is
## recognised. A comment of the same shape anywhere else in the file is somebody
## else's, and reading it would let a card be placed by a line the Composer does
## not own.
static func _body_of(source: String) -> PackedStringArray:
	var lines: PackedStringArray = source.split("
")
	var body: ComposerSpan = ComposerSubset.body_span(lines)
	if not body.is_valid():
		return PackedStringArray()
	return lines.slice(body.first_line - 1, body.last_line)
#endregion
