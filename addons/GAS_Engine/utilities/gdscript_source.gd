## The GDScript this addon writes into generated files.
##
## Two generators emit GDScript - the attribute-set writer and the tag
## generator - and both were spelling the same annotations. One spelling of
## "what a generated file looks like" means a change to the house style is one
## edit rather than a hunt.
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

## The addon line every generated file carries, so a reader knows what wrote it.
const ADDON_DOC_LINE: String = "## @meta_addon: GAS_Engine"

## The licence line every generated file carries, matching this addon's.
const LICENSE_DOC_LINE: String = "## @meta_license: GAS_Engine Community Use License 1.0"

const NEWLINE: String = "\n"


## Write a generated file, making its directory when the checkout has none yet.
##
## Both generators did this, line for line: resolve a path, create the folder,
## open, store, check, close, and report the same failure in the same words. Two
## copies of a write is two places for a half-written file to be reported as a
## whole one.
static func write(path: String, source: String) -> bool:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(WRITE_FAILED % path)
		return false

	file.store_string(source)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error(WRITE_FAILED % path)
		return false
	return true
