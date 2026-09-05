## A graph back into the file it came from.
##
## The dangerous half. A reader that misunderstands a file draws it wrong; a
## writer that misunderstands one destroys it. Everything here is arranged so
## that the second cannot happen quietly.
##
## Three rules do the work:
##
## - **Only the body is written.** Everything outside `_activate_ability()` -
##   exports, constants, helpers, the comments someone wrote at the top - is
##   spliced back byte for byte. The writer never sees it as text it may change.
## - **An untouched node is reprinted, not rebuilt.** A node keeps the lines it
##   was read from, so a save changes only what someone actually edited. A tool
##   that reformats the file on every save is a tool people stop saving with.
## - **Nothing reaches disk unverified.** The result is printed to memory, read
##   back with the reader, and compared against the graph that produced it. If
##   the two disagree, the write is refused and the file is left alone.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerWriter extends RefCounted

const TAB: String = "\t"
const AWAIT_MARK: String = "await "


## The text to save, or the reason it was refused.
##
## Never both. A caller that gets text may write it; a caller that gets a
## refusal has a file that was not touched and a message saying why.
class Result extends RefCounted:
	var text: String = ""
	var refusal: ComposerGraph.Diagnostic = null

	func is_ok() -> bool:
		return refusal == null


#region Printing
## The line a call from the palette becomes, in the file it is being put into.
##
## A call has to be written on the thing it is a method of, and which thing that
## is depends on the file: on the ability itself it is written bare, on the
## ability system it is written on the property that holds one, and on a class
## with static methods it is written on the class. Read from the file rather
## than assumed, because a game's ability may name its own things differently.
##
## Empty when there is nothing to write - no entry, or nothing in the file that
## the call could be made on. Guessing a receiver would produce a line that does
## not compile, put there by the tool rather than by the person.
static func call_for(entry: ComposerCatalog.Entry, path: String) -> String:
	return ComposerStatementFactory.call_statement(entry, path)


## One statement, rebuilt from the model.
##
## Used only for a node someone edited. Everything else keeps the text it came
## with, so this is the narrow path where the Composer's idea of a statement
## becomes the file's - and the narrower it stays, the less there is to get
## wrong.
static func render(node: ComposerNode) -> String:
	if node.type_id.is_empty():
		# A branch, a return, a wait on a signal: there is no call here, and
		# printing `()` for one would replace a person's line with nothing.
		return "\n".join(node.source_text)

	var rebuilt: String = render_with_field_overrides(node, {})

	# A statement that came wrapped across lines and still says exactly what it
	# said keeps the wrapping the person chose. Only one the Composer actually
	# changed is reflowed, and then onto one line - the project declares no width
	# to wrap at, and picking one here would be this tool imposing a style on
	# somebody else's file.
	if node.source_text.size() > 1 and _same_statement(rebuilt, node.source_text):
		return "\n".join(node.source_text)
	return rebuilt


## Whether a rebuilt statement says what the lines it came from said.
##
## Compared with the runs of whitespace collapsed, because that is the only
## difference wrapping makes - a line break and an indent where a space would
## otherwise be.
static func _same_statement(rebuilt: String, source: PackedStringArray) -> bool:
	return _flattened(rebuilt) == _flattened(" ".join(source))


static func _flattened(text: String) -> String:
	var flat: String = text.replace(TAB, " ").strip_edges()
	while flat.contains("  "):
		flat = flat.replace("  ", " ")
	return flat.replace("( ", "(").replace(" )", ")")


## One statement, rebuilt with some of its arguments replaced.
##
## Pure on purpose: nothing here marks the node dirty and nothing here touches
## its fields. A field edit has to be able to ask "what would this statement
## look like" and then refuse, and a renderer that changed the node on the way
## would leave the refusal drawn on the canvas.
##
## Keyed by field index rather than by label: two arguments of one call can be
## called the same thing, and position is what the language goes by.
static func render_with_field_overrides(
	node: ComposerNode, overrides: Dictionary[int, String]
) -> String:
	var rebuilt: String = TAB.repeat(maxi(node.indent, 1)) + node.prefix
	if node.awaits:
		rebuilt += AWAIT_MARK
	var called: String = String(node.type_id)
	if not node.receiver.is_empty():
		called = "%s.%s" % [node.receiver, called]
	return rebuilt + "%s(%s)" % [called, _arguments(node, overrides)]


## What one field is written as.
##
## A field the file passes is written as what it passes. A required one the
## file left out is written as its declared default, or as the zero of its
## type - because rebuilding a call around an empty string produces
## `apply(, 2.0)`, which is not a statement, and the reread that follows would
## refuse the whole edit rather than the one argument.
static func field_source(field: ComposerNode.Field) -> String:
	if field.is_satisfied():
		return field.display
	if not field.default_expression.is_empty():
		return field.default_expression
	return ComposerTypes.default_expression(field.type_name, field.variant_type)


static func _arguments(
	node: ComposerNode, overrides: Dictionary[int, String] = {}
) -> String:
	var written: PackedStringArray = PackedStringArray()
	for position: int in node.fields.size():
		written.append(
			overrides[position] if overrides.has(position)
			else field_source(node.fields[position])
		)
	return ", ".join(written)


## The body, as lines.
##
## Nodes in the order the graph holds them, which is the order they were read
## in and the order they run. A clean node hands back its own lines - including
## the blanks and comments it carried - so the file's shape survives.
static func print_body(graph: ComposerGraph) -> PackedStringArray:
	var body: PackedStringArray = PackedStringArray()
	for node: ComposerNode in graph.nodes:
		# Entry is where the method begins, not a line of it. It is in the graph
		# so the canvas has somewhere to start a wire; asking the writer to print
		# it would put a card into the file.
		if not node.source_backed:
			continue
		# Whatever the node picked up on the way in goes back out untouched,
		# edited or not. A rebuilt statement says nothing about the comment
		# above it, so printing only the statement is how that comment is lost.
		for line: String in node.carried:
			body.append(line)
		if node.dirty or node.source_text.is_empty():
			body.append(render(node))
			continue
		for line: String in node.source_text:
			body.append(line)
	return body
#endregion


#region Saving
## Splice the printed body into `source`, then prove the result reads back the
## same before handing it over.
static func apply(graph: ComposerGraph, source: String, verify: bool = true) -> Result:
	var result: Result = Result.new()
	if graph == null or not graph.is_editable():
		result.refusal = refuse("a file this tool cannot draw is not one it may write")
		return result

	var lines: PackedStringArray = source.split("\n")
	var span: ComposerSpan = ComposerSubset.body_span(lines)
	if not span.is_valid():
		result.refusal = refuse("no %s() to write into" % ComposerSubset.ENTRY_POINT)
		return result

	var rebuilt: String = spliced(lines, span, print_body(graph))
	if not verify:
		result.text = rebuilt
		return result

	var verdict: ComposerGraph.Diagnostic = _verify(graph, rebuilt, graph.source_path)
	if verdict != null:
		result.refusal = verdict
		return result

	result.text = rebuilt
	return result


## Everything before the body, the new body, everything after. The two ends are
## copied, never rewritten, which is the whole promise about the rest of the file.
##
## Public because a field edit replaces the lines of one statement the same way
## a save replaces the lines of a body, and two functions that cut a file into
## three pieces are two chances to be off by one at the seam.
static func spliced(
	lines: PackedStringArray, span: ComposerSpan, body: PackedStringArray
) -> String:
	var out: PackedStringArray = PackedStringArray()
	out.append_array(lines.slice(0, span.first_line - 1))
	out.append_array(body)
	out.append_array(lines.slice(span.last_line))
	return "\n".join(out)


## Read the printed text back and compare it to what was printed.
##
## This is the guard the whole design leans on. A printer that drops a field or
## reorders an argument produces a file that still compiles and no longer does
## what the graph said - which is exactly the failure nobody notices until the
## ability misbehaves in a game.
static func _verify(
	graph: ComposerGraph, text: String, path: String
) -> ComposerGraph.Diagnostic:
	var reread: ComposerGraph = ComposerReader.read(text, path)
	if not reread.is_editable():
		return refuse("the text this produced cannot be read back: %s" % reread.blocked_reason())

	var wanted: String = signature(graph)
	var got: String = signature(reread)
	if wanted != got:
		return refuse("what this produced is not what it was given")
	return null


## What a graph is, as one comparable string.
##
## Structure only. Line numbers are left out on purpose: an edited graph
## legitimately moves its statements, and comparing spans would refuse every
## real edit while catching nothing. What must survive a round trip is which
## statements there are, what they carry, and what leads to what.
static func signature(graph: ComposerGraph) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var position: Dictionary[StringName, int] = {}
	for index: int in graph.nodes.size():
		var node: ComposerNode = graph.nodes[index]
		# The signature answers "did a semantic edit change something the reread
		# does not represent". Entry is represented by nothing, so counting it
		# would make every file differ from itself.
		if not node.source_backed:
			continue
		position[node.id] = index
		parts.append(
			"%s(%s)%s" % [
				String(node.type_id), _arguments(node), "!" if node.awaits else ""
			]
		)

	# By position, never by id. A node's id is derived from the line it was read
	# from, so wiring the signature to ids would smuggle line numbers back in
	# through the wires - and adding a blank line would read as a different
	# ability. Found by the test that says exactly that.
	var wires: PackedStringArray = PackedStringArray()
	for wire: ComposerGraph.Connection in graph.connections:
		wires.append(
			"%d.%s>%d.%s" % [
				position.get(wire.from_node, -1), wire.from_port,
				position.get(wire.to_node, -1), wire.to_port,
			]
		)
	wires.sort()

	return "|".join(parts) + "#" + "|".join(wires)


## Say no, in the one shape everything that reads a refusal already knows.
static func refuse(message: String) -> ComposerGraph.Diagnostic:
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = ComposerGraph.Severity.ERROR
	found.message = message
	return found
#endregion
