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
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT

@tool
class_name GameplayTagTree extends RefCounted

const GodotGasProjectSettings = preload("res://addons/GodotGAS/utilities/project_settings.gd")

const SEPARATOR: String = "."
const UNAVAILABLE_TOOLTIP: String = "Tag already mapped to a Cue"


## How one tag should be drawn.
class Style extends RefCounted:
	var leaf_icon: Texture2D = null
	var leaf_color: Color = Color.WHITE
	var unavailable_color: Color = Color.GRAY


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


static func load_registry() -> GameplayTagRegistry:
	var path: String = GodotGasProjectSettings.get_registry_tag_path()
	if not ResourceLoader.exists(path):
		push_error("GodotGAS: tag registry not found at " + path)
		return null
	return load(path)


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

	leaf.set_icon(0, style.leaf_icon)
	leaf.set_custom_color(0, style.leaf_color)
	leaf.set_text(0, leaf.get_text(0) + " (" + String(tag) + ")")
	# Only a leaf carries the tag, so a grouping node can never be picked.
	leaf.set_metadata(0, tag)
