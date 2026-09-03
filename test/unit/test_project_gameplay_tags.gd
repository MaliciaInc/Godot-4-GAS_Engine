## The project's tags, in the one file that holds them.
##
## `gas_engine/gameplay_tags.gd` used to be a copy: a registry resource held the
## tags and this was generated from it, versioned so an editor could complete a
## name. Two tracked files that must agree do not stay agreeing on their own -
## somebody edits the resource by hand, nothing regenerates, and the constants
## the code refers to are not the tags the project has.
##
## So the copy became the original. The file is written by the registry, read
## back by the registry, and there is nothing left for it to disagree with. What
## is worth pinning now is that the round trip is exact: what is written comes
## back, and what comes back renders to what is on disk.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest


func _tracked_source() -> String:
	return FileAccess.get_file_as_string(
		GASEngineProjectSettings.get_generated_tag_script_path()
	)


#region The file the project ships
func test_the_tracked_file_carries_the_project_s_tags() -> void:
	var found: Array[StringName] = GameplayTagGenerator.tags_in_file()

	assert_gt(found.size(), 0, "the project has tags, and they are in the file")
	for tag: StringName in found:
		assert_true(
			GameplayTagRegistry.is_valid_tag_string(String(tag)),
			"%s is a tag the grammar accepts" % tag
		)


## Read, then written again, gives the file back unchanged.
##
## The check that would catch a reader and a writer drifting apart: if reading
## dropped a tag, or writing ordered them differently, this stops matching. It
## is the same guarantee the Composer holds over an ability, for the same
## reason - a tool that rewrites your file has to give it back.
func test_reading_the_file_and_rendering_it_again_is_the_same_file() -> void:
	var found: Array[StringName] = GameplayTagGenerator.tags_in_file()

	assert_eq(
		GameplayTagGenerator.render_tags_source(found), _tracked_source(),
		"byte for byte what is on disk"
	)
#endregion


#region What a registry built from it says
## The loader hands back what the file holds, and says it speaks for the project.
func test_a_registry_loaded_from_the_file_holds_the_same_tags() -> void:
	var registry: GameplayTagRegistry = GameplayTagTree.load_registry()

	assert_not_null(registry, "there is a registry to load")
	assert_eq(registry.tags, GameplayTagGenerator.tags_in_file(), "holding the file's tags")
	assert_true(registry.speaks_for_project, "and it is the project's, not a copy")


## A registry made by hand is a working copy and writes nothing.
##
## The rule that used to hang on whether a resource had been loaded from a path.
## There is no path now, so it is said out loud - and it matters more than it
## did: a copy that wrote would replace every tag in the project with whatever
## it happened to hold.
func test_a_registry_made_by_hand_does_not_speak_for_the_project() -> void:
	var before: String = _tracked_source()
	var copy: GameplayTagRegistry = GameplayTagRegistry.new()

	assert_false(copy.speaks_for_project, "made by hand, so not the project's")
	copy.add_tag("Probe.Should.Not.Reach.Disk")

	assert_eq(_tracked_source(), before, "and the project's file was not touched")
#endregion
