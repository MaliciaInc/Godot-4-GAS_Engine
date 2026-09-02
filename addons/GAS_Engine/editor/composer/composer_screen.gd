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

const CODE_TAB: String = "Code"
const COMPOSER_TAB: String = "Ability Composer"
const NO_ABILITY: String = "No ability open"
const NOTHING_TO_SAVE: String = "no ability is open"
## Borrowed: a path that holds nothing is one fact, and a second spelling of it
## is a second thing to keep true.
const NO_FILE: String = ComposerCatalog.NO_SCRIPT
const NOT_WRITABLE: String = "%s cannot be written to"
const SAVE_REFUSED: String = "GAS_Engine: the Composer did not save - %s"
const PICKER_MARK: String = "⌄"

const TOP_BAR: float = 54.0
const PALETTE_WIDTH: float = 250.0
const INSPECTOR_WIDTH: float = 290.0
const OUTPUT_HEIGHT: float = 132.0

## Asked for when someone clicks `Code`. The screen does not open the script
## itself: the plugin owns the editor, and a view that reached for it would be a
## view that knows about Godot's docks.
signal code_requested(source_path: String)

var _graph: ComposerGraph = null
var _palette: ComposerPalette = null
var _canvas: ComposerCanvas = null
var _inspector: ComposerInspector = null
var _output: ComposerOutput = null
var _title: Label = null
var _path: Label = null


func _ready() -> void:
	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_build_top_bar()

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

	resized.connect(_arrange)
	_arrange()


#region Top bar
func _build_top_bar() -> void:
	add_child(ComposerPanel.rule(Vector2(0.0, TOP_BAR), Vector2(size.x, 1.0)))

	var code: Button = _tab(CODE_TAB, false)
	code.position = Vector2(ComposerTheme.S4 + 2.0, ComposerTheme.S3)
	code.pressed.connect(_on_code_pressed)
	add_child(code)

	add_child(_divider(Vector2(76.0, ComposerTheme.S3 + 5.0)))

	var here: Button = _tab(COMPOSER_TAB, true)
	here.position = Vector2(90.0, ComposerTheme.S3)
	add_child(here)

	var underline: ColorRect = ColorRect.new()
	underline.position = Vector2(90.0, TOP_BAR - 2.0)
	underline.size = Vector2(124.0, 2.0)
	underline.color = ComposerTheme.ACCENT
	add_child(underline)

	_title = ComposerPanel.label(
		NO_ABILITY, ComposerTheme.TEXT, ComposerTheme.FONT_TITLE
	)
	_title.position = Vector2(300.0, ComposerTheme.S3 + 1.0)
	add_child(_title)

	_path = ComposerPanel.label(
		"", ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_LABEL
	)
	_path.position = Vector2(300.0, ComposerTheme.S4 + 14.0)
	add_child(_path)


func _tab(text: String, active: bool) -> Button:
	var made: Button = Button.new()
	made.text = text
	made.flat = true
	made.add_theme_color_override(
		DashboardTheme.FONT_COLOR,
		ComposerTheme.TEXT if active else ComposerTheme.TEXT_DIM
	)
	made.add_theme_font_size_override(DashboardTheme.FONT_SIZE, ComposerTheme.FONT_TITLE)
	return made


func _divider(at: Vector2) -> Label:
	var made: Label = ComposerPanel.label("│", ComposerTheme.RULE, ComposerTheme.FONT_TITLE)
	made.position = at
	return made


func _on_code_pressed() -> void:
	code_requested.emit(_graph.source_path if _graph != null else "")
#endregion


#region Showing a graph
## Hand the same graph to everything that draws part of it.
##
## One call, so the canvas and the output cannot end up describing different
## files - which is the failure a person notices last and trusts least.
func show_graph(graph: ComposerGraph) -> void:
	_graph = graph
	_title.text = _ability_name(graph)
	_path.text = graph.source_path if graph != null else ""
	# Opening a file is when a person looks at the palette, so it is when the
	# panel finds out about anything a game registered since it was built.
	_palette.refresh()
	_output.show_graph(graph)
	_inspector.show_node(null)
	await _canvas.show_graph(graph)


static func _ability_name(graph: ComposerGraph) -> String:
	if graph == null or graph.source_path.is_empty():
		return NO_ABILITY
	return graph.source_path.get_file().get_basename().capitalize()


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

	ComposerValidator.apply(_graph)
	var held: Array[StringName] = _canvas.picked()
	await show_graph(_graph)
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
	if _graph == null:
		result.refusal = ComposerWriter.refuse(NOTHING_TO_SAVE)
		return result

	var path: String = _graph.source_path
	if not FileAccess.file_exists(path):
		result.refusal = ComposerWriter.refuse(NO_FILE % path)
		return result

	result = ComposerWriter.apply(_graph, FileAccess.get_file_as_string(path))
	if not result.is_ok():
		return result

	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		result.refusal = ComposerWriter.refuse(NOT_WRITABLE % path)
		return result
	out.store_string(result.text)
	out.close()

	await show_graph(ComposerReader.read(result.text, path))
	return result


## Ctrl+S, the way every other editor in the world spells it.
func _shortcut_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_S or not key.ctrl_pressed:
		return
	accept_event()
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
