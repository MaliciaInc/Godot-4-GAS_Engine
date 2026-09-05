## The body of an ability, cut into the statements it is made of.
##
## One line is not one statement: a call whose brackets have not closed runs on
## into the line below it, and a comment or a blank belongs to whatever comes
## next. Answering that is a different question from answering what a single
## line is, which is what `ComposerSubset` is for, and the two were one file
## until the file grew past the size this project keeps one to.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerStatements extends RefCounted


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
static func of(lines: PackedStringArray, span: ComposerSpan) -> Array[Statement]:
	var found: Array[Statement] = []
	if not span.is_valid():
		return found

	var line: int = span.first_line
	while line <= span.last_line:
		var made: Statement = Statement.new()
		made.first = line
		made.last = _statement_end(lines, line, span.last_line)
		made.text = _joined(lines, made.first, made.last)
		made.verdict = ComposerSubset.classify(made.text)
		found.append(made)
		line = made.last + 1
	return found


## The last line of the statement that starts at `first`.
##
## A statement whose brackets have not closed runs on into the line below it.
static func _statement_end(lines: PackedStringArray, first: int, limit: int) -> int:
	var last: int = first
	var text: String = lines[first - 1]
	while last < limit and ComposerLine.scan(text).depth > 0:
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
			"no %s() to draw" % ComposerSubset.ENTRY_POINT, ComposerSpan.new()
		)

	for made: Statement in of(lines, span):
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
