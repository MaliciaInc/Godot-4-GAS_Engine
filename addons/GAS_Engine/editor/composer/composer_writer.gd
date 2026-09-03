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
## @meta_license: MIT
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
	if entry == null:
		return ""
	var receiver: String = ComposerTypes.name_reaching(entry.source, path)
	var written: String = String(entry.type_id)
	if not receiver.is_empty():
		written = "%s.%s" % [receiver, written]
	var call: String = "%s()" % written
	if entry.awaits:
		call = AWAIT_MARK + call
	return TAB + call


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

	var rebuilt: String = TAB.repeat(maxi(node.indent, 1)) + node.prefix
	if node.awaits:
		rebuilt += AWAIT_MARK
	var written: String = String(node.type_id)
	if not node.receiver.is_empty():
		written = "%s.%s" % [node.receiver, written]
	rebuilt += "%s(%s)" % [written, _arguments(node)]

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


static func _arguments(node: ComposerNode) -> String:
	var written: PackedStringArray = PackedStringArray()
	for field: ComposerNode.Field in node.fields:
		written.append(field.display)
	return ", ".join(written)


## The body, as lines.
##
## Nodes in the order the graph holds them, which is the order they were read
## in and the order they run. A clean node hands back its own lines - including
## the blanks and comments it carried - so the file's shape survives.
static func print_body(graph: ComposerGraph) -> PackedStringArray:
	var body: PackedStringArray = PackedStringArray()
	for node: ComposerNode in graph.nodes:
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

	var spliced: String = _splice(lines, span, print_body(graph))
	if not verify:
		result.text = spliced
		return result

	var verdict: ComposerGraph.Diagnostic = _verify(graph, spliced, graph.source_path)
	if verdict != null:
		result.refusal = verdict
		return result

	result.text = spliced
	return result


## Everything before the body, the new body, everything after. The two ends are
## copied, never rewritten, which is the whole promise about the rest of the file.
static func _splice(
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
