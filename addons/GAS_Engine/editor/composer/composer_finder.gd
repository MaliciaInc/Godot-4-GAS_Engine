## Space, then type what you want.
##
## The fastest way to put a node down, and the only one that does not require
## knowing which of ten categories somebody filed it under. A palette you scroll
## is a palette you have to have read; a palette you type at is one you can use
## the first time.
##
## Each row says what the call is, where it is filed, and whose it is. It does
## not say what the call does, because nothing in the project knows: Godot does
## not hand a method's doc comment to reflection, and a description written here
## would be a copy of one already above the method - which is the copy that
## stops being true.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFinder extends Control

const HINT: String = "Type to find a node"
const NOTHING_FOUND: String = "Nothing matches that"
const ENGINE_BADGE: String = "engine"
const GAME_BADGE: String = "game"

const WIDTH: float = 520.0
const HEIGHT: float = 360.0
const ROW_PITCH: float = 34.0
const SHOWN: int = 8

## The call somebody settled on.
signal chose(key: StringName)

var _query: LineEdit = null
var _rows: VBoxContainer = null
var _found: Array[StringName] = []
var _at: int = 0


func _ready() -> void:
	visible = false
	size = Vector2(WIDTH, HEIGHT)

	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_query = LineEdit.new()
	_query.placeholder_text = HINT
	_query.position = Vector2(ComposerTheme.S3, ComposerTheme.S3)
	_query.custom_minimum_size = Vector2(WIDTH - ComposerTheme.S3 * 2.0, 0.0)
	_query.add_theme_stylebox_override(
		GASEditorTheme.NORMAL_STYLEBOX, ComposerTheme.field_box()
	)
	_query.add_theme_color_override(GASEditorTheme.FONT_COLOR, ComposerTheme.TEXT)
	_query.add_theme_font_size_override(GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_TITLE)
	_query.text_changed.connect(_on_typed)
	add_child(_query)

	_rows = ComposerPanel.column(ComposerTheme.S1)
	_rows.position = Vector2(ComposerTheme.S3, ComposerTheme.S4 + ROW_PITCH)
	add_child(_rows)


## Open it, empty, with whatever the catalog holds right now.
func begin() -> void:
	visible = true
	_query.text = ""
	_query.grab_focus()
	_on_typed("")


func dismiss() -> void:
	visible = false


#region Finding
## Everything whose name or category contains what was typed.
##
## Matched on the method as well as on the title, because somebody who knows the
## engine will type `wait_target` before they type `Wait Target Data`, and being
## made to spell it the pretty way is the palette asking them to translate.
func matches(query: String) -> Array[StringName]:
	var wanted: String = query.strip_edges().to_lower()
	var found: Array[StringName] = []
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if wanted.is_empty() or _touches(entry, wanted):
			found.append(entry.key)
	return found


static func _touches(entry: ComposerCatalog.Entry, wanted: String) -> bool:
	return (
		entry.title.to_lower().contains(wanted)
		or String(entry.type_id).contains(wanted)
		or String(entry.group).to_lower().contains(wanted)
	)


func _on_typed(query: String) -> void:
	_found = matches(query)
	_at = 0
	_rebuild()


func _rebuild() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	if _found.is_empty():
		_rows.add_child(
			ComposerPanel.label(NOTHING_FOUND, ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_VALUE)
		)
		return
	for index: int in mini(_found.size(), SHOWN):
		_rows.add_child(_row(_found[index], index == _at))


func _row(key: StringName, here: bool) -> Control:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
	var line: HBoxContainer = ComposerPanel.row(ComposerTheme.S2)
	line.add_child(
		ComposerPanel.label(
			entry.title, ComposerTheme.TEXT if here else ComposerTheme.TEXT_DIM,
			ComposerTheme.FONT_VALUE
		)
	)
	line.add_child(
		ComposerPanel.label(
			String(entry.group), ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_LABEL
		)
	)
	line.add_child(
		ComposerPanel.label(_badge(entry), ComposerTheme.ACCENT, ComposerTheme.FONT_LABEL)
	)
	return line


## Whose call this is, worked out rather than declared: an entry read from one
## of the scripts the catalog reads is the engine's, and anything else was
## registered by somebody.
static func _badge(entry: ComposerCatalog.Entry) -> String:
	for declared: StringName in ComposerCatalog.SOURCES:
		if ComposerCatalog.script_for(declared) == entry.source:
			return ENGINE_BADGE
	return GAME_BADGE
#endregion


#region Choosing one
## What is highlighted, or nothing when there is nothing to highlight.
func here() -> StringName:
	return _found[_at] if _at >= 0 and _at < _found.size() else &""


func _gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			accept_event()
			dismiss()
		KEY_DOWN:
			accept_event()
			_step(1)
		KEY_UP:
			accept_event()
			_step(-1)
		KEY_ENTER, KEY_KP_ENTER:
			accept_event()
			_take()


func _step(by: int) -> void:
	if _found.is_empty():
		return
	_at = clampi(_at + by, 0, mini(_found.size(), SHOWN) - 1)
	_rebuild()


func _take() -> void:
	var wanted: StringName = here()
	if wanted.is_empty():
		return
	dismiss()
	chose.emit(wanted)
#endregion
