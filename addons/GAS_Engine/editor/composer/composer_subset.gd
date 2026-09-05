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
## @meta_license: GAS_Engine Community Use License 1.0
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

	## Lines Composer wrote to hold a shape the language has no other word for.
	##
	## DETACHED is `if false:` around statements a person unplugged: they are
	## still in the file, still readable, and no longer run. FLOW_STOP is the
	## `return` put in so a live path still ends somewhere after that happened.
	## Both only count as support when they carry the exact marker below, so a
	## person's own `if false:` stays an ordinary branch.
	DETACHED,
	FLOW_STOP,
	ASSIGN,
	NOTHING,
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

const OPENING: String = "([{"
const CLOSING: String = ")]}"
const DOUBLE_QUOTE: String = "\""
const SINGLE_QUOTE: String = "'"
const ESCAPE: String = "\\"
const COMMENT_MARK: String = "#"
const COMMA: String = ","
const EQUALS: String = "="

## An ability that does nothing yet still has to say so. `pass` is the first
## line of every body somebody has started and not finished, and a tool that
## cannot open one cannot be opened while the work is being done.
const NOTHING_MARK: String = "pass"

## Characters that turn a following `=` into something that is not an
## assignment. `:` is here for `:=`, which the subset refuses for its own
## reasons and must not be mistaken for a plain assignment on the way.
const COMPARISONS: String = "=!<>:"

## The exact comments that make a line Composer's rather than a person's.
##
## Reserved on purpose and matched whole: `if false:` written by hand is a
## branch somebody meant, and reading it as machinery would take their code off
## the canvas. The detached marker carries a number so a file can hold several
## unplugged islands and each one can be found again.
const DETACHED_MARK: String = "# @composer-detached "
const FLOW_STOP_MARK: String = "# @composer-flow-stop"
const DETACHED_OPENER: String = "if false: "

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
		var forbidden: String = rule[0]
		if text.begins_with(forbidden) or text.contains(" " + forbidden):
			verdict.reason = rule[1]
			return verdict

	# Asked before the ordinary openers, because both support lines are also
	# valid ordinary lines and would be read as a branch and a return.
	if text.contains(DETACHED_MARK):
		verdict.kind = Kind.DETACHED
		return verdict
	if text.ends_with(FLOW_STOP_MARK):
		verdict.kind = Kind.FLOW_STOP
		return verdict

	if text == "else:":
		verdict.kind = Kind.BRANCH_ELSE
		return verdict

	for opener: Array in OPENERS:
		var begins: String = opener[0]
		if text.begins_with(begins):
			verdict.kind = opener[1]
			return _checked(verdict, text)

	if _is_match_case(text):
		verdict.kind = Kind.MATCH_CASE
		return verdict
	if text == NOTHING_MARK:
		verdict.kind = Kind.NOTHING
		return verdict
	if _is_call(text):
		verdict.kind = Kind.CALL
		return verdict
	if scan(text).assign > 0:
		verdict.kind = Kind.ASSIGN
		return verdict

	verdict.reason = "not a call, a local, an assignment, a branch or a return"
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
static func _is_call(text: String) -> bool:
	var open: int = text.find("(")
	if open <= 0 or not text.ends_with(")"):
		return false
	var name: String = text.substr(0, open)
	if not (name.is_valid_identifier() or _is_dotted_name(name)):
		return false

	var inside: Brackets = scan(text.substr(open + 1, text.length() - open - 2))
	return inside.depth == 0 and inside.lowest >= 0


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
## One statement: where it starts, where it ends, and what it says as one line.
class Statement extends RefCounted:
	var first: int = ComposerSpan.NO_LINE
	var last: int = ComposerSpan.NO_LINE

	## The wrapping taken out. A call split across three lines is one statement
	## and is judged as one.
	var text: String = ""

	var verdict: ComposerSubset.Verdict = null


## The statements of `span`, in order.
##
## The one place a body is cut into statements. There were two walks over the
## same lines - one to refuse a file, one to build its nodes - and the first time
## somebody wrapped a long call they disagreed: the builder joined the lines and
## the refuser judged the continuation on its own, saw `owner_asc, world, sweep`,
## and turned the file away for being formatted. The walk that refuses always
## wins, so a second walk is not a second opinion, it is the only one.
static func statements(lines: PackedStringArray, span: ComposerSpan) -> Array[Statement]:
	var found: Array[Statement] = []
	if not span.is_valid():
		return found

	var line: int = span.first_line
	while line <= span.last_line:
		var made: Statement = Statement.new()
		made.first = line
		made.last = _statement_end(lines, line, span.last_line)
		made.text = _joined(lines, made.first, made.last)
		made.verdict = classify(made.text)
		found.append(made)
		line = made.last + 1
	return found


## The last line of the statement that starts at `first`.
##
## A statement whose brackets have not closed runs on into the line below it.
static func _statement_end(lines: PackedStringArray, first: int, limit: int) -> int:
	var last: int = first
	var text: String = lines[first - 1]
	while last < limit and scan(text).depth > 0:
		last += 1
		text += lines[last - 1]
	return last


## The lines of one statement as a single line, wrapping removed.
static func _joined(lines: PackedStringArray, first: int, last: int) -> String:
	var text: String = lines[first - 1]
	for line: int in range(first + 1, last + 1):
		text += " " + lines[line - 1].strip_edges()
	return text


static func first_refusal(
	lines: PackedStringArray, span: ComposerSpan
) -> ComposerGraph.Diagnostic:
	if not span.is_valid():
		return _refusal(
			"no %s() to draw" % ENTRY_POINT, ComposerSpan.new()
		)

	for made: Statement in statements(lines, span):
		if made.verdict.is_representable():
			continue
		return _refusal(made.verdict.reason, ComposerSpan.new(made.first, made.last))
	return null


static func _refusal(message: String, where: ComposerSpan) -> ComposerGraph.Diagnostic:
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = ComposerGraph.Severity.NOT_REPRESENTABLE
	found.message = message
	found.span = where
	return found
#endregion
