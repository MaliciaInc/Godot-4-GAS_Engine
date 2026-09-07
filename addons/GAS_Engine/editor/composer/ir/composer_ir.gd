## A script read as what it is made of, before anything decides how to draw it.
##
## There used to be no layer here. The reader went from lines straight to cards,
## which worked until it met a line it did not understand - and then it had one
## move: refuse the file. An ability with a `for` loop in it had no Composer at
## all, for a loop the tool only needed to leave alone, and the nine statements
## around it were unreachable for the sake of the one.
##
## So reading answers a smaller question first: what IS this file. Functions,
## and inside them the events they are made of - statements the tool knows,
## regions it does not, loops, and the points where the body suspends. The graph
## is derived from this, and the writer puts this back. What the tool cannot
## draw it can still locate, which is the whole difference between "leave that
## alone" and "I cannot open this".
##
## Built out of `ComposerSubset` and `ComposerStatements`, the two that already
## decide what a line and a statement are - never out of a second pass of string
## replacement over the source. A tool that edits somebody's file by pattern
## matching is a tool that eventually edits the wrong thing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerIR extends RefCounted

const FUNC_MARK: String = "func "
const OPENS_BLOCK: String = ":"

var source_path: String = ""
var lines: PackedStringArray = PackedStringArray()

## Every function in the file, in the order they are written.
var functions: Array[ComposerIRFunction] = []


## Read a script into its IR. Always answers; a file with no functions in it is
## an IR with no functions in it.
static func of(source: String, path: String) -> ComposerIR:
	var made: ComposerIR = ComposerIR.new()
	made.source_path = path
	made.lines = source.split("\n")

	for signature: int in made._signature_lines():
		made.functions.append(made._function_at(signature))
	return made


## The function the Composer draws, or null when the file has none.
func entry() -> ComposerIRFunction:
	for made: ComposerIRFunction in functions:
		if made.is_entry_point():
			return made
	return null


func function_named(wanted: StringName) -> ComposerIRFunction:
	for made: ComposerIRFunction in functions:
		if made.declared_name == wanted:
			return made
	return null


#region Finding functions
## Every line that opens a function, in order.
##
## At any indent: a function nested inside a class declared in the same file is
## still a function, and skipping it would leave its body read as though it
## belonged to whatever came before.
func _signature_lines() -> Array[int]:
	var found: Array[int] = []
	for index: int in lines.size():
		if _names_a_function(lines[index]):
			found.append(index)
	return found


static func _names_a_function(line: String) -> bool:
	var text: String = line.strip_edges()
	return text.begins_with(FUNC_MARK) and text.ends_with(OPENS_BLOCK)


## What the signature on `signature` is called.
func _declared_name(signature: int) -> StringName:
	var text: String = lines[signature].strip_edges().substr(FUNC_MARK.length())
	var bracket: int = text.find("(")
	return StringName(text.left(bracket).strip_edges() if bracket > 0 else text)


## The one-based span of the body under `signature`.
##
## Blank lines and comments inside a body belong to it; the body ends at the
## first line that is neither and is no further in than the signature. Kept
## one-based to match `ComposerSpan` everywhere else, so nothing has to convert
## between two ideas of where line one is.
func _body_span(signature: int) -> ComposerSpan:
	var depth: int = ComposerSubset.indent_of(lines[signature])
	var last: int = signature
	for index: int in range(signature + 1, lines.size()):
		var text: String = lines[index].strip_edges()
		if text.is_empty() or text.begins_with("#"):
			continue
		if ComposerSubset.indent_of(lines[index]) <= depth:
			break
		last = index

	if last == signature:
		return ComposerSpan.new()
	return ComposerSpan.new(signature + 2, last + 1)
#endregion


#region Cutting a body into events
func _function_at(signature: int) -> ComposerIRFunction:
	var made: ComposerIRFunction = ComposerIRFunction.new()
	made.declared_name = _declared_name(signature)
	made.signature_line = signature + 1
	made.body = _body_span(signature)
	made.returns = _returns_of(signature)
	if made.body.is_valid():
		_fill_events(made)
	return made


func _returns_of(signature: int) -> StringName:
	var text: String = lines[signature]
	var arrow: int = text.find("->")
	var colon: int = text.rfind(OPENS_BLOCK)
	if arrow < 0 or colon < arrow:
		return &""
	var start: int = arrow + 2
	return StringName(text.substr(start, colon - start).strip_edges())


## Walk the body once, and let each statement claim what belongs to it.
##
## A statement outside the subset takes the block under it as well, when it
## opens one - that is what makes a loop one region rather than a header
## followed by a run of lines nobody can place.
func _fill_events(made: ComposerIRFunction) -> void:
	var statements: Array[ComposerStatements.Statement] = ComposerStatements.of(
		lines, made.body
	)
	var carried: int = ComposerSpan.NO_LINE
	var skip_past: int = ComposerSpan.NO_LINE

	for statement: ComposerStatements.Statement in statements:
		if skip_past != ComposerSpan.NO_LINE and statement.first <= skip_past:
			continue
		skip_past = ComposerSpan.NO_LINE

		if not statement.verdict.is_drawn() and statement.verdict.is_representable():
			# A comment or a blank belongs to whatever comes next, which is how
			# a person reads them and how the writer puts them back.
			if carried == ComposerSpan.NO_LINE:
				carried = statement.first
			continue

		var first: int = carried if carried != ComposerSpan.NO_LINE else statement.first
		carried = ComposerSpan.NO_LINE

		if statement.verdict.is_representable():
			made.events.append(_statement_event(statement, first))
			_note_async_exit(made, statement)
			continue

		var opaque: ComposerIREvent = _opaque_event(made, statement, first)
		made.events.append(opaque)
		skip_past = opaque.span.last_line


func _statement_event(
	statement: ComposerStatements.Statement, first: int
) -> ComposerIREvent:
	var event: ComposerIREvent = ComposerIREvent.new()
	event.shape = ComposerIREvent.Shape.STATEMENT
	event.span = ComposerSpan.new(first, statement.last)
	event.statement_line = statement.first
	event.text = statement.text.strip_edges()
	event.kind = statement.verdict.kind
	event.statement = statement
	return event


## An event for a region the tool does not understand, ending where the region
## ends rather than where its first line does.
func _opaque_event(
	made: ComposerIRFunction, statement: ComposerStatements.Statement, first: int
) -> ComposerIREvent:
	var event: ComposerIREvent = ComposerIREvent.new()
	event.shape = ComposerIREvent.Shape.OPAQUE
	event.statement_line = statement.first
	event.text = statement.text.strip_edges()
	event.kind = statement.verdict.kind
	event.reason = statement.verdict.reason
	event.statement = statement

	var last: int = statement.last
	if event.text.ends_with(OPENS_BLOCK):
		last = _block_end(statement.last, statement.verdict.indent, made.body.last_line)
	event.span = ComposerSpan.new(first, last)

	if ComposerIRLoop.opens_one(event.text):
		# Kept as its own thing as well as an event. "Can this be drawn" and
		# "where does this stop being drawable" are two questions, and answering
		# the second by filtering the first means every caller re-derives what a
		# loop looks like. The reason stays the subset's own words: it is the one
		# place that says why, and a second wording here would be a second answer.
		made.loops.append(_loop_for(event, statement))
	return event


func _loop_for(
	event: ComposerIREvent, statement: ComposerStatements.Statement
) -> ComposerIRLoop:
	var loop: ComposerIRLoop = ComposerIRLoop.new()
	loop.sort = ComposerIRLoop.sort_of(event.text)
	loop.header = event.text
	loop.span = ComposerSpan.new(statement.first, event.span.last_line)
	loop.indent = statement.verdict.indent
	return loop


## The last line of the block opened on `header`, which is everything further in
## than the header itself.
func _block_end(header: int, indent: int, limit: int) -> int:
	var last: int = header
	for index: int in range(header + 1, limit + 1):
		var text: String = lines[index - 1].strip_edges()
		if text.is_empty() or text.begins_with("#"):
			continue
		if ComposerSubset.indent_of(lines[index - 1]) <= indent:
			break
		last = index
	return last


func _note_async_exit(
	made: ComposerIRFunction, statement: ComposerStatements.Statement
) -> void:
	if not ComposerIRAsyncExit.suspends(statement.text):
		return
	var exit: ComposerIRAsyncExit = ComposerIRAsyncExit.new()
	exit.span = ComposerSpan.new(statement.first, statement.last)
	exit.text = statement.text.strip_edges()
	exit.awaited = ComposerIRAsyncExit.awaited_in(statement.text)
	made.async_exits.append(exit)
#endregion
