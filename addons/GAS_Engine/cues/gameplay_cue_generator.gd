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
		"const BINDINGS: Dictionary[StringName, PackedScene] = {",
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
static func bindings_in_file() -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	var path: String = Settings.get_generated_cue_script_path()
	if not FileAccess.file_exists(path):
		return found

	for line: String in FileAccess.get_file_as_string(path).split(LINE_BREAK):
		var trimmed: String = line.strip_edges()
		var tag: String = _between(trimmed, OPEN_TAG, CLOSE_TAG)
		var scene: String = _between(trimmed, OPEN_SCENE, CLOSE_SCENE)
		if not tag.is_empty() and not scene.is_empty():
			found[StringName(tag)] = scene
	return found


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
