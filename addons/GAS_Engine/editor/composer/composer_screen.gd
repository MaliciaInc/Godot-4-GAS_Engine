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
