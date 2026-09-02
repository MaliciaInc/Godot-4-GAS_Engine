## The node vocabulary, on the left, permanently.
##
## It gets the standing column because it is what a person reaches for on every
## edit. Which ability is open changes a few times an hour and belongs in the top
## bar; the tools do not move.
##
## Reads its groups from the catalog rather than owning a list, so the palette
## cannot quietly become a second opinion about what the Composer can express.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerPalette extends Control

const TITLE: String = "PALETTE"
const SEARCH_HINT: String = "  Search nodes…"
const OPEN_MARK: String = "⌄"
const SHUT_MARK: String = "›"

signal node_picked(type_id: StringName)

var _open: StringName = ComposerCatalog.TASKS
var _list: VBoxContainer = null


func _ready() -> void:
	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var column: VBoxContainer = ComposerPanel.column(ComposerTheme.S3)
	column.position = Vector2(ComposerTheme.S3, ComposerTheme.S4)
	column.custom_minimum_size = Vector2(size.x - ComposerTheme.S3 * 2.0, 0.0)
	add_child(column)

	column.add_child(ComposerPanel.caption(TITLE))
	column.add_child(
		ComposerPanel.slot(
			SEARCH_HINT, ComposerTheme.TEXT_FAINT, size.x - ComposerTheme.S3 * 2.0
		)
	)

	_list = ComposerPanel.column(ComposerTheme.S2)
	column.add_child(_list)
	_rebuild()


## One row per group, and the open one shows what it holds.
##
## Everything is listed even while the catalog is empty: a palette that hid its
## empty groups would look like a tool that can do less than it will, and the
## shape of the vocabulary is worth seeing before the entries exist.
func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()

	for group: StringName in ComposerCatalog.GROUPS:
		var open: bool = group == _open
		var head: HBoxContainer = ComposerPanel.row(ComposerTheme.S2)
		head.add_child(
			ComposerPanel.label(
				OPEN_MARK if open else SHUT_MARK,
				ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_VALUE
			)
		)
		head.add_child(
			ComposerPanel.label(
				String(group),
				ComposerTheme.TEXT if open else ComposerTheme.TEXT_DIM,
				ComposerTheme.FONT_VALUE
			)
		)
		_list.add_child(head)

		if not open:
			continue
		for entry: StringName in ComposerCatalog.entries(group):
			_list.add_child(_entry_row(entry))


func _entry_row(entry: StringName) -> Control:
	var button: Button = Button.new()
	button.text = String(entry)
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.TEXT_DIM)
	button.add_theme_font_size_override(
		DashboardTheme.FONT_SIZE, ComposerTheme.FONT_LABEL + 1
	)
	button.pressed.connect(func _picked() -> void: node_picked.emit(entry))
	return button


## Open a group, closing whichever was open. One at a time, because a palette
## with everything expanded is a list nobody can scan.
func open_group(group: StringName) -> void:
	if group == _open or not ComposerCatalog.GROUPS.has(group):
		return
	_open = group
	_rebuild()


func open_group_name() -> StringName:
	return _open
