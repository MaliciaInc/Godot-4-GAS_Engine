## One row of the cue dashboard: a tag, the scene it plays, and two actions.
##
## Extracted from the tab, which owns the registry and the edit form. Drawing a
## row and deciding what a click does are different jobs, and keeping them in
## one function is what pushed that file past its size limit.
##
## The row is built but not wired: `build` returns the two buttons so the tab
## can bind them to the entry's index in the registry, which only the tab knows.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT

@tool
class_name CueRow extends RefCounted

## Shown in place of a field the user has not filled in yet.
const UNASSIGNED_TAG: String = "No Tag Assigned"
const UNASSIGNED_SCENE: String = "No Scene Assigned"

## Godot's standard icon edge, before the editor's UI scale is applied.
const BASE_ICON_PIXELS: int = 16

## BBCode for one inline icon, tinted to the editor's font colour so it reads
## as part of the text rather than as artwork.
const ICON_BBCODE: String = "[img width=%d height=%d color=#%s]%s[/img]"


## A built row and the two controls the caller still has to connect.
class Built extends RefCounted:
	var card: PanelContainer = null
	var edit_button: Button = null
	var delete_button: Button = null


static func build(
	entry: GameplayCueEntry, theme: DashboardTheme, tag_icon: Texture2D, scene_icon: Texture2D
) -> Built:
	var built: Built = Built.new()

	built.card = PanelContainer.new()
	built.card.add_theme_stylebox_override(DashboardTheme.PANEL_STYLEBOX, theme.list_item)

	var row: HBoxContainer = HBoxContainer.new()
	built.card.add_child(row)

	row.add_child(_label_column(entry, theme, tag_icon, scene_icon))

	var editor_theme: Theme = EditorInterface.get_editor_theme()
	built.edit_button = _action_button(editor_theme, DashboardTheme.ICON_EDIT)
	built.delete_button = _action_button(editor_theme, DashboardTheme.ICON_REMOVE)
	row.add_child(built.edit_button)
	row.add_child(built.delete_button)
	return built


static func _action_button(editor_theme: Theme, icon_name: String) -> Button:
	var button: Button = Button.new()
	button.icon = editor_theme.get_icon(icon_name, DashboardTheme.EDITOR_ICON_THEME)
	return button


## The description, wrapped so it centres against the taller button row.
static func _label_column(
	entry: GameplayCueEntry, theme: DashboardTheme, tag_icon: Texture2D, scene_icon: Texture2D
) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Without this the label paints the editor's faint text background inside
	# the card, which reads as a second nested panel.
	label.add_theme_stylebox_override(DashboardTheme.RICH_TEXT_STYLEBOX, StyleBoxEmpty.new())
	label.text = _describe(entry, theme, tag_icon, scene_icon)

	column.add_child(label)
	return column


static func _describe(
	entry: GameplayCueEntry, theme: DashboardTheme, tag_icon: Texture2D, scene_icon: Texture2D
) -> String:
	var tag_name: String = String(entry.tag) if entry.tag != &"" else UNASSIGNED_TAG
	var scene_name: String = UNASSIGNED_SCENE
	var scene_path: String = UNASSIGNED_SCENE
	if entry.scene != null:
		scene_name = entry.scene.resource_path.get_file()
		scene_path = entry.scene.resource_path

	return (
		_inline_icon(tag_icon)
		+ " " + _accented(tag_name, theme)
		+ " [i]executes [b]→[/b][/i] "
		+ _inline_icon(scene_icon)
		+ " " + _accented(scene_name, theme)
		+ " [i](" + scene_path + ")[/i]"
	)


static func _accented(text: String, theme: DashboardTheme) -> String:
	return "[color=" + theme.accent_html + "][b]" + text + "[/b][/color]"


## One icon at the editor's own size and font colour.
static func _inline_icon(icon: Texture2D) -> String:
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	var hex: String = editor_theme.get_color(
		DashboardTheme.FONT_COLOR, DashboardTheme.EDITOR_THEME_TYPE
	).to_html(false)
	var size: int = int(BASE_ICON_PIXELS * EditorInterface.get_editor_scale())
	return ICON_BBCODE % [size, size, hex, icon.resource_path]
