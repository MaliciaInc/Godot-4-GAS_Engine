## Creates the smallest valid ability the Composer can open immediately.
##
## Creation lives outside the view and outside the runtime. The result is just a
## normal GDScript whose behavior authority is the same source file every other
## ability uses.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerAbilityTemplate extends RefCounted

const SCRIPT_SUFFIX: String = ".gd"
const RESOURCE_PREFIX: String = "res://"

const SOURCE: String = """@tool
extends GameplayAbility


func _activate_ability() -> bool:
	return true
"""

const INVALID_PATH: String = "Ability path must be a res:// GDScript path."
const ALREADY_EXISTS: String = "An ability already exists at %s."
const CANNOT_WRITE: String = "Could not create ability at %s."


static func create(path: String) -> String:
	if not path.begins_with(RESOURCE_PREFIX) or not path.ends_with(SCRIPT_SUFFIX):
		return INVALID_PATH
	if FileAccess.file_exists(path):
		return ALREADY_EXISTS % path

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return CANNOT_WRITE % path
	file.store_string(SOURCE)
	file.close()

	ComposerLibrary.forget()
	return ""
