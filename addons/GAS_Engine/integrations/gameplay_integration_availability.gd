## Whether an optional third-party addon is present, asked without touching it.
##
## GAS_Engine ships bridges to Dialogic, GLoot and QuestSystem, and ships none
## of them. Every bridge therefore has to answer "is it there?" before it can do
## anything, and it has to answer without loading a class that may not exist -
## naming an absent `class_name` is a parse error, not a false.
##
## The question is answered by looking for the addon's own `plugin.cfg` on disk.
## Deliberately with `FileAccess.file_exists` rather than `ResourceLoader.exists`:
## a `plugin.cfg` is a config file, not a Resource, and asking the resource
## loader about it invites an importer to have an opinion about a path that is
## simply either there or not.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayIntegrationAvailability extends RefCounted

const DIALOGIC_PLUGIN_PATH: String = "res://addons/dialogic/plugin.cfg"
const GLOOT_PLUGIN_PATH: String = "res://addons/gloot/plugin.cfg"
const QUEST_SYSTEM_PLUGIN_PATH: String = "res://addons/quest_system/plugin.cfg"

const DIALOGIC_AUTOLOAD_PATH: NodePath = ^"/root/Dialogic"
const QUEST_SYSTEM_AUTOLOAD_PATH: NodePath = ^"/root/QuestSystem"


#region Installed
static func is_dialogic_installed() -> bool:
	return FileAccess.file_exists(DIALOGIC_PLUGIN_PATH)


static func is_gloot_installed() -> bool:
	return FileAccess.file_exists(GLOOT_PLUGIN_PATH)


static func is_quest_system_installed() -> bool:
	return FileAccess.file_exists(QUEST_SYSTEM_PLUGIN_PATH)
#endregion


#region Running
## The live Dialogic singleton, or null.
##
## Installed and running are different questions: the files can be present while
## the plugin is disabled, in which case the autoload does not exist. Both are
## checked, and either answering no gives null rather than an error - an absent
## optional integration is an ordinary state, not a fault.
static func dialogic_runtime(tree: SceneTree) -> Node:
	if tree == null or not is_dialogic_installed():
		return null
	return tree.root.get_node_or_null(DIALOGIC_AUTOLOAD_PATH)


static func quest_system_runtime(tree: SceneTree) -> Node:
	if tree == null or not is_quest_system_installed():
		return null
	return tree.root.get_node_or_null(QUEST_SYSTEM_AUTOLOAD_PATH)
#endregion
