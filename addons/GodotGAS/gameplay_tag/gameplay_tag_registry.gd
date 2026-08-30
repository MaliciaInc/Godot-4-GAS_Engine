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


## A tag is one or more dot-separated segments, each starting with an uppercase
## letter. Compiled once, lazily, rather than per call.
const TAG_PATTERN: String = "^([A-Z][a-zA-Z0-9]*)(\\.[A-Z][a-zA-Z0-9]*)*$"

const SEGMENT_SEPARATOR: String = "."
const ERROR_PREFIX: String = "Error: "
const SAVE_FAILED: String = "GodotGAS: could not save the tag registry to %s."

@export var tags: Array[StringName] = []

var _validator: RegEx = null


#region Tag Management
## Add a tag, auto-formatting its casing first.
##
## Returns the formatted tag on success, or a message beginning with "Error: "
## on failure. The string protocol is upstream's and is preserved deliberately:
## this fork changed the typing, not the behaviour a caller depends on.
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
	_persist()
	return formatted_tag


## Capitalise the first letter of every segment and leave the rest alone.
##
## Only the first letter, because the grammar above accepts `[A-Z][a-zA-Z0-9]*`
## and a capital inside a segment is therefore legal. This used to lower the
## whole segment first, so `Cue.NeverUsed` - a tag this repository already uses -
## came back as `Cue.Neverused`: the registry silently held a different tag from
## the one the code referred to, and the query that should have matched simply
## returned nothing. The formatter and the grammar have to agree, and the
## grammar is the declared contract.
##
## Empty segments are preserved so the grammar rejects a double dot rather than
## the formatter quietly repairing it.
func format_tag(tag_string: String) -> String:
	var formatted_parts: Array[String] = []
	for part: String in tag_string.split(SEGMENT_SEPARATOR):
		if part.is_empty():
			formatted_parts.append("")
			continue
		formatted_parts.append(part.substr(0, 1).to_upper() + part.substr(1))
	return SEGMENT_SEPARATOR.join(formatted_parts)


func _matches_tag_grammar(candidate: String) -> bool:
	if _validator == null:
		_validator = RegEx.new()
		_validator.compile(TAG_PATTERN)
	return _validator.search(candidate) != null


func _compare_tags(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


## Write the registry and the constants it generates, in that order.
##
## Returns whether both landed. The generator used to be called and its answer
## dropped, so a failed write left the tag in memory, no constant on disk, and
## the caller believing it had succeeded.
## Save this registry, and keep the generated constants in step with it.
##
## A registry nothing has saved anywhere is somebody's working copy, and it
## does not regenerate the project's constants: doing so would replace every
## constant in the project with whatever that copy happened to hold. Only the
## registry that lives on disk speaks for the project.
func _persist() -> bool:
	if resource_path.is_empty():
		return true
	var saved: bool = ResourceSaver.save(self, resource_path) == OK
	if not saved:
		push_error(SAVE_FAILED % resource_path)
	return GameplayTagGenerator.generate_tags_file(tags) and saved


## Remove an exact tag.
func remove_tag(tag_name: StringName) -> void:
	if not has_tag(tag_name):
		return
	tags.erase(tag_name)
	emit_changed()
	_persist()
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
