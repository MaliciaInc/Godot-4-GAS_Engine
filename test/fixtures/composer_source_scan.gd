## Reading the Composer's own files, the way a gate has to read them.
##
## Every architectural gate asks one of three questions: which files are there,
## does this one name that identifier as code, and where does a class name
## resolve to. Written out per battery they were the same three functions twice,
## and two scanners that answered differently would make two gates disagree
## about the same folder.
##
## The whole-word match matters more than it looks. `ComposerWiringRoutes` is a
## live class whose name begins with a retired one, so a scan on substrings would
## report the file that replaced the old wiring as the old wiring coming back.
##
## Nothing here asserts. A fixture that judged would be a second set of rules to
## keep in step with the real ones.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerSourceScan extends RefCounted

## Where the Composer's production code lives, and nothing else does.
const DIR: String = "res://addons/GAS_Engine/editor/composer"
const A_SCRIPT: String = ".gd"


## Every production file of the Composer, by path.
##
## Read off the folder rather than off a list: a gate that scans the files
## somebody remembered to name cannot see the one they added afterwards.
static func sources() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for file_name: String in DirAccess.get_files_at(DIR):
		if not file_name.ends_with(A_SCRIPT):
			continue
		var at: String = DIR + "/" + file_name
		found[at] = FileAccess.get_file_as_string(at)
	return found


## One of them, by name.
static func source_of(file_name: String) -> String:
	return FileAccess.get_file_as_string(DIR + "/" + file_name)


## Whether `source` names `identifier` as code: a whole word, outside comments.
static func names(source: String, identifier: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("\\b" + identifier + "\\b")
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		if pattern.search(line) != null:
			return true
	return false


## Every global class the project declares, and the file it comes from.
static func declared_classes() -> Dictionary[String, String]:
	var declared: Dictionary[String, String] = {}
	for described: Dictionary in ProjectSettings.get_global_class_list():
		declared[described["class"]] = described["path"]
	return declared
