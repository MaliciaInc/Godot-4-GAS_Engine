## Reading an ability and answering with everything wrong with it, and whether
## it can be run.
##
## The two questions were one before, and being one was the problem. "Can the
## Composer draw this" and "is this ready to run" have different answers all the
## time: an ability half written is drawable and not ready; one with a `for`
## loop in it is ready and only partly drawable. A single verdict forced one of
## those to be reported as the other.
##
## So this answers both, separately, and it answers the second the way a build
## does: a list of findings, each one placed at a file and a line, each carrying
## a code somebody can filter a log by. A draft that does not compile is a draft
## - it saves, it opens, it draws - and `ready_to_run` is false until the errors
## in it are gone.
##
## Nothing is executed. The ability is read, not run: the findings come from the
## graph and from what the catalog knows about the calls in it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCompileService extends RefCounted

## Columns are one-based where they are known, and zero where they are not.
##
## A statement's own column is where its text starts, which is after the indent.
## Zero says "this finding is about the whole line", and an editor asked to go
## to column zero puts the caret at the start of it - which is right, and is
## what a finding with no column should do.
const NO_COLUMN: int = 0


## What compiling one ability produced.
class Result extends RefCounted:
	var source_path: String = ""
	var diagnostics: Array[GameplayCompileDiagnostic] = []

	## Whether this ability can be run as it stands.
	##
	## False while anything in it stops a run. Kept as a field rather than asked
	## of the list every time because it is what a caller acts on, and a caller
	## that had to re-derive it would eventually derive it differently.
	var ready_to_run: bool = false

	## Every finding that stops a run, for a caller showing them first.
	func errors() -> Array[GameplayCompileDiagnostic]:
		var found: Array[GameplayCompileDiagnostic] = []
		for finding: GameplayCompileDiagnostic in diagnostics:
			if finding.stops_a_run():
				found.append(finding)
		return found

	func has(code: StringName) -> bool:
		for finding: GameplayCompileDiagnostic in diagnostics:
			if finding.code == code:
				return true
		return false


## Compile `source` as the ability at `path`.
##
## Always answers. A file that cannot be drawn at all comes back with one
## finding saying so and `ready_to_run` false, rather than with nothing and a
## caller left to work out whether that meant "fine" or "never looked".
static func compile(source: String, path: String) -> Result:
	return of_graph(ComposerReader.read(source, path), source)


## The same answer about a graph somebody already has.
##
## The Composer has one open and re-reading the file to ask about it would be
## asking a second time and risking a different answer - the file on disk is not
## what is on screen the moment anybody has typed anything.
static func of_graph(graph: ComposerGraph, source: String) -> Result:
	var made: Result = Result.new()
	if graph == null:
		made.diagnostics.append(_about_the_file("there is no ability to compile", ""))
		return made

	made.source_path = graph.source_path
	var lines: PackedStringArray = source.split("\n")
	for found: ComposerGraph.Diagnostic in graph.diagnostics:
		made.diagnostics.append(_from(found, graph, lines))

	made.ready_to_run = made.errors().is_empty()
	return made


#region Turning one into the other
static func _from(
	found: ComposerGraph.Diagnostic, graph: ComposerGraph, lines: PackedStringArray
) -> GameplayCompileDiagnostic:
	var made: GameplayCompileDiagnostic = GameplayCompileDiagnostic.new()
	made.severity = found.severity
	made.code = found.code
	made.message = found.message
	made.source_path = graph.source_path
	made.node_id = found.node_id
	made.line = found.span.first_line if found.span.is_valid() else 0
	made.column = _column_of(lines, made.line)
	return made


## Where the text of a line starts, one-based, past the indent.
##
## A finding about a statement points at the statement rather than at the tab in
## front of it: an editor taken to column one puts the caret before the
## indentation, which is not where anybody was looking.
static func _column_of(lines: PackedStringArray, line: int) -> int:
	if line <= 0 or line > lines.size():
		return NO_COLUMN
	return ComposerSubset.indent_of(lines[line - 1]) + 1


static func _about_the_file(message: String, path: String) -> GameplayCompileDiagnostic:
	var made: GameplayCompileDiagnostic = GameplayCompileDiagnostic.new()
	made.severity = ComposerGraph.Severity.NOT_REPRESENTABLE
	made.code = GameplayCompileDiagnostic.NOT_DRAWABLE
	made.message = message
	made.source_path = path
	return made
#endregion
