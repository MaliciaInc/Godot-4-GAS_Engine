## The copy that is written when there is no longer anywhere to ask.
##
## Not a substitute for Save/Discard/Cancel. The plugin can leave the tree -
## a reload, a project close - and at that point it cannot hold a modal open
## and cannot wait for an answer. Losing the work silently is the one outcome
## that must not happen, so it goes to a file named after where it came from.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerRecovery extends RefCounted

const DIRECTORY: String = "user://gas_engine/composer_recovery"

static func write(source_path: String, content: String) -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return ""

	var safe_name: String = source_path.trim_prefix("res://")
	safe_name = safe_name.replace("/", "__").replace("\\", "__")
	if safe_name.is_empty():
		safe_name = "unnamed_ability.gd"

	var recovery_path: String = DIRECTORY + "/" + safe_name + ".recovery"
	var out: FileAccess = FileAccess.open(recovery_path, FileAccess.WRITE)
	if out == null:
		return ""

	out.store_string(content)
	out.flush()
	out.close()
	return recovery_path
