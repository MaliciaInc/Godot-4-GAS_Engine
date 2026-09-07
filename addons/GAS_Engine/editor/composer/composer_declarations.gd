## The doc comments of a script, found by the method each one sits above.
##
## The catalog needs to read what a method says about itself, and Godot does not
## hand that over: `get_script_method_list()` answers with names and types and
## has never heard of a comment. So the file is read as text - the same file the
## reflection came from, so the two cannot be describing different versions of
## anything.
##
## Text, but not pattern matching over code. What is found here is the run of
## `##` lines immediately above a `func`, which is a rule about layout rather
## than about GDScript, and the rule is the one every doc comment in this
## project already follows.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerDeclarations extends RefCounted

const DOC_PREFIX: String = "##"
const FUNC_MARK: String = "func "
const STATIC_MARK: String = "static func "


## Every method of `path` that carries a doc comment, and the lines of it.
##
## Read once per script. A method with nothing written above it is absent from
## this rather than present with nothing, so a caller asking about one gets an
## empty answer either way and never has to tell "undocumented" from "not a
## method".
static func doc_comments_in(path: String) -> Dictionary[StringName, PackedStringArray]:
	var found: Dictionary[StringName, PackedStringArray] = {}
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty():
		return found

	var lines: PackedStringArray = source.split("\n")
	var carried: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var text: String = line.strip_edges()
		if text.begins_with(DOC_PREFIX):
			carried.append(text)
			continue

		var named: StringName = _method_named(text)
		if named != &"":
			found[named] = carried.duplicate()
		# Anything that is not a doc line ends the run, whether it was a method
		# or a blank: a comment separated from what it describes is a comment
		# about something else.
		carried = PackedStringArray()
	return found


## Which method a line declares, or empty when it declares none.
static func _method_named(text: String) -> StringName:
	var rest: String = ""
	if text.begins_with(STATIC_MARK):
		rest = text.substr(STATIC_MARK.length())
	elif text.begins_with(FUNC_MARK):
		rest = text.substr(FUNC_MARK.length())
	else:
		return &""

	var bracket: int = rest.find("(")
	if bracket <= 0:
		return &""
	return StringName(rest.left(bracket).strip_edges())
