## The Ability Composer, assembled.
##
## The top bar reads `Code │ Ability Composer`, and that is the whole design
## stated in two words. They are two views of one thing: clicking between them
## changes what you look at, never what runs. A product offering a "code mode"
## and a "visual mode" would be promising two systems; these are two windows onto
## the same file.
##
## Everything below is arranged by hand rather than by containers. The inspector
## collapses and the canvas has to take the width back, which a container would
## do by resizing the canvas' children too - and the cards are placed in world
## coordinates the layout decided, not by any container.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerScreen extends Control

const NOTHING_TO_SAVE: String = "no ability is open"
const BROKE_IT: String = "that would leave a file the Composer cannot read"
## Borrowed: a path that holds nothing is one fact, and a second spelling of it
## is a second thing to keep true.
const NO_FILE: String = ComposerCatalog.NO_SCRIPT
const NOT_WRITABLE: String = "%s cannot be written to"
const SAVE_REFUSED: String = "GAS_Engine: the Composer did not save - %s"

const TOP_BAR: float = 54.0
const PALETTE_WIDTH: float = 250.0
const INSPECTOR_WIDTH: float = 290.0
const OUTPUT_HEIGHT: float = 132.0

## Asked for when someone clicks `Code`. The screen does not open the script
## itself: the plugin owns the editor, and a view that reached for it would be a
## view that knows about Godot's docks.
signal code_requested(source_path: String)

var _top: ComposerTopBar = null
var _graph: ComposerGraph = null

## The file as it stands, saved or not. The graph is read out of this and
## nothing else, so the two cannot describe different abilities.
var _source: String = ""

var _history: ComposerHistory = ComposerHistory.new()
var _chords: Dictionary[int, Callable] = {}
var _palette: ComposerPalette = null
var _canvas: ComposerCanvas = null
var _inspector: ComposerInspector = null
var _output: ComposerOutput = null


func _ready() -> void:
	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_top = ComposerTopBar.new()
	_top.size = Vector2(size.x, TOP_BAR)
	_top.code_requested.connect(_on_code_pressed)
	add_child(_top)

	_palette = ComposerPalette.new()
	_palette.size = Vector2(PALETTE_WIDTH, size.y - TOP_BAR)
	add_child(_palette)

	_canvas = ComposerCanvas.new()
	add_child(_canvas)

	_inspector = ComposerInspector.new()
	_inspector.size = Vector2(INSPECTOR_WIDTH, size.y - TOP_BAR)
	_inspector.collapsed_changed.connect(func _shifted(_shut: bool) -> void: _arrange())
	add_child(_inspector)

	_output = ComposerOutput.new()
	add_child(_output)

	# Connected after every panel exists, not as each one is built: wiring a
	# panel to one that has not been made yet reads as done and is not.
	_canvas.selection_changed.connect(_on_selection_changed)
	_output.row_picked.connect(_on_row_picked)
	_inspector.value_edited.connect(_on_value_edited)
	_palette.node_picked.connect(_on_node_picked)

	_build_chords()
	resized.connect(_arrange)
	_arrange()




#region Showing a graph
## Hand the same graph to everything that draws part of it.
##
## One call, so the canvas and the output cannot end up describing different
## files - which is the failure a person notices last and trusts least.
func show_graph(graph: ComposerGraph) -> void:
	_graph = graph
	_top.show_graph(graph)
	# Opening a file is when a person looks at the palette, so it is when the
	# panel finds out about anything a game registered since it was built.
	_palette.refresh()
	_output.show_graph(graph)
	_inspector.show_node(null)
	await _canvas.show_graph(graph)


## The Inspector shows whatever is picked on the canvas.
##
## One card at a time: with several picked there is no single set of fields to
## show, and inventing something to fill the panel would be the panel making
## something up. The first is the one nearest the start of the graph.
func _on_selection_changed(picked: Array[StringName]) -> void:
	_inspector.show_node(
		_graph.find_node(picked[0]) if not picked.is_empty() and _graph != null else null,
		_graph != null and _graph.is_editable()
	)


## A row in the Output panel is a place in the graph, not just a message.
func _on_row_picked(node_id: StringName, _line: int) -> void:
	_canvas.reveal(node_id)


## Open a file.
##
## The text is held, not just the graph read out of it. Everything the canvas
## shows is worked out from this string, so an edit is a new string and undo is
## the old one - there is nothing else to keep in step and nothing that can fall
## out of step.
func open(source: String, path: String) -> void:
	_source = source
	_history.forget()
	await show_graph(ComposerReader.read(source, path))


## Take the file somewhere new, or refuse and leave it exactly where it was.
##
## Read before it is accepted. An edit that produced something the Composer
## cannot read would be an edit that blanks the canvas, and the person would be
## left holding a file they can no longer see - so it does not happen, and the
## reason is said out loud instead.
func _commit(next: String) -> bool:
	if _graph == null:
		return false
	var read: ComposerGraph = ComposerReader.read(next, _graph.source_path)
	if not read.is_editable():
		push_error(SAVE_REFUSED % BROKE_IT)
		return false

	_history.record(_source)
	_source = next
	await show_graph(read)
	return true


## Back one step, and forward again.
##
## Putting the text back puts everything back: the nodes, the cables, the marks
## and where each card sits are all read out of it again. There is no stack of
## operations that each know how to undo themselves, so there is no operation
## that knows wrongly.
func undo() -> void:
	if not _history.can_undo():
		return
	var back: String = _history.undo(_source)
	_source = back
	await show_graph(ComposerReader.read(back, _graph.source_path))


func redo() -> void:
	if not _history.can_redo():
		return
	var forward: String = _history.redo(_source)
	_source = forward
	await show_graph(ComposerReader.read(forward, _graph.source_path))


func history() -> ComposerHistory:
	return _history


#region Statements, as things you can move about
## The spans of what is picked, in the order the file has them.
func _picked_spans() -> Array[ComposerSpan]:
	var found: Array[ComposerSpan] = []
	if _graph == null:
		return found
	for id: StringName in _canvas.picked():
		var node: ComposerNode = _graph.find_node(id)
		if node != null:
			found.append(node.span)
	return found


## Take the picked statements out.
##
## A body with nothing left in it still has to say so, or the file stops
## parsing - and a tool that breaks somebody's script by deleting the last node
## is not one they open again.
func remove_picked() -> bool:
	var spans: Array[ComposerSpan] = _picked_spans()
	if spans.is_empty():
		return false
	return await _commit(
		ComposerEdits.keep_a_body(ComposerEdits.remove(_source, spans))
	)


func repeat_picked() -> bool:
	var spans: Array[ComposerSpan] = _picked_spans()
	if spans.is_empty():
		return false
	return await _commit(ComposerEdits.repeat(_source, spans))


## The picked statements, as the text they are.
##
## The system clipboard, not one of our own: a statement is GDScript, and
## somebody who copies one here should be able to paste it into the script
## editor beside this one.
func copy_picked() -> String:
	var spans: Array[ComposerSpan] = _picked_spans()
	if spans.is_empty():
		return ""
	var taken: String = ComposerEdits.lines_of(_source, spans)
	DisplayServer.clipboard_set(taken)
	return taken


## Put whatever is on the clipboard in after what is picked.
##
## Anything at all may be on it, so the result is read before it is accepted
## like every other edit. Text that does not belong in an ability body is
## refused rather than pasted and then complained about.
func paste() -> bool:
	return await paste_text(DisplayServer.clipboard_get())


## The same, told what to put in.
##
## Split from `paste` because the clipboard is how the text arrives, not what
## the operation is - and a machine with no clipboard at all should still be
## able to answer whether pasting a given statement works.
func paste_text(written: String) -> bool:
	if written.strip_edges().is_empty() or _graph == null:
		return false
	return await _commit(ComposerEdits.insert_after(_source, _after(), written))


## The line a new statement goes in after: the last one picked, or the end of
## the body when nothing is.
func _after() -> int:
	var spans: Array[ComposerSpan] = _picked_spans()
	var last: int = 0
	for span: ComposerSpan in spans:
		last = maxi(last, span.last_line)
	if last > 0:
		return last
	var body: ComposerSpan = ComposerSubset.body_span(_source.split("\n"))
	return body.last_line if body.is_valid() else 0


## A node picked out of the palette becomes a statement in the body.
func _on_node_picked(key: StringName) -> void:
	if _graph == null or not _graph.is_editable():
		return
	var written: String = ComposerWriter.call_for(
		ComposerCatalog.find(key), _graph.source_path
	)
	if written.is_empty():
		return
	await _commit(ComposerEdits.insert_after(_source, _after(), written))
#endregion


## A typed value reaches the model, and everything that draws the model is asked
## again.
##
## Redrawn rather than patched. The card's text, the dot on it and the rows in
## the Output panel all come from one pass over the graph, and reaching in to
## change one of them is how the three start disagreeing about the same node.
func _on_value_edited(node_id: StringName, position: int, written: String) -> void:
	if _graph == null or not _graph.is_editable():
		return
	var node: ComposerNode = _graph.find_node(node_id)
	if node == null or position < 0 or position >= node.fields.size():
		return
	# Asked here and not only where the box was drawn. The panel does not offer
	# one for a value that arrives on a cable, but a guard that lives only in the
	# thing that draws the control is a guard the next caller walks straight
	# past - and this is the door every one of them comes through.
	if not node.may_edit(node.fields[position]):
		return

	node.fields[position].display = written
	# A value somebody typed is a written one, whatever it was before. An
	# argument that was missing has just been supplied, and leaving it marked
	# absent would have the validator strip it back out on the next pass.
	node.fields[position].source = ComposerNode.ValueSource.LITERAL
	node.dirty = true

	var printed: ComposerWriter.Result = ComposerWriter.apply(_graph, _source)
	if not printed.is_ok():
		push_error(SAVE_REFUSED % printed.refusal.message)
		return
	var held: Array[StringName] = _canvas.picked()
	if await _commit(printed.text) and not held.is_empty():
		_canvas.reveal(held[0])


## Write the graph back to the file it came from.
##
## Everything goes through `ComposerWriter.apply`, which prints the body, reads
## it back and compares before anything reaches the disk. A save that would not
## read back as the graph it came from is refused, and the file is left exactly
## as it was - the one promise this tool cannot break and still be worth having.
##
## The file is re-read afterwards rather than assumed. Spans move when a line
## changes length, and a second save built on the first save's spans would
## splice into the wrong place.
func save() -> ComposerWriter.Result:
	var result: ComposerWriter.Result = ComposerWriter.Result.new()
	if _graph == null:
		result.refusal = ComposerWriter.refuse(NOTHING_TO_SAVE)
		return result

	if not _graph.is_editable():
		# Identical bytes are still a write: a timestamp moves, anything watching
		# the file wakes up, and the promise was that a file this cannot draw is
		# never touched. Not nearly never.
		result.refusal = ComposerWriter.refuse(_graph.blocked_reason())
		return result

	var path: String = _graph.source_path
	if not FileAccess.file_exists(path):
		result.refusal = ComposerWriter.refuse(NO_FILE % path)
		return result

	# What is written is what has been held all along. Every edit already went
	# through the writer and was read back before it was accepted, so a save has
	# nothing left to verify - it has only to put the file where the text is.
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		result.refusal = ComposerWriter.refuse(NOT_WRITABLE % path)
		return result
	out.store_string(_source)
	out.close()

	result.text = _source
	return result


## The chords, spelled the way every other editor spells them.
##
## A table of what each one does rather than a chain of branches: the chords are
## what somebody reading this came to find, and a list of them is the answer.
## Built here and not written as a constant because the values are the methods
## themselves - a name in a table is a name that goes stale the day a method is
## renamed and nothing says so.
func _build_chords() -> void:
	_chords = {
		KEY_S | KEY_MASK_CTRL: _save_now,
		KEY_Z | KEY_MASK_CTRL: undo,
		KEY_Z | KEY_MASK_CTRL | KEY_MASK_SHIFT: redo,
		KEY_Y | KEY_MASK_CTRL: redo,
		KEY_C | KEY_MASK_CTRL: copy_picked,
		KEY_V | KEY_MASK_CTRL: paste,
		KEY_D | KEY_MASK_CTRL: repeat_picked,
		KEY_DELETE: remove_picked,
	}


func _shortcut_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var chord: int = key.keycode
	if key.ctrl_pressed:
		chord |= KEY_MASK_CTRL
	if key.shift_pressed:
		chord |= KEY_MASK_SHIFT
	if not _chords.has(chord):
		return
	accept_event()
	await _chords[chord].call()


## Saving says so when it will not, because a chord that appears to do nothing
## is worse than one that explains itself.
func _save_now() -> void:
	var result: ComposerWriter.Result = await save()
	if not result.is_ok():
		push_error(SAVE_REFUSED % result.refusal.message)


## What is on screen right now.
##
## Read rather than kept by a caller: an edit replaces the graph, so anything
## holding the old one would be describing an ability that is no longer open.
## The file as it stands, edits and all. What a save would write.
func printed() -> String:
	return _source


func graph() -> ComposerGraph:
	return _graph


func canvas() -> ComposerCanvas:
	return _canvas


func inspector() -> ComposerInspector:
	return _inspector
#endregion


## Place every region. Re-run whenever the screen resizes or the inspector
## folds, since both change how much width the canvas has.
func _arrange() -> void:
	if _palette == null:
		return
	var body: float = size.y - TOP_BAR
	var right: float = _inspector.occupied_width()

	_palette.position = Vector2(0.0, TOP_BAR)
	_palette.size = Vector2(PALETTE_WIDTH, body)

	_canvas.position = Vector2(PALETTE_WIDTH + 1.0, TOP_BAR)
	_canvas.size = Vector2(
		maxf(size.x - PALETTE_WIDTH - right - 1.0, 0.0), maxf(body - OUTPUT_HEIGHT, 0.0)
	)

	_output.position = Vector2(PALETTE_WIDTH + 1.0, size.y - OUTPUT_HEIGHT)
	_output.size = Vector2(_canvas.size.x, OUTPUT_HEIGHT)

	_inspector.position = Vector2(size.x - right, TOP_BAR)
	_inspector.size = Vector2(INSPECTOR_WIDTH, body)


## The Code chip asked to leave, and only this knows where to.
func _on_code_pressed() -> void:
	code_requested.emit(_graph.source_path if _graph != null else "")
