## Generates a GDScript file of tag constants for IDE autocomplete.
##
## Turns the registry's StringName tags into `const Status_Stunned: StringName =
## &"Status.Stunned"`, so gameplay code names a tag through a symbol the editor
## can complete and a rename can follow, instead of retyping the literal.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayTagGenerator extends RefCounted

## The line printed once a generated file is written.
const CONST_WORD: String = "const "
const TAG_OPEN: String = '&"'
const TAG_CLOSE: String = '"'
const NEWLINE: String = "
"

const GENERATED_REPORT: String = "GAS_Engine: generated %s with %d constants."

## Said out loud rather than printed: a designer who added a tag and got no
## constant needs to know, and stderr scrolls past.

## Anything outside this set becomes an underscore in a generated identifier.
const IDENTIFIER_PATTERN: String = "[^a-zA-Z0-9_]"

const SEGMENT_SEPARATOR: String = "."
const LINE_BREAK: String = "\n"
const IDENTIFIER_SEPARATOR: String = "_"

## The header every generated file carries, so nobody edits one by hand.
const HEADER_LINES: Array[String] = [
	"## The project's gameplay tags.",
	"##",
	"## Written by GAS_Engine and read back by it, and safe to edit by hand: this",
	"## file is the registry rather than a copy of one, so there is nothing for it",
	"## to fall out of step with. A constant's value is the tag; its name is there",
	"## so code can reach the tag without spelling the string.",
	"##",
	GDScriptSource.ADDON_DOC_LINE,
	GDScriptSource.LICENSE_DOC_LINE,
	"",
	GDScriptSource.TOOL_ANNOTATION,
	"class_name GameplayTags",
	"",
]

## The three declarations that are about tags rather than a list of them.
##
## Their own dictionaries rather than columns on a constant, because a
## constant's value is the tag and its type says so. A tag appears in one of
## these only when there is something to say about it, which for most tags in
## most projects is never.
const REDIRECTS_NAME: String = "const REDIRECTS"
const REDIRECTS_DECLARATION: String = (
	REDIRECTS_NAME + ": Dictionary[StringName, StringName] = {"
)

const RESTRICTED_NAME: String = "const RESTRICTED"
const RESTRICTED_DECLARATION: String = (
	RESTRICTED_NAME + ": Dictionary[StringName, StringName] = {"
)

const COMMENTS_NAME: String = "const COMMENTS"
const COMMENTS_DECLARATION: String = (
	COMMENTS_NAME + ": Dictionary[StringName, String] = {"
)

## One entry of any of the three: a tag, then what is said about it.
const ENTRY_LINE: String = '	&"%s": &"%s",'
const COMMENT_LINE: String = '	&"%s": "%s",'
const CLOSING_LINE: String = "}"


#region Code Generation
## The whole generated file as text, from these tags and nothing else.
##
## Pure and deterministic: the same tags produce the same bytes. That is what
## lets a test compare the tracked file against this without an editor, and it
## is why the writer below produces nothing of its own - two places building
## the same text would eventually build it differently.
static func render_tags_source(
	tags: Array[StringName],
	redirects: Dictionary[StringName, StringName] = {},
	restricted: Dictionary[StringName, StringName] = {},
	comments: Dictionary[StringName, String] = {}
) -> String:
	var lines: Array[String] = []
	lines.assign(HEADER_LINES)
	for tag: StringName in tags:
		lines.append(constant_line(tag))
	_render_block(lines, REDIRECTS_DECLARATION, redirects, ENTRY_LINE)
	_render_block(lines, RESTRICTED_DECLARATION, restricted, ENTRY_LINE)
	_render_block(lines, COMMENTS_DECLARATION, comments, COMMENT_LINE)
	return LINE_BREAK.join(lines) + LINE_BREAK


## One declaration and its entries, or an empty one when there are none.
##
## Written even when empty, so the file always has somewhere to put the
## first redirect a project needs - and so the round trip that reads this
## file back and re-renders it produces the same bytes either way.
static func _render_block(
	lines: Array[String],
	declaration: String,
	entries: Dictionary,
	entry_line: String
) -> void:
	lines.append("")
	lines.append("")
	lines.append(declaration)
	for tag: StringName in entries:
		# `str()` rather than `String()`: the dictionary is untyped because the
		# three declarations it renders hold different value types, so its
		# values are Variants, and `String()` will not take one.
		lines.append(entry_line % [String(tag), str(entries[tag])])
	lines.append(CLOSING_LINE)


## Write the constants file for these tags.
## The tags this project has, read back out of the file that holds them.
##
## The file used to be a copy of a registry resource, which meant two places a
## tag could live and one of them going stale the moment somebody edited the
## other by hand. It is the registry now: written here, read here, and nothing
## else to keep in step with it.
##
## Read as text rather than loaded. The file declares a global `class_name`, so
## loading a second copy of it - which is exactly what a test does, and what any
## caller pointing at another path would do - collides with the one Godot has
## already registered. Reading also costs no compile, and the format being
## parsed is the one rendered eight lines further down.
static func tags_in_file() -> Array[StringName]:
	var found: Array[StringName] = []
	var path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	if not FileAccess.file_exists(path):
		return found

	for line: String in FileAccess.get_file_as_string(path).split(NEWLINE):
		var tag: String = _tag_named_in(line.strip_edges())
		if not tag.is_empty():
			found.append(StringName(tag))
	# Not sorted here. The file was written in order and reading it back must
	# hand that order over unchanged - and `Array[StringName].sort()` would not
	# even be the right order to impose: StringName compares by its own internal
	# ordering, not alphabetically, so sorting here silently reshuffled the
	# project's tags on the first read.
	return found


## The tag a constant line names, or nothing when the line names none.
##
## A commented line is already out, because a comment does not begin with
## `const `. What was not out was a comment at the END of one: the closing quote
## was found with `rfind`, so
## `const Noted: StringName = &"Status.Noted"  # they call it "big"` came back
## as a tag named `Status.Noted"  # they call it "big`. A tag cannot contain a
## quote, so the first quote after the opener is always the right one.
static func _tag_named_in(line: String) -> String:
	if not line.begins_with(CONST_WORD):
		return ""
	var opened: int = line.find(TAG_OPEN)
	if opened < 0:
		return ""
	var from: int = opened + TAG_OPEN.length()
	var closed: int = line.find(TAG_CLOSE, from)
	if closed <= from:
		return ""
	return line.substr(from, closed - from)


## Everything one of the three declarations says, read out of the file.
##
## Read as text for the reason the tags are: the file declares a global
## `class_name`, so loading a second copy of it collides with the one Godot
## has already registered.
##
## An entry is a line inside the declared body that starts where an entry
## starts. Everything else in the file - a commented-out entry, an example in
## a doc comment, a second dictionary further down - is somebody else's
## business, which is the same rule the cue registry's reader learned.
static func redirects_in_file() -> Dictionary[StringName, StringName]:
	return _named_entries_in(REDIRECTS_NAME)


static func restricted_in_file() -> Dictionary[StringName, StringName]:
	return _named_entries_in(RESTRICTED_NAME)


## The comments, whose values are plain strings rather than tag names.
static func comments_in_file() -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	for line: String in _body_of(COMMENTS_NAME):
		var tag: String = _between(line, TAG_OPEN, TAG_CLOSE)
		var said: String = _after_the_colon(line)
		if not tag.is_empty():
			found[StringName(tag)] = said
	return found


static func _named_entries_in(
	declaration_name: String
) -> Dictionary[StringName, StringName]:
	var found: Dictionary[StringName, StringName] = {}
	for line: String in _body_of(declaration_name):
		var tag: String = _between(line, TAG_OPEN, TAG_CLOSE)
		var said: String = _between(_after_the_colon_raw(line), TAG_OPEN, TAG_CLOSE)
		if not tag.is_empty() and not said.is_empty():
			found[StringName(tag)] = StringName(said)
	return found


## The lines inside one declared body, and nothing else in the file.
static func _body_of(declaration_name: String) -> Array[String]:
	var body: Array[String] = []
	var path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	if not FileAccess.file_exists(path):
		return body

	var inside: bool = false
	for line: String in FileAccess.get_file_as_string(path).split(NEWLINE):
		var trimmed: String = line.strip_edges()
		if not inside:
			inside = trimmed.begins_with(declaration_name)
			continue
		if trimmed.begins_with(CLOSING_LINE):
			break
		if trimmed.begins_with(TAG_OPEN):
			body.append(trimmed)
	return body


## What one entry line holds between two markers, or nothing.
static func _between(line: String, opens: String, closes: String) -> String:
	var from: int = line.find(opens)
	if from < 0:
		return ""
	from += opens.length()
	var to: int = line.find(closes, from)
	if to <= from:
		return ""
	return line.substr(from, to - from)


## Everything past the tag, which is where the value of an entry begins.
static func _after_the_colon_raw(line: String) -> String:
	var closed: int = line.find(TAG_CLOSE, line.find(TAG_OPEN) + TAG_OPEN.length())
	if closed < 0:
		return ""
	return line.substr(closed + TAG_CLOSE.length())


## A comment's own text, which is an ordinary quoted string rather than a tag.
static func _after_the_colon(line: String) -> String:
	return _between(_after_the_colon_raw(line), TAG_CLOSE, TAG_CLOSE)


## Write the tags file, keeping everything else it already declared.
##
## The redirects, the restricted prefixes and the comments are read back and
## written again. Rendering with the defaults would delete every one of them the
## first time anybody added a tag - authored work removed by an unrelated
## action, in a file nobody thinks of as theirs to check.
static func generate_tags_file(tags: Array[StringName]) -> bool:
	var path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	var source: String = render_tags_source(
		tags, redirects_in_file(), restricted_in_file(), comments_in_file()
	)
	if not GDScriptSource.write(path, source):
		return false
	print(GENERATED_REPORT % [path, tags.size()])
	return true


## One `const NAME: StringName = &"Tag"` line.
static func constant_line(tag: StringName) -> String:
	var tag_string: String = String(tag)
	var constant_name: String = sanitize_identifier(
		tag_string.replace(SEGMENT_SEPARATOR, IDENTIFIER_SEPARATOR)
	)
	return "const " + constant_name + ": StringName = &\"" + tag_string + "\""
#endregion


#region Helpers
## Make a string safe to use as a GDScript identifier.
##
## A leading digit is prefixed rather than dropped: dropping it would collapse
## `1Fire` and `Fire` into one constant, and the second definition would
## silently win.
static func sanitize_identifier(raw: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile(IDENTIFIER_PATTERN)
	var sanitized: String = regex.sub(raw, IDENTIFIER_SEPARATOR, true)

	if not sanitized.is_empty() and sanitized[0].is_valid_int():
		sanitized = IDENTIFIER_SEPARATOR + sanitized

	return sanitized
#endregion
