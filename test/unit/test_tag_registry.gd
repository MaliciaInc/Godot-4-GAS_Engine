## The tag registry: formatting, validation and the queries built on them.
##
## The registry had no tests. It is authoring code rather than gameplay code,
## which is exactly why it was skipped and exactly why it matters: a tag it
## mangles or refuses is a tag gameplay can never match, and the mismatch shows
## up far from here as a query that quietly returns nothing.
##
## @meta_license: MIT
extends GutTest

## Somewhere to write that nothing tracks. The project's own generated file
## is a versioned artefact now, and a test that wrote there would either break
## the sync check or quietly repair the drift that check exists to find.
const SCRATCH_SCRIPT: String = "user://generated_tags_probe.gd"

var registry: GameplayTagRegistry = null


func before_each() -> void:
	registry = GameplayTagRegistry.new()


func after_each() -> void:
	registry = null


#region Formatting
## Casing is normalised per segment, not per tag.
func test_each_segment_gets_a_capital_and_the_dots_are_kept() -> void:
	assert_eq(registry.format_tag("status.stunned"), "Status.Stunned")
	assert_eq(registry.format_tag("event.damage.critical"), "Event.Damage.Critical")


## The grammar accepts `[A-Z][a-zA-Z0-9]*`, so a capital inside a segment is
## legal and must survive formatting.
##
## It did not. `Cue.NeverUsed` came back as `Cue.Neverused`, and that tag is
## already used in this repository's own tests: a designer registering it
## through the dashboard got a different tag from the one the code refers to,
## with nothing reported. The formatter and the grammar have to agree, and the
## grammar is the declared contract.
func test_a_capital_inside_a_segment_survives() -> void:
	assert_eq(registry.format_tag("Cue.NeverUsed"), "Cue.NeverUsed")
	assert_eq(registry.format_tag("Damage.CritChance"), "Damage.CritChance")
	# Only the first letter is forced; the rest is the author's.
	assert_eq(registry.format_tag("damage.critChance"), "Damage.CritChance")


## An empty segment is preserved rather than repaired, so the grammar can
## reject a double dot instead of the formatter hiding it.
func test_an_empty_segment_is_left_for_the_grammar_to_refuse() -> void:
	assert_eq(registry.format_tag("a..b"), "A..B")
	assert_true(
		registry.add_tag("a..b").begins_with(GameplayTagRegistry.ERROR_PREFIX),
		"and the grammar does refuse it"
	)
#endregion


#region Refusals
## Every refusal returns before the registry is touched, so none of these write
## a file or leave a partial tag behind.
func test_an_empty_tag_is_refused() -> void:
	assert_true(registry.add_tag("").begins_with(GameplayTagRegistry.ERROR_PREFIX))
	assert_true(registry.add_tag("   ").begins_with(GameplayTagRegistry.ERROR_PREFIX), "and blank")
	assert_eq(registry.tags.size(), 0, "nothing was added")


func test_a_tag_that_does_not_match_the_grammar_is_refused() -> void:
	assert_true(registry.add_tag("1Leading").begins_with(GameplayTagRegistry.ERROR_PREFIX))
	assert_true(registry.add_tag("has space").begins_with(GameplayTagRegistry.ERROR_PREFIX))
	assert_true(registry.add_tag("has-dash").begins_with(GameplayTagRegistry.ERROR_PREFIX))
	assert_eq(registry.tags.size(), 0, "nothing was added")


func test_a_duplicate_is_refused_after_formatting_not_before() -> void:
	registry.tags = [&"Status.Stunned"] as Array[StringName]
	# Different casing, same tag once formatted.
	var refusal: String = registry.add_tag("status.stunned")
	assert_true(refusal.begins_with(GameplayTagRegistry.ERROR_PREFIX), "refused as a duplicate")
	assert_eq(registry.tags.size(), 1, "and not appended a second time")
#endregion


#region Queries
func test_has_tag_is_exact() -> void:
	registry.tags = [&"Status.Stunned"] as Array[StringName]
	assert_true(registry.has_tag(&"Status.Stunned"))
	assert_false(registry.has_tag(&"Status"), "a parent is not registered by its child")
	assert_false(registry.has_tag(&"Status.Stun"), "nor is a prefix of one")


func test_child_tags_are_the_ones_under_the_separator() -> void:
	registry.tags = [
		&"Status", &"Status.Stunned", &"Status.Burning", &"Statusless.Thing", &"Other.Status"
	] as Array[StringName]

	var children: Array[StringName] = registry.get_child_tags(&"Status")
	assert_eq(children.size(), 2, "two children")
	assert_true(children.has(&"Status.Stunned"))
	assert_true(children.has(&"Status.Burning"))
	# The separator is what makes a child. Without it `Statusless.Thing` would
	# be swept in by a bare prefix match, which is the classic tag-tree bug.
	assert_false(children.has(&"Statusless.Thing"), "a longer word is not a child")
	assert_false(children.has(&"Status"), "a tag is not a child of itself")
	assert_false(children.has(&"Other.Status"), "nor is a tag that merely ends the same")


func test_an_unknown_parent_has_no_children() -> void:
	registry.tags = [&"Status.Stunned"] as Array[StringName]
	assert_eq(registry.get_child_tags(&"Nothing").size(), 0)


func test_removing_an_absent_tag_changes_nothing() -> void:
	registry.tags = [&"Status.Stunned"] as Array[StringName]
	registry.remove_tag(&"Status.Missing")
	assert_eq(registry.tags.size(), 1, "the registry is untouched")
#endregion


#region One grammar, shared
## The static validator and `add_tag` judge by the same grammar.
##
## They used to hold separate compiled expressions, which is how two parts of a
## project end up disagreeing about what a tag is.
func test_the_static_validator_agrees_with_what_add_tag_accepts() -> void:
	assert_true(GameplayTagRegistry.is_valid_tag_string("Status.Stunned"), "a legal tag")
	assert_false(
		registry.add_tag("Status.Stunned").begins_with(GameplayTagRegistry.ERROR_PREFIX),
		"and add_tag takes it"
	)

	assert_false(
		GameplayTagRegistry.is_valid_tag_string("Status..Stunned"),
		"a double dot is not"
	)
	assert_true(
		registry.add_tag("Status..Stunned").begins_with(GameplayTagRegistry.ERROR_PREFIX),
		"and add_tag refuses it too"
	)


## The validator judges what it was handed. It does not repair.
##
## `add_tag` formats first, so a designer who typed lowercase gets the tag they
## meant. A message arriving from outside the project was not typed by a
## designer, and repairing it would let the sender believe it had addressed a
## tag it never actually named.
func test_the_static_validator_does_not_repair_what_format_tag_would() -> void:
	assert_eq(
		registry.format_tag("status.stunned"),
		"Status.Stunned",
		"formatting would happily fix it"
	)
	assert_false(
		GameplayTagRegistry.is_valid_tag_string("status.stunned"),
		"but the validator refuses it exactly as written"
	)
#endregion


#region Generating the constants file
## The renderer is pure, so what it would write can be asked without writing.
func test_the_rendered_source_carries_the_constants_it_was_given() -> void:
	var source: String = GameplayTagGenerator.render_tags_source(
		[&"Status.Stunned"] as Array[StringName]
	)
	assert_true(source.contains("Status_Stunned"), "the identifier the tag becomes")
	assert_true(source.contains("class_name GameplayTags"), "inside the generated class")


## Adding a tag must not report success when the constants file was not written.
##
## The output directory does not exist in a fresh checkout, so the generator
## opened nothing, printed to stderr and returned. add_tag ignored that and
## handed back the formatted tag: the tag lived in memory, the constant a
## designer went there to create did not exist, and nothing said so.
func test_generation_reports_whether_it_actually_wrote() -> void:
	var setting: String = (
		GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT
	)
	var previous: Variant = ProjectSettings.get_setting(setting)
	ProjectSettings.set_setting(setting, SCRATCH_SCRIPT)

	var tags: Array[StringName] = [&"Status.Stunned"] as Array[StringName]
	assert_true(GameplayTagGenerator.generate_tags_file(tags), "it reports having written")
	assert_true(FileAccess.file_exists(SCRATCH_SCRIPT), "and the file is really there")
	assert_eq(
		FileAccess.get_file_as_string(SCRATCH_SCRIPT),
		GameplayTagGenerator.render_tags_source(tags),
		"carrying exactly what the renderer produced, with no second format"
	)

	ProjectSettings.set_setting(setting, previous)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SCRIPT))


## A registry nothing has saved is somebody's working copy, and it does not
## speak for the project.
##
## Every test above mutates such a registry. If those mutations regenerated the
## project's constants, one suite run would replace the whole project's tags
## with whatever the last test happened to hold.
func test_an_anonymous_registry_does_not_regenerate_the_project_file() -> void:
	var generated_path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	var before: String = FileAccess.get_file_as_string(generated_path)

	registry.add_tag("Scratch.Tag")

	assert_eq(
		FileAccess.get_file_as_string(generated_path),
		before,
		"the project's constants were left exactly as they were"
	)
#endregion
