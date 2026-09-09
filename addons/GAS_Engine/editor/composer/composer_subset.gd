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
	## FLOW_ELSE and FLOW_DEFAULT are the two boundaries this tool writes to
	## stop a path that used to fall through. Kinds of their own so that a
	## person's own `else` and their own `_:` are never mistaken for machinery
	## and taken away by a cleanup.
	DETACHED,
	FLOW_STOP,
	FLOW_ELSE,
	FLOW_DEFAULT,
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


## An ability that does nothing yet still has to say so. `pass` is the first
## line of every body somebody has started and not finished, and a tool that
## cannot open one cannot be opened while the work is being done.
const NOTHING_MARK: String = "pass"

## The two words for yes and no, which are values a match arm can be written
## as and are not identifiers.
const TRUE_MARK: String = "true"
const FALSE_MARK: String = "false"

## The characters a written-out string can start and end with, and the two
## letters that can stand in front of one.
const QUOTES: String = "\"'"
const STRING_PREFIXES: String = "&^"


## What ends a match arm, and the arm that takes whatever is left.
const CASE_END: String = ":"
const WILDCARD_MARK: String = "_"

## Why an arm this tool cannot draw is turned away, in the words a person
## needs to fix it.
const COMPLEX_PATTERN: String = (
	"a match arm here is one name, one written-out value, or _"
)

## The exact comments that make a line Composer's rather than a person's.
##
## Reserved on purpose and matched whole: `if false:` written by hand is a
## branch somebody meant, and reading it as machinery would take their code off
## the canvas. The detached marker carries a number so a file can hold several
## unplugged islands and each one can be found again.
const DETACHED_MARK: String = "# @composer-detached "
const FLOW_STOP_MARK: String = "# @composer-flow-stop"
const DETACHED_OPENER: String = "if false: "

## The two boundaries the Composer writes to cut a path that used to fall
## through. An `else` or a `_:` carrying one of these was put there by this
## tool and comes out again when the path is reconnected; one without a mark is
## somebody's own and is never removed.
const FLOW_ELSE_MARK: String = "# @composer-flow-else"
const FLOW_DEFAULT_MARK: String = "# @composer-flow-default"

## The two openers other modules name as well: `elif` draws as a branch, and a
## `return` carries its value on the line rather than in brackets.
const IF_OPENER: String = "if "
const ELIF_OPENER: String = "elif "
const ELSE_OPENER: String = "else:"
const RETURN_OPENER: String = "return"

## What separates a method's parameters from what it hands back.
const RETURNS_MARK: String = "->"

## Openers whose shape is enough to name them.
const OPENERS: Array[Array] = [
	["match ", Kind.MATCH],
	[ELIF_OPENER, Kind.BRANCH_ELSE],
	[IF_OPENER, Kind.BRANCH],
	[RETURN_OPENER, Kind.RETURN],
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
	if text.ends_with(FLOW_ELSE_MARK):
		verdict.kind = Kind.FLOW_ELSE
		return verdict
	if text.ends_with(FLOW_DEFAULT_MARK):
		verdict.kind = Kind.FLOW_DEFAULT
		return verdict

	if ComposerLine.code_of(text).strip_edges() == ELSE_OPENER:
		verdict.kind = Kind.BRANCH_ELSE
		return verdict

	for opener: Array in OPENERS:
		var begins: String = opener[0]
		if text.begins_with(begins):
			verdict.kind = opener[1]
			return _checked(verdict, text)

	var head: String = ComposerLine.code_of(text).strip_edges()
	if _is_match_case(head):
		verdict.kind = Kind.MATCH_CASE
		return verdict
	# Anything else ending in a colon down here is a match arm written as
	# something cleverer than one value: an array of patterns, a dictionary,
	# several patterns on one line, a binding. Named rather than left to the
	# catch-all below, because "not a call, a local, an assignment, a branch or
	# a return" is true of every arm and tells the person nothing.
	if head.ends_with(CASE_END):
		verdict.reason = COMPLEX_PATTERN
		return verdict
	if text == NOTHING_MARK:
		verdict.kind = Kind.NOTHING
		return verdict
	if _is_call(text):
		verdict.kind = Kind.CALL
		return verdict
	if ComposerLine.scan(text).assign > 0:
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


## Whether that kind is one of the two boundaries this tool writes.
static func is_a_boundary(kind: ComposerSubset.Kind) -> bool:
	return kind == Kind.FLOW_ELSE or kind == Kind.FLOW_DEFAULT


## Whether a line is one arm of a `match`: a name, a written-out value, or
## the catch-all.
##
## A value is admitted because `1:` and `"idle":` are ordinary GDScript and
## the card draws the arm by the text of the pattern either way. What stays
## out is every pattern that is more than one value - an array, a dictionary,
## several on a line, a binding - because the projection gives a match one
## output per arm and those arms bind names the graph has nowhere to show.
static func _is_match_case(text: String) -> bool:
	if not text.ends_with(":"):
		return false
	var head: String = text.left(text.length() - 1).strip_edges()
	if head == WILDCARD_MARK:
		return true
	return (
		head.is_valid_identifier() or _is_dotted_name(head) or _is_written_value(head)
	)


## Whether `text` is a value written out in full rather than named.
static func _is_written_value(text: String) -> bool:
	if text.is_valid_int() or text.is_valid_float():
		return true
	if text == TRUE_MARK or text == FALSE_MARK:
		return true
	var quoted: String = text.lstrip(STRING_PREFIXES)
	return (
		quoted.length() >= 2
		and QUOTES.contains(quoted.left(1))
		and quoted.right(1) == quoted.left(1)
	)


static func _is_dotted_name(text: String) -> bool:
	var parts: PackedStringArray = text.split(".")
	if parts.size() < 2:
		return false
	for part: String in parts:
		if not part.is_valid_identifier():
			return false
	return true


static func _is_call(text: String) -> bool:
	var open: int = text.find("(")
	if open <= 0 or not text.ends_with(")"):
		return false
	var name: String = text.substr(0, open)
	if not (name.is_valid_identifier() or _is_dotted_name(name)):
		return false

	var inside: ComposerLine.Brackets = ComposerLine.scan(text.substr(open + 1, text.length() - open - 2))
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


## The type the entry point declares it returns, or nothing when it declares
## none.
##
## Read off the signature the body was found under, not off the running class:
## the file already says it, and asking the engine would be asking a second
## authority about the first.
static func entry_return_type(lines: PackedStringArray) -> StringName:
	var signature: int = _signature_line(lines)
	if signature < 0:
		return &""
	var text: String = lines[signature]
	var arrow: int = text.find(RETURNS_MARK)
	var colon: int = text.rfind(":")
	if arrow < 0 or colon < arrow:
		return &""
	var start: int = arrow + RETURNS_MARK.length()
	return StringName(text.substr(start, colon - start).strip_edges())
#endregion
