## Editor tool for managing the global GameplayTag registry.
##
## Provides a UI to add, search, and delete gameplay tags in a hierarchical 
## tree view, utilizing regex validation to ensure structural integrity.
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends Control

const TAGS_ICON_PATH: String = "res://addons/GodotGAS/icons/godot_gas_tags.svg"

## Colours and styleboxes, shared with the other dashboard tabs.
var _theme: DashboardTheme = DashboardTheme.new()

## Addon project settings.
const GodotGasProjectSettings: = preload("res://addons/GodotGAS/utilities/project_settings.gd")

## Icon used to represent gameplay tags in the tree view.
var _tag_icon: Texture2D

## Reference to the active global tag registry resource.
var _registry: GameplayTagRegistry

## Dialog used to confirm the deletion of a tag.
var _delete_confirm_dialog: ConfirmationDialog

## Temporary storage for the tag currently staged for deletion.
var _tag_to_delete: StringName = ""

## The generated system accent color for active UI elements.

## In-memory styles used to override panels natively to prevent dirtying .tres files

## Reference to the search filter input field.
@onready var _search_bar: LineEdit = %SearchTagFilter

## Reference to the tree node displaying the gameplay tags.
@onready var _tag_tree: Tree = %TagTree

## Reference to the input field for adding a new tag.
@onready var _new_tag_input: LineEdit = %NewTagInput

## Reference to the button to add a new tag.
@onready var _btn_add_tag: Button = %BtnAddTag

## Reference to the button to toggle the expand/collapse state of the tag tree.
@onready var _btn_expand_collapse: Button = %BtnExpandCollapse


#region Initialization
## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		_load_registry()
		_setup_ui()
		_sync_theme_colors()
		_refresh_tag_tree()


## Loads the tag registry from disk.
func _load_registry() -> void:
	var tag_registry_path = GodotGasProjectSettings.get_registry_tag_path()
	if ResourceLoader.exists(tag_registry_path):
		_registry = load(tag_registry_path) as GameplayTagRegistry
	else:
		if not Engine.is_editor_hint() or EditorInterface.is_plugin_enabled(GodotGasProjectSettings.ADDON_NAME):
			push_warning("GodotGAS: Tag Registry not found at " + tag_registry_path)


## Receives Godot Engine broadcasts, allowing us to seamlessly update colors if the user changes themes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if Engine.is_editor_hint() and is_node_ready():
			_sync_theme_colors()
			_refresh_tag_tree()


## Wires up signals and configures the initial UI state.
func _setup_ui() -> void:
	# Configure Tree
	_tag_tree.hide_root = true
	_tag_tree.columns = 1
	_tag_tree.button_clicked.connect(_on_tree_button_clicked)
	
	# Connect Inputs
	_btn_add_tag.pressed.connect(_on_add_tag_pressed)
	_btn_expand_collapse.pressed.connect(_on_expand_collapse_pressed)
	_btn_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME)
	
	# Allow hitting 'Enter' in the text box to add the tag
	_new_tag_input.text_submitted.connect(func(_text): _on_add_tag_pressed()) 
	
	# Fetch theme colors and apply styling
	_sync_theme_colors()
	
	if _search_bar:
		_search_bar.text_changed.connect(_on_search_changed)
		
	# Setup Delete Confirmation
	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.confirmed.connect(_execute_delete)
	add_child(_delete_confirm_dialog)


## Refresh colours from the editor theme and repaint this tab.
##
## The derivation lives in DashboardTheme, shared with the other tabs. This
## file held the third private copy of it.
func _sync_theme_colors() -> void:
	if not _theme.sync_from_editor():
		return
	_theme.apply_panels(self)
	_tag_icon = DashboardTheme.icon(TAGS_ICON_PATH)
	_theme.apply_tab_icon(self, _tag_icon)
#endregion


#region Tree Building & Filtering
## Called when the search bar text is updated.
func _on_search_changed(_text: String) -> void:
	_refresh_tag_tree()


## Rebuilds the visual tree of all registered gameplay tags.
func _refresh_tag_tree() -> void:
	_tag_tree.clear()
	var root = _tag_tree.create_item()
	
	if not _registry:
		return
		
	var filter = _search_bar.text.to_lower() if _search_bar else ""

	# Get Icons and Colors natively from Editor
	var trash_icon = get_theme_icon(DashboardTheme.ICON_REMOVE, DashboardTheme.EDITOR_ICON_THEME)
	var editor_theme = EditorInterface.get_editor_theme()
	var accent_color = editor_theme.get_color(DashboardTheme.ACCENT_COLOR, DashboardTheme.EDITOR_THEME_TYPE)

	for tag_name in _registry.tags:
		var tag_str = String(tag_name)
		
		# If searching, skip tags that don't match
		if filter != "" and not filter in tag_str.to_lower():
			continue
			
		var parts = tag_str.split(".")
		var current = root
		
		for i in range(parts.size()):
			var part = parts[i]
			var found_item: TreeItem = null
			
			# Index-based child traversal (Godot 4 safe)
			for child_idx in range(current.get_child_count()):
				var child = current.get_child(child_idx)
				if child.get_text(0) == part:
					found_item = child
					break
			
			if found_item:
				current = found_item
			else:
				current = _tag_tree.create_item(current)
				current.set_text(0, part)
				# Automatically expand folders when searching
				if filter != "":
					current.collapsed = false 
				
			# If this is the final part of the tag (the leaf)
			if i == parts.size() - 1:
				current.set_icon(0, _tag_icon)
				current.set_custom_color(0, accent_color)
				current.set_metadata(0, tag_str)
				current.set_text(0, part + " (" + tag_name + ")")
				
				# Add the native Trash button to the right side of this item
				current.add_button(0, trash_icon, 0)
#endregion


#region CRUD Logic
## Submits the input field text to the registry for validation and addition.
func _on_add_tag_pressed() -> void:
	var input_text = _new_tag_input.text.strip_edges()
	if input_text == "":
		return
		
	if not _registry:
		push_error("GodotGAS: Cannot add tag, registry is missing.")
		return
		
	# Call your custom add_tag function which handles regex and sorting
	var result = _registry.add_tag(input_text)
	
	if result.begins_with(GameplayTagRegistry.ERROR_PREFIX.strip_edges()):
		# Show a native editor warning dialog
		var warning = AcceptDialog.new()
		warning.dialog_text = result
		add_child(warning)
		warning.popup_centered()
	else:
		# Success! Clear input and refresh
		_new_tag_input.text = ""
		_refresh_tag_tree()


## Toggles the expand/collapse state of the entire tag tree.
func _on_expand_collapse_pressed() -> void:
	# Collapse/Expand Logic
	for child in _tag_tree.get_root().get_children():
		child.collapsed = !child.collapsed
		
	# Update tooltip
	_btn_expand_collapse.tooltip_text = DashboardTheme.LABEL_EXPAND_TREE if _tag_tree.get_root().get_first_child().collapsed else DashboardTheme.LABEL_COLLAPSE_TREE
	
	# Update Icon
	if _tag_tree.get_root().collapsed:
		_btn_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_EXPAND_TREE, DashboardTheme.EDITOR_ICON_THEME)
	else:
		_btn_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME)


## Triggered when an action button on a tree item is clicked (e.g., delete).
func _on_tree_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	# id 0 is our trashcan button
	if id == 0: 
		var tag_val = item.get_metadata(0)
		if tag_val != null:
			_tag_to_delete = tag_val
			_delete_confirm_dialog.dialog_text = "Are you sure you want to delete the tag:\n'%s'?" % _tag_to_delete
			_delete_confirm_dialog.popup_centered()


## Global routing function that fires after the delete confirm dialog is accepted.
func _execute_delete() -> void:
	if _tag_to_delete != "" and _registry:
		_registry.remove_tag(_tag_to_delete)
		_tag_to_delete = ""
		_refresh_tag_tree()
#endregion
