## Replaces the default inspector UI of tag-shaped properties with a tag picker.
##
## `_parse_property` below takes seven parameters, past the five this project
## holds itself to. The signature is Godot's, not ours: overriding it with
## fewer simply stops the override working, and the tag picker has no other
## entry point. It is exempted by name, with that reason written down, rather
## than the limit being raised for everything.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends EditorInspectorPlugin

const GameplayTagEditorProperty = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_editor_property.gd")

## The property name the tag registry itself uses for its tag list.
const REGISTRY_PROPERTY: String = "tags"

## Property types a tag picker can stand in for.
const PICKABLE_TYPES: Array[int] = [
	TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_STRING, TYPE_STRING_NAME
]


#region Inspector Parsing
func _can_handle(_object: Object) -> bool:
	return true


## Intercept a property and offer a tag picker instead of the default field.
##
## Seven parameters, fixed by Godot. See the gate conflict noted above.
func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if not GASEngineProjectSettings.get_editor_tag_property_editor_enabled():
		return false
	if is_registry_tag_list(object, name):
		return false
	if not matches_tag_naming(name):
		return false
	if not PICKABLE_TYPES.has(type):
		return false

	add_property_editor(name, GameplayTagEditorProperty.new())
	return true


## The registry's own `tags` array must keep the default editor.
##
## With a picker there, clicking a tag would read as "deselect" and would delete
## it from the project permanently.
static func is_registry_tag_list(object: Object, name: String) -> bool:
	return name.to_lower() == REGISTRY_PROPERTY and object is GameplayTagRegistry


## Whether a property name looks like a tag, per the configured match rule.
##
## Each needle is trimmed and lowered to meet the name, which is already
## lowered. The list is read from a text setting, so it arrives however somebody
## typed it: writing it the ordinary way - `gas_tag, gas_tags` - used to drop
## every needle after the first, because " gas_tags" is not a suffix of
## anything, and any needle in mixed case was dropped outright. No error, no
## picker, and nothing to suggest the setting was the reason.
##
## A needle that is nothing but spaces claims no property. Empty, under PREFIX
## or ANYWHERE, would match every string field in the inspector.
static func matches_tag_naming(name: String) -> bool:
	var lowered: String = name.to_lower()
	var match_type: int = GASEngineProjectSettings.get_editor_tag_property_editor_match_type()
	for needle: String in GASEngineProjectSettings.get_editor_tag_property_editor_match_on():
		var cleaned: String = needle.strip_edges().to_lower()
		if cleaned.is_empty():
			continue
		if _matches_one(lowered, cleaned, match_type):
			return true
	return false


static func _matches_one(lowered: String, needle: String, match_type: int) -> bool:
	match match_type:
		GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.PREFIX:
			return lowered.begins_with(needle)
		GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.SUFFIX:
			return lowered.ends_with(needle)
		GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.ANYWHERE:
			return lowered.contains(needle)
	return false
#endregion
