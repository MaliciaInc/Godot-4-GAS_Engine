## Editor tool for mapping GameplayTags to GameplayCues.
##
## Provides a UI to associate visual/audio scenes with specific tags,
## storing these mappings in the global cue registry.
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends Control

## Addon project settings.

## Icon used to represent gameplay tags.
const TAG_ICON: Texture2D = preload("res://addons/GodotGAS/icons/godot_gas_tags.svg")

## Icon used to represent packed scenes (cues).
const SCENE_ICON: Texture2D = preload("res://addons/GodotGAS/icons/godot_gas_cues.svg")
const CUES_ICON_PATH: String = "res://addons/GodotGAS/icons/godot_gas_cues.svg"

## Placeholders shown on the edit form while a mapping is half-built.
const NO_SCENE_SELECTED: String = "No Scene Selected"
const SELECT_TAG_PROMPT: String = "Select Tag..."

## Shown when the user acts on a registry the project does not have. A fresh
## checkout has none, so this is reachable the first time the dashboard opens.
const NO_REGISTRY_TITLE: String = "No Cue Registry"
const NO_REGISTRY_MESSAGE: String = (
	"This project has no cue registry yet, so there is nowhere to store the mapping. Create one before adding cues."
)

## Colours and styleboxes, shared with the other dashboard tabs.
var _theme: DashboardTheme = DashboardTheme.new()

## Reference to the active global cue registry resource.
var _registry: GameplayCueRegistry = null

## Temporary storage for the tag currently being mapped.
var _draft_tag: StringName = &""

## Temporary storage for the scene currently being mapped.
var _draft_scene: PackedScene = null

## Tracks the array index of the cue currently being edited (-1 if new).
var _editing_index: int = -1

## Tracks the array index of the cue staged for deletion.
var _delete_index: int = -1

## Dialog used to select a PackedScene file.
var _scene_dialog: EditorFileDialog = null

## Dialog used to select a GameplayTag from the registry.
var _tag_dialog: ConfirmationDialog = null

## Container for the tag selection tree interface.
var _tag_tree_vbox: VBoxContainer = null

## Input field for filtering the tag selection tree.
var _tag_search_bar: LineEdit = null

## Button to toggle the expand/collapse state of the tag tree.
var _btn_tag_expand_collapse: Button = null

## Tree node displaying available gameplay tags.
var _tag_tree: Tree = null

## Dialog used to confirm the deletion of a cue mapping.
var _delete_confirm_dialog: ConfirmationDialog = null

## The generated system accent color for active UI elements.

## In-memory styles used to override panels natively to prevent dirtying .tres files

## Reference to the search filter input field.
@onready var _search_bar: LineEdit = %SearchFilter

## Reference to the vertical box containing the mapped cues.
@onready var _cue_list_vbox: VBoxContainer = %CueListVBox

## Reference to the label displaying the selected scene file name.
@onready var _lbl_selected_scene: Label = %LblSelectedScene

## Reference to the button used to trigger tag selection.
@onready var _btn_select_tag: Button = %BtnSelectTag

## Reference to the button used to browse for a scene file.
@onready var _btn_browse_scene: Button = %BtnBrowseScene

## Reference to the button used to commit a new or edited mapping.
@onready var _btn_add_mapping: Button = %BtnAddMapping

## Reference to the button used to cancel the current edit.
@onready var _btn_cancel: Button = %BtnCancel


#region Initialization
## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		_load_registry()
		_setup_ui()
		_sync_theme_colors()
		_refresh_cue_list()
		_reset_form()
		
		# Connect the Search Filter
		if _search_bar:
			_search_bar.text_changed.connect(_on_search_changed)


## Loads the cue registry from disk.
func _load_registry() -> void:
	var cue_registry_path: String = GodotGasProjectSettings.get_registry_cue_path()
	if ResourceLoader.exists(cue_registry_path):
		_registry = load(cue_registry_path) as GameplayCueRegistry
	else:
		push_warning("GodotGAS: Cue Registry not found at " + cue_registry_path)


## Receives Godot Engine broadcasts, allowing us to seamlessly update colors if the user changes themes.
func _notification(what: int) -> void:
	if what == Control.NOTIFICATION_THEME_CHANGED:
		if Engine.is_editor_hint() and is_node_ready():
			_sync_theme_colors()
			_refresh_cue_list(_current_filter())


## Wires up signals and instantiates the dynamic UI dialogs.
func _setup_ui() -> void:
	# Connect Form Buttons
	_btn_browse_scene.pressed.connect(_on_browse_scene_pressed)
	_btn_select_tag.pressed.connect(_on_select_tag_pressed)
	_btn_add_mapping.pressed.connect(_on_add_mapping_pressed)
	
	_btn_cancel.pressed.connect(_reset_form)
	_btn_cancel.icon = get_theme_icon("Close", DashboardTheme.EDITOR_ICON_THEME)
	
	# Fetch theme colors and apply styling
	_sync_theme_colors()
	
	if _cue_list_vbox:
		_cue_list_vbox.add_theme_constant_override("separation", 8)
	
	# Build the Scene Browser Dialog
	_scene_dialog = EditorFileDialog.new()
	_scene_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_scene_dialog.add_filter("*.tscn", "Godot Scene")
	_scene_dialog.file_selected.connect(_on_scene_selected)
	add_child(_scene_dialog)
	
	# Build the Delete Confirmation Dialog
	_delete_confirm_dialog = ConfirmationDialog.new()
	_delete_confirm_dialog.confirmed.connect(_execute_delete)
	add_child(_delete_confirm_dialog)
	
	# Build the Scalable Tag Picker (Tree View with Search)
	_tag_dialog = ConfirmationDialog.new()
	_tag_dialog.title = "Select Gameplay Tag"
	_tag_dialog.confirmed.connect(_on_tag_dialog_confirmed)
	
	_tag_tree_vbox = VBoxContainer.new()
	_tag_tree_vbox.custom_minimum_size = Vector2(800, 600)
	
	# Create HBox for Search Bar + Expand/Collapse Button
	var search_hbox: HBoxContainer = HBoxContainer.new()
	_tag_tree_vbox.add_child(search_hbox)
	
	_tag_search_bar = LineEdit.new()
	_tag_search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_search_bar.placeholder_text = "Filter Tags..."
	_tag_search_bar.clear_button_enabled = true
	_tag_search_bar.text_changed.connect(_on_tag_search_changed)
	search_hbox.add_child(_tag_search_bar)
	
	_btn_tag_expand_collapse = Button.new()
	_btn_tag_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME)
	_btn_tag_expand_collapse.tooltip_text = DashboardTheme.LABEL_COLLAPSE_TREE
	_btn_tag_expand_collapse.pressed.connect(_on_tag_expand_collapse_pressed)
	search_hbox.add_child(_btn_tag_expand_collapse)
	
	_tag_tree = Tree.new()
	_tag_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tag_tree.hide_root = true
	_tag_tree_vbox.add_child(_tag_tree)
	
	_tag_dialog.add_child(_tag_tree_vbox)
	add_child(_tag_dialog)


## Synchronizes internal color variables and generates dynamic StyleBoxes to match the Editor Theme.
func _sync_theme_colors() -> void:
	if not _theme.sync_from_editor():
		return
	_theme.apply_panels(self)
	_theme.apply_tab_icon(self, DashboardTheme.icon(CUES_ICON_PATH))


#endregion


## The text currently in the search bar, or nothing when there is no bar.
##
## Four call sites re-read it inline, and each spelled the null check itself.
func _current_filter() -> String:
	return _search_bar.text if _search_bar != null else ""


#region Button Handlers & Search
## Called when the main search bar text is updated.
func _on_search_changed(new_text: String) -> void:
	_refresh_cue_list(new_text)


## Opens the file dialog to browse for a scene.
func _on_browse_scene_pressed() -> void:
	_scene_dialog.popup_file_dialog()


## Stores the selected scene path and updates the UI label.
func _on_scene_selected(path: String) -> void:
	_draft_scene = load(path) as PackedScene
	_lbl_selected_scene.text = path.get_file()


## Prepares and opens the dynamic tag picker dialog.
func _on_select_tag_pressed() -> void:
	_tag_search_bar.text = "" # Reset filter on open
	
	# Reset expand/collapse button state to default (Expanded)
	_btn_tag_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME)
	_btn_tag_expand_collapse.tooltip_text = DashboardTheme.LABEL_COLLAPSE_TREE
	
	_build_tag_tree()
	_tag_dialog.popup_centered()


## Filters the dynamic tag tree based on search input.
func _on_tag_search_changed(new_text: String) -> void:
	_build_tag_tree(new_text)


## Toggles the expand/collapse state of all top-level tag tree items.
func _on_tag_expand_collapse_pressed() -> void:
	var root: TreeItem = _tag_tree.get_root()
	if not root or not root.get_first_child(): 
		return
	
	# Determine the new state based on the first child folder
	var new_collapsed_state: bool = not root.get_first_child().collapsed
	
	# Apply to all top-level children
	for child: TreeItem in root.get_children():
		child.collapsed = new_collapsed_state
		
	# Update Button UI
	if new_collapsed_state:
		_btn_tag_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_EXPAND_TREE, DashboardTheme.EDITOR_ICON_THEME)
		_btn_tag_expand_collapse.tooltip_text = DashboardTheme.LABEL_EXPAND_TREE
	else:
		_btn_tag_expand_collapse.icon = get_theme_icon(DashboardTheme.ICON_COLLAPSE_TREE, DashboardTheme.EDITOR_ICON_THEME)
		_btn_tag_expand_collapse.tooltip_text = DashboardTheme.LABEL_COLLAPSE_TREE


## Rebuild the tag picker, greying out tags this registry already maps.
##
## The tree itself is built by GameplayTagTree, shared so the picker is one
## implementation rather than one per dashboard tab.
func _build_tag_tree(filter: String = "") -> void:
	var style: GameplayTagTree.Style = GameplayTagTree.Style.new()
	style.leaf_icon = TAG_ICON
	style.leaf_color = _theme.text_accent
	style.unavailable_color = EditorInterface.get_editor_theme().get_color(
		DashboardTheme.DISABLED_FONT_COLOR, DashboardTheme.EDITOR_THEME_TYPE
	)
	GameplayTagTree.build(_tag_tree, filter, _mapped_tags(), style)


## The tags this registry has already bound to a cue.
func _mapped_tags() -> Array[StringName]:
	var taken: Array[StringName] = []
	if _registry == null:
		return taken
	for entry: GameplayCueEntry in _registry.entries:
		taken.append(entry.tag)
	return taken


## Validates and stores the tag selected from the picker dialog.
func _on_tag_dialog_confirmed() -> void:
	var selected: TreeItem = _tag_tree.get_selected()
	if selected == null:
		return
	# A grouping node carries no metadata; only a leaf carries a tag. Testing
	# the type rather than null also rejects a leaf built with the wrong one.
	var chosen: Variant = selected.get_metadata(0)
	if not chosen is StringName:
		return
	_draft_tag = chosen
	_btn_select_tag.text = String(_draft_tag)
#endregion


#region CRUD Logic
## Commits the drafted mapping (tag + scene) into the cue registry.
func _on_add_mapping_pressed() -> void:
	if _registry == null:
		# The form fills in without a registry, so this is the one path a user can
		# reach with nothing to write to. Told in a dialog rather than the console,
		# because they pressed a button and are waiting for an answer.
		DashboardDialogs.show_message(self, NO_REGISTRY_MESSAGE, NO_REGISTRY_TITLE)
		return
	if _draft_tag == "" or _draft_scene == null:
		push_warning("GodotGAS: Must select both a Tag and a Scene.")
		return
		
	# DUPLICATE CHECK: Prevent 1 tag having multiple scenes
	for i: int in _registry.entries.size():
		if i != _editing_index and _registry.entries[i].tag == _draft_tag:
			push_error("GodotGAS: A cue is already mapped to '%s'. Only 1 Scene per Tag is allowed." % str(_draft_tag))
			return
		
	if _editing_index >= 0:
		var entry: GameplayCueEntry = _registry.entries[_editing_index]
		entry.tag = _draft_tag
		entry.scene = _draft_scene
	else:
		var new_entry: GameplayCueEntry = GameplayCueEntry.new()
		new_entry.tag = _draft_tag
		new_entry.scene = _draft_scene
		_registry.entries.append(new_entry)
		
	ResourceSaver.save(_registry, GodotGasProjectSettings.get_registry_cue_path())
	_reset_form()
	
	# Refresh with the current filter so the list does not visually reset.
	_refresh_cue_list(_current_filter())


## Sets up the form fields to edit an existing cue mapping.
func _on_edit_pressed(index: int) -> void:
	if _registry == null:
		return
	_editing_index = index
	var entry: GameplayCueEntry = _registry.entries[index]
	
	_draft_tag = entry.tag
	_draft_scene = entry.scene
	
	_btn_select_tag.text = String(entry.tag) if entry.tag != &"" else SELECT_TAG_PROMPT
	_lbl_selected_scene.text = (
		entry.scene.resource_path.get_file() if entry.scene != null else NO_SCENE_SELECTED
	)
	
	_btn_add_mapping.text = "Save Changes"
	_btn_add_mapping.icon = get_theme_icon("Save", DashboardTheme.EDITOR_ICON_THEME)
	_btn_cancel.show()


## Prepares the deletion confirmation dialog for a specific row.
func _on_delete_pressed(index: int) -> void:
	if _registry == null:
		return
	_delete_index = index
	var entry: GameplayCueEntry = _registry.entries[index]
	
	# Contextual popup showing what is being deleted
	_delete_confirm_dialog.dialog_text = "Delete Mapping?\nTag: %s\nScene: %s" % [str(entry.tag), entry.scene.resource_path.get_file() if entry.scene else "None"]
	_delete_confirm_dialog.popup_centered()


## Global routing function that fires after the delete confirm dialog is accepted.
func _execute_delete() -> void:
	if _registry == null:
		return
	if _delete_index < 0 or _delete_index >= _registry.entries.size():
		return
		
	_registry.entries.remove_at(_delete_index)
	ResourceSaver.save(_registry,  GodotGasProjectSettings.get_registry_cue_path())
	
	if _delete_index == _editing_index:
		_reset_form()
		
	_delete_index = -1
	_refresh_cue_list(_current_filter())


## Resets the data entry form back to its default state.
func _reset_form() -> void:
	_editing_index = -1
	_draft_tag = ""
	_draft_scene = null
	
	_btn_select_tag.text = SELECT_TAG_PROMPT
	_lbl_selected_scene.text = NO_SCENE_SELECTED
	
	_btn_add_mapping.text = "Add Mapping"
	_btn_add_mapping.icon = get_theme_icon("Add", DashboardTheme.EDITOR_ICON_THEME)
	_btn_cancel.hide()


## Rebuilds the visual list of configured cue mappings.
func _refresh_cue_list(filter: String = "") -> void:
	for child: Node in _cue_list_vbox.get_children():
		child.queue_free()
	if _registry == null:
		return

	var needle: String = filter.to_lower()
	for entry: GameplayCueEntry in _registry.entries:
		var tag_str: String = String(entry.tag) if entry.tag != &"" else CueRow.UNASSIGNED_TAG
		if not needle.is_empty() and not tag_str.to_lower().contains(needle):
			continue

		# The entry's index in the registry, not its position in the filtered
		# list: Edit and Delete address the registry.
		var index: int = _registry.entries.find(entry)
		var row: CueRow.Built = CueRow.build(entry, _theme, TAG_ICON, SCENE_ICON)
		row.edit_button.pressed.connect(_on_edit_pressed.bind(index))
		row.delete_button.pressed.connect(_on_delete_pressed.bind(index))
		_cue_list_vbox.add_child(row.card)
#endregion
