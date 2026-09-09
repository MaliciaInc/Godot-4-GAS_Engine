## Writes and reads the file that says which scene answers which cue tag.
##
## The mirror of GameplayTagGenerator, and for the same reason: the bindings
## used to live in a resource that a generated file was never made from, so the
## only way to edit them was a screen that no longer exists, and the only way to
## check them was to open a resource in an Inspector. They are a file now -
## written here, read here, and readable by a person.
##
## Each binding preloads its scene rather than naming a path in a string. That
## buys a compile-time check, a rename the editor can follow, and a mistake the
## parser catches instead of the player.
##
## It does NOT make the exporter aware of the scene, whatever an earlier version
## of this comment claimed. Measured on 4.7.2:
## `ResourceLoader.get_dependencies()` returns 0 for every `.gd` file, preloads
## and all, while a `.tscn` returns its whole list - and that call is what the
## exporter walks. Under "Export all resources", Godot's own default, every cue
## scene ships regardless. Under "Selected scenes and dependencies" nothing
## reached only through GDScript ships: not this file, not the scenes it
## preloads, and not the eight scripts the cue manager autoload preloads either.
## Consumers on that mode have to name what they want in the export preset; see
## the export note in README.md.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GameplayCueGenerator extends RefCounted

## Preloaded by path, not named globally: this file is reachable from the
## GameplayCueManager autoload, and Godot parses autoloads before the global
## class cache exists.
const Settings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")
const Source = preload("res://addons/GAS_Engine/utilities/gdscript_source.gd")

const LINE_BREAK: String = "\n"
const OPEN_TAG: String = '&"'
const CLOSE_TAG: String = '":'
const OPEN_SCENE: String = 'preload("'
const CLOSE_SCENE: String = '")'

const GENERATED_REPORT: String = "GAS_Engine: wrote %s with %d cue bindings."

## The name the bindings live under, written once because both halves read it:
## the renderer puts the declaration in the file, and the reader looks for it to
## know where the body it may trust begins.
const BINDINGS_NAME: String = "const BINDINGS"
const BINDINGS_DECLARATION: String = (
	BINDINGS_NAME + ": Dictionary[StringName, PackedScene] = {"
)

## What may follow the name, if the line is declaring it and not something else.
##
## A type hint opens with a colon, an untyped constant with an equals sign, and
## either may be spaced away from the name. What may NOT follow it is more name.
const AFTER_THE_NAME: String = ": =\t"

## The lines above the bindings.
##
## Built rather than declared: a `const` may not read another const that is a
## preload, and the licence and @tool lines have to come from GDScriptSource -
## which this file must preload by path rather than name, because it is
## reachable from the GameplayCueManager autoload.
static func _header_lines() -> Array[String]:
	return [
		"## The project's gameplay cues: which scene answers which tag.",
		"##",
		"## Written by GAS_Engine and read back by it, and safe to edit by hand:",
		"## this file is the registry rather than a copy of one, so there is",
		"## nothing for it to fall out of step with.",
		"##",
		"## A cue asked for by a tag nobody bound falls back up the family:",
		"## A.B.C, then A.B, then A, and the first binding found is the one",
		"## that plays. A tag listed under OVERRIDE_PARENT ends that walk",
		"## where it stands - with its own binding when it has one, and with",
		"## silence when it has none.",
		"##",
		"## A tag under HANDLERS is answered by a script instead of a scene, for the",
		"## cues that never draw anything. Both are consulted at each level of that",
		"## walk, so which kind a tag uses never changes which tag answers.",
		"##",
		Source.ADDON_DOC_LINE,
		Source.LICENSE_DOC_LINE,
		"",
		Source.TOOL_ANNOTATION,
		"class_name GameplayCues",
		"",
		BINDINGS_DECLARATION,
	]


const CLOSING_LINE: String = "}"
## One entry, whether it names a scene or a script: both are a tag and a
## path, and two constants saying so would be two places to change it.
const BINDING_LINE: String = '	&"%s": preload("%s"),'

## The second declaration in the file: the tags that end a fallback walk.
##
## Separate rather than a third column on a binding, because a binding's value
## is a PackedScene and its type says so. It is not a list of bindings either:
## a tag here with no binding is the useful case, and says "nothing plays under
## here, and do not go looking further up".
## The third declaration: tags answered by a script rather than by a scene.
##
## Its own dictionary rather than a second column on a binding, for the
## reason OVERRIDE_PARENT is its own list: a binding's value is a PackedScene
## and its type says so. A tag belongs to one of the two, and the resolution
## walk consults both at every level so that which one it is never changes
## which tag answers a request.
const HANDLERS_NAME: String = "const HANDLERS"
const HANDLERS_DECLARATION: String = (
	HANDLERS_NAME + ": Dictionary[StringName, Script] = {"
)

const OVERRIDE_NAME: String = "const OVERRIDE_PARENT"
const OVERRIDE_DECLARATION: String = OVERRIDE_NAME + ": Array[StringName] = ["
const OVERRIDE_LINE: String = '	&"%s",'
const OVERRIDE_CLOSING_LINE: String = "]"

## A tag ends at its closing quote rather than at a comma, so a list somebody
## hand-edited and left without a trailing comma still reads.
const QUOTE: String = '"'


## What the file for these bindings looks like.
static func render_source(
	bindings: Dictionary[StringName, String],
	overrides: Array[StringName] = [],
	handlers: Dictionary[StringName, String] = {}
) -> String:
	var lines: Array[String] = []
	lines.assign(_header_lines())
	for tag: StringName in bindings:
		lines.append(BINDING_LINE % [tag, bindings[tag]])
	lines.append(CLOSING_LINE)
	lines.append("")
	lines.append("")
	lines.append(HANDLERS_DECLARATION)
	for tag: StringName in handlers:
		lines.append(BINDING_LINE % [tag, handlers[tag]])
	lines.append(CLOSING_LINE)
	lines.append("")
	lines.append("")
	lines.append(OVERRIDE_DECLARATION)
	for tag: StringName in overrides:
		lines.append(OVERRIDE_LINE % tag)
	lines.append(OVERRIDE_CLOSING_LINE)
	return LINE_BREAK.join(lines) + LINE_BREAK


## The bindings this project has, read out of the file that holds them.
##
## Read as text for the reason the tags are: the file declares a global
## `class_name`, so loading a second copy of it collides with the one Godot has
## already registered - which is exactly what a test pointing elsewhere does.
##
## Reading it as text is why the two rules below exist. The header calls this
## file safe to edit by hand, so it has to be read the way GDScript reads it,
## and it was not: any line anywhere holding `&"..."` and `preload("...")`
## counted. A commented-out binding therefore stayed live - gone for Godot and
## present for the cue manager, which builds its table from here. An example in
## a doc comment and a second dictionary further down counted too.
##
## So a binding is a line inside the BINDINGS body that starts where a binding
## starts. Everything else in the file is somebody else's business.
static func bindings_in_file() -> Dictionary[StringName, String]:
	return _entries_in(BINDINGS_NAME)


## Every tag-and-path entry inside one declared body.
##
## Both declarations are the same shape - a tag, a preloaded path - so both
## are read the same way. A second copy of this loop would be a second set of
## rules about what counts as an entry, and the rules are the careful part.
static func _entries_in(declaration_name: String) -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	for trimmed: String in _body_of(declaration_name, CLOSING_LINE):
		var tag: String = _between(trimmed, OPEN_TAG, CLOSE_TAG)
		var path: String = _between(trimmed, OPEN_SCENE, CLOSE_SCENE)
		if not tag.is_empty() and not path.is_empty():
			found[StringName(tag)] = path
	return found


## The tags answered by a script, read out of the same file, the same way
## and for the same reasons the bindings are.
static func handlers_in_file() -> Dictionary[StringName, String]:
	return _entries_in(HANDLERS_NAME)


## The tags that end a fallback walk, read out of the same file.
##
## A tag may appear here with or without a binding, and both say something:
## with one, it plays and nothing above it is consulted; without one, nothing
## plays and nothing above it is consulted either.
static func overrides_in_file() -> Array[StringName]:
	var found: Array[StringName] = []
	for trimmed: String in _body_of(OVERRIDE_NAME, OVERRIDE_CLOSING_LINE):
		var tag: String = _between(trimmed, OPEN_TAG, QUOTE)
		if not tag.is_empty() and not found.has(StringName(tag)):
			found.append(StringName(tag))
	return found


## The lines inside one declared body, and nothing else in the file.
##
## The whole of why the reader is careful lives here. An entry is a line
## inside the declared body that starts where an entry starts - not any line
## anywhere holding the same quotes, which is what a commented-out entry, a
## doc-comment example and a second dictionary further down all are.
static func _body_of(declaration_name: String, closing: String) -> Array[String]:
	var body: Array[String] = []
	var path: String = Settings.get_generated_cue_script_path()
	if not FileAccess.file_exists(path):
		return body

	var inside: bool = false
	for line: String in FileAccess.get_file_as_string(path).split(LINE_BREAK):
		var trimmed: String = line.strip_edges()
		if not inside:
			inside = _declares(trimmed, declaration_name)
			continue
		if trimmed.begins_with(closing):
			break
		if trimmed.begins_with(OPEN_TAG):
			body.append(trimmed)
	return body


## Whether this line declares the bindings, and not something else.
##
## Matched on the name rather than the whole declaration, so that adjusting the
## type hint by hand does not stop it being a declaration - but on the WHOLE
## name. `const BINDINGS_BACKUP = {` begins with `const BINDINGS` too, and a
## reader that took a prefix would read somebody's backup copy as the real
## thing, stop at its closing brace, and never reach the one GDScript uses. The
## same disagreement as a commented-out binding, arrived at by another road, so
## what follows the name has to be something that can follow a name.
static func _declares(trimmed: String, name: String) -> bool:
	if not trimmed.begins_with(name):
		return false
	if trimmed.length() == name.length():
		return true
	return AFTER_THE_NAME.contains(trimmed[name.length()])


## What one line holds between two markers, or nothing when it holds neither.
static func _between(line: String, opens: String, closes: String) -> String:
	var from: int = line.find(opens)
	if from < 0:
		return ""
	from += opens.length()
	var to: int = line.find(closes, from)
	if to < from:
		return ""
	return line.substr(from, to - from)


## Write the cues file for these bindings.
static func generate_cues_file(
	bindings: Dictionary[StringName, String], overrides: Array[StringName] = []
) -> bool:
	var path: String = Settings.get_generated_cue_script_path()
	if not Source.write(path, render_source(bindings, overrides)):
		return false
	print(GENERATED_REPORT % [path, bindings.size()])
	return true
