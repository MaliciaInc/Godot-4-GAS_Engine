## The ability being edited: its text, its graph, and everything you can do to it.
##
## One string is the whole state. The graph is read out of it, the canvas is
## drawn from the graph, and undo is the string from before - so there is nothing
## to keep in step, and nothing that can fall out of step. Every operation here
## produces a new string and hands it to one door, which reads it back before
## accepting it.
##
## That door is the important part. An edit that would leave a file the Composer
## cannot read is refused **before** it happens: the alternative is a blank
## canvas and an explanation, and a person holding a file they can no longer see
## is not somebody an explanation helps.
##
## Nothing here draws, and nothing here announces. A screen asks it to change
## and then redraws, in that order and on purpose: an announcement would be
## redrawn whenever the emitter happened to run, and a caller that wanted to
## know the canvas had caught up would have nothing to wait on.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerDocument extends RefCounted

const NOTHING_OPEN: String = "no ability is open"
const BROKE_IT: String = "that would leave a file the Composer cannot read"
const NOT_WRITABLE: String = "%s cannot be written to"

var _source: String = ""
var _path: String = ""
var _graph: ComposerGraph = null
var _history: ComposerHistory = ComposerHistory.new()


#region What is open
func open(source: String, path: String) -> void:
	_source = source
	_path = path
	_graph = ComposerReader.read(source, path)
	_history.forget()


func graph() -> ComposerGraph:
	return _graph


## The file as it stands, edits and all. What a save would write.
func printed() -> String:
	return _source


func path() -> String:
	return _path


func history() -> ComposerHistory:
	return _history


func is_open() -> bool:
	return _graph != null


## Whether this may be changed at all. A file outside the subset opens to be
## looked at and nothing more.
func may_write() -> bool:
	return _graph != null and _graph.is_editable()
#endregion


#region Going somewhere new, or refusing to
## Take the file to `next`, or leave it exactly where it was and say why.
func commit(next: String) -> ComposerGraph.Diagnostic:
	if _graph == null:
		return ComposerWriter.refuse(NOTHING_OPEN)
	# A change that changes nothing is not one. Recorded anyway, it would give
	# somebody an undo that appears to do nothing and puts the edit they meant
	# to reach one step further away.
	if next == _source:
		return null
	var read: ComposerGraph = ComposerReader.read(next, _path)
	if not read.is_editable():
		return ComposerWriter.refuse(BROKE_IT)

	_history.record(_source)
	_source = next
	_graph = read
	return null


## Back one step, and forward again.
##
## Putting the text back puts everything back: the nodes, the cables, the marks
## and where each card sits are all read out of it again. There is no stack of
## operations that each know how to undo themselves, so there is none that knows
## wrongly.
func undo() -> void:
	if _history.can_undo():
		_replace(_history.undo(_source))


func redo() -> void:
	if _history.can_redo():
		_replace(_history.redo(_source))


func _replace(next: String) -> void:
	_source = next
	_graph = ComposerReader.read(next, _path)
#endregion


#region Changing it
## Take those statements out, and leave a body behind.
##
## GDScript will not parse a method with an empty body, and a tool that breaks
## somebody's script by deleting the last node is not one they open again.
func remove(spans: Array[ComposerSpan]) -> ComposerGraph.Diagnostic:
	return commit(ComposerEdits.keep_a_body(ComposerEdits.remove(_source, spans)))


func repeat(spans: Array[ComposerSpan]) -> ComposerGraph.Diagnostic:
	return commit(ComposerEdits.repeat(_source, spans))


## Give one statement a visual position without changing where it executes.
##
## The position is written into the same GDScript as a reserved comment. Reading
## the resulting text back is still the authority, so Undo/Redo and reopening
## the file need no parallel state.
func place(node_id: StringName, position: Vector2) -> ComposerGraph.Diagnostic:
	var one: Dictionary[StringName, Vector2] = {node_id: position}
	return place_many(one)


## Put several cards where they were left, as one change.
##
## One commit for the whole gesture. Somebody who dragged four selected cards did
## one thing, and four steps to take it back would be three more than they made -
## which is what a placement per node produced.
##
## A card that is no longer in the ability is skipped rather than refused: the
## positions arrive from a canvas that was drawn a moment ago, and a redraw in
## between is not somebody's mistake.
func place_many(
	positions: Dictionary[StringName, Vector2]
) -> ComposerGraph.Diagnostic:
	if not may_write():
		return ComposerWriter.refuse(NOTHING_OPEN)
	return commit(
		ComposerLayoutMetadata.positioned_many(_source, _graph, positions)
	)


func insert(written: String, after: int) -> ComposerGraph.Diagnostic:
	if written.strip_edges().is_empty():
		return ComposerWriter.refuse(BROKE_IT)
	return commit(ComposerEdits.insert_after(_source, after, written))


## The text those statements are made of.
func copy(spans: Array[ComposerSpan]) -> String:
	return ComposerLayoutMetadata.without_layout_text(
		ComposerEdits.lines_of(_source, spans)
	)


## The line something new goes in after: the last of `spans`, or the end of the
## body when there are none.
func after(spans: Array[ComposerSpan]) -> int:
	var last: int = 0
	for span: ComposerSpan in spans:
		last = maxi(last, span.last_line)
	if last > 0:
		return last
	var body: ComposerSpan = ComposerSubset.body_span(_source.split("\n"))
	return body.last_line if body.is_valid() else 0
#endregion


#region Reaching the disk
## Write the file.
##
## Every edit already went through the writer and was read back before it was
## accepted, so there is nothing left to verify here - only to put the file
## where the text already is.
##
## A file the Composer cannot draw is not written at all. Identical bytes are
## still a write: a timestamp moves, anything watching wakes up, and the promise
## was that such a file is never touched, not nearly never.
func save() -> ComposerGraph.Diagnostic:
	if _graph == null:
		return ComposerWriter.refuse(NOTHING_OPEN)
	if not _graph.is_editable():
		return ComposerWriter.refuse(_graph.blocked_reason())
	if not FileAccess.file_exists(_path):
		return ComposerWriter.refuse(ComposerCatalog.NO_SCRIPT % _path)

	var out: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if out == null:
		return ComposerWriter.refuse(NOT_WRITABLE % _path)
	out.store_string(_source)
	out.close()
	return null
#endregion
