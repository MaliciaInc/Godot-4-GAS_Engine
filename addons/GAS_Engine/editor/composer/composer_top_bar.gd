## Code │ Ability Composer, and which ability is open.
##
## The two chips are not two tools. They are one file seen two ways, and the bar
## says so by putting them side by side with nothing between them but a rule -
## the same shape a person already reads as "the same thing, another view".
##
## Nothing here repeats what the panel at the bottom already owns. The counts
## and the problems live down there; up here is which ability this is and where
## it came from, which is the one thing a person cannot work out from the canvas.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerTopBar extends Control

const CODE_TAB: String = "Code"
const COMPOSER_TAB: String = "Ability Composer"
const NO_ABILITY: String = "No ability open"
const DIVIDER: String = "│"

const HEIGHT: float = 54.0
const CODE_AT: float = 22.0
const DIVIDER_AT: float = 76.0
const COMPOSER_AT: float = 90.0
const UNDERLINE_WIDTH: float = 124.0
const TITLE_AT: float = 300.0

## Asked to be taken to the same file, as text.
signal code_requested

var _title: Label = null
var _path: Label = null


func _ready() -> void:
	add_child(ComposerPanel.rule(Vector2(0.0, HEIGHT), Vector2(size.x, 1.0)))

	var code: Button = _tab(CODE_TAB, false)
	code.position = Vector2(CODE_AT, ComposerTheme.S3)
	code.pressed.connect(func _leave() -> void: code_requested.emit())
	add_child(code)

	add_child(_divider(Vector2(DIVIDER_AT, ComposerTheme.S3 + 5.0)))

	var here: Button = _tab(COMPOSER_TAB, true)
	here.position = Vector2(COMPOSER_AT, ComposerTheme.S3)
	add_child(here)

	var underline: ColorRect = ColorRect.new()
	underline.position = Vector2(COMPOSER_AT, HEIGHT - 2.0)
	underline.size = Vector2(UNDERLINE_WIDTH, 2.0)
	underline.color = ComposerTheme.ACCENT
	add_child(underline)

	_title = ComposerPanel.label(NO_ABILITY, ComposerTheme.TEXT, ComposerTheme.FONT_TITLE)
	_title.position = Vector2(TITLE_AT, ComposerTheme.S3 + 1.0)
	add_child(_title)

	_path = ComposerPanel.label("", ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_LABEL)
	_path.position = Vector2(TITLE_AT, ComposerTheme.S4 + 14.0)
	add_child(_path)


## Say which ability is open, and where it lives.
func show_graph(graph: ComposerGraph) -> void:
	if _title == null:
		return
	_title.text = _ability_name(graph)
	_path.text = graph.source_path if graph != null else ""


## The file's own name, said the way a person says it.
##
## Taken from the path rather than from anything inside the file: an ability
## does not have to declare a name, and most do not.
static func _ability_name(graph: ComposerGraph) -> String:
	if graph == null or graph.source_path.is_empty():
		return NO_ABILITY
	return graph.source_path.get_file().get_basename().capitalize()


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


static func _divider(at: Vector2) -> Label:
	var made: Label = ComposerPanel.label(DIVIDER, ComposerTheme.RULE, ComposerTheme.FONT_TITLE)
	made.position = at
	return made
