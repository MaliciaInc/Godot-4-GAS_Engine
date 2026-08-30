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
