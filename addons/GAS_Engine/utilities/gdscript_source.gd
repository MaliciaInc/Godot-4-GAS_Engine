## The GDScript this addon writes into generated files.
##
## Two generators emit GDScript - the tag generator and the cue generator - and
## both were spelling the same annotations, and later the same write. One
## spelling of "what a generated file looks like" means a change to the house
## style is one edit rather than a hunt.
##
## Only fragments both emitters share live here. A fragment used by one of them
## belongs in that emitter, next to the code that decides its shape.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0

@tool
class_name GDScriptSource extends RefCounted

## Marks a generated script as editor-runnable, which anything generated here
## needs: a class the editor is expected to read has to run in the editor.
const TOOL_ANNOTATION: String = "@tool"

## What a failed write says, wherever it happened.
const WRITE_FAILED: String = "GAS_Engine: could not write the generated file: %s"

## Said when the replacement could not be built. The file being replaced is
## untouched when this happens, which is the point of saying it separately.
const STAGING_FAILED: String = "GAS_Engine: could not stage the generated file: %s"

## What a half-written replacement is called while it is still half-written.
const STAGED_SUFFIX: String = ".staged"

## The addon line every generated file carries, so a reader knows what wrote it.
const ADDON_DOC_LINE: String = "## @meta_addon: GAS_Engine"

## The licence line every generated file carries, matching this addon's.
const LICENSE_DOC_LINE: String = "## @meta_license: GAS_Engine Community Use License 1.0"

const NEWLINE: String = "\n"


## Write a generated file without putting the existing one at risk.
##
## Staged, verified, then swapped in - the same order the effect runtime uses,
## and for the same reason. `FileAccess.WRITE` truncates the moment it opens, so
## the old shape discovered a full disk, a lock or a partial write *after* it had
## already destroyed the file it was replacing. These files are the project's
## only copy of its tags and cues now, so that is the wrong moment to find out.
##
## A failure before the swap leaves the original byte for byte as it was.
static func write(path: String, source: String) -> bool:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	var staged: String = path + STAGED_SUFFIX
	if not _store(staged, source):
		return false

	# Read back rather than trusting the write: a store that reported no error
	# and landed short is the failure this whole shape exists to survive.
	if FileAccess.get_file_as_string(staged) != source:
		push_error(STAGING_FAILED % staged)
		_discard(staged)
		return false
	return _swap_in(path, staged)


static func _store(path: String, source: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(STAGING_FAILED % path)
		return false
	file.store_string(source)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error(STAGING_FAILED % path)
		_discard(path)
		return false
	return true


## Put the staged file where the real one is. The only destructive step, and it
## does not happen until the replacement is known to be complete.
static func _swap_in(path: String, staged: String) -> bool:
	var folder: DirAccess = DirAccess.open(path.get_base_dir())
	if folder == null:
		push_error(WRITE_FAILED % path)
		_discard(staged)
		return false
	if folder.file_exists(path.get_file()) and folder.remove(path.get_file()) != OK:
		push_error(WRITE_FAILED % path)
		_discard(staged)
		return false
	if folder.rename(staged.get_file(), path.get_file()) != OK:
		push_error(WRITE_FAILED % path)
		return false
	return true


## A staged file nobody is going to use is rubbish in the project folder.
static func _discard(staged: String) -> void:
	if FileAccess.file_exists(staged):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staged))
