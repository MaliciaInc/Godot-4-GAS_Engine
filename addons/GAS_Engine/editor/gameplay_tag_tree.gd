## Builds a Tree of the project's gameplay tags, grouped by their hierarchy.
##
## `Status.Buff.Haste` becomes Status > Buff > Haste, with each segment created
## once however many tags share it. Only leaves carry the full tag as metadata,
## so a caller cannot mistake a grouping node for a selectable tag.
##
## Extracted from the cue dashboard so the tag picker is one implementation. Two
## trees drawing the same registry differently is how a tag looks available in
## one place and taken in another.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name GameplayTagTree extends RefCounted


const SEPARATOR: String = "."
const UNAVAILABLE_TOOLTIP: String = "Tag already mapped to a Cue"
const REGISTRY_MISSING: String = "GAS_Engine: tag registry not found at "


## How one tag should be drawn.
class Style extends RefCounted:
	var leaf_icon: Texture2D = null
	var leaf_color: Color = Color.WHITE
	var unavailable_color: Color = Color.GRAY

	## An optional per-leaf action, e.g. the tag manager's delete button.
	## Only leaves get it, so a grouping node can never be deleted.
	var leaf_button: Texture2D = null
	var leaf_button_id: int = 0
	var leaf_button_tooltip: String = ""

	## Draw each leaf as a checkbox, ticked when it is in `checked`.
	##
	## The inspector property picks several tags at once rather than one, which
	## is the only way its tree differs from the pickers'. It is a decoration,
	## not a different hierarchy, so it does not justify a second walk.
	var checkable: bool = false
	var checked: Array[StringName] = []


## Populate `tree` from the tag registry.
##
## `unavailable` are drawn greyed and unselectable rather than hidden: a tag the
## user cannot pick because it is already used is information, and removing it
## from the list only makes them look for it.
static func build(
	tree: Tree, filter: String, unavailable: Array[StringName], style: Style
) -> bool:
	tree.clear()
	var registry: GameplayTagRegistry = load_registry()
	if registry == null:
		return false

	# The five values every placement needs travel together rather than as five
	# parameters threaded through each call.
	var run: Run = Run.new()
	run.tree = tree
	run.root = tree.create_item()
	run.unavailable = unavailable
	run.style = style
	run.needle = filter.to_lower()

	for tag: StringName in registry.tags:
		var full: String = String(tag)
		if not run.needle.is_empty() and not full.to_lower().contains(run.needle):
			continue
		_place(run, tag, full)
	return true


## One build in progress: where the rows go and how they are drawn.
class Run extends RefCounted:
	var tree: Tree = null
	var root: TreeItem = null
	var unavailable: Array[StringName] = []
	var style: Style = null
	var needle: String = ""

	func is_searching() -> bool:
		return not needle.is_empty()


## The tag registry, or null when the project has not created one.
##
## Silent in a project that has simply not declared any tags yet, and loud
## in one where the addon is enabled and the registry should exist. Callers
## used to each decide this, so the same absence was a warning in one tab
## and an error in another.
static func load_registry() -> GameplayTagRegistry:
	var path: String = GASEngineProjectSettings.get_registry_tag_path()
	if ResourceLoader.exists(path):
		return load(path)
	if Engine.is_editor_hint() and EditorInterface.is_plugin_enabled(
		GASEngineProjectSettings.ADDON_NAME
	):
		push_warning(REGISTRY_MISSING + path)
	return null


## Walk one tag's segments, reusing branches that already exist.
static func _place(run: Run, tag: StringName, full: String) -> void:
	var current: TreeItem = run.root
	for part: String in full.split(SEPARATOR):
		var existing: TreeItem = _child_named(current, part)
		if existing != null:
			current = existing
			continue
		current = run.tree.create_item(current)
		current.set_text(0, part)
		# Auto-expand while searching, so a match is not hidden under a
		# collapsed parent the user never opened.
		if run.is_searching():
			current.collapsed = false

	_decorate_leaf(current, tag, run.unavailable, run.style)


static func _child_named(parent: TreeItem, text: String) -> TreeItem:
	for child: TreeItem in parent.get_children():
		if child.get_text(0) == text:
			return child
	return null


static func _decorate_leaf(
	leaf: TreeItem, tag: StringName, unavailable: Array[StringName], style: Style
) -> void:
	if unavailable.has(tag):
		leaf.set_selectable(0, false)
		leaf.set_custom_color(0, style.unavailable_color)
		leaf.set_tooltip_text(0, UNAVAILABLE_TOOLTIP)
		return

	# Before the text is written: switching cell mode afterwards is what makes
	# a checkable row come up blank.
	if style.checkable:
		leaf.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		leaf.set_checked(0, style.checked.has(tag))
		leaf.set_editable(0, true)

	leaf.set_icon(0, style.leaf_icon)
	leaf.set_custom_color(0, style.leaf_color)
	leaf.set_text(0, leaf.get_text(0) + " (" + String(tag) + ")")
	# Only a leaf carries the tag, so a grouping node can never be picked.
	leaf.set_metadata(0, tag)
	if style.leaf_button != null:
		leaf.add_button(0, style.leaf_button, style.leaf_button_id, false, style.leaf_button_tooltip)
