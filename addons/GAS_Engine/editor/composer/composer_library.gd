## Every ability in this project, found rather than asked for.
##
## The Composer used to draw whatever the Script editor happened to have open,
## and said so when that was not an ability. That is friction charged to the
## person for the tool's convenience: somebody who chose Ability Composer asked
## for their abilities, not for instructions about opening one first.
##
## Found by reading rather than by loading. `load()` on every script in a
## project compiles every script in a project, which is a visible pause on a
## real game for a question that a first line answers. So each file is read as
## text, its `extends` is resolved through the project's own class list, and a
## chain that reaches GameplayAbility makes it a candidate.
##
## A candidate, not a verdict. `ComposerHost.open()` is still what decides, and
## it decides on the loaded script; a false positive here costs one refusal with
## a reason on it, which is a cheaper mistake than a scan that misses somebody's
## ability and leaves them unable to reach it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerLibrary extends RefCounted

const ROOT: String = "res://"
const SCRIPT_SUFFIX: String = ".gd"
const EXTENDS_WORD: String = "extends "
const NAMED_WORD: String = "class_name "

## Where nothing of a game's own can live. `addons/gut` is a vendored test
## dependency and `.godot` is the engine's cache; walking either is time spent
## reading files that could not be somebody's ability.
const SKIPPED: Array[String] = ["res://addons/gut", "res://.godot"]


## What the last look found, and whether one has happened.
##
## A project with Dialogic, GLoot and QuestSystem installed carries about five
## hundred scripts that are not anybody's abilities, and looking through all of
## them again on every press is work nobody asked for. The answer is remembered
## instead, and thrown away whenever the editor says the filesystem moved.
static var _remembered: PackedStringArray = PackedStringArray()
static var _looked: bool = false


## Look again next time. Cheap, and correct to call whenever anything might have
## changed: the cost of forgetting too often is one scan, and the cost of
## forgetting too rarely is somebody's new ability being invisible.
static func forget() -> void:
	_looked = false
	_remembered = PackedStringArray()


## Start listening for somebody's word that files moved, exactly once.
##
## The editor's filesystem outlives the plugin, and `forget` is static, so a
## plugin that connects on enable and never lets go has connected twice by its
## second enable. Godot refuses that with an error rather than ignoring it - and
## disable-then-enable is not an unusual thing to do, it is the documented way
## to reload a plugin after its files change on disk.
static func listen_to(source: Object, moved: StringName) -> void:
	if not source.is_connected(moved, forget):
		source.connect(moved, forget)


## And stop. Safe to call when it was never listening, because an exit path that
## has to be sure it ran first is an exit path that eventually does not.
static func stop_listening_to(source: Object, moved: StringName) -> void:
	if source.is_connected(moved, forget):
		source.disconnect(moved, forget)


## Every file whose base chain reaches GameplayAbility, sorted so the list a
## person sees does not reshuffle itself between two openings.
static func abilities_in_project() -> PackedStringArray:
	if not _looked:
		_remembered = scan()
		_looked = true
	return _remembered


## The look itself, without the remembering. Separate so a caller that has to
## know the answer is current can ask for one, and so the two can be compared.
static func scan() -> PackedStringArray:
	var known: Dictionary[String, String] = _declared_classes()
	var settled: Dictionary[String, bool] = {}
	var found: PackedStringArray = PackedStringArray()

	for path: String in _scripts_under(ROOT):
		if _is_ability(path, known, settled):
			found.append(path)
	found.sort()
	return found


## Class name to the file that declares it, for resolving one `extends` to the
## next. Godot already keeps this list; rebuilding it by reading every file
## would be a second answer to a question that has one.
static func _declared_classes() -> Dictionary[String, String]:
	var known: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = entry["class"]
		var at: String = entry["path"]
		known[declared] = at
	return known


static func _scripts_under(folder: String) -> PackedStringArray:
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
		found.append_array(_scripts_under(folder.path_join(name)))
	return found


## Whether this file's base chain reaches GameplayAbility.
##
## `settled` is both a cache and the cycle guard: a file already being resolved
## is recorded as not-an-ability before its own base is asked about, so a class
## that somehow extends itself answers rather than recurses forever.
static func _is_ability(
	path: String, known: Dictionary[String, String], settled: Dictionary[String, bool]
) -> bool:
	if settled.has(path):
		return settled[path]
	settled[path] = false

	var base: String = _base_of(path)
	if base.is_empty():
		return false
	if base == ComposerCatalog.ABILITY_CLASS:
		settled[path] = true
		return true

	var next: String = known[base] if known.has(base) else base
	if not next.begins_with(ROOT) or next == path:
		return false
	settled[path] = _is_ability(next, known, settled)
	return settled[path]


## What a script says it extends, or nothing when it does not say.
##
## Read from the file rather than from a loaded script, and only until the line
## is found: `extends` is a header, so this stops within the first few lines of
## anything it is asked about.
static func _base_of(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		var said: String = _base_in(file.get_line().strip_edges())
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
## game bases its own abilities on, and therefore all of them.
static func _base_in(line: String) -> String:
	var said: String = ""
	if line.begins_with(EXTENDS_WORD):
		said = line.substr(EXTENDS_WORD.length())
	elif line.begins_with(NAMED_WORD) and line.contains(" " + EXTENDS_WORD):
		said = line.split(" " + EXTENDS_WORD)[1]
	return said.strip_edges().trim_prefix('"').trim_suffix('"')
