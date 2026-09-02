## The GDScript the Composer can draw, declared once.
##
## The reader asks this what a line is; the writer asks it what shapes it may
## print. Two copies of that judgement would drift, and the drift would show up
## as a file the Composer reads and then cannot write back.
##
## Deliberately small. Only what is understood can be drawn, and promising more
## produces a tool that damages files - so the subset is a short list rather
## than an attempt at GDScript. Anything outside it is not an error in the file:
## it is a file this tool opens read-only and does not touch.
##
## Scope is the body of one method. Everything else in the script - exports,
## constants, helpers, comments, other methods - is preserved byte for byte and
## never rewritten, which is why `body_span()` exists before any parsing does.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerSubset extends RefCounted

## The method a visual ability is a view of.
const ENTRY_POINT: String = "_activate_ability"

## What a line of the body is.
##
## There is no "unknown". Every line resolves to one of these, and the last one
## carries the reason - because a reader that silently skips a line it does not
## understand produces a graph that looks complete, and a writer that then emits
## what it drew deletes the line from the file. That is data loss discovered
## when the ability stops working in the game.
enum Kind {
	BLANK,
	COMMENT,
	CALL,
	LOCAL,
	AWAIT,
	BRANCH,
	BRANCH_ELSE,
	MATCH,
	MATCH_CASE,
	RETURN,
	SUPER,
	UNSUPPORTED,
}

## Constructions that end the reading, and the words to say why.
##
## Each names a keyword rather than guessing at intent. `for` is refused because
## a loop has no single place on a canvas, not because loops are bad code.
const REFUSED: Array[Array] = [
	["for ", "a loop has no single place on a canvas"],
	["while ", "a loop has no single place on a canvas"],
	["func(", "an inline function is code the graph cannot show"],
	["func (", "an inline function is code the graph cannot show"],
	["lambda", "an inline function is code the graph cannot show"],
	["breakpoint", "a debugger statement has no node"],
	["assert(", "an assertion has no node"],
	["continue", "a loop keyword, and loops are outside the subset"],
	["break", "a loop keyword, and loops are outside the subset"],
]

## Openers whose shape is enough to name them.
const OPENERS: Array[Array] = [
	["match ", Kind.MATCH],
	["elif ", Kind.BRANCH_ELSE],
	["if ", Kind.BRANCH],
	["return", Kind.RETURN],
	["super", Kind.SUPER],
	["await ", Kind.AWAIT],
	["var ", Kind.LOCAL],
]


## What a line is, and why if it is nothing this tool can draw.
class Verdict extends RefCounted:
	var kind: ComposerSubset.Kind = ComposerSubset.Kind.UNSUPPORTED
	var reason: String = ""
	var indent: int = 0

	func is_representable() -> bool:
		return kind != ComposerSubset.Kind.UNSUPPORTED

	## Whether this line becomes a node. Blank lines and comments are kept in the
	## file and carried through, but nothing on the canvas stands for them.
	func is_drawn() -> bool:
		return (
			is_representable()
			and kind != ComposerSubset.Kind.BLANK
			and kind != ComposerSubset.Kind.COMMENT
		)


#region Classifying
## Decide what one line is. Never returns without deciding.
static func classify(line: String) -> Verdict:
	var verdict: Verdict = Verdict.new()
	verdict.indent = indent_of(line)

	var text: String = line.strip_edges()
	if text.is_empty():
		verdict.kind = Kind.BLANK
		return verdict
	if text.begins_with("#"):
		verdict.kind = Kind.COMMENT
		return verdict

	for rule: Array in REFUSED:
		if text.begins_with(rule[0]) or text.contains(" " + rule[0]):
			verdict.reason = rule[1]
			return verdict

	if text == "else:":
		verdict.kind = Kind.BRANCH_ELSE
		return verdict

	for opener: Array in OPENERS:
		if text.begins_with(opener[0]):
			verdict.kind = opener[1]
			return _checked(verdict, text)

	if _is_match_case(text):
		verdict.kind = Kind.MATCH_CASE
		return verdict
	if _is_call(text):
		verdict.kind = Kind.CALL
		return verdict

	verdict.reason = "not a call, a local, a branch or a return"
	return verdict


## Extra conditions an opener still has to meet.
##
## `var` without a written type is refused: the graph shows a port's type, and
## inferring it here would mean the canvas and the file disagree about what a
## value is until someone runs the game.
static func _checked(verdict: Verdict, text: String) -> Verdict:
	if verdict.kind == Kind.LOCAL and _is_inferred(text):
		verdict.kind = Kind.UNSUPPORTED
		verdict.reason = "a local needs a written type, not an inferred one"
	return verdict


## Whether a `var` leaves its type to the compiler.
##
## `:=` carries a colon, so looking for one is not enough - checking that was
## how the first version let `var level := 1.0` through while claiming to refuse
## it. The written form is a colon followed by something that is not `=`.
static func _is_inferred(text: String) -> bool:
	if text.contains(":="):
		return true
	return not text.contains(":")


## `Enum.VALUE:` or `_:` - the arms of a match, and nothing else with a colon.
static func _is_match_case(text: String) -> bool:
	if not text.ends_with(":"):
		return false
	var head: String = text.left(text.length() - 1).strip_edges()
	if head == "_":
		return true
	return head.is_valid_identifier() or _is_dotted_name(head)


static func _is_dotted_name(text: String) -> bool:
	var parts: PackedStringArray = text.split(".")
	if parts.size() < 2:
		return false
	for part: String in parts:
		if not part.is_valid_identifier():
			return false
	return true


## A bare call: one name, one pair of brackets, nothing nested inside them.
##
## Nested calls are refused because a node draws one operation. `apply(build())`
## is two, and showing it as one would make the canvas a summary of the code
## rather than a view of it.
static func _is_call(text: String) -> bool:
	var open: int = text.find("(")
	if open <= 0 or not text.ends_with(")"):
		return false
	var name: String = text.substr(0, open)
	if not (name.is_valid_identifier() or _is_dotted_name(name)):
		return false
	var args: String = text.substr(open + 1, text.length() - open - 2)
	return not args.contains("(")


static func indent_of(line: String) -> int:
	var count: int = 0
	while count < line.length() and (line[count] == "\t" or line[count] == " "):
		count += 1
	return count
#endregion


#region Finding the body
## The lines of `_activate_ability()`, or an invalid span when there is none.
##
## Found before anything is parsed, because the writer's whole promise rests on
## it: outside this range the file is not touched, so a person's comments,
## helpers and hand-written code survive a save untouched.
static func body_span(lines: PackedStringArray) -> ComposerSpan:
	var signature: int = _signature_line(lines)
	if signature < 0:
		return ComposerSpan.new()

	var depth: int = indent_of(lines[signature])
	var last: int = signature
	for index: int in range(signature + 1, lines.size()):
		var text: String = lines[index].strip_edges()
		if text.is_empty() or text.begins_with("#"):
			continue
		if indent_of(lines[index]) <= depth:
			break
		last = index

	if last == signature:
		return ComposerSpan.new()
	return ComposerSpan.new(signature + 2, last + 1)


static func _signature_line(lines: PackedStringArray) -> int:
	for index: int in lines.size():
		var text: String = lines[index].strip_edges()
		if text.begins_with("func " + ENTRY_POINT) and text.ends_with(":"):
			return index
	return -1
#endregion


#region Judging a whole body
## The first line of the body this tool cannot draw, or null when it can draw
## them all.
##
## One refusal is enough: the file opens read-only either way, and naming the
## first one is what a person needs to decide whether to change it.
static func first_refusal(
	lines: PackedStringArray, span: ComposerSpan
) -> ComposerGraph.Diagnostic:
	if not span.is_valid():
		return _refusal(
			"no %s() to draw" % ENTRY_POINT, ComposerSpan.new()
		)

	for line: int in range(span.first_line, span.last_line + 1):
		var verdict: Verdict = classify(lines[line - 1])
		if verdict.is_representable():
			continue
		return _refusal(verdict.reason, ComposerSpan.new(line, line))
	return null


static func _refusal(message: String, where: ComposerSpan) -> ComposerGraph.Diagnostic:
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = ComposerGraph.Severity.NOT_REPRESENTABLE
	found.message = message
	found.span = where
	return found
#endregion
