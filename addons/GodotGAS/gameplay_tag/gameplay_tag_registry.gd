## The master list of every gameplay tag registered in the project.
##
## Stored as StringName for cheap comparison. Tags are auto-formatted and
## validated on entry, so the registry never holds a shape the queries cannot
## reason about.
##
## Reachable from the GameplayCueManager autoload through project settings, so
## the generator is preloaded rather than named globally: Godot parses this file
## before a global class cache exists on a never-imported checkout.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayTagRegistry extends Resource

const TagGenerator: GDScript = preload("res://addons/GodotGAS/gameplay_tag/gameplay_tag_generator.gd")

## A tag is one or more dot-separated segments, each starting with an uppercase
## letter. Compiled once, lazily, rather than per call.
const TAG_PATTERN: String = "^([A-Z][a-zA-Z0-9]*)(\\.[A-Z][a-zA-Z0-9]*)*$"

const SEGMENT_SEPARATOR: String = "."
const ERROR_PREFIX: String = "Error: "

@export var tags: Array[StringName] = []

var _validator: RegEx = null


#region Tag Management
## Add a tag, auto-formatting its casing first.
##
## Returns the formatted tag on success, or a message beginning with "Error: "
## on failure. The string protocol is upstream's and is preserved here because
## Task 2 changes typing, not behaviour.
func add_tag(tag_string: String) -> String:
	var clean_tag: String = tag_string.strip_edges()
	if clean_tag.is_empty():
		return ERROR_PREFIX + "Cannot add an empty tag."

	var formatted_tag: String = format_tag(clean_tag)
	if not _matches_tag_grammar(formatted_tag):
		return (
			ERROR_PREFIX + "Invalid format '" + formatted_tag
			+ "'. Must use alphanumeric characters and dots."
		)

	var new_tag: StringName = StringName(formatted_tag)
	if has_tag(new_tag):
		return ERROR_PREFIX + "Tag '" + formatted_tag + "' already exists."

	tags.append(new_tag)
	tags.sort_custom(_compare_tags)

	emit_changed()
	TagGenerator.generate_tags_file(tags)
	_save_if_backed_by_a_file()
	return formatted_tag


## Normalise casing: every segment becomes Capitalised, so `test.tesTest`
## becomes `Test.Testest`. Empty segments are preserved so the grammar check
## rejects a double dot rather than silently repairing it.
func format_tag(tag_string: String) -> String:
	var formatted_parts: Array[String] = []
	for part: String in tag_string.split(SEGMENT_SEPARATOR):
		if part.is_empty():
			formatted_parts.append("")
			continue
		var lowered: String = part.to_lower()
		formatted_parts.append(lowered.substr(0, 1).to_upper() + lowered.substr(1))
	return SEGMENT_SEPARATOR.join(formatted_parts)


func _matches_tag_grammar(candidate: String) -> bool:
	if _validator == null:
		_validator = RegEx.new()
		_validator.compile(TAG_PATTERN)
	return _validator.search(candidate) != null


func _compare_tags(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


func _save_if_backed_by_a_file() -> void:
	if not resource_path.is_empty():
		ResourceSaver.save(self, resource_path)


## Remove an exact tag.
func remove_tag(tag_name: StringName) -> void:
	if not has_tag(tag_name):
		return
	tags.erase(tag_name)
	emit_changed()
	TagGenerator.generate_tags_file(tags)
	_save_if_backed_by_a_file()
#endregion


#region Tag Queries
func has_tag(tag_name: StringName) -> bool:
	return tags.has(tag_name)


## Every tag under a parent, so `Status` yields `Status.Stunned` and
## `Status.Burning`. A tag is not a child of itself.
func get_child_tags(parent_tag: StringName) -> Array[StringName]:
	var children: Array[StringName] = []
	var prefix: String = String(parent_tag) + SEGMENT_SEPARATOR
	for tag: StringName in tags:
		if String(tag).begins_with(prefix):
			children.append(tag)
	return children
#endregion
