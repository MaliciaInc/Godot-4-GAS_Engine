## Replacing a file without ever having none of it on disk.
##
## An ability is somebody's work, and the moment between opening a file for
## writing and finishing the write is a moment in which it is empty. A crash
## there - or a disk that fills - leaves nothing. So the new text is written
## beside the original, the original is moved aside, the new one takes its
## place, and only once what is on disk reads back as what was asked for is
## the old one let go. Every failure puts the original back.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerAtomicFile extends RefCounted

const TMP_SUFFIX: String = ".gas_engine.tmp"
const BAK_SUFFIX: String = ".gas_engine.bak"

static func replace(path: String, content: String) -> bool:
	# What follows renames whatever is at `path` out of the way and then deletes
	# it, and `DirAccess.rename_absolute()` is perfectly willing to move a
	# directory. Handed one, this would replace it with a file and delete it and
	# everything under it. The only caller checks first; this checks anyway,
	# because the cost of being wrong here is somebody's folder.
	if not FileAccess.file_exists(path):
		return false

	var temp_path: String = path + TMP_SUFFIX
	var backup_path: String = path + BAK_SUFFIX

	var out: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if out == null:
		return false
	out.store_string(content)
	out.flush()
	out.close()

	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_temp: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)

	if DirAccess.rename_absolute(absolute_path, absolute_backup) != OK:
		DirAccess.remove_absolute(absolute_temp)
		return false

	if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
		DirAccess.rename_absolute(absolute_backup, absolute_path)
		DirAccess.remove_absolute(absolute_temp)
		return false

	var verify: FileAccess = FileAccess.open(path, FileAccess.READ)
	if verify == null:
		DirAccess.remove_absolute(absolute_path)
		DirAccess.rename_absolute(absolute_backup, absolute_path)
		return false

	var written: String = verify.get_as_text()
	verify.close()

	if written != content:
		DirAccess.remove_absolute(absolute_path)
		DirAccess.rename_absolute(absolute_backup, absolute_path)
		return false

	DirAccess.remove_absolute(absolute_backup)
	return true
