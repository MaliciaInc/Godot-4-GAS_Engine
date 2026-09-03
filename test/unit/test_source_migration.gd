## Folding an old registry resource in, and never again.
##
## The shape this replaces read the legacy resource on every editor start and
## added back whatever the file was missing. That is not a migration, and the
## test below is the reason: a tag somebody deleted came back on the next
## restart, so the file everyone had just been told was the only authority was
## quietly not.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const TAGS_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT
const LEGACY_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY
const CUES_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_CUES_GENERATED_SCRIPT
const DONE_SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_INTERNAL_SOURCE_MIGRATION

const SCRATCH_TAGS: String = "user://test_migration_tags.gd"
const SCRATCH_CUES: String = "user://test_migration_cues.gd"
const SCRATCH_LEGACY: String = "user://test_migration_legacy.tres"

const AN_OLD_TAG: StringName = &"Legacy.Only.Here"

var _restore: Dictionary[String, Variant] = {}


func before_each() -> void:
	for name: String in [TAGS_SETTING, LEGACY_SETTING, CUES_SETTING, DONE_SETTING]:
		_restore[name] = ProjectSettings.get_setting(name, null)
	ProjectSettings.set_setting(TAGS_SETTING, SCRATCH_TAGS)
	ProjectSettings.set_setting(CUES_SETTING, SCRATCH_CUES)
	ProjectSettings.set_setting(LEGACY_SETTING, SCRATCH_LEGACY)
	ProjectSettings.set_setting(DONE_SETTING, 0)

	var legacy: GameplayTagRegistry = GameplayTagRegistry.new()
	legacy.tags = [AN_OLD_TAG]
	assert_eq(ResourceSaver.save(legacy, SCRATCH_LEGACY), OK, "a project from before the file")


## Put back in memory, and never saved.
##
## Recording the fold sets a setting; persisting it is the plugin's job, which
## is what lets this test drive the whole thing without rewriting
## project.godot - a save would take its comments with it.
func after_each() -> void:
	for name: String in _restore:
		ProjectSettings.set_setting(name, _restore[name])
	for path: String in [SCRATCH_TAGS, SCRATCH_CUES, SCRATCH_LEGACY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The whole contract, walked in order, because the order is the contract.
##
## Each step only means anything after the one before it: folding proves the
## tags arrive, deleting proves a person can take one out, and running again is
## the step the old shape failed - it put the tag back and called that a
## migration.
func test_a_tag_deleted_after_the_fold_does_not_come_back() -> void:
	assert_true(GASSourceMigration.pending(), "a project that has not folded yet")
	assert_true(GASSourceMigration.run(), "folds")
	assert_true(
		GameplayTagGenerator.tags_in_file().has(AN_OLD_TAG),
		"and the old tag arrives in the file"
	)
	assert_false(GASSourceMigration.pending(), "and it is recorded as done")

	var without: Array[StringName] = []
	assert_true(GameplayTagGenerator.generate_tags_file(without), "somebody removes it")
	assert_false(GameplayTagGenerator.tags_in_file().has(AN_OLD_TAG), "and it is gone")

	assert_true(GASSourceMigration.run(), "the editor starts again")

	assert_false(
		GameplayTagGenerator.tags_in_file().has(AN_OLD_TAG),
		"and the tag stays gone - the file is the file"
	)


## The legacy resource is not read once the fold is recorded, whether or not it
## is still on disk. Deleting somebody's file is not the addon's business, and
## not needing it is enough.
func test_a_recorded_fold_does_not_read_the_old_resource_again() -> void:
	ProjectSettings.set_setting(DONE_SETTING, GASEngineProjectSettings.SOURCE_MIGRATION_DONE)

	assert_false(GASSourceMigration.pending(), "already done")
	assert_true(GASSourceMigration.run(), "so running is a no-op")
	assert_false(
		FileAccess.file_exists(SCRATCH_TAGS),
		"nothing was even written, let alone read from the old resource"
	)
