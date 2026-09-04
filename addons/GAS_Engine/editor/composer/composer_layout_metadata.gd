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
