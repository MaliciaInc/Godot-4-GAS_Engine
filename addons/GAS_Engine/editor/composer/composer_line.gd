## Where a line's brackets, quotes and comment are.
##
## The punctuation, not the meaning. Everything that reads a statement leans on
## this: whether a statement has finished or runs on into the line below, where
## its arguments are cut, where the code stops and a person's note begins. All of
## it comes off one scan, because three scanners disagreeing about a quote is
## three different ideas of what a file says.
##
## Kept apart from `ComposerSubset`, which is about what a line *is*. That is a
## question asked of this one's answers, and putting both in one file made the
## file the largest in the project by half.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerLine extends RefCounted

const OPENING: String = "([{"
const CLOSING: String = ")]}"
const DOUBLE_QUOTE: String = "\""
const SINGLE_QUOTE: String = "'"
const ESCAPE: String = "\\"
const COMMENT_MARK: String = "#"
const COMMA: String = ","
const EQUALS: String = "="

## Characters that turn a following `=` into something that is not an
## assignment. `:` is here for `:=`, which the subset refuses for its own
## reasons and must not be mistaken for a plain assignment on the way.
const COMPARISONS: String = "=!<>:"


## What the brackets in a line do.
##
## One scan answers three questions that were being answered three ways: whether
## a statement is finished, whether a call is one call, and where its arguments
## end. Separate answers to the same question drift, and the drift shows up as a
## file the tool refuses for being formatted.
class Brackets extends RefCounted:
	## Where the top-level commas are - the ones between arguments, not the ones
	## inside them.
	var breaks: PackedInt32Array = PackedInt32Array()

	## Where the statement's own `=` is, or -1. Not a comparison, not one buried
	## inside an argument list.
	var assign: int = -1

	## Bracket depth at the end. Anything but zero means the statement runs on
	## into the next line.
	var depth: int = 0

	## The lowest depth reached on the way. Below zero means a bracket closed
	## something that was never opened here.
	var lowest: int = 0

	## Where a trailing comment begins, or -1 for a line that is all code.
	var comment: int = -1


## The part of `line` that is code, without the comment trailing it.
##
## One question with one answer. What a header carries is read across this
## boundary and written back across it, and a `_:` this tool marked as its own
## has to be classified as the case it still is - so a second opinion about
## where the code ends is a marked line nobody can read back.
static func code_of(line: String) -> String:
	var mark: int = scan(line).comment
	return line if mark < 0 else line.substr(0, mark)


## Read the brackets of `text`.
##
## Quotes and trailing comments are skipped: a bracket inside a string is a
## character, and a reader that counted it would join a line to the one after it
## for the rest of the file.
static func scan(text: String) -> Brackets:
	var found: Brackets = Brackets.new()
	var quote: String = ""
	var index: int = 0
	while index < text.length():
		var character: String = text[index]
		if not quote.is_empty():
			if character == ESCAPE:
				index += 2
				continue
			if character == quote:
				quote = ""
		elif character == DOUBLE_QUOTE or character == SINGLE_QUOTE:
			quote = character
		elif character == COMMENT_MARK:
			found.comment = index
			break
		elif OPENING.contains(character):
			found.depth += 1
		elif CLOSING.contains(character):
			found.depth -= 1
			found.lowest = mini(found.lowest, found.depth)
		elif character == COMMA and found.depth == 0:
			found.breaks.append(index)
		elif character == EQUALS and found.depth == 0 and found.assign < 0:
			if not _is_comparison(text, index):
				found.assign = index
		index += 1
	return found


## Whether the `=` at `index` belongs to `==`, `!=`, `<=`, `>=` or `:=`.
##
## `+=` is not one of them: a line that adds to something is still a line that
## assigns to it, and refusing it would leave a person's own counter unreadable.
static func _is_comparison(text: String, index: int) -> bool:
	if index + 1 < text.length() and text[index + 1] == EQUALS:
		return true
	if index == 0:
		return false
	return COMPARISONS.contains(text[index - 1])


## The pieces of an argument list, split on its own commas.
static func arguments_of(inside: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var start: int = 0
	for stop: int in scan(inside).breaks:
		found.append(inside.substr(start, stop - start))
		start = stop + 1
	found.append(inside.substr(start))
	return found


## One call: a name, and one pair of brackets closing at the end of the line.
##
## A call inside the argument list is allowed and kept as the text it is. It was
## refused once, on the grounds that a node draws one operation - but the subset
## already allowed `level + 1.0` in an argument, which is also an operation, so
## the rule was never really about that. It was a comma: splitting arguments on
## every comma mis-reads `apply(a, build(x, y))`, and refusing the whole line was
## the cheap way out. Counting brackets instead costs one scan and lets the
## Composer open the abilities people actually write - a call whose level comes
## from `get_ability_level()` is not exotic, it is most of them.
##
## What is still refused is two calls standing side by side. `foo() + bar()`
## ends with a bracket and starts with a name, and only the depth never
## returning to zero in between tells it apart from one call.
