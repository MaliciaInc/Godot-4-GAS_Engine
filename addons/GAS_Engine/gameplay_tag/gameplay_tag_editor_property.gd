## Inspector editor for a gameplay tag property.
##
## Shows a button on the property row that opens a tag tree with a checkbox per
## tag. The property being edited may hold one tag or many, and the many may be
## an Array or a PackedStringArray, so the shape it arrived in is read once and
## written back unchanged: a property authored as PackedStringArray that comes
## back as Array is a silent type change in the user's scene.
##
## The tree itself is built by GameplayTagTree, shared with both dashboard tabs.
## This file used to walk the tag hierarchy itself, which made four walks of one
## hierarchy in the addon and four places for a tag to be grouped differently.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends EditorProperty


## The id of the per-leaf delete button, distinct from any other button column.
## This script's own type, preloaded rather than named.
##
## The file declares no `class_name`, so its `enum Shape` has no owner to
## qualify it with - and a bare `Shape` annotation binds to any global named
## Shape in whatever project this addon is installed into, not to the enum
## below. The alias gives the enum an owner to be written through. Same idiom
## as GameplayTargetHit's own `Hit`.
const Self = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_editor_property.gd")

const DELETE_BUTTON_ID: int = 1
const DELETE_TOOLTIP: String = "Delete from Registry"

const POPUP_TITLE: String = "Gameplay Tag Editor"
const POPUP_SIZE: Vector2i = Vector2i(900, 750)
const POPUP_MARGIN: int = 8
const NO_TAG: StringName = &""


## How the edited property stores its tags.
##
## Read from the value actually present rather than assumed, and used again on
## write so the property keeps the type it was authored with.
enum Shape {
	## A single StringName or String.
	SINGLE,
	## An untyped or StringName-typed Array.
	ARRAY,
	## A PackedStringArray.
	PACKED,
}

var _button: Button = Button.new()
var _popup: Window = null
var _search_bar: LineEdit = null
var _tree: Tree = null
var _new_tag_input: LineEdit = null
var _add_tag_button: Button = null
var _status_label: Label = null
var _registry: GameplayTagRegistry = null

## The tags currently on the inspected object, mirrored for the button label.
var _current_tags: Array[StringName] = []

## Set while this editor is the one writing, so the write does not rebuild the
## tree under the user's cursor and lose the row they were clicking.
var _is_updating_from_tree: bool = false


#region Lifecycle
func _init() -> void:
	_registry = GameplayTagTree.load_registry()

	_button.text = "Edit Tags..."
	_button.clip_text = true
	add_child(_button)
	add_focusable(_button)
	_button.pressed.connect(_on_button_pressed)


func _enter_tree() -> void:
	if _registry != null and not _registry.changed.is_connected(_on_registry_changed):
		_registry.changed.connect(_on_registry_changed)


func _exit_tree() -> void:
	if _registry != null and _registry.changed.is_connected(_on_registry_changed):
		_registry.changed.disconnect(_on_registry_changed)
#endregion


#region Reading and writing the edited property
## The shape of the value currently in the property.
func _shape_of(value: Variant) -> Self.Shape:
	if value is PackedStringArray:
		return Shape.PACKED
	if value is Array:
		return Shape.ARRAY
	return Shape.SINGLE


## The tags in the property, whatever container they arrived in.
##
## Always a fresh typed array. Handing back the property's own Array would let a
## later `erase` mutate the inspected object behind the inspector's back, which
## is how an edit appeared to work and then failed to save.
func _read_tags(value: Variant) -> Array[StringName]:
	var tags: Array[StringName] = []
	match _shape_of(value):
		Shape.PACKED:
			# Assigned rather than cast: `as` on a Variant is an unsafe cast, while
			# assignment to a typed local is a conversion the engine checks.
			var packed: PackedStringArray = value
			for item: String in packed:
				tags.append(StringName(item))
		Shape.ARRAY:
			var items: Array = value
			for item: Variant in items:
				var tag: StringName = _as_tag(item)
				if tag != NO_TAG:
					tags.append(tag)
		Shape.SINGLE:
			var single: StringName = _as_tag(value)
			if single != NO_TAG:
				tags.append(single)
	return tags


## One Variant as a tag, or NO_TAG when it is neither string type.
##
## An untyped Array property can hold anything, and coercing a stray entry into
## a tag would invent a tag the registry never defined.
func _as_tag(raw: Variant) -> StringName:
	if raw is StringName:
		var already: StringName = raw
		return already
	if raw is String:
		var text: String = raw
		return StringName(text)
	return NO_TAG


## Emit `tags` back in the shape the property was authored with.
func _publish(tags: Array[StringName], shape: Self.Shape) -> void:
	var property: StringName = get_edited_property()
	match shape:
		Shape.PACKED:
			var packed: PackedStringArray = PackedStringArray()
			for tag: StringName in tags:
				packed.append(String(tag))
			emit_changed(property, packed)
		Shape.ARRAY:
			emit_changed(property, tags)
		Shape.SINGLE:
			emit_changed(property, tags[0] if not tags.is_empty() else NO_TAG)

	_current_tags = tags
	_sync_button()


func _sync_button() -> void:
	_button.text = "Tags (%d selected)" % _current_tags.size()


## The value the inspected object currently holds, or null when there is none.
func _edited_value() -> Variant:
	var object: Object = get_edited_object()
	if not is_instance_valid(object):
		return null
	return object.get(get_edited_property())
#endregion


#region Inspector callbacks
## Drop tags this property holds that the registry no longer defines.
##
## Without this a tag deleted globally stays on every object that referenced it,
## and the object keeps claiming a tag nothing can grant.
func _on_registry_changed() -> void:
	if _registry == null:
		return
	var value: Variant = _edited_value()
	if value == null:
		return

	var shape: Self.Shape = _shape_of(value)
	var before: Array[StringName] = _read_tags(value)
	var surviving: Array[StringName] = []
	for tag: StringName in before:
		if _registry.has_tag(tag):
			surviving.append(tag)

	if surviving.size() != before.size():
		_publish(surviving, shape)


func _update_property() -> void:
	var value: Variant = _edited_value()
	_current_tags = _read_tags(value) if value != null else [] as Array[StringName]
	_sync_button()

	if is_instance_valid(_popup) and _popup.visible and not _is_updating_from_tree:
		_refresh_tree()
#endregion


#region The popup
func _on_button_pressed() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()

	_popup = Window.new()
	_popup.title = POPUP_TITLE
	_popup.size = POPUP_SIZE
	_popup.transient = true
	_popup.exclusive = true
	_popup.close_requested.connect(_on_popup_close_requested)

	EditorInterface.get_base_control().add_child(_popup)
	_popup.popup_centered()
	_build_body(_popup)
	_refresh_tree()


func _on_popup_close_requested() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free.call_deferred()


func _build_body(parent: Window) -> void:
	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, POPUP_MARGIN
	)
	parent.add_child(main_vbox)

	_search_bar = LineEdit.new()
	_search_bar.placeholder_text = "Search tags..."
	_search_bar.clear_button_enabled = true
	_search_bar.text_changed.connect(_on_search_changed)
	main_vbox.add_child(_search_bar)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_edited.connect(_on_tree_item_edited)
	_tree.button_clicked.connect(_on_tree_button_clicked)
	main_vbox.add_child(_tree)

	var h_split: HBoxContainer = HBoxContainer.new()
	main_vbox.add_child(h_split)

	_new_tag_input = LineEdit.new()
	_new_tag_input.placeholder_text = "New.Tag.Hierarchy"
	_new_tag_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_split.add_child(_new_tag_input)

	_add_tag_button = Button.new()
	_add_tag_button.text = "Add Tag"
	_add_tag_button.pressed.connect(_on_add_custom_tag)
	h_split.add_child(_add_tag_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_status_label)


func _on_search_changed(_new_text: String) -> void:
	_refresh_tree()


func _refresh_tree() -> void:
	if not is_instance_valid(_tree) or _registry == null:
		return

	var style: GameplayTagTree.Style = GameplayTagTree.Style.new()
	style.checkable = true
	style.checked = _current_tags
	style.leaf_button = EditorInterface.get_editor_theme().get_icon(
		DashboardTheme.ICON_REMOVE, DashboardTheme.EDITOR_ICON_THEME
	)
	style.leaf_button_id = DELETE_BUTTON_ID
	style.leaf_button_tooltip = DELETE_TOOLTIP

	var filter: String = _search_bar.text if is_instance_valid(_search_bar) else ""
	# Nothing is unavailable: this picker assigns tags rather than consuming them.
	GameplayTagTree.build(_tree, filter, [] as Array[StringName], style)
#endregion


#region Editing
## Ticking or unticking a leaf adds or removes exactly that tag.
func _on_tree_item_edited() -> void:
	var item: TreeItem = _tree.get_edited()
	if item == null:
		return
	var raw: Variant = item.get_metadata(0)
	if not raw is StringName:
		return
	var tag: StringName = raw

	var value: Variant = _edited_value()
	if value == null:
		return
	var shape: Self.Shape = _shape_of(value)
	var checked: bool = item.is_checked(0)
	var tags: Array[StringName] = _read_tags(value)

	if shape == Shape.SINGLE:
		# A single-tag property holds one, so ticking replaces rather than adds.
		tags = [tag] as Array[StringName] if checked else [] as Array[StringName]
	elif checked:
		if not tags.has(tag):
			tags.append(tag)
	else:
		tags.erase(tag)

	_is_updating_from_tree = true
	_publish(tags, shape)
	_is_updating_from_tree = false

	if shape == Shape.SINGLE and is_instance_valid(_popup):
		_popup.hide()
		_popup.queue_free.call_deferred()


## The per-leaf button deletes the tag from the registry itself.
func _on_tree_button_clicked(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	if id != DELETE_BUTTON_ID or _registry == null:
		return
	var raw: Variant = item.get_metadata(0)
	if not raw is StringName:
		return
	var tag: StringName = raw

	# Drop it from this property first. Removing it from the registry emits
	# `changed`, and a property still holding it would then be purged by a
	# second write announcing the same edit twice.
	var value: Variant = _edited_value()
	if value != null:
		var shape: Self.Shape = _shape_of(value)
		var tags: Array[StringName] = _read_tags(value)
		if tags.has(tag):
			tags.erase(tag)
			_publish(tags, shape)

	# remove_tag() answers whether the registry and its generated constants were
	# actually written, and rolls the tag back when they were not. `Deleted tag:`
	# used to be printed either way, over a tree that came back still holding it.
	# The drop from this property stands: the tag is still there to pick again.
	if not _registry.remove_tag(tag):
		_set_status("Could not delete '" + String(tag) + "': the registry was not written.", false)
		_refresh_tree()
		return

	_set_status("Deleted tag: " + String(tag), true)
	_refresh_tree()


func _on_add_custom_tag() -> void:
	var text: String = _new_tag_input.text.strip_edges()
	if text.is_empty():
		return
	if _registry == null:
		_set_status("Error: Tag Registry not found.", false)
		return

	var result: String = _registry.add_tag(text)
	if result.begins_with(GameplayTagRegistry.ERROR_PREFIX):
		_set_status(result.replace(GameplayTagRegistry.ERROR_PREFIX, ""), false)
		return

	_set_status("Successfully added: " + result, true)
	_new_tag_input.text = ""
	_refresh_tree()


func _set_status(message: String, is_success: bool) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = message
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	var color_name: String = (
		DashboardTheme.SUCCESS_COLOR if is_success else DashboardTheme.ERROR_COLOR
	)
	_status_label.add_theme_color_override(
		DashboardTheme.FONT_COLOR,
		editor_theme.get_color(color_name, DashboardTheme.EDITOR_THEME_TYPE)
	)
#endregion
