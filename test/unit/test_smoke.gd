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
