## Folding an old registry resource in, and never again.
##
## The shape this replaces read the legacy resources on every editor start and
## added back whatever the files were missing. That is not a migration, and the
## first test is the reason: a tag somebody deleted came back on the next
## restart, so the files everyone had just been told were the only authority
## quietly were not.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const TAGS_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT
const CUES_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_CUES_GENERATED_SCRIPT
const OLD_TAGS_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY
const OLD_CUES_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_CUES_REGISTRY
const DONE_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_INTERNAL_SOURCE_MIGRATION

const SCRATCH_TAGS: String = "user://test_migration_tags.gd"
const SCRATCH_CUES: String = "user://test_migration_cues.gd"
const OLD_TAGS: String = "user://test_migration_old_tags.tres"
const OLD_CUES: String = "user://test_migration_old_cues.tres"

const AN_OLD_TAG: StringName = &"Legacy.Only.Here"
const AN_OLD_CUE: StringName = &"Legacy.Cue.Only.Here"
const A_SCENE: String = "res://test/gut_headless_runner.tscn"

const SOME_EXAMPLES: Array[String] = ["Example.From.A.Fresh.Install"]

var _restore: Dictionary[String, Variant] = {}


func before_each() -> void:
	var touched: Array[String] = [
		TAGS_SETTING, CUES_SETTING, OLD_TAGS_SETTING, OLD_CUES_SETTING, DONE_SETTING
	]
	for setting: String in touched:
		_restore[setting] = ProjectSettings.get_setting(setting, null)
	ProjectSettings.set_setting(TAGS_SETTING, SCRATCH_TAGS)
	ProjectSettings.set_setting(CUES_SETTING, SCRATCH_CUES)
	ProjectSettings.set_setting(OLD_TAGS_SETTING, OLD_TAGS)
	ProjectSettings.set_setting(OLD_CUES_SETTING, OLD_CUES)
	ProjectSettings.set_setting(DONE_SETTING, 0)


## Put back in memory, and never saved.
##
## Recording the fold sets a setting; persisting it is the plugin's job, which
## is what lets this test drive the whole thing without rewriting project.godot
## - a save would take its comments with it.
func after_each() -> void:
	for setting: String in _restore:
		ProjectSettings.set_setting(setting, _restore[setting])
	var scratch: Array[String] = [SCRATCH_TAGS, SCRATCH_CUES, OLD_TAGS, OLD_CUES]
	for path: String in scratch:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A project from before the files, with something in both resources.
func _give_the_project_a_past() -> void:
	var tags: GameplayTagRegistry = GameplayTagRegistry.new()
	tags.tags.append(AN_OLD_TAG)
	assert_eq(ResourceSaver.save(tags, OLD_TAGS), OK, "an old tag registry")

	var entry: GameplayCueEntry = GameplayCueEntry.new()
	entry.tag = AN_OLD_CUE
	entry.scene = load(A_SCENE) as PackedScene
	var cues: GameplayCueRegistry = GameplayCueRegistry.new()
	cues.entries.append(entry)
	assert_eq(ResourceSaver.save(cues, OLD_CUES), OK, "and an old cue registry")


#region Once, and then never again
## The whole contract, walked in order, because the order is the contract.
##
## Both halves in one test because they are one promise: the files are the
## authority. Each step only means anything after the one before it - folding
## proves the old content arrives, deleting proves a person can take it out,
## and running again is the step the old shape failed. It put both back and
## called that a migration.
func test_what_is_deleted_after_the_fold_does_not_come_back() -> void:
	_give_the_project_a_past()

	assert_true(GASSourceMigration.pending(), "a project that has not folded yet")
	assert_true(GASSourceMigration.run(), "folds")
	assert_true(GameplayTagGenerator.tags_in_file().has(AN_OLD_TAG), "the tag arrives")
	assert_true(
		GameplayCueGenerator.bindings_in_file().has(AN_OLD_CUE), "and so does the binding"
	)
	assert_false(GASSourceMigration.pending(), "and it is recorded as done")

	var no_tags: Array[StringName] = []
	var no_cues: Dictionary[StringName, String] = {}
	assert_true(GameplayTagGenerator.generate_tags_file(no_tags), "somebody removes the tag")
	assert_true(GameplayCueGenerator.generate_cues_file(no_cues), "and the binding")

	assert_true(GASSourceMigration.run(), "the editor starts again")

	assert_false(GameplayTagGenerator.tags_in_file().has(AN_OLD_TAG), "the tag stays gone")
	assert_false(
		GameplayCueGenerator.bindings_in_file().has(AN_OLD_CUE),
		"and so does the binding - the files are the files"
	)


## A fold that could not finish is not recorded, and tries again.
##
## Worth a test rather than an inspection: the tags write succeeds and the cues
## write cannot, so marking it done would lose the cue bindings for good - there
## would be no second attempt left to lose them in.
func test_a_half_finished_fold_is_not_recorded() -> void:
	_give_the_project_a_past()
	var blocked: String = "user://test_migration_blocked_cues"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
	ProjectSettings.set_setting(CUES_SETTING, blocked)

	_expect_engine_error()
	var finished: bool = GASSourceMigration.run()
	_handle_tracked_errors()

	assert_false(finished, "it could not finish")
	assert_true(GASSourceMigration.pending(), "so it is still pending, and will try again")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
#endregion


#region A project with no past at all
## A fresh install gets the example tags, not two empty files.
##
## The fold used to run on a project with nothing to fold, write two empty
## files, and mark itself done - after which the seeding found the files already
## there and left them alone. The examples were reachable by nothing.
func test_a_project_with_nothing_to_fold_still_gets_its_examples() -> void:
	assert_true(GASSourceMigration.run(), "there is nothing to carry")
	assert_false(GASSourceMigration.pending(), "which is still a finished migration")
	assert_false(
		FileAccess.file_exists(SCRATCH_TAGS), "and nothing was written on the way past"
	)

	GASSourceMigration.ensure_sources(SOME_EXAMPLES)

	var expected: Array[StringName] = [&"Example.From.A.Fresh.Install"]
	assert_eq(
		GameplayTagGenerator.tags_in_file(), expected,
		"the examples are what a new project starts with"
	)
	assert_true(FileAccess.file_exists(SCRATCH_CUES), "and it has somewhere to put a cue")


## A file that is already there is left exactly as it is.
func test_seeding_does_not_touch_a_file_that_exists() -> void:
	var mine: Array[StringName] = [&"Mine.Only"]
	assert_true(GameplayTagGenerator.generate_tags_file(mine), "somebody's own tags")
	var before: String = FileAccess.get_file_as_string(SCRATCH_TAGS)

	GASSourceMigration.ensure_sources(SOME_EXAMPLES)

	assert_eq(FileAccess.get_file_as_string(SCRATCH_TAGS), before, "untouched")
#endregion


## The engine is expected to complain: a write it cannot make is a write it
## should say it cannot make.
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
