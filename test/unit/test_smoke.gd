## Bootstrap smoke test.
##
## Proves that a clean checkout reaches a running test suite without anyone
## opening the editor: GUT executes, the two core GAS_Engine types instantiate,
## and the GameplayCueManager autoload is present in a headless tree.
##
## Every declaration here is explicitly typed and no `:=` appears anywhere, as
## in every file of this addon.
extends GutTest

const CUE_MANAGER_PATH: String = "/root/GameplayCueManager"

const Plugin = preload("res://addons/GAS_Engine/gas_engine_plugin.gd")
const GasEnginePlugin = preload("res://addons/GAS_Engine/gas_engine_plugin.gd")


func test_gut_executes() -> void:
	# If GUT could not run, this assertion would never be reached at all. Its
	# value is that the suite reports it, which is the evidence wanted.
	assert_true(true, "GUT executed this test")


func test_attribute_data_can_be_instantiated() -> void:
	var attribute: AttributeData = AttributeData.new()
	assert_not_null(attribute, "AttributeData.new() returned a value")
	assert_true(attribute is Resource, "AttributeData is a Resource")


func test_ability_system_component_can_be_instantiated() -> void:
	var component: AbilitySystemComponent = AbilitySystemComponent.new()
	assert_not_null(component, "AbilitySystemComponent.new() returned a value")
	assert_true(component is Node, "AbilitySystemComponent is a Node")
	# Instantiated outside the tree, so it is this test's job to free it.
	component.free()


func test_gameplay_cue_manager_autoload_exists_headless() -> void:
	var manager: Node = get_node_or_null(CUE_MANAGER_PATH)
	assert_not_null(manager, "GameplayCueManager autoload is present at " + CUE_MANAGER_PATH)


func test_gameplay_cue_manager_is_a_single_authority() -> void:
	# project.godot declares the autoload directly, and the GAS_Engine plugin is
	# enabled alongside it. The plugin refuses to register a second time, which
	# is what keeps this at exactly one - and this is the test that would notice
	# if that refusal were ever dropped.
	var root: Node = get_tree().get_root()
	var matches: int = 0
	for child: Node in root.get_children():
		if child.name == "GameplayCueManager":
			matches += 1
	assert_eq(matches, 1, "exactly one GameplayCueManager is registered")


func test_no_interactive_editor_is_required() -> void:
	# A headless run has no editor hints. If this ever reports true, the suite
	# was run from inside the editor and the bootstrap claim is unproven.
	assert_false(Engine.is_editor_hint(), "suite runs outside the editor")


## Enabling the plugin must never take over an autoload the project declared.
##
## This project declares it, so the plugin adds nothing and owns nothing - and
## a plugin that owns nothing removes nothing when it is disabled. Asked through
## the plugin's own decision, because the enable path itself only runs inside an
## editor and this suite deliberately has none.
func test_the_plugin_will_not_claim_an_autoload_the_project_declares() -> void:
	assert_false(
		Plugin.would_add_cue_manager_autoload(),
		"the declaration in project.godot is left alone"
	)


func test_the_seeded_authoring_resources_load() -> void:
	var cues: Resource = ResourceLoader.load(
		GASEngineProjectSettings.get_registry_cue_path()
	)
	var tags: Resource = ResourceLoader.load(
		GASEngineProjectSettings.get_registry_tag_path()
	)
	assert_true(cues is GameplayCueRegistry, "the seeded cue registry is a real registry")
	assert_true(tags is GameplayTagRegistry, "and so is the seeded tag registry")


## The generated constants are reachable by name from ordinary code.
##
## If the generated file had not parsed, or its class were not registered, this
## script would not have compiled - so reaching the assertion is half of it, and
## the value proves the constant means what the registry says.
func test_the_generated_tag_constants_are_reachable_by_name() -> void:
	assert_eq(
		GameplayTags.Example_Ability_Arrow_Shoot,
		&"Example.Ability.Arrow.Shoot",
		"a seeded tag completes to the tag it was generated from"
	)


func test_gas_engine_project_settings_use_the_canonical_namespace() -> void:
	assert_eq(GASEngineProjectSettings.ADDON_NAME, "GAS_Engine")
	assert_eq(GASEngineProjectSettings.PROJECT_SETTINGS_NAME, "gas_engine")
	assert_eq(GASEngineProjectSettings.DEFAULT_PATH, "res://gas_engine")


func test_legacy_default_paths_migrate_to_gas_engine_defaults() -> void:
	var current: String = (
		GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT
	)
	var suffix: String = current.substr(GASEngineProjectSettings.PROJECT_SETTINGS_NAME.length())
	var legacy: String = GASEngineProjectSettings.LEGACY_PROJECT_SETTINGS_NAME + suffix

	var previous_current: Variant = ProjectSettings.get_setting(current, null)
	var previous_legacy: Variant = ProjectSettings.get_setting(legacy, null)

	ProjectSettings.set_setting(current, null)
	ProjectSettings.set_setting(
		legacy,
		GASEngineProjectSettings.LEGACY_DEFAULT_PATH + "/gameplay_tags.gd"
	)

	GASEngineProjectSettings.init_project_settings()

	var migrated_value: Variant = ProjectSettings.get_setting(current)
	assert_true(migrated_value is String, "the migrated setting is a String")
	if migrated_value is String:
		var migrated_string: String = migrated_value
		assert_eq(migrated_string, "res://gas_engine/gameplay_tags.gd")
	assert_false(ProjectSettings.has_setting(legacy))

	ProjectSettings.set_setting(current, previous_current)
	ProjectSettings.set_setting(legacy, previous_legacy)


func test_legacy_custom_path_is_preserved_during_namespace_migration() -> void:
	var current: String = (
		GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY
	)
	var suffix: String = current.substr(GASEngineProjectSettings.PROJECT_SETTINGS_NAME.length())
	var legacy: String = GASEngineProjectSettings.LEGACY_PROJECT_SETTINGS_NAME + suffix

	var previous_current: Variant = ProjectSettings.get_setting(current, null)
	var previous_legacy: Variant = ProjectSettings.get_setting(legacy, null)

	ProjectSettings.set_setting(current, null)
	ProjectSettings.set_setting(legacy, "res://my_game/custom_tags.tres")

	GASEngineProjectSettings.init_project_settings()

	var migrated_value: Variant = ProjectSettings.get_setting(current)
	assert_true(migrated_value is String, "the preserved setting is a String")
	if migrated_value is String:
		var migrated_string: String = migrated_value
		assert_eq(migrated_string, "res://my_game/custom_tags.tres")
	assert_false(ProjectSettings.has_setting(legacy))

	ProjectSettings.set_setting(current, previous_current)
	ProjectSettings.set_setting(legacy, previous_legacy)


func test_plugin_autoload_policy_recognizes_only_the_exact_canonical_path() -> void:
	var setting_name: String = "autoload/" + GasEnginePlugin.CUE_MANAGER_NAME
	var previous: Variant = ProjectSettings.get_setting(setting_name, null)

	ProjectSettings.set_setting(
		setting_name,
		"*" + GasEnginePlugin.CUE_MANAGER_PATH
	)
	assert_true(GasEnginePlugin._autoload_points_to_gas_engine())

	ProjectSettings.set_setting(
		setting_name,
		"*res://my_game/custom_gameplay_cue_manager.gd"
	)
	assert_false(GasEnginePlugin._autoload_points_to_gas_engine())

	ProjectSettings.set_setting(setting_name, previous)
