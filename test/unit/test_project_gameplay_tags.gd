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


#region The file says what GDScript says it says
## A note at the end of a line is a note, not part of the tag.
##
## The reader took the LAST quote on the line as the tag's closing one, so
## `const Noted: StringName = &"Status.Noted"  # they call it "big"` came back
## as a tag named `Status.Noted"  # they call it "big`. Not a tag the grammar
## would accept, and it would have been written straight back into the file the
## next time anything edited it.
##
## A commented-out constant was already safe, and stays here as the other half
## of the pair: a comment does not begin with `const `, so it never got in.
func test_a_note_at_the_end_of_a_line_is_not_part_of_the_tag() -> void:
	var read: Variant = HandEditedSource.read(
		GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT,
		[
			"class_name ProbeTags",
			"",
			'const Plain: StringName = &"Status.Plain"',
			'const Noted: StringName = &"Status.Noted"  # the one they call "big"',
			'# const Gone: StringName = &"Status.Gone"',
		],
		GameplayTagGenerator.tags_in_file
	)
	var found: Array[StringName] = read
	var expected: Array[StringName] = [&"Status.Plain", &"Status.Noted"]

	assert_eq(found, expected, "the note stayed out and so did the commented one")
	for tag: StringName in found:
		assert_true(
			GameplayTagRegistry.is_valid_tag_string(String(tag)),
			"%s is a tag the grammar accepts" % tag
		)
#endregion


#region A failed write leaves the file it was replacing alone
## The file is the project's only copy of its tags now, so the moment to find
## out a write cannot happen is before the old one is gone.
##
## Failure is provoked rather than imagined: a directory sitting exactly where
## the staged file wants to be means FileAccess cannot open it, which is the
## same shape as a lock, a full disk, or a permission the editor does not have.
func test_a_write_that_cannot_be_staged_leaves_the_original_untouched() -> void:
	var path: String = "user://test_write_target.gd"
	var blocked: String = path + GDScriptSource.STAGED_SUFFIX
	var before: String = "# what was there first"

	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(before)
	out.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))

	_expect_engine_error()
	var wrote: bool = GDScriptSource.write(path, "# something else entirely")
	_handle_tracked_errors()

	assert_false(wrote, "it refused")
	assert_eq(FileAccess.get_file_as_string(path), before, "and the original is untouched")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## And the other half of the window: staged fine, could not be put in place.
##
## The write is two moments and the test above only covers the first. This is
## the second: the staged file is written and the swap is what fails. What it
## pins is that a swap that did not happen is reported as not having happened,
## that the file is still the file, and that the staged copy is cleaned up
## rather than left in the project folder for somebody to find.
##
## The failure is provoked rather than simulated: an open handle on the target
## makes the rename fail, measured, which is what a virus scanner or another
## editor holding the file looks like from here.
##
## It does not, on its own, pin that the swap no longer deletes the target
## first - Windows will not delete a file this test is holding open, so the
## delete would fail harmlessly here. `test_tag_registry.gd` is what catches
## that, by putting a directory where the target goes.
func test_a_write_that_cannot_be_committed_leaves_the_original_untouched() -> void:
	var path: String = "user://test_commit_target.gd"
	var before: String = "# the only copy the project has"

	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(before)
	out.close()
	var held: FileAccess = FileAccess.open(path, FileAccess.READ)

	_expect_engine_error()
	var wrote: bool = GDScriptSource.write(path, "# a replacement nobody gets")
	_handle_tracked_errors()
	held.close()

	assert_false(wrote, "it could not be put in place")
	assert_eq(FileAccess.get_file_as_string(path), before, "so the file is still the file")
	assert_false(
		FileAccess.file_exists(path + GDScriptSource.STAGED_SUFFIX),
		"and the half-written one was cleared away"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The engine is expected to complain here: a write it cannot make is a write
## it should say it cannot make.
func _expect_engine_error() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING


## Mark them handled and put the default back, so the next test still fails on
## an error nobody asked for.
func _handle_tracked_errors() -> void:
	@warning_ignore_start("unsafe_cast")
	var tracker: GutErrorTracker = GutUtils.get_error_tracker() as GutErrorTracker
	@warning_ignore_restore("unsafe_cast")
	for tracked: GutTrackedError in tracker.get_current_test_errors():
		tracked.handled = true
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE
#endregion
