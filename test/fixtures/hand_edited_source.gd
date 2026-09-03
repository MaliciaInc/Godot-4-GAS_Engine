## Puts a file of your choosing where a generated one is supposed to be.
##
## The tags and cues files are the project's registries and are documented as
## safe to edit by hand, which means the readers have to be tested against what
## a person might actually leave behind - a commented-out line, a note at the
## end of one, an example in a doc comment. None of that can be tested against
## the project's own file: it is generated, so it never contains any of it.
##
## One function rather than one per reader, because the two would be the same
## eight lines with a different call in the middle - and the duplication gate
## would be right to say so.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name HandEditedSource extends RefCounted

const LINE_BREAK: String = "\n"
const PROBE_PATH: String = "user://hand_edited_source_probe.gd"


## Point `setting` at a file holding these lines, ask `reader` for its answer,
## and put the setting back before handing the answer over.
##
## The setting is restored before the caller can assert on anything, so a
## failing expectation cannot leave the rest of the suite reading a scratch
## file instead of the project's.
static func read(setting: String, lines: Array[String], reader: Callable) -> Variant:
	var previous: Variant = ProjectSettings.get_setting(setting, null)
	var file: FileAccess = FileAccess.open(PROBE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("HandEditedSource: could not write " + PROBE_PATH)
		return null
	file.store_string(LINE_BREAK.join(lines) + LINE_BREAK)
	file.close()

	ProjectSettings.set_setting(setting, PROBE_PATH)
	var answer: Variant = reader.call()
	ProjectSettings.set_setting(setting, previous)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE_PATH))
	return answer
