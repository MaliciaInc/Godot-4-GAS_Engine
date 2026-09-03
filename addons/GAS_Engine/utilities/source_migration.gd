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

	var tags: Array[StringName] = _folded_tags()
	var cues: Dictionary[StringName, String] = _folded_cues()
	if not GameplayTagGenerator.generate_tags_file(tags):
		return false
	if not GameplayCueGenerator.generate_cues_file(cues):
		return false

	GASEngineProjectSettings.mark_source_migration_done()
	return true


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
