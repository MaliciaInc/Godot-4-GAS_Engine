## Project settings this addon owns, read and registered in one place.
##
## Every declaration is explicitly typed and no `:=` appears: section 2.1 of the
## phase plan forbids inference, and this file is reached from the
## GameplayCueManager autoload, so an inference warning here is a boot failure
## rather than a lint note.
##
## This file declares settings and reads them. It does NOT create the default
## registry resources any more: doing so required preloading the two registry
## scripts, and the tag registry preloads the generator, which preloads this
## file back - a preload cycle. Seeding defaults is an editor concern and now
## lives in godot_gas_plugin.gd, which the autoload never reaches.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT
extends Object

enum EditorTagsTagEditorPropertyMatchType {
	PREFIX,
	SUFFIX,
	ANYWHERE,
}

const PROJECT_SETTINGS_NAME: String = "godot_gas"
const PROJECT_SETTINGS_NAME_EDITOR: String = PROJECT_SETTINGS_NAME + "/editor"
const PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR: String = PROJECT_SETTINGS_NAME_EDITOR + "/tag_property_editor"
const PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_ENABLE: String = PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR + "/enable"
const PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH: String = PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR + "/match"
const PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_ON: String = PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH + "/on"
const PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_TYPE: String = PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH + "/type"
const PROJECT_SETTINGS_NAME_RESOURCES: String = PROJECT_SETTINGS_NAME + "/resources"
const PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES: String = PROJECT_SETTINGS_NAME_RESOURCES + "/attributes"
const PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_DRAFT_CONFIG_FILE: String = PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES + "/draft_configuration_file"
const PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_OUTPUT_DIR: String = PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES + "/output_directory"
const PROJECT_SETTINGS_NAME_RESOURCES_CUES: String = PROJECT_SETTINGS_NAME_RESOURCES + "/cues"
const PROJECT_SETTINGS_NAME_RESOURCES_CUES_REGISTRY: String = PROJECT_SETTINGS_NAME_RESOURCES_CUES + "/registry_file"
const PROJECT_SETTINGS_NAME_RESOURCES_TAGS: String = PROJECT_SETTINGS_NAME_RESOURCES + "/tags"
const PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY: String = PROJECT_SETTINGS_NAME_RESOURCES_TAGS + "/registry_file"
const PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT: String = PROJECT_SETTINGS_NAME_RESOURCES_TAGS + "/generated_script"

const DEFAULT_TAG_PROPERTY_EDITOR_ENABLE: bool = true
const DEFAULT_TAG_PROPERTY_EDITOR_MATCH_ON: String = "gas_tag,gas_tags"
const DEFAULT_TAG_PROPERTY_EDITOR_MATCH_TYPE: EditorTagsTagEditorPropertyMatchType = EditorTagsTagEditorPropertyMatchType.SUFFIX

const DEFAULT_PATH: String = "res://godot_gas"
const DEFAULT_PATH_ATTRIBUTES_DRAFT_CONFIG_FILE: String = DEFAULT_PATH + "/attributes_draft.cfg"
const DEFAULT_PATH_ATTRIBUTES_OUTPUT_DIR: String = DEFAULT_PATH + "/attributes"
const DEFAULT_PATH_CUES_REGISTRY: String = DEFAULT_PATH + "/cue_registry.tres"
const DEFAULT_PATH_TAGS_REGISTRY: String = DEFAULT_PATH + "/tag_registry.tres"
const DEFAULT_PATH_TAGS_GENERATED_SCRIPT: String = DEFAULT_PATH + "/gameplay_tags.gd"

## Property-info keys, named once. They are Godot's own dictionary schema, and
## writing them out at each of the six call sites is how one of them ends up
## misspelled with nothing to report it.
const INFO_NAME: String = "name"
const INFO_TYPE: String = "type"
const INFO_HINT: String = "hint"
const INFO_HINT_STRING: String = "hint_string"

## The example tags a fresh tag registry is seeded with.
const EXAMPLE_TAGS: Array[StringName] = [
	&"Example.Ability.Arrow.Impact",
	&"Example.Ability.Arrow.Shoot",
	&"Example.Ability.Heal.Triggered",
	&"Example.Ability.Poison.Applied",
	&"Example.Ability.Poison.Cast",
	&"Example.Event.Damage.Critical",
	&"Example.Event.Damage.Missed",
	&"Example.Event.Damage.Normal",
	&"Example.Event.Defend.Hit",
	&"Example.State.Cooldown.Arrow",
	&"Example.State.Cooldown.Poison",
]

## Greys the editor icons are recoloured from. Declared rather than repeated so
## the set is auditable and the magic-string gate has nothing to find.
const ICON_NEUTRAL_GREYS: Array[String] = ["#e0e0e0", "#E0E0E0", "#ffffff", "#FFFFFF"]


#region Registration
static func init_project_settings() -> void:
	_init_attributes_draft_config_path()
	_init_attributes_output_dir()
	_init_generated_tag_script_path()
	_init_registry_cue()
	_init_registry_tag()
	_init_editor_tag_property_editor()


## Read a setting, registering the default the first time it is asked for. All
## readers go through this, so no accessor can invent a different default.
static func _setting_or_default(setting_name: String, default_value: Variant) -> Variant:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)
	return ProjectSettings.get_setting(setting_name)


static func _declare(setting_name: String, default_value: Variant, info: Dictionary) -> void:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)
	ProjectSettings.set_initial_value(setting_name, default_value)
	ProjectSettings.add_property_info(info)


static func _file_info(setting_name: String) -> Dictionary:
	return {INFO_NAME: setting_name, INFO_TYPE: TYPE_STRING, INFO_HINT: PROPERTY_HINT_FILE_PATH}
#endregion


#region Accessors
static func get_attributes_draft_config_path() -> String:
	return _setting_or_default(
		PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_DRAFT_CONFIG_FILE,
		DEFAULT_PATH_ATTRIBUTES_DRAFT_CONFIG_FILE
	)


static func get_attributes_output_dir_path() -> String:
	return _setting_or_default(
		PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_OUTPUT_DIR, DEFAULT_PATH_ATTRIBUTES_OUTPUT_DIR
	)


static func get_generated_tag_script_path() -> String:
	return _setting_or_default(
		PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT, DEFAULT_PATH_TAGS_GENERATED_SCRIPT
	)


static func get_registry_cue_path() -> String:
	return _setting_or_default(PROJECT_SETTINGS_NAME_RESOURCES_CUES_REGISTRY, DEFAULT_PATH_CUES_REGISTRY)


static func get_registry_tag_path() -> String:
	return _setting_or_default(PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY, DEFAULT_PATH_TAGS_REGISTRY)


static func get_editor_tag_property_editor_enabled() -> bool:
	return _setting_or_default(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_ENABLE, DEFAULT_TAG_PROPERTY_EDITOR_ENABLE
	)


static func get_editor_tag_property_editor_match_on() -> PackedStringArray:
	var match_on_list: String = _setting_or_default(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_ON, DEFAULT_TAG_PROPERTY_EDITOR_MATCH_ON
	)
	return match_on_list.split(",", false)


static func get_editor_tag_property_editor_match_type() -> EditorTagsTagEditorPropertyMatchType:
	var raw: int = _setting_or_default(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_TYPE, DEFAULT_TAG_PROPERTY_EDITOR_MATCH_TYPE
	)
	return raw as EditorTagsTagEditorPropertyMatchType
#endregion


#region Initialisers
static func _init_attributes_output_dir() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_OUTPUT_DIR,
		DEFAULT_PATH_ATTRIBUTES_OUTPUT_DIR,
		{
			INFO_NAME: PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_OUTPUT_DIR,
			INFO_TYPE: TYPE_STRING,
			INFO_HINT: PROPERTY_HINT_DIR,
		}
	)
	var output_dir: String = ProjectSettings.get_setting(PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_OUTPUT_DIR)
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)


static func _init_attributes_draft_config_path() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_DRAFT_CONFIG_FILE,
		DEFAULT_PATH_ATTRIBUTES_DRAFT_CONFIG_FILE,
		_file_info(PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_DRAFT_CONFIG_FILE)
	)


static func _init_generated_tag_script_path() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT,
		DEFAULT_PATH_TAGS_GENERATED_SCRIPT,
		_file_info(PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT)
	)


static func _init_registry_cue() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_RESOURCES_CUES_REGISTRY,
		DEFAULT_PATH_CUES_REGISTRY,
		_file_info(PROJECT_SETTINGS_NAME_RESOURCES_CUES_REGISTRY)
	)


static func _init_registry_tag() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY,
		DEFAULT_PATH_TAGS_REGISTRY,
		_file_info(PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY)
	)


static func _init_editor_tag_property_editor() -> void:
	_declare(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_ENABLE,
		DEFAULT_TAG_PROPERTY_EDITOR_ENABLE,
		{INFO_NAME: PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_ENABLE, INFO_TYPE: TYPE_BOOL}
	)
	_declare(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_ON,
		DEFAULT_TAG_PROPERTY_EDITOR_MATCH_ON,
		{INFO_NAME: PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_ON, INFO_TYPE: TYPE_STRING}
	)
	_declare(
		PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_TYPE,
		DEFAULT_TAG_PROPERTY_EDITOR_MATCH_TYPE,
		{
			INFO_NAME: PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_TYPE,
			INFO_TYPE: TYPE_INT,
			INFO_HINT: PROPERTY_HINT_ENUM,
			INFO_HINT_STRING: "Prefix,Suffix,Anywhere",
		}
	)
#endregion


#region Editor Icons
## Recolour an SVG in memory to the editor's font colour and rasterise it at the
## user's UI scale, so icons stay legible on a 4K monitor and under both themes.
##
## Returns the plain resource outside the editor, where none of this applies.
static func get_svg_icon(path: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return load(path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return load(path)

	var svg_text: String = file.get_as_text()
	file.close()

	var editor_theme: Theme = EditorInterface.get_editor_theme()
	var font_color: String = "#" + editor_theme.get_color("font_color", "Editor").to_html(false)
	for grey: String in ICON_NEUTRAL_GREYS:
		svg_text = svg_text.replace(grey, font_color)

	var image: Image = Image.new()
	var editor_scale: float = EditorInterface.get_editor_scale()
	var err: int = image.load_svg_from_string(svg_text, editor_scale)
	if err == OK:
		return ImageTexture.create_from_image(image)

	return load(path)
#endregion
