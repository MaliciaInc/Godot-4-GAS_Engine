## Bootstrap smoke test.
##
## Proves that a clean checkout reaches a running test suite without anyone
## opening the editor: GUT executes, the two core GodotGAS types instantiate,
## and the GameplayCueManager autoload is present in a headless tree.
##
## Every declaration here is explicitly typed and no `:=` appears anywhere, as
## in every file of this addon.
extends GutTest

const CUE_MANAGER_PATH: String = "/root/GameplayCueManager"


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
	# project.godot declares the autoload directly and the GodotGAS EditorPlugin
	# stays disabled, precisely so this node has exactly one registration. If the
	# plugin were ever enabled without making _enable_plugin() idempotent, this
	# is the test that would notice.
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
