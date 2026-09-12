## The project's cue bindings, in the one file that holds them.
##
## They used to live in a resource with no generated counterpart, so the only
## way to see which scene answered which tag was to open it in an Inspector, and
## the only way to change one was a screen that no longer exists. They are a
## file now, written and read by the same module.
##
## Each binding is a `preload` rather than a path in a string, for the checking
## it buys at parse time. Not for the exporter: a GDScript preload is not an
## export dependency on 4.7.2, measured, so what ships is decided by the export
## preset and not by this file. The header of `gameplay_cue_generator.gd` has
## the numbers.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const A_TAG: StringName = &"Example.Cue.Probe"
## Rendering must not care whether the scene is there, so this one is not.
const A_SCENE: String = "res://addons/GAS_Engine/a_scene_a_game_would_bind.tscn"
## And this one is, for the check that needs a real answer.
const A_SCENE_THAT_EXISTS: String = "res://test/gut_headless_runner.tscn"

## For the regeneration check, which needs a second binding, a tag answered by a
## script and a tag that ends a walk - none of which are ever loaded, only
## written and read back as text.
const ANOTHER_TAG: StringName = &"Example.Cue.Probe.Second"
const A_HANDLED_TAG: StringName = &"Example.Cue.Answered.By.A.Script"
const A_HANDLER: String = "res://addons/GAS_Engine/a_script_a_game_would_bind.gd"
const A_STOPPED_TAG: StringName = &"Example.Cue.Walk.Stops.Here"
const SCRATCH: String = "user://test_cue_regeneration.gd"

## For the check that a tag can be pointed at the wrong kind of script. The
## base handler is a handler; the flags record is a RefCounted that is not,
## which is what a project pointing HANDLERS at the wrong file looks like.
const A_REAL_HANDLER: String = "res://addons/GAS_Engine/cues/gameplay_cue_handler.gd"
const NOT_A_HANDLER_TAG: StringName = &"Example.Cue.Pointed.At.The.Wrong.Thing"
const NOT_A_HANDLER_SCRIPT: String = "res://addons/GAS_Engine/cues/gameplay_cue_flags.gd"
const CUES_SETTING: String = (
	GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_CUES_GENERATED_SCRIPT
)


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
	assert_true(source.contains(GameplayCueGenerator.OVERRIDE_NAME), "and so is the list")
	assert_true(source.strip_edges().ends_with("]"), "and both are closed")


## Writing the file again keeps what somebody authored in it by hand.
##
## `generate_tags_file` reads its three declarations back before it renders,
## and its header says why: rendering with the defaults would delete them the
## first time anybody added a tag - authored work removed by an unrelated
## action, in a file nobody thinks of as theirs to check. The cue file has two
## declarations of exactly that kind, HANDLERS and OVERRIDE_PARENT, and its
## writer read back neither: the bindings were the only thing a regeneration
## carried over.
##
## Driven through `generate_cues_file` rather than `render_source`, because
## `render_source` was never the part that was wrong - it takes all three and
## always has. What was missing is the writer handing them to it.
func test_writing_the_cue_file_again_keeps_what_was_authored_in_it() -> void:
	var restore: Dictionary[String, Variant] = {}
	restore[CUES_SETTING] = ProjectSettings.get_setting(CUES_SETTING, null)
	ProjectSettings.set_setting(CUES_SETTING, SCRATCH)

	var authored_handlers: Dictionary[StringName, String] = {A_HANDLED_TAG: A_HANDLER}
	var authored_stops: Array[StringName] = [A_STOPPED_TAG]
	var before: Dictionary[StringName, String] = {A_TAG: A_SCENE}
	GDScriptSource.write(
		SCRATCH, GameplayCueGenerator.render_source(before, authored_stops, authored_handlers)
	)

	var after: Dictionary[StringName, String] = {A_TAG: A_SCENE, ANOTHER_TAG: A_SCENE}
	var wrote: bool = GameplayCueGenerator.generate_cues_file(after)

	var handlers_left: Dictionary[StringName, String] = GameplayCueGenerator.handlers_in_file()
	var stops_left: Array[StringName] = GameplayCueGenerator.overrides_in_file()
	var bindings_left: Dictionary[StringName, String] = GameplayCueGenerator.bindings_in_file()

	# Put the setting back before asserting, so a failure here does not leave
	# every test after this one pointed at a scratch file.
	ProjectSettings.set_setting(CUES_SETTING, restore[CUES_SETTING])
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

	assert_true(wrote, "the file was written")
	assert_eq(bindings_left.size(), 2, "with the bindings it was asked for")
	assert_eq(
		handlers_left, authored_handlers, "and the handler somebody authored survived it"
	)
	assert_eq(stops_left, authored_stops, "and so did the tag that ends a walk")


## A tag that ends a fallback walk reads back as one.
func test_a_rendered_override_reads_back_as_itself() -> void:
	var none: Dictionary[StringName, String] = {}
	var stops: Array[StringName] = [A_TAG]

	var source: String = GameplayCueGenerator.render_source(none, stops)

	assert_true(source.contains(String(A_TAG)), "the tag is in the file")
	assert_false(source.contains("preload"), "and it is not pretending to be a binding")
#endregion


## A tag pointed at a script that is not a handler is reported, not fatal.
##
## `HANDLERS` is hand-authored - no editor writes it - so the wrong path in it
## is a normal way for a project to be wrong, and the catalogue is where that
## is found out. It used to build whatever the script made and assign it into a
## `Dictionary[StringName, CueHandler]`, so the wrong kind of script ended the
## whole load with a type error on an assignment, and took every cue after it
## with it. Now it says which tag and which file, skips that one, and the rest
## of the registry still loads.
func test_a_tag_pointed_at_a_script_that_is_not_a_handler_is_skipped() -> void:
	var restore: Dictionary[String, Variant] = {}
	restore[CUES_SETTING] = ProjectSettings.get_setting(CUES_SETTING, null)
	ProjectSettings.set_setting(CUES_SETTING, SCRATCH)

	var no_bindings: Dictionary[StringName, String] = {}
	var no_stops: Array[StringName] = []
	var handlers: Dictionary[StringName, String] = {
		A_HANDLED_TAG: A_REAL_HANDLER, NOT_A_HANDLER_TAG: NOT_A_HANDLER_SCRIPT
	}
	GDScriptSource.write(
		SCRATCH, GameplayCueGenerator.render_source(no_bindings, no_stops, handlers)
	)

	var catalog: GameplayCueCatalog = GameplayCueCatalog.new()
	var loaded: bool = catalog.load_from_project()
	var answered: Dictionary[StringName, GameplayCueHandler] = catalog.handlers

	ProjectSettings.set_setting(CUES_SETTING, restore[CUES_SETTING])
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

	# Asserted rather than tolerated: saying which tag and which file is the
	# behaviour under test, and asserting it also tells GUT the error was
	# expected. Built from the catalogue's own constant rather than spelled
	# out here, so this checks which of its two diagnoses it reached and not
	# how that one is worded - a missing file has the other one.
	assert_push_error(
		GameplayCueCatalog.NOT_A_HANDLER % [String(NOT_A_HANDLER_TAG), NOT_A_HANDLER_SCRIPT],
		"it says which tag it is and which file it points at"
	)
	assert_true(loaded, "the registry loaded")
	assert_true(answered.has(A_HANDLED_TAG), "the tag that names a handler got one")
	assert_false(
		answered.has(NOT_A_HANDLER_TAG), "and the one that names something else did not"
	)
#endregion


#region The file the project ships
func test_the_project_has_a_cues_file_and_it_parses() -> void:
	var path: String = GASEngineProjectSettings.get_generated_cue_script_path()

	assert_true(FileAccess.file_exists(path), "the file is where the setting says")
	assert_eq(
		GameplayCueGenerator.render_source(
			GameplayCueGenerator.bindings_in_file(),
			GameplayCueGenerator.overrides_in_file(),
			GameplayCueGenerator.handlers_in_file()
		),
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


#region The file says what GDScript says it says
## What a person leaves in the file, put where the reader will look.
func _read_with(reader: Callable, lines: Array[String]) -> Variant:
	return HandEditedSource.read(
		GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_CUES_GENERATED_SCRIPT,
		lines,
		reader
	)


func _bindings_in(lines: Array[String]) -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = _read_with(
		GameplayCueGenerator.bindings_in_file, lines
	)
	return found


func _overrides_in(lines: Array[String]) -> Array[StringName]:
	var found: Array[StringName] = _read_with(GameplayCueGenerator.overrides_in_file, lines)
	return found


## A binding somebody commented out is a binding that is gone.
##
## The reader used to take any line holding `&"..."` and `preload("...")`, in
## any position, so a `#` in front of one changed nothing for it while changing
## everything for Godot. The two disagreed about what the file said, and the
## reader is the one the cue manager builds its table from - so the cue was
## dead in the editor, absent from the export that no longer saw the
## dependency, and still being asked for at runtime.
func test_a_commented_out_binding_is_not_a_binding() -> void:
	var found: Dictionary[StringName, String] = _bindings_in([
		GameplayCueGenerator.BINDINGS_DECLARATION,
		'	&"Cue.Kept": preload("%s"),' % A_SCENE_THAT_EXISTS,
		'	# &"Cue.TakenOut": preload("%s"),' % A_SCENE_THAT_EXISTS,
		"}",
	])

	assert_true(found.has(&"Cue.Kept"), "the one that is there is there")
	assert_false(found.has(&"Cue.TakenOut"), "and the one behind a # is not")


## And a binding-shaped line that is not in THE bindings is not one either.
##
## Everything here is binding-shaped and only one of them is a binding. The doc
## comment above the declaration and the dictionary below it were read as
## bindings; `BINDINGS_BACKUP` was read as the declaration itself, because the
## reader matched a prefix and `const BINDINGS_BACKUP` starts with
## `const BINDINGS` - so it took a backup copy for the real thing, stopped at
## its closing brace, and never reached the one GDScript uses.
##
## Three roads to the same disagreement, in one file, because a file a person is
## invited to edit will eventually hold all of it.
func test_only_the_real_bindings_body_counts() -> void:
	var found: Dictionary[StringName, String] = _bindings_in([
		'## For example: &"Cue.FromTheDocs": preload("%s")' % A_SCENE_THAT_EXISTS,
		"const BINDINGS_BACKUP: Dictionary[StringName, PackedScene] = {",
		'	&"Cue.FromTheBackup": preload("%s"),' % A_SCENE_THAT_EXISTS,
		"}",
		"",
		GameplayCueGenerator.BINDINGS_DECLARATION,
		'	&"Cue.Real": preload("%s"),' % A_SCENE_THAT_EXISTS,
		"}",
		"",
		"const SOMETHING_OF_MY_OWN: Dictionary[StringName, PackedScene] = {",
		'	&"Cue.Mine": preload("%s"),' % A_SCENE_THAT_EXISTS,
		"}",
	])

	var only_the_real_one: Array[StringName] = [&"Cue.Real"]
	assert_eq(found.keys(), only_the_real_one, "the bindings, not what resembles them")


## The same three roads, on the list beside the bindings.
##
## One function reads both bodies, so this is not a second copy of the rule -
## it is the check that the second caller actually reaches it.
func test_only_the_real_override_body_counts() -> void:
	var found: Array[StringName] = _overrides_in([
		'## For example: &"Cue.FromTheDocs",',
		GameplayCueGenerator.BINDINGS_DECLARATION,
		'	&"Cue.Bound": preload("%s"),' % A_SCENE_THAT_EXISTS,
		"}",
		"",
		GameplayCueGenerator.OVERRIDE_DECLARATION,
		'	&"Cue.Real",',
		'	# &"Cue.TakenOut",',
		"]",
	])

	var only_the_real_one: Array[StringName] = [&"Cue.Real"]
	assert_eq(found, only_the_real_one, "the list, not what resembles it")


## A list somebody hand-wrote without a trailing comma is still a list:
## GDScript accepts it, so the reader has to as well.
func test_an_entry_without_a_trailing_comma_still_reads() -> void:
	var found: Array[StringName] = _overrides_in([
		GameplayCueGenerator.OVERRIDE_DECLARATION,
		'	&"Cue.Last"',
		"]",
	])

	var last: Array[StringName] = [&"Cue.Last"]
	assert_eq(found, last)
#endregion
