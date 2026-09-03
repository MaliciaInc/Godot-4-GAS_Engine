## The generated constants and the registry they came from say the same thing.
##
## `gas_engine/tag_registry.tres` is the only source of truth for authored tags.
## `gas_engine/gameplay_tags.gd` is derived from it and versioned so an editor can
## complete a tag name, and it is never edited by hand.
##
## Two tracked files that are supposed to agree will not stay agreeing on their
## own: someone edits the registry through the dashboard, the generated file is
## rewritten, and only one of the two gets committed. This test reads both from
## disk exactly as they are tracked and demands they match byte for byte. No
## normalisation is applied - `.gitattributes` already pins LF in the checkout,
## so normalising here could only hide a drift rather than reveal one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest


func _tracked_registry() -> GameplayTagRegistry:
	var loaded: Resource = ResourceLoader.load(GASEngineProjectSettings.get_registry_tag_path())
	return loaded as GameplayTagRegistry


func test_the_tracked_registry_loads_and_is_not_empty() -> void:
	var registry: GameplayTagRegistry = _tracked_registry()
	assert_not_null(registry, "the registry is a real resource, not a broken path")
	assert_gt(registry.tags.size(), 0, "and it carries the project's authored tags")


func test_the_generated_script_is_exactly_what_the_registry_renders() -> void:
	var registry: GameplayTagRegistry = _tracked_registry()
	var expected: String = GameplayTagGenerator.render_tags_source(registry.tags)
	var actual: String = FileAccess.get_file_as_string(
		GASEngineProjectSettings.get_generated_tag_script_path()
	)

	# Byte for byte, and asked through the same public renderer the writer uses.
	# Comparing only the constants would let the header drift; comparing a
	# reformatted version of either would let whitespace drift.
	assert_eq(
		actual,
		expected,
		"the generated file is stale: regenerate it by editing tags through the registry"
	)


## Every tag in the registry reaches the file as a constant, and none appears
## that the registry does not have.
##
## The equality above would catch either on its own. This says which of the two
## went wrong when it does, because "the whole file differs" is a poor first
## thing to read at the top of a failed run.
func test_every_registry_tag_has_a_constant_and_no_others_do() -> void:
	var registry: GameplayTagRegistry = _tracked_registry()
	var generated: String = FileAccess.get_file_as_string(
		GASEngineProjectSettings.get_generated_tag_script_path()
	)

	var constants: int = 0
	for line: String in generated.split(GameplayTagGenerator.LINE_BREAK):
		if line.begins_with("const "):
			constants += 1

	for tag: StringName in registry.tags:
		assert_true(
			generated.contains(GameplayTagGenerator.constant_line(tag)),
			"a tag in the registry with no constant: " + String(tag)
		)
	assert_eq(constants, registry.tags.size(), "and no constant without a tag behind it")
