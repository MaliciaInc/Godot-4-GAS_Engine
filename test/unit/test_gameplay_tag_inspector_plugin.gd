## Which property names the inspector offers a tag picker for.
##
## The rule is configurable - a comma-separated list of needles and a
## prefix/suffix/anywhere match type - and it decides, silently, whether a
## designer gets a tag picker or a bare text field. A needle that quietly never
## matches looks exactly like an addon that does not work.
##
## `matches_tag_naming` is static, so this asks it directly rather than standing
## up an EditorInspectorPlugin the editor is the only thing that can drive.
##
## @meta_license: MIT
extends GutTest

const Plugin = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_inspector_plugin.gd")
const GASEngineProjectSettings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")

const MATCH_ON: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_ON
const MATCH_TYPE: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_EDITOR_TAG_PROPERTY_EDITOR_MATCH_TYPE

const PROPERTY: String = "damage_gas_tag"

var _had_match_on: bool = false
var _had_match_type: bool = false
var _match_on: Variant = null
var _match_type: Variant = null


func before_each() -> void:
	_had_match_on = ProjectSettings.has_setting(MATCH_ON)
	_had_match_type = ProjectSettings.has_setting(MATCH_TYPE)
	if _had_match_on:
		_match_on = ProjectSettings.get_setting(MATCH_ON)
	if _had_match_type:
		_match_type = ProjectSettings.get_setting(MATCH_TYPE)


## Restoring "there was none" matters as much as restoring a value: a redirect
## left standing outlives this script.
func after_each() -> void:
	ProjectSettings.set_setting(MATCH_ON, _match_on if _had_match_on else null)
	ProjectSettings.set_setting(MATCH_TYPE, _match_type if _had_match_type else null)
	_had_match_on = false
	_had_match_type = false
	_match_on = null
	_match_type = null


func _configure(match_on: String, match_type: GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType) -> void:
	ProjectSettings.set_setting(MATCH_ON, match_on)
	ProjectSettings.set_setting(MATCH_TYPE, int(match_type))


#region The shipped default
func test_the_default_rule_matches_the_names_it_was_written_for() -> void:
	_configure(
		GASEngineProjectSettings.DEFAULT_TAG_PROPERTY_EDITOR_MATCH_ON,
		GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.SUFFIX
	)
	assert_true(Plugin.matches_tag_naming(PROPERTY), "a single tag property")
	assert_true(Plugin.matches_tag_naming("granted_gas_tags"), "and a list of them")
	assert_false(Plugin.matches_tag_naming("damage_amount"), "and nothing else")
#endregion


#region What a designer actually types
## The list is read from a text setting, so it arrives however somebody typed
## it. The property name is lowered before matching and the needles were not,
## and nothing trimmed the space after a comma - so writing the list the
## ordinary way silently dropped every needle but the first, and writing any
## needle in mixed case dropped it entirely. No error, no picker, no clue.
func test_a_needle_written_with_a_space_after_the_comma_still_matches() -> void:
	_configure("gas_tag, gas_tags", GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.SUFFIX)
	assert_true(Plugin.matches_tag_naming(PROPERTY), "the first needle, as always")
	assert_true(Plugin.matches_tag_naming("granted_gas_tags"), "and the one after the space")


func test_a_needle_written_in_mixed_case_still_matches() -> void:
	_configure("GAS_Tag", GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.SUFFIX)
	assert_true(Plugin.matches_tag_naming(PROPERTY))


func test_a_needle_that_is_only_whitespace_matches_nothing() -> void:
	# Under PREFIX or ANYWHERE an empty needle would match every property in the
	# inspector, turning every string field into a tag picker.
	_configure("gas_tag,   ", GASEngineProjectSettings.EditorTagsTagEditorPropertyMatchType.ANYWHERE)
	assert_true(Plugin.matches_tag_naming(PROPERTY), "the real needle still works")
	assert_false(Plugin.matches_tag_naming("damage_amount"), "and the blank one claims nothing")
#endregion


#region The registry's own list
## Clicking a tag in a picker reads as "deselect", which on the registry's own
## array would delete it from the project. That property keeps the default
## editor whatever the naming rule says.
func test_the_registrys_own_tag_list_is_never_replaced_by_a_picker() -> void:
	var registry: GameplayTagRegistry = GameplayTagRegistry.new()
	assert_true(Plugin.is_registry_tag_list(registry, "tags"))
	assert_false(Plugin.is_registry_tag_list(registry, "other"), "only that one property")
	assert_false(
		Plugin.is_registry_tag_list(GameplayCueRegistry.new(), "tags"),
		"and only on the registry that owns it"
	)
#endregion
