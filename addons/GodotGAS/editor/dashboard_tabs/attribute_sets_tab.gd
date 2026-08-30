## Editor tool for managing, configuring, and generating GodotGAS AttributeSets.
##
## Provides a UI for creating attribute categories, defining default values,
## assigning icons, and compiling the configuration into GDScript files.
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends Control

const ICON_ATTRIBUTES: String = "res://addons/GodotGAS/icons/godot_gas_attributes.svg"
const ICON_STAR: String = "res://addons/GodotGAS/icons/godot_gas_icon_star.svg"
const ICON_EDIT: String = "res://addons/GodotGAS/icons/godot_gas_icon_edit.svg"

## Godot's own icon theme, and the two confirmation subjects.
const DELETE_SET: String = "set"
const DELETE_ATTRIBUTE: String = "attribute"
const ACTION_FAILED: String = "Action Failed"
const DEFAULT_ICON_NAME: String = AttributeIcons.DEFAULT_NAME

## Icon for Attribute Set categories.
var _set_icon: Texture2D

## Default icon for an individual attribute.
var _default_attr_icon: Texture2D

## Icon used for the inline edit action.
var _edit_icon_icon: Texture2D

## Enum representing the available inline tree action buttons.
enum TreeBtn { EDIT, DUPLICATE, DELETE, CHANGE_ICON }

## The drafted sets, as a typed model. The tab no longer touches a
## ConfigFile directly, so no code path can forget to persist a change.
var _drafts: AttributeSetDrafts = AttributeSetDrafts.new()

## The name of the currently selected Attribute Set.
var _current_set: String = ""

## The dialog used to confirm deletion of sets or attributes.
var _delete_confirm_dialog: ConfirmationDialog

## The dynamic inline popup menu for selecting attribute icons.
var _icon_popup: PopupMenu

## A mapped array of icon names matching the index in the popup menu.
var _icon_names_map: Array[String] = []

## Tracks the name of the attribute currently having its icon changed.
var _editing_icon_attr: String = ""

## Tracks whether a 'set' or 'attribute' is currently staged for deletion.
var _delete_target_type: String = ""

## Tracks the specific name of the item staged for deletion.
var _delete_target_name: String = ""

## Colours and styleboxes, derived from the editor theme and shared with the
## other dashboard tabs.
var _theme: DashboardTheme = DashboardTheme.new()

## Reference to the tree node displaying Attribute Sets.
@onready var _set_tree: Tree = %SetTree

## Reference to the line edit for new set names.
@onready var _new_set_input: LineEdit = %NewSetInput

## Reference to the button to create a new set.
@onready var _btn_create_set: Button = %BtnCreateSet

## Reference to the label displaying the currently selected set.
@onready var _lbl_selected_set: Label = %LblSelectedSet

## Reference to the tree node displaying attributes for the selected set.
@onready var _attribute_tree: Tree = %AttributeTree

## Reference to the line edit for new attribute names.
@onready var _new_attribute_input: LineEdit = %NewAttributeInput

## Reference to the option button for selecting an attribute icon.
@onready var _btn_icon: OptionButton = %BtnIcon

## Reference to the spinbox for the new attribute value.
@onready var _new_attribute_value: SpinBox = %NewAttributeValue

## Reference to the button to add a new attribute.
@onready var _btn_add_attribute: Button = %BtnAddAttribute

## Reference to the button to generate the final GDScript.
@onready var _btn_generate_script: Button = %BtnGenerateScript


#region Initialization
## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		_load_drafts()
		_setup_ui()
		_sync_theme_colors()
		_refresh_set_tree()
		_refresh_attribute_tree()


## Loads the saved draft data and settings.
func _load_drafts() -> void:
	_drafts.load_from_disk()


## Receives Godot Engine broadcasts, allowing us to seamlessly update colors if the user changes themes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if Engine.is_editor_hint() and is_node_ready():
			_sync_theme_colors()
			_refresh_set_tree()
			_refresh_attribute_tree()


## Binds all signals and constructs the dynamic dialogs.
func _setup_ui() -> void:
	# General Buttons
	_btn_create_set.pressed.connect(_on_create_set_pressed)
	_btn_add_attribute.pressed.connect(_on_add_attribute_pressed)
	_btn_generate_script.pressed.connect(_on_generate_script_pressed)

	_new_attribute_input.text_submitted.connect(
		func(_submitted: String) -> void: _on_add_attribute_pressed()
	)
	_new_set_input.text_submitted.connect(
		func(_submitted: String) -> void: _on_create_set_pressed()
	)

	# Populate Icon Dropdowns & Popup Menus
	AttributeIcons.fill_dropdown(_btn_icon)
	_icon_popup = PopupMenu.new()
	_icon_names_map = AttributeIcons.fill_popup(_icon_popup)
	_icon_popup.id_pressed.connect(_on_icon_popup_id_pressed)
	add_child(_icon_popup)

	# Fetch theme colors and apply styling
	_sync_theme_colors()

	_theme.configure_tree(_set_tree, [""] as Array[String], [] as Array[int])
	_set_tree.button_clicked.connect(_on_set_tree_button_clicked)
	_set_tree.item_edited.connect(_on_set_tree_item_edited)
	_set_tree.item_selected.connect(_on_set_tree_item_selected)

	_theme.configure_tree(
		_attribute_tree,
		["Attribute Name", "Base Value"] as Array[String],
		[3, 1] as Array[int]
	)
	_attribute_tree.button_clicked.connect(_on_attribute_tree_button_clicked)
	_attribute_tree.item_edited.connect(_on_attribute_tree_item_edited)

	# Build Shared Dialogs
	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.confirmed.connect(_execute_delete)
	add_child(_delete_confirm_dialog)

	_update_right_panel_state()


## Refresh colours from the editor theme and repaint the dashboard.
##
## The derivation lives in DashboardTheme, shared with the other tabs. Three
## private copies of it meant three chances to drift from the editor after a
## theme change.
func _sync_theme_colors() -> void:
	if not _theme.sync_from_editor():
		return

	_theme.apply_panels(self)
	_set_icon = DashboardTheme.icon(ICON_ATTRIBUTES)
	_default_attr_icon = DashboardTheme.icon(ICON_STAR)
	_edit_icon_icon = DashboardTheme.icon(ICON_EDIT)
	_btn_generate_script.icon = _set_icon
	_theme.apply_tab_icon(self, _set_icon)


#endregion


#region Set Manager Logic
## Rebuild the tree of attribute sets.
func _refresh_set_tree() -> void:
	_set_tree.clear()
	var root: TreeItem = _set_tree.create_item()

	for set_name: String in _drafts.set_names():
		var item: TreeItem = _set_tree.create_item(root)
		item.set_text(0, set_name)
		item.set_icon(0, _set_icon)
		item.set_metadata(0, set_name)
		item.set_editable(0, false)
		item.add_button(0, get_theme_icon(DashboardTheme.ICON_EDIT, DashboardTheme.EDITOR_ICON_THEME), TreeBtn.EDIT, false, "Rename Set")
		item.add_button(0, get_theme_icon(DashboardTheme.ICON_COPY, DashboardTheme.EDITOR_ICON_THEME), TreeBtn.DUPLICATE, false, "Duplicate Set")
		item.add_button(0, get_theme_icon(DashboardTheme.ICON_REMOVE, DashboardTheme.EDITOR_ICON_THEME), TreeBtn.DELETE, false, "Delete Set")
		if set_name == _current_set:
			item.select(0)


func _on_set_tree_button_clicked(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	var set_name: String = item.get_metadata(0)
	match id:
		TreeBtn.EDIT:
			_begin_inline_rename(_set_tree, item)
		TreeBtn.DUPLICATE:
			_drafts.duplicate_set(set_name)
			_refresh_set_tree()
		TreeBtn.DELETE:
			_stage_deletion(
				DELETE_SET,
				set_name,
				"Delete Attribute Set?" + "\n" + "This permanently destroys '" + set_name + "' and everything in it."
			)


## Unlock a row for editing and put the caret in it.
func _begin_inline_rename(tree: Tree, item: TreeItem) -> void:
	item.set_editable(0, true)
	item.select(0)
	tree.edit_selected(true)


func _on_set_tree_item_edited() -> void:
	var item: TreeItem = _set_tree.get_edited()
	if item == null:
		return
	item.set_editable(0, false)

	var old_name: String = item.get_metadata(0)
	var new_name: String = item.get_text(0).strip_edges().to_pascal_case()
	if new_name.is_empty() or new_name == old_name:
		item.set_text(0, old_name)
		return

	if not _drafts.rename_set(old_name, new_name):
		_show_dialog(ACTION_FAILED, "'" + new_name + "' is taken or reserved.")
		item.set_text(0, old_name)
		return

	item.set_metadata(0, new_name)
	item.set_text(0, new_name)
	if _current_set == old_name:
		_current_set = new_name
		_update_right_panel_state()


func _on_set_tree_item_selected() -> void:
	var item: TreeItem = _set_tree.get_selected()
	if item == null:
		return
	_current_set = item.get_metadata(0)
	_refresh_attribute_tree()


func _on_create_set_pressed() -> void:
	var set_name: String = _new_set_input.text.strip_edges().to_pascal_case()
	if set_name.is_empty():
		return

	if not _drafts.create_set(set_name):
		_show_dialog(ACTION_FAILED, "'" + set_name + "' is taken or reserved.")
		return

	_new_set_input.text = ""
	_current_set = set_name
	_refresh_set_tree()
	_refresh_attribute_tree()
#endregion


#region Attribute Manager Logic
## Enable the right-hand panel only when a set is selected.
func _update_right_panel_state() -> void:
	var has_set: bool = not _current_set.is_empty()
	_new_attribute_input.editable = has_set
	_new_attribute_value.editable = has_set
	_btn_icon.disabled = not has_set
	_btn_add_attribute.disabled = not has_set
	_btn_generate_script.disabled = not has_set
	_lbl_selected_set.text = (_current_set + " Attributes") if has_set else "No Set Selected"


## Rebuild the tree of attributes for the selected set.
func _refresh_attribute_tree() -> void:
	_attribute_tree.clear()
	_update_right_panel_state()
	if _current_set.is_empty() or not _drafts.has_set(_current_set):
		return

	var root: TreeItem = _attribute_tree.create_item()
	for key: String in _drafts.attribute_names(_current_set):
		_build_attribute_row(root, key, _drafts.entry(_current_set, key))


func _build_attribute_row(root: TreeItem, key: String, entry: AttributeSetDrafts.Entry) -> void:
	var item: TreeItem = _attribute_tree.create_item(root)
	item.set_text(0, key)
	item.set_metadata(0, key)
	item.set_editable(0, true)
	item.set_icon(0, AttributeIcons.texture_for(entry.icon, _default_attr_icon))

	item.set_text(1, str(entry.value))
	item.set_editable(1, true)
	item.add_button(1, _edit_icon_icon, TreeBtn.CHANGE_ICON, false, "Change Icon")
	item.add_button(1, get_theme_icon(DashboardTheme.ICON_COPY, DashboardTheme.EDITOR_ICON_THEME), TreeBtn.DUPLICATE, false, "Duplicate Attribute")
	item.add_button(1, get_theme_icon(DashboardTheme.ICON_REMOVE, DashboardTheme.EDITOR_ICON_THEME), TreeBtn.DELETE, false, "Delete Attribute")


func _on_attribute_tree_button_clicked(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	var attribute_name: String = item.get_metadata(0)
	match id:
		TreeBtn.CHANGE_ICON:
			_editing_icon_attr = attribute_name
			_icon_popup.popup(Rect2(DisplayServer.mouse_get_position(), Vector2.ZERO))
		TreeBtn.DUPLICATE:
			_drafts.duplicate_attribute(_current_set, attribute_name)
			_refresh_attribute_tree()
		TreeBtn.DELETE:
			_stage_deletion(
				DELETE_ATTRIBUTE,
				attribute_name,
				"Delete attribute '" + attribute_name + "' from '" + _current_set + "'?"
			)


func _on_icon_popup_id_pressed(id: int) -> void:
	if _editing_icon_attr.is_empty() or _current_set.is_empty():
		return
	var entry: AttributeSetDrafts.Entry = _drafts.entry(_current_set, _editing_icon_attr)
	entry.icon = _icon_names_map[id]
	_drafts.put(_current_set, _editing_icon_attr, entry)
	_editing_icon_attr = ""
	_refresh_attribute_tree()


func _on_attribute_tree_item_edited() -> void:
	var item: TreeItem = _attribute_tree.get_edited()
	if item == null:
		return
	if _attribute_tree.get_edited_column() == 0:
		_rename_edited_attribute(item)
	else:
		_revalue_edited_attribute(item)


func _rename_edited_attribute(item: TreeItem) -> void:
	var old_name: String = item.get_metadata(0)
	var new_name: String = item.get_text(0).strip_edges().to_snake_case()
	if new_name.is_empty() or new_name == old_name:
		item.set_text(0, old_name)
		return

	if not _drafts.rename_attribute(_current_set, old_name, new_name):
		_show_dialog(ACTION_FAILED, "'" + new_name + "' already exists in this set.")
		item.set_text(0, old_name)
		return

	item.set_metadata(0, new_name)
	item.set_text(0, new_name)


func _revalue_edited_attribute(item: TreeItem) -> void:
	var key: String = item.get_metadata(0)
	var entry: AttributeSetDrafts.Entry = _drafts.entry(_current_set, key)
	entry.value = item.get_text(1).to_float()
	item.set_text(1, str(entry.value))
	_drafts.put(_current_set, key, entry)


func _on_add_attribute_pressed() -> void:
	var attribute_name: String = _new_attribute_input.text.strip_edges().to_snake_case()
	if attribute_name.is_empty() or _current_set.is_empty():
		return

	var icon_index: int = _btn_icon.selected
	var icon_name: String = _btn_icon.get_item_text(icon_index) if icon_index >= 0 else DEFAULT_ICON_NAME
	var entry: AttributeSetDrafts.Entry = AttributeSetDrafts.Entry.of(
		_new_attribute_value.value, icon_name
	)

	if not _drafts.add_attribute(_current_set, attribute_name, entry):
		_show_dialog(ACTION_FAILED, "'" + attribute_name + "' already exists in this set.")
		return

	_new_attribute_input.text = ""
	_new_attribute_value.value = 0.0
	_refresh_attribute_tree()
#endregion


#region Deletion Routing
## Remember what a confirmation is about, then ask.
func _stage_deletion(target_type: String, target_name: String, message: String) -> void:
	_delete_target_type = target_type
	_delete_target_name = target_name
	_delete_confirm_dialog.dialog_text = message
	_delete_confirm_dialog.popup_centered()


## Fired once the confirmation is accepted.
func _execute_delete() -> void:
	if _delete_target_type == DELETE_SET:
		_drafts.delete_set(_delete_target_name)
		if _current_set == _delete_target_name:
			_current_set = ""
		_refresh_set_tree()
	elif _delete_target_type == DELETE_ATTRIBUTE:
		_drafts.delete_attribute(_current_set, _delete_target_name)

	_delete_target_type = ""
	_delete_target_name = ""
	_refresh_attribute_tree()
#endregion


#region Script Generation
## Compile the selected draft and report what happened.
##
## The decision about what is safe to write lives in AttributeSetCompiler,
## which returns an outcome. This function only shows it.
func _on_generate_script_pressed() -> void:
	var outcome: AttributeSetCompiler.Outcome = AttributeSetCompiler.compile(_drafts, _current_set)
	_show_dialog(outcome.title, outcome.message)


func _show_dialog(title: String, message: String) -> void:
	DashboardDialogs.show_message(self, message, title)
#endregion
