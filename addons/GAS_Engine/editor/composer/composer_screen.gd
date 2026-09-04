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
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerScreen extends Control

const SAVE_REFUSED: String = "GAS_Engine: the Composer did not save - %s"

const TOP_BAR: float = 54.0
const PALETTE_WIDTH: float = 250.0
const INSPECTOR_WIDTH: float = 290.0
const OUTPUT_HEIGHT: float = 132.0

## Asked for when someone clicks `Code`. The screen does not open the script
## itself: the plugin owns the editor, and a view that reached for it would be a
## view that knows about Godot's docks.
signal code_requested(source_path: String)

## Asked for an ability to open. Forwarded, not answered: choosing a file is
## the editor's job, and a view that popped its own dialog would be a view
## that knows about Godot's docks.
signal open_requested

## Asked for a new ability file. The plugin owns filesystem/editor dialogs.
signal create_requested

var _top: ComposerTopBar = null
var _graph: ComposerGraph = null

var _doc: ComposerDocument = ComposerDocument.new()

## The one thing allowed to turn a dropped wire into GDScript. The canvas
## asks; this answers, or says why not.
var _wires: ComposerConnectionController = ComposerConnectionController.new()
var _menu: PopupMenu = null
var _finder: ComposerFinder = null
var _chords: ComposerChords = ComposerChords.new()
var _palette: ComposerPalette = null
var _canvas: ComposerCanvas = null
var _inspector: ComposerInspector = null
var _output: ComposerOutput = null


func _ready() -> void:
	# The editor's main screen is a container, and a container sizes its children
	# by these flags and ignores anchors. Without them this was given its minimum
	# height - the palette overflowed, the canvas was a strip, and the Output
	# panel sat at the top of the window. It read as half the interface missing.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_top = ComposerTopBar.new()
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

	_finder = ComposerFinder.new()
	_finder.chose.connect(_on_node_picked)
	add_child(_finder)

	# Connected after every panel exists, not as each one is built: wiring a
	# panel to one that has not been made yet reads as done and is not.
	_canvas.selection_changed.connect(_on_selection_changed)
	_canvas.nodes_positioned.connect(_on_nodes_positioned)
	_canvas.connection_requested.connect(_on_connection_requested)
	_canvas.disconnection_requested.connect(_on_disconnection_requested)
	_canvas.value_edited.connect(_on_value_edited)
	# A call dragged in from the palette is inserted exactly as a clicked one is.
	_canvas.node_requested.connect(_on_call_dropped)
	_canvas.menu_requested.connect(_on_menu_requested)
	# Every refusal the wiring can produce is said out loud in one place, so a
	# gesture that does nothing always says why it did nothing.
	_wires.bind(_doc)
	_wires.refused.connect(_on_refused)
	_output.row_picked.connect(_on_row_picked)
	_top.open_requested.connect(func _asked() -> void: open_requested.emit())
	_top.create_requested.connect(func _asked() -> void: create_requested.emit())
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
		_graph != null and _graph.is_editable(),
		_graph
	)


## A row in the Output panel is a place in the graph, not just a message.
func _on_row_picked(node_id: StringName, _line: int) -> void:
	_canvas.reveal(node_id)


## Nothing could be opened, and here is why.
##
## The screen still comes forward. A refusal that leaves the editor where it was
## is indistinguishable from a menu item that does nothing, which is how this
## was actually experienced: the console carried the reason and the person
## carried the impression that the Composer was broken.
func show_refusal(reason: String) -> void:
	await show_graph(null)
	_output.show_refusal(reason)


## Open a file.
func open(source: String, path: String) -> void:
	_doc.open(source, path)
	await _redraw()


## Draw whatever the document says now.
##
## Called after every change rather than announced by the document. An
## announcement is redrawn whenever the emitter gets round to it, and a caller
## that wanted to know the canvas had caught up would have nothing to wait on.
func _redraw() -> void:
	await show_graph(_doc.graph())


## Do it, redraw, and say so out loud when it was refused.
##
## A refusal that only returns false is one the person experiences as the tool
## ignoring them.
func _did(refusal: ComposerGraph.Diagnostic) -> bool:
	if refusal != null:
		push_error(SAVE_REFUSED % refusal.message)
		return false
	await _redraw()
	return true


func undo() -> void:
	_doc.undo()
	await _redraw()


func redo() -> void:
	_doc.redo()
	await _redraw()


func history() -> ComposerHistory:
	return _doc.history()


func printed() -> String:
	return _doc.printed()


func graph() -> ComposerGraph:
	return _doc.graph()


#region Statements, as things you can move about
## The spans of what is picked, in the order the file has them.
func _picked_spans() -> Array[ComposerSpan]:
	var found: Array[ComposerSpan] = []
	for id: StringName in _canvas.picked():
		var node: ComposerNode = _doc.graph().find_node(id) if _doc.is_open() else null
		if node != null:
			found.append(node.span)
	return found


func remove_picked() -> bool:
	var spans: Array[ComposerSpan] = _picked_spans()
	return await _did(_doc.remove(spans)) if not spans.is_empty() else false


func repeat_picked() -> bool:
	var spans: Array[ComposerSpan] = _picked_spans()
	return await _did(_doc.repeat(spans)) if not spans.is_empty() else false


## The picked statements, as the text they are.
##
## The system clipboard as well, because a statement is GDScript and somebody
## who copies one here should be able to paste it into the script editor beside
## this one - but the text is returned, so the operation can be asked a question
## on a machine that has no clipboard at all.
func copy_picked() -> String:
	var spans: Array[ComposerSpan] = _picked_spans()
	if spans.is_empty():
		return ""
	var taken: String = _doc.copy(spans)
	DisplayServer.clipboard_set(taken)
	return taken


func paste() -> bool:
	return await paste_text(DisplayServer.clipboard_get())


## Anything at all may be on a clipboard, so what comes off one is read back
## before it is accepted, like every other edit.
func paste_text(written: String) -> bool:
	if not _doc.is_open() or written.strip_edges().is_empty():
		return false
	return await _did(_doc.insert(written, _doc.after(_picked_spans())))


## A node picked out of the palette becomes a statement in the body.
func _on_node_picked(key: StringName) -> void:
	if not _doc.may_write():
		return
	var written: String = ComposerWriter.call_for(
		ComposerCatalog.find(key), _doc.path()
	)
	if not written.is_empty():
		await _did(_doc.insert(written, _doc.after(_picked_spans())))


## A call dragged in from the palette, inserted exactly as a clicked one is.
##
## Where it was dropped is carried but not yet honoured: placing the new card
## there needs the id of a statement that does not exist until after the insert
## and the reread, which is the placement transaction TASK 13 builds. Said out
## loud rather than left as a docstring that claims more than the code does.
func _on_call_dropped(call_id: StringName, _graph_position: Vector2) -> void:
	await _on_node_picked(call_id)


## Dragging cards changes only where they are drawn.
##
## One commit for the whole gesture, whatever moved: somebody who dragged four
## selected cards did one thing, and four undos to put it back would be four
## more than they did.
func _on_nodes_positioned(positions: Dictionary[StringName, Vector2]) -> void:
	if not _doc.may_write():
		return
	for node_id: StringName in positions:
		var refusal: ComposerGraph.Diagnostic = _doc.place(node_id, positions[node_id])
		if refusal != null:
			push_error(SAVE_REFUSED % refusal.message)
			return
	await _redraw()


## A wire somebody dropped, handed to the one thing allowed to write one.
func _on_connection_requested(edge: ComposerGraph.Connection) -> void:
	if _wires.connect_edge(edge):
		await _redraw()


func _on_disconnection_requested(edge: ComposerGraph.Connection) -> void:
	if _wires.disconnect_edge(edge):
		await _redraw()


func _on_refused(message: String) -> void:
	push_warning(message)


## What can be done to a card, offered where the pointer is.
##
## The same three operations the chords do, said out loud. A tool whose only way
## in is a chord is a tool you have to be told about, and nobody is there to
## tell somebody opening it for the first time.
const MENU_ITEMS: Array[String] = ["Remove", "Repeat", "Copy"]


func _on_menu_requested(node_id: StringName, at: Vector2) -> void:
	if not _doc.may_write():
		return
	# The menu acts on what is selected, so right-clicking a card has to select
	# it first. Without this the three items operate on whatever was picked
	# before - a person right-clicks one node and removes another.
	if not node_id.is_empty() and not _canvas.picked().has(node_id):
		_canvas.reveal(node_id)
	if _menu == null:
		_menu = PopupMenu.new()
		for item: String in MENU_ITEMS:
			_menu.add_item(item)
		_menu.id_pressed.connect(_on_menu_chosen)
		add_child(_menu)
	# `at` is already where the pointer is in the viewport. Adding this screen's
	# own position again would open the menu that far down and to the right of
	# the card it belongs to.
	_menu.position = Vector2i(at)
	_menu.reset_size()
	_menu.popup()


func _on_menu_chosen(chosen: int) -> void:
	match chosen:
		0:
			await remove_picked()
		1:
			await repeat_picked()
		2:
			copy_picked()
#endregion


## A typed value goes through the one door that writes a field.
##
## The card and the Inspector arrive here alike, and neither writes: the
## controller stages the edit on a graph read fresh out of the text, so a refused
## value leaves the file and the canvas exactly as they were.
##
## Redrawn rather than patched. The card's text, the dot on it and the rows in
## the Output panel all come from one pass over the graph, and reaching in to
## change one of them is how the three start disagreeing about the same node.
func _on_value_edited(node_id: StringName, position: int, written: String) -> void:
	var held: Array[StringName] = _canvas.picked()
	if not _wires.rewrite_field(node_id, position, written):
		return
	await _redraw()
	if not held.is_empty():
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
	result.refusal = _doc.save()
	if result.is_ok():
		result.text = _doc.printed()
	return result


## The chords, spelled the way every other editor spells them.
func _build_chords() -> void:
	_chords.bind({
		KEY_S | KEY_MASK_CTRL: _save_now,
		KEY_Z | KEY_MASK_CTRL: undo,
		KEY_Z | KEY_MASK_CTRL | KEY_MASK_SHIFT: redo,
		KEY_Y | KEY_MASK_CTRL: redo,
		KEY_C | KEY_MASK_CTRL: copy_picked,
		KEY_V | KEY_MASK_CTRL: paste,
		KEY_D | KEY_MASK_CTRL: repeat_picked,
		KEY_DELETE: remove_picked,
		KEY_SPACE: _find_a_node,
	})


func _shortcut_input(event: InputEvent) -> void:
	# While the finder is open every key belongs to it, space most of all: the
	# chord that opens it is a character the moment there is somewhere to type.
	if _finder != null and _finder.visible:
		return
	var chord: int = ComposerChords.chord_of(event)
	if not _chords.has(chord):
		return
	accept_event()
	await _chords.perform(chord)


## Space: type the name of what you want instead of finding which of ten
## categories somebody filed it under.
func _find_a_node() -> void:
	if not _doc.may_write():
		return
	_finder.position = (size - _finder.size) * 0.5
	_finder.begin()


## Saving says so when it will not, because a chord that appears to do nothing
## is worse than one that explains itself.
func _save_now() -> void:
	var result: ComposerWriter.Result = await save()
	if not result.is_ok():
		push_error(SAVE_REFUSED % result.refusal.message)


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
	_top.size = Vector2(size.x, TOP_BAR)
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
