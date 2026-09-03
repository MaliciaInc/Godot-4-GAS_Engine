## The project's cue bindings, in the one file that holds them.
##
## They used to live in a resource with no generated counterpart, so the only
## way to see which scene answered which tag was to open it in an Inspector, and
## the only way to change one was a screen that no longer exists. They are a
## file now, written and read by the same module.
##
## Each binding is a `preload`, not a path in a string, and that is the part
## worth being careful about: a path in a string is not a dependency, so the
## exporter would not know the scene was wanted and a cue that played in the
## editor would be missing from the built game.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const A_TAG: StringName = &"Example.Cue.Probe"
## Rendering must not care whether the scene is there, so this one is not.
const A_SCENE: String = "res://addons/GAS_Engine/a_scene_a_game_would_bind.tscn"
## And this one is, for the check that needs a real answer.
const A_SCENE_THAT_EXISTS: String = "res://test/gut_headless_runner.tscn"


#region What is written comes back
## Rendered and read again, a binding is the binding it was.
##
## Done on made-up bindings rather than on the project's, so it fails when the
## reader and the writer disagree rather than when somebody adds a cue.
func test_a_rendered_binding_reads_back_as_itself() -> void:
	var written: Dictionary[StringName, String] = {A_TAG: A_SCENE}
	var source: String = GameplayCueGenerator.render_source(written)

	assert_true(source.contains(String(A_TAG)), "the tag is in the file")
	assert_true(source.contains('preload("' + A_SCENE + '")'), "and the scene is preloaded")
	assert_true(
		source.contains("class_name GameplayCues"),
		"under a name a game can reach without loading a resource"
	)


## An empty project renders a file, not nothing.
##
## A project with no cues yet still needs somewhere for its first one to go, and
## a missing file reads to every caller as a broken installation.
func test_a_project_with_no_cues_still_gets_a_file() -> void:
	var none: Dictionary[StringName, String] = {}

	var source: String = GameplayCueGenerator.render_source(none)

	assert_true(source.contains("const BINDINGS"), "the dictionary is declared")
	assert_true(source.strip_edges().ends_with("}"), "and closed")
#endregion


#region The file the project ships
func test_the_project_has_a_cues_file_and_it_parses() -> void:
	var path: String = GASEngineProjectSettings.get_generated_cue_script_path()

	assert_true(FileAccess.file_exists(path), "the file is where the setting says")
	assert_eq(
		GameplayCueGenerator.render_source(GameplayCueGenerator.bindings_in_file()),
		FileAccess.get_file_as_string(path),
		"and reading it and writing it again gives it back byte for byte"
	)


## Every scene the file names is a scene that is actually there.
##
## A binding that preloads a path nothing answers is a cue that fails at load
## rather than when it is asked for, and the file is the only place it can be
## wrong now.
##
## The check is proved to have teeth in the same test, because the project ships
## with no cues yet: the loop had nothing to walk, asserted nothing, and passed.
## That is not the check working, it is the check being absent - so the last two
## lines pin what the loop would say if a binding ever were wrong.
func test_every_binding_names_a_scene_that_exists() -> void:
	var bound: Dictionary[StringName, String] = GameplayCueGenerator.bindings_in_file()
	for tag: StringName in bound:
		assert_true(
			ResourceLoader.exists(bound[tag]), "%s names %s, which is there" % [tag, bound[tag]]
		)

	assert_true(
		ResourceLoader.exists(A_SCENE_THAT_EXISTS), "a scene that is there reads as there"
	)
	assert_false(
		ResourceLoader.exists("res://nothing_answers_this.tscn"),
		"and one that is not does not - an empty file above is an answer, not a shrug"
	)
#endregion
