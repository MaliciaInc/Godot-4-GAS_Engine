## Writes a drafted attribute set to a GDScript file on disk.
##
## Split from the dashboard tab so the tab decides what to show and this decides
## what is safe to write. Returns a typed outcome rather than popping its own
## dialog, which is what lets the decision be tested without a UI.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT

@tool
class_name AttributeSetCompiler extends RefCounted


## What happened, and what to tell the user about it.
class Outcome extends RefCounted:
	var ok: bool = false
	var title: String = ""
	var message: String = ""

	static func failure(failure_title: String, detail: String) -> Outcome:
		var outcome: Outcome = Outcome.new()
		outcome.title = failure_title
		outcome.message = detail
		return outcome

	static func success(detail: String) -> Outcome:
		var outcome: Outcome = Outcome.new()
		outcome.ok = true
		outcome.title = "Success"
		outcome.message = detail
		return outcome


const TITLE_BLOCKED: String = "Cannot Generate Script"
const TITLE_WRITE_ERROR: String = "Write Error"


## Compile one set. Nothing is written unless every check passes.
static func compile(drafts: AttributeSetDrafts, set_name: String) -> Outcome:
	if set_name.is_empty():
		return Outcome.failure(TITLE_BLOCKED, "No attribute set is selected.")

	var file_name: String = AttributeSetScriptWriter.file_name_for(set_name)
	var output_dir: String = GodotGasProjectSettings.get_attributes_output_dir_path()
	var file_path: String = output_dir.path_join(file_name)

	if is_open_in_the_script_editor(file_path):
		# The editor holds its own copy of an open script and writes it back on
		# save, so generating underneath it loses whichever version the user
		# does not expect.
		return Outcome.failure(
			TITLE_BLOCKED,
			"'" + file_name + "' is open in the Script workspace. Close its tab before"
			+ " regenerating, or the editor's copy will overwrite what is written here."
		)

	if not DirAccess.dir_exists_absolute(output_dir):
		if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
			return Outcome.failure(TITLE_WRITE_ERROR, "Could not create: " + output_dir)

	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return Outcome.failure(TITLE_WRITE_ERROR, "Could not write: " + file_path)

	file.store_string(AttributeSetScriptWriter.write(set_name, attributes_of(drafts, set_name)))
	file.close()
	EditorInterface.get_resource_filesystem().scan()
	return Outcome.success(file_name + " was generated at:" + "\n" + file_path)


## The set's attributes, in the shape the writer expects.
static func attributes_of(
	drafts: AttributeSetDrafts, set_name: String
) -> Array[AttributeSetScriptWriter.Attribute]:
	var attributes: Array[AttributeSetScriptWriter.Attribute] = []
	for key: String in drafts.attribute_names(set_name):
		attributes.append(AttributeSetScriptWriter.Attribute.of(key, drafts.entry(set_name, key).value))
	return attributes


static func is_open_in_the_script_editor(file_path: String) -> bool:
	for script: Script in EditorInterface.get_script_editor().get_open_scripts():
		if script.resource_path == file_path:
			return true
	return false
