## Writes and reads the file that says which scene answers which cue tag.
##
## The mirror of GameplayTagGenerator, and for the same reason: the bindings
## used to live in a resource that a generated file was never made from, so the
## only way to edit them was a screen that no longer exists, and the only way to
## check them was to open a resource in an Inspector. They are a file now -
## written here, read here, and readable by a person.
##
## Each binding preloads its scene rather than naming a path in a string. A path
## in a string is not a dependency: the exporter would not know the scene was
## wanted, and a cue that played in the editor would be missing from the game.
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
		Source.ADDON_DOC_LINE,
		Source.LICENSE_DOC_LINE,
		"",
		Source.TOOL_ANNOTATION,
		"class_name GameplayCues",
		"",
		BINDINGS_DECLARATION,
	]


const CLOSING_LINE: String = "}"
const BINDING_LINE: String = '	&"%s": preload("%s"),'


## What the file for these bindings looks like.
static func render_source(bindings: Dictionary[StringName, String]) -> String:
	var lines: Array[String] = []
	lines.assign(_header_lines())
	for tag: StringName in bindings:
		lines.append(BINDING_LINE % [tag, bindings[tag]])
	lines.append(CLOSING_LINE)
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
## counted. A commented-out binding therefore stayed live - gone for Godot, gone
## for the exporter that no longer sees the dependency, and present for the cue
## manager, which builds its table from here. An example in a doc comment and a
## second dictionary further down counted too.
##
## So a binding is a line inside the BINDINGS body that starts where a binding
## starts. Everything else in the file is somebody else's business.
static func bindings_in_file() -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	var path: String = Settings.get_generated_cue_script_path()
	if not FileAccess.file_exists(path):
		return found

	var inside: bool = false
	for line: String in FileAccess.get_file_as_string(path).split(LINE_BREAK):
		var trimmed: String = line.strip_edges()
		if not inside:
			inside = _declares_bindings(trimmed)
			continue
		if trimmed.begins_with(CLOSING_LINE):
			break
		if not trimmed.begins_with(OPEN_TAG):
			continue
		var tag: String = _between(trimmed, OPEN_TAG, CLOSE_TAG)
		var scene: String = _between(trimmed, OPEN_SCENE, CLOSE_SCENE)
		if not tag.is_empty() and not scene.is_empty():
			found[StringName(tag)] = scene
	return found


## Whether this line declares the bindings, and not something else.
##
## Matched on the name rather than the whole declaration, so that adjusting the
## type hint by hand does not stop it being a declaration - but on the WHOLE
## name. `const BINDINGS_BACKUP = {` begins with `const BINDINGS` too, and a
## reader that took a prefix would read somebody's backup copy as the real
## thing, stop at its closing brace, and never reach the one GDScript uses. The
## same disagreement as a commented-out binding, arrived at by another road, so
## what follows the name has to be something that can follow a name.
static func _declares_bindings(trimmed: String) -> bool:
	if not trimmed.begins_with(BINDINGS_NAME):
		return false
	if trimmed.length() == BINDINGS_NAME.length():
		return true
	return AFTER_THE_NAME.contains(trimmed[BINDINGS_NAME.length()])


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
static func generate_cues_file(bindings: Dictionary[StringName, String]) -> bool:
	var path: String = Settings.get_generated_cue_script_path()
	if not Source.write(path, render_source(bindings)):
		return false
	print(GENERATED_REPORT % [path, bindings.size()])
	return true
