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
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPalette extends Control

const TITLE: String = "PALETTE"
const SEARCH_HINT: String = "  Search nodes…"
const OPEN_MARK: String = "⌄"
const SHUT_MARK: String = "›"

signal node_picked(type_id: StringName)

var _open: StringName = ComposerCatalog.TASKS
var _list: VBoxContainer = null

## The vocabulary this was drawn from. A game may offer nodes after the panel is
## already on screen, and a palette that never asked again would be the reason
## someone thinks their registration did nothing.
var _drawn: int = -1


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
	_drawn = ComposerCatalog.revision()
	for child: Node in _list.get_children():
		child.queue_free()

	for group: StringName in ComposerCatalog.groups():
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
		# A row of two labels is not a button. Nothing was connected to this, so
		# open_group() could only ever be called from a test and a person could
		# not open or close a single group in the palette.
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.gui_input.connect(_on_head_input.bind(group))
		_list.add_child(head)

		if not open:
			continue
		for entry: StringName in ComposerCatalog.entries(group):
			_list.add_child(_entry_row(entry))


## A row says what the call is called, not where it is filed.
##
## The key carries the script so two calls with one name can both be offered;
## putting that in front of a person would be showing them the filing system.
func _entry_row(key: StringName) -> Control:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
	var button: Button = Button.new()
	button.text = entry.title if entry != null else String(key)
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.TEXT_DIM)
	button.add_theme_font_size_override(
		DashboardTheme.FONT_SIZE, ComposerTheme.FONT_LABEL + 1
	)
	# The key, not the entry. The signal declares a StringName and the screen
	# looks the entry up again from it; emitting the object satisfied neither and
	# failed at the connection, which is why every palette click was refused by
	# Godot before it reached anything that could have reported it.
	button.pressed.connect(func _picked() -> void: node_picked.emit(key))
	# Dragged as well as pressed. A palette beside a canvas invites a drag, and
	# one that only answers clicks reads as broken rather than as different.
	button.set_drag_forwarding(_carry.bind(key), Callable(), Callable())
	return button


## What leaves the palette when a row is dragged.
##
## The preview is the row's own words, so what is under the cursor is what was
## picked up rather than a shape standing in for it.
func _carry(_at: Vector2, key: StringName) -> Variant:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
	set_drag_preview(
		ComposerPanel.label(
			entry.title if entry != null else String(key),
			ComposerTheme.TEXT, ComposerTheme.FONT_VALUE
		)
	)
	return carried_call(key)


## What one end of the drag hands the other, and the only part of it a test can
## hold: Godot refuses set_drag_preview() outside a live drag, so the preview is
## the one line here no suite can reach.
static func carried_call(key: StringName) -> Dictionary:
	return {ComposerCatalog.DRAGGED_CALL: key}


## Open a group, closing whichever was open. One at a time, because a palette
## with everything expanded is a list nobody can scan.
## Draw again if what is offered has changed since last time.
##
## Compared rather than rebuilt unconditionally: every row is a Control, and
## throwing the panel away on each file that opens would be work nobody asked
## for in the common case where nothing was registered.
func refresh() -> void:
	if _list == null or _drawn == ComposerCatalog.revision():
		return
	_rebuild()


func open_group(group: StringName) -> void:
	if group == _open or not ComposerCatalog.groups().has(group):
		return
	_open = group
	_rebuild()


## Open this group, or close it when it is the one already open.
##
## Closing leaves every group shut, which is a state worth being able to reach:
## the shape of the vocabulary is easier to read with nothing expanded over it.
func toggle_group(group: StringName) -> void:
	if group != _open:
		open_group(group)
		return
	_open = &""
	_rebuild()


func _on_head_input(event: InputEvent, group: StringName) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	toggle_group(group)


func open_group_name() -> StringName:
	return _open
