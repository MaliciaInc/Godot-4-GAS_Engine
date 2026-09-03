## Changing a body by changing its lines.
##
## Every structural edit the Composer offers - remove a statement, repeat one,
## put one somewhere, take a copy - is a change to the text and nothing else.
## The graph is read again afterwards, so the canvas cannot end up describing
## something the file does not say: there is no second place for the change to
## be applied to and no chance of applying it to only one of them.
##
## A statement is its whole span, comments and blank lines included. Taking a
## call out and leaving the note somebody wrote above it hanging over the next
## one is worse than either keeping both or dropping both.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerEdits extends RefCounted

## What a body says when it says nothing. GDScript needs a statement, and this
## is the one that means there is not one - so removing the last line of a body
## leaves this rather than a file that will not parse.
const NOTHING: String = "pass"

const NEWLINE: String = "\n"
const TAB: String = "\t"


## `source` without the lines those spans cover.
##
## Taken from the bottom up, so removing one span does not move the lines the
## next one is measured against.
static func remove(source: String, spans: Array[ComposerSpan]) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	for span: ComposerSpan in _bottom_up(spans):
		if not span.is_valid():
			continue
		for line: int in range(span.last_line, span.first_line - 1, -1):
			lines.remove_at(line - 1)
	return NEWLINE.join(lines)


## `source` with each of those statements repeated straight after itself.
static func repeat(source: String, spans: Array[ComposerSpan]) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	for span: ComposerSpan in _bottom_up(spans):
		if not span.is_valid():
			continue
		var copied: PackedStringArray = lines.slice(span.first_line - 1, span.last_line)
		for offset: int in copied.size():
			lines.insert(span.last_line + offset, copied[offset])
	return NEWLINE.join(lines)


## `source` with `written` put in after line `at`.
static func insert_after(source: String, at: int, written: String) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var added: PackedStringArray = written.split(NEWLINE)
	var place: int = clampi(at, 0, lines.size())
	for offset: int in added.size():
		lines.insert(place + offset, added[offset])
	return NEWLINE.join(lines)


## `source` with the statement at `moved` put where `before` starts.
##
## Taken out first and then put back, with the target measured again afterwards:
## removing lines above it moves it up by exactly as many, and a target line
## remembered from before the removal lands the statement somewhere else.
static func move(source: String, moved: ComposerSpan, before: ComposerSpan) -> String:
	if not moved.is_valid() or not before.is_valid() or moved.first_line == before.first_line:
		return source

	var lines: PackedStringArray = source.split(NEWLINE)
	var taken: PackedStringArray = lines.slice(moved.first_line - 1, moved.last_line)
	for line: int in range(moved.last_line, moved.first_line - 1, -1):
		lines.remove_at(line - 1)

	var at: int = before.first_line - 1
	if before.first_line > moved.last_line:
		at -= moved.line_count()
	for offset: int in taken.size():
		lines.insert(at + offset, taken[offset])
	return NEWLINE.join(lines)


## The text those statements are made of, in the order the file has them.
static func lines_of(source: String, spans: Array[ComposerSpan]) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var taken: PackedStringArray = PackedStringArray()
	for span: ComposerSpan in _top_down(spans):
		if span.is_valid():
			taken.append_array(lines.slice(span.first_line - 1, span.last_line))
	return NEWLINE.join(taken)


## A body with every statement gone still has to say so.
##
## Called after a removal: if the method's body is empty, GDScript will not
## parse the file at all, and a tool that can leave somebody's script broken by
## deleting the last node is not one they will use twice.
static func keep_a_body(source: String) -> String:
	var lines: PackedStringArray = source.split(NEWLINE)
	var body: ComposerSpan = ComposerSubset.body_span(lines)
	if body.is_valid():
		return source

	var signature: int = _signature_line(lines)
	if signature < 0:
		return source
	return insert_after(source, signature, TAB + NOTHING)


static func _signature_line(lines: PackedStringArray) -> int:
	for index: int in lines.size():
		if lines[index].begins_with("func %s(" % ComposerSubset.ENTRY_POINT):
			return index + 1
	return -1


## Bottom up, so an edit does not move what the next one is measured against.
static func _bottom_up(spans: Array[ComposerSpan]) -> Array[ComposerSpan]:
	var sorted: Array[ComposerSpan] = spans.duplicate()
	sorted.sort_custom(
		func _later(left: ComposerSpan, right: ComposerSpan) -> bool:
			return left.first_line > right.first_line
	)
	return sorted


static func _top_down(spans: Array[ComposerSpan]) -> Array[ComposerSpan]:
	var sorted: Array[ComposerSpan] = spans.duplicate()
	sorted.sort_custom(
		func _earlier(left: ComposerSpan, right: ComposerSpan) -> bool:
			return left.first_line < right.first_line
	)
	return sorted
