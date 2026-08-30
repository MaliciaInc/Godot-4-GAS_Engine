## Editor tab for managing the project's gameplay tag registry.
##
## Add, search and delete tags in a hierarchical view. The tree itself is built
## by GameplayTagTree, shared with the cue dashboard: two trees drawing the same
## registry differently is how a tag looks one way in one place and another way
## somewhere else.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends Control


const TAGS_ICON_PATH: String = "res://addons/GodotGAS/icons/godot_gas_tags.svg"

## The id of the per-leaf delete button.
const DELETE_BUTTON_ID: int = 0
const DELETE_TOOLTIP: String = "Delete this tag"

## Colours and styleboxes, shared with the other dashboard tabs.
var _theme: DashboardTheme = DashboardTheme.new()

var _tag_icon: Texture2D = null
var _registry: GameplayTagRegistry = null
var _delete_confirm_dialog: ConfirmationDialog = null
var _tag_to_delete: StringName = &""

@onready var _search_bar: LineEdit = %SearchTagFilter
@onready var _tag_tree: Tree = %TagTree
@onready var _new_tag_input: LineEdit = %NewTagInput
@onready var _btn_add_tag: Button = %BtnAddTag
@onready var _btn_expand_collapse: Button = %BtnExpandCollapse


#region Initialization
func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_load_registry()
	_setup_ui()
	_sync_theme_colors()
	_refresh_tag_tree()


func _load_registry() -> void:
	_registry = GameplayTagTree.load_registry()


func _notification(what: int) -> void:
	if what != NOTIFICATION_THEME_CHANGED:
		return
	if Engine.is_editor_hint() and is_node_ready():
		_sync_theme_colors()
		_refresh_tag_tree()


func _setup_ui() -> void:
	_theme.configure_tree(_tag_tree, [""] as Array[String], [] as Array[int])
	_tag_tree.button_clicked.connect(_on_tree_button_clicked)

	_btn_add_tag.pressed.connect(_on_add_tag_pressed)
	_btn_expand_collapse.pressed.connect(_on_expand_collapse_pressed)
	_btn_expand_collapse.icon = get_theme_icon(
		DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME
	)

	_new_tag_input.text_submitted.connect(
		func(_submitted: String) -> void: _on_add_tag_pressed()
	)
	if _search_bar != null:
		_search_bar.text_changed.connect(_on_search_changed)

	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.confirmed.connect(_execute_delete)
	add_child(_delete_confirm_dialog)


## Refresh colours from the editor theme and repaint this tab.
func _sync_theme_colors() -> void:
	if not _theme.sync_from_editor():
		return
	_theme.apply_panels(self)
	_tag_icon = DashboardTheme.icon(TAGS_ICON_PATH)
	_theme.apply_tab_icon(self, _tag_icon)
#endregion


#region Tree
func _on_search_changed(_text: String) -> void:
	_refresh_tag_tree()


## Rebuild the tag tree, each leaf carrying a delete button.
func _refresh_tag_tree() -> void:
	if _registry == null:
		_tag_tree.clear()
		return

	var style: GameplayTagTree.Style = GameplayTagTree.Style.new()
	style.leaf_icon = _tag_icon
	style.leaf_color = _theme.text_accent
	style.leaf_button = get_theme_icon(
		DashboardTheme.ICON_REMOVE, DashboardTheme.EDITOR_ICON_THEME
	)
	style.leaf_button_id = DELETE_BUTTON_ID
	style.leaf_button_tooltip = DELETE_TOOLTIP

	var filter: String = _search_bar.text if _search_bar != null else ""
	# Nothing is unavailable here: this tab manages the registry rather than
	# picking from it.
	GameplayTagTree.build(_tag_tree, filter, [] as Array[StringName], style)


## Toggle every top-level branch, and show the action the button will next take.
func _on_expand_collapse_pressed() -> void:
	var root: TreeItem = _tag_tree.get_root()
	if root == null:
		return

	for child: TreeItem in root.get_children():
		child.collapsed = not child.collapsed

	var first: TreeItem = root.get_first_child()
	var now_collapsed: bool = first != null and first.collapsed
	_btn_expand_collapse.tooltip_text = (
		DashboardTheme.LABEL_EXPAND_TREE if now_collapsed else DashboardTheme.LABEL_COLLAPSE_TREE
	)
	_btn_expand_collapse.icon = get_theme_icon(
		DashboardTheme.ICON_EXPAND_TREE if now_collapsed else DashboardTheme.ICON_COLLAPSE_TREE,
		DashboardTheme.EDITOR_ICON_THEME
	)
#endregion


#region Adding and deleting
func _on_add_tag_pressed() -> void:
	var input_text: String = _new_tag_input.text.strip_edges()
	if input_text.is_empty():
		return
	if _registry == null:
		push_error("GodotGAS: cannot add a tag, the registry is missing.")
		return

	# add_tag validates and sorts; it returns the formatted tag or a message.
	var result: String = _registry.add_tag(input_text)
	if result.begins_with(GameplayTagRegistry.ERROR_PREFIX):
		_show_dialog(result)
		return

	_new_tag_input.text = ""
	_refresh_tag_tree()


## Only a leaf carries a tag, so a grouping node cannot be staged for deletion.
func _on_tree_button_clicked(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	if id != DELETE_BUTTON_ID:
		return
	var raw_tag: Variant = item.get_metadata(0)
	if not raw_tag is StringName:
		return

	_tag_to_delete = raw_tag
	_delete_confirm_dialog.dialog_text = (
		"Delete the tag:" + "\n" + "'" + String(_tag_to_delete) + "'?"
	)
	_delete_confirm_dialog.popup_centered()


func _execute_delete() -> void:
	if _tag_to_delete == &"" or _registry == null:
		return
	_registry.remove_tag(_tag_to_delete)
	_tag_to_delete = &""
	_refresh_tag_tree()


## Freed on dismissal. Building an AcceptDialog per message and add_child()ing
## it without freeing leaks a node every time.
func _show_dialog(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
#endregion
