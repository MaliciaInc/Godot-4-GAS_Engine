## Every script in a project whose base chain reaches a named class.
##
## Two tools need this and neither needs the other: the Composer wants the
## abilities, and the attribute picker wants the attribute sets. Written twice
## it would be two answers to one question, and the second one is where a
## project with an unusual `extends` line stops being found.
##
## Found by reading rather than by loading. `load()` on every script in a
## project compiles every script in a project, which is a visible pause on a
## real game for a question that a first line answers. Each file is read as
## text, its `extends` is resolved through the project's own class list, and a
## chain that reaches the named base makes it a candidate.
##
## A candidate, not a verdict. Whoever asked still decides on the loaded script;
## a false positive costs one refusal with a reason on it, which is a cheaper
## mistake than a scan that misses somebody's file and leaves them unable to
## reach it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GDScriptClassScan extends RefCounted

const ROOT: String = "res://"
const SCRIPT_SUFFIX: String = ".gd"
const EXTENDS_WORD: String = "extends "
const NAMED_WORD: String = "class_name "

## Where nothing of a game's own can live. `addons/gut` is a vendored test
## dependency and `.godot` is the engine's cache; walking either is time spent
## reading files that could not be what anybody is looking for.
const SKIPPED: Array[String] = ["res://addons/gut", "res://.godot"]


## Every script under `folder` whose base chain reaches `base_class`, sorted so
## the list a person sees does not reshuffle itself between two openings.
static func scripts_extending(
	base_class: String, folder: String = ROOT
) -> PackedStringArray:
	var known: Dictionary[String, String] = declared_classes()
	var settled: Dictionary[String, bool] = {}
	var found: PackedStringArray = PackedStringArray()

	for path: String in scripts_under(folder):
		if reaches(path, base_class, known, settled):
			found.append(path)
	found.sort()
	return found


## Class name to the file that declares it, for resolving one `extends` to the
## next. Godot already keeps this list; rebuilding it by reading every file
## would be a second answer to a question that has one.
static func declared_classes() -> Dictionary[String, String]:
	var known: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = entry["class"]
		var at: String = entry["path"]
		known[declared] = at
	return known


static func scripts_under(folder: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for skipped: String in SKIPPED:
		if folder.begins_with(skipped):
			return found

	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return found

	for name: String in directory.get_files():
		if name.ends_with(SCRIPT_SUFFIX):
			found.append(folder.path_join(name))
	for name: String in directory.get_directories():
		found.append_array(scripts_under(folder.path_join(name)))
	return found


## Whether this file's base chain reaches `base_class`.
##
## `settled` is both a cache and the cycle guard: a file already being resolved
## is recorded as not-a-match before its own base is asked about, so a class
## that somehow extends itself answers rather than recurses forever. It is keyed
## per scan, so one scan's answers never leak into another's.
static func reaches(
	path: String,
	base_class: String,
	known: Dictionary[String, String],
	settled: Dictionary[String, bool]
) -> bool:
	if settled.has(path):
		return settled[path]
	settled[path] = false

	var base: String = base_of(path)
	if base.is_empty():
		return false
	if base == base_class:
		settled[path] = true
		return true

	var next: String = known[base] if known.has(base) else base
	if not next.begins_with(ROOT) or next == path:
		return false
	settled[path] = reaches(next, base_class, known, settled)
	return settled[path]


## What a script says it extends, or nothing when it does not say.
##
## Read from the file rather than from a loaded script, and only until the line
## is found: `extends` is a header, so this stops within the first few lines of
## anything it is asked about.
static func base_of(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		var said: String = base_in(file.get_line().strip_edges())
		if said.is_empty():
			continue
		file.close()
		return said
	file.close()
	return ""


## The base named on one line, in either place GDScript allows it to appear.
##
## `class_name Foo extends Bar` puts it mid-line, and a reader that only looked
## at the start of a line would miss every named class - including the one a
## game bases its own on, and therefore all of them.
static func base_in(line: String) -> String:
	var said: String = ""
	if line.begins_with(EXTENDS_WORD):
		said = line.substr(EXTENDS_WORD.length())
	elif line.begins_with(NAMED_WORD) and line.contains(" " + EXTENDS_WORD):
		said = line.split(" " + EXTENDS_WORD)[1]
	return said.strip_edges().trim_prefix('"').trim_suffix('"')
