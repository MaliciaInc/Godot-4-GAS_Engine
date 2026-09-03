## Folding a pre-file registry resource into the file that replaced it, once.
##
## Tags and cues used to live in resources and are files now. A project made
## before that has resources, and their contents have to arrive somewhere - but
## "read the old one on every start and add whatever is missing" is not a
## migration. It is a second authority wearing a migration's clothes: a tag
## deleted from the file comes back on the next restart, and the file is no
## longer the file.
##
## So it happens once and says so, in a setting that survives restarts. After
## that the old resource is never read again, whether or not it is still there -
## deleting somebody's file is not this addon's business, and not needing it is
## enough.
##
## Lives here rather than on the plugin because the plugin cannot be driven
## without an editor, and this is the part worth being able to prove.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GASSourceMigration extends RefCounted

const TAGS_UNWRITABLE: String = "GAS_Engine: could not write the project's gameplay tags."
const CUES_UNWRITABLE: String = "GAS_Engine: could not write the project's gameplay cues."


## Everything this project needs done to its source files when the editor
## starts, in the one order that is correct.
##
## Returns whether something was recorded that now has to be persisted - the
## only part of this the plugin still owns, because saving a setting is an
## editor's job and this has to stay drivable without one.
##
## The order is the whole point. Seeding runs after the fold has finished, or
## when there was nothing to fold; never after one that failed. A project
## part-way through a migration is still an old project, and writing "what a
## new project starts with" on top of a half-finished fold creates exactly the
## files the next attempt is supposed to fold the old registry into. It used to
## run either way, and only the fact that a filesystem failure usually repeats
## kept that from being visible.
static func bring_project_up_to_date(example_tags: Array[String]) -> bool:
	var folded: bool = false
	if pending():
		if not run():
			return false
		folded = true
	ensure_sources(example_tags)
	return folded


## Whether the fold still has to happen in this project.
static func pending() -> bool:
	return not GASEngineProjectSettings.source_migration_done()


## Do it, and record it. True when there was nothing to do as well as when
## there was: both mean the project is where it should be afterwards.
##
## Nothing is recorded unless both writes succeeded. A fold that half happened
## and called itself finished would lose the half it did not write, and would
## never try again.
static func run() -> bool:
	if not pending():
		return true

	# Nothing to carry is not the same as nothing to do, and it is certainly not
	# the same as writing two empty files. A project that never had the old
	# resources gets its files from `ensure_sources()`, which knows what a new
	# one should start with; folding here would hand it two empty ones first and
	# leave the examples in a branch nothing reaches. It also means upgrading a
	# project that has a hand-edited file and no legacy resource does not
	# canonicalise it on the way past.
	if not _has_a_legacy_registry():
		GASEngineProjectSettings.mark_source_migration_done()
		return true

	var tags: Array[StringName] = _folded_tags()
	var cues: Dictionary[StringName, String] = _folded_cues()
	if not GameplayTagGenerator.generate_tags_file(tags):
		return false
	if not GameplayCueGenerator.generate_cues_file(cues):
		return false

	GASEngineProjectSettings.mark_source_migration_done()
	return true


## Whether this project has a registry resource from before the files.
static func _has_a_legacy_registry() -> bool:
	return (
		FileAccess.file_exists(GASEngineProjectSettings.get_legacy_registry_tag_path())
		or FileAccess.file_exists(GASEngineProjectSettings.get_legacy_registry_cue_path())
	)


## Make sure the project has both files, and leave them alone when it has.
##
## The seeding a new project needs, kept beside the fold because between them
## they are the whole answer to "what does this project start with" - and kept
## out of the plugin because the plugin cannot be driven without an editor, and
## this is the half worth proving.
static func ensure_sources(example_tags: Array[String]) -> void:
	if not FileAccess.file_exists(
		GASEngineProjectSettings.get_generated_tag_script_path()
	):
		var registry: GameplayTagRegistry = GameplayTagRegistry.new()
		for tag: String in example_tags:
			registry.add_tag(tag)
		if not GameplayTagGenerator.generate_tags_file(registry.tags):
			push_error(TAGS_UNWRITABLE)

	if not FileAccess.file_exists(
		GASEngineProjectSettings.get_generated_cue_script_path()
	):
		var none: Dictionary[StringName, String] = {}
		if not GameplayCueGenerator.generate_cues_file(none):
			push_error(CUES_UNWRITABLE)


## What the tags file holds, plus anything a legacy registry still names.
static func _folded_tags() -> Array[StringName]:
	var registry: GameplayTagRegistry = GameplayTagRegistry.new()
	registry.tags.assign(GameplayTagGenerator.tags_in_file())

	var path: String = GASEngineProjectSettings.get_legacy_registry_tag_path()
	if not FileAccess.file_exists(path):
		return registry.tags

	var legacy: GameplayTagRegistry = load(path) as GameplayTagRegistry
	if legacy == null:
		return registry.tags
	for tag: StringName in legacy.tags:
		# Through add_tag, so a legacy tag arrives formatted and validated the
		# way one added today would, rather than trusted for being old.
		registry.add_tag(String(tag))
	return registry.tags


## And what the cues file holds, plus anything a legacy registry still binds.
static func _folded_cues() -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = GameplayCueGenerator.bindings_in_file()
	var path: String = GASEngineProjectSettings.get_legacy_registry_cue_path()
	if not FileAccess.file_exists(path):
		return found

	var legacy: GameplayCueRegistry = load(path) as GameplayCueRegistry
	if legacy == null:
		return found
	for entry: GameplayCueEntry in legacy.entries:
		if entry == null or entry.tag == &"" or entry.scene == null:
			continue
		if not found.has(entry.tag):
			found[entry.tag] = entry.scene.resource_path
	return found
