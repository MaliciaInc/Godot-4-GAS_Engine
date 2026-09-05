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

## Every gesture that changes a wire goes through these, and they hear the
## canvas themselves.
var _routes: ComposerWiringRoutes = ComposerWiringRoutes.new()

## What the selected statements can be made to do.
var _statements: ComposerStatementOps = ComposerStatementOps.new()
## The menus this screen opens. It says when; they say what was picked.
var _menus: ComposerMenus = ComposerMenus.new()

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
	_canvas.value_edited.connect(_on_value_edited)
	# The widget's shortcuts, on the same operations the menu uses. Why they are
	# not in the chord table is written where that table is built.
	_canvas.delete_requested.connect(remove_picked)
	_canvas.copy_requested.connect(copy_picked)
	_canvas.cut_requested.connect(cut_picked)
	_canvas.paste_requested.connect(paste)
	_canvas.duplicate_requested.connect(repeat_picked)
	# A call dragged in from the palette is inserted exactly as a clicked one is.
	_canvas.node_requested.connect(_on_node_picked)
	# The routes hear the canvas themselves. A gesture added there is connected
	# beside the others rather than in a list here that has to be remembered.
	_routes.bind(_doc)
	_routes.listen_to(_canvas)
	_routes.changed.connect(_redraw)
	_routes.refused.connect(_on_refused)
	add_child(_menus)
	_menus.bind(_doc)
	_menus.listen_to(_canvas)
	_menus.chose.connect(_on_menu_chosen)
	_menus.entry_chosen.connect(_on_entry_chosen)
	_statements.bind(_doc)
	_output.row_picked.connect(_on_row_picked)
	_top.open_requested.connect(func _asked() -> void: open_requested.emit())
	_top.create_requested.connect(func _asked() -> void: create_requested.emit())
	_inspector.value_edited.connect(_on_value_edited)
	_inspector.disconnect_requested.connect(_routes.unplug_argument)
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
## Each of these hands the selection to the one place that knows what the
## operation means, and redraws if the document accepted it.
func remove_picked() -> bool:
	var picked: Array[StringName] = _canvas.picked()
	return not picked.is_empty() and await _did(_statements.remove(picked))


func repeat_picked() -> bool:
	var picked: Array[StringName] = _canvas.picked()
	return not picked.is_empty() and await _did(_statements.repeat(picked))


## The picked statements as text, and on the system clipboard, so somebody can
## paste one into the script editor beside this one. The text is returned as
## well, so the operation can be asked a question where there is no clipboard.
func copy_picked() -> String:
	var taken: String = _statements.copy(_canvas.picked())
	if not taken.is_empty():
		DisplayServer.clipboard_set(taken)
	return taken


## Copy what is picked and take it out, as one change.
##
## The copy reads and the removal writes, so this is one commit and one thing to
## undo - which is what somebody who pressed Ctrl-X did.
func cut_picked() -> String:
	var taken: String = copy_picked()
	if not taken.is_empty():
		await remove_picked()
	return taken


func paste() -> bool:
	return await paste_text(DisplayServer.clipboard_get())


func paste_text(written: String) -> bool:
	if written.strip_edges().is_empty():
		return false
	return await _did(_statements.paste(_canvas.picked(), written))


## A call somebody chose, from the palette, the finder or a drag onto the canvas.
##
## One handler for all three. Where it was dropped is carried and not yet
## honoured - placing the new card there needs the id of a statement that does
## not exist until after the insert and the reread, which is the placement
## transaction TASK 13 builds.
func _on_node_picked(key: StringName, _at: Vector2 = Vector2.ZERO) -> void:
	await _did(_statements.insert_call(_canvas.picked(), key))


## Dragging cards changes only where they are drawn.
##
## One commit for the whole gesture, whatever moved: somebody who dragged four
## selected cards did one thing, and four undos to put it back would be four
## more than they did.
func _on_nodes_positioned(positions: Dictionary[StringName, Vector2]) -> void:
	if _doc.may_write():
		await _did(_doc.place_many(positions))


## Why a gesture did nothing. A refusal a person cannot read is a tool that
## ignored them.
func _on_refused(message: String) -> void:
	push_warning(message)


## A call picked from the catalog becomes a statement and, where the drag came
## out of a pin, the cable joining it - as one change.
func _on_entry_chosen(
	entry_key: StringName, context: ComposerActionMenu.Context
) -> void:
	_routes.create_and_connect(ComposerCatalog.find(entry_key), context)


## One place where a menu item becomes an operation, whichever menu offered it.
##
## Matched on the name it was offered under, not on an index two lists have to
## keep agreeing about.
func _on_menu_chosen(
	chosen: String, node_id: StringName, port_id: StringName
) -> void:
	match chosen:
		ComposerMenus.REMOVE:
			await remove_picked()
		ComposerMenus.REPEAT:
			await repeat_picked()
		ComposerMenus.COPY:
			copy_picked()
		ComposerMenus.BREAK_ALL:
			_routes.break_pin(node_id, port_id)
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
	if not _routes.rewrite_field(node_id, position, written):
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
	# Only the keys GraphEdit does not ask about itself. Delete, Ctrl-C, Ctrl-X,
	# Ctrl-V and Ctrl-D arrive as the widget's own requests and are connected
	# where the canvas is built; listing them here as well would give each of
	# them two handlers, and a shortcut that fires twice removes two statements.
	_chords.bind({
		KEY_S | KEY_MASK_CTRL: _save_now,
		KEY_Z | KEY_MASK_CTRL: undo,
		KEY_Z | KEY_MASK_CTRL | KEY_MASK_SHIFT: redo,
		KEY_Y | KEY_MASK_CTRL: redo,
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


## Which keys this screen answers for itself, so the rule that no key has two
## handlers can be checked rather than trusted.
func chords() -> ComposerChords:
	return _chords
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
