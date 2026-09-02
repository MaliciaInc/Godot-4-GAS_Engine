## Which wire may be drawn, decided the way GDScript decides an assignment.
##
## This invents nothing. A wire the Composer refuses is a `.gd` that would not
## compile, and a wire it allows is one that would - so the rules here are
## GDScript's own: the same type, a subclass reaching a base, an `int` widening
## to a `float`. Anything else is refused, and the refusal is the compiler's
## error said earlier and in a better place.
##
## The class hierarchy is read from the project rather than written down.
## Declaring "GameplayAbilityTargetData extends RefCounted" here would be a copy
## of something the code already says, and the copy is what stops being true
## when someone changes a base class.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerTypes extends RefCounted

## A parameter with no written type takes anything, because GDScript lets it.
## Refusing a wire there would be this tool being stricter than the language and
## calling a legal file an error.
const UNTYPED: Array[StringName] = [&"", &"Variant", &"Nil"]

const INT: StringName = &"int"
const FLOAT: StringName = &"float"

## Script class name -> the class it extends. Built once from the project.
static var _bases: Dictionary[StringName, StringName] = {}

## Script class name -> the file that declares it. Built once from the project.
static var _paths: Dictionary[StringName, String] = {}


#region Deciding
## Whether a value of `source` may be handed to a slot of `target`.
static func accepts(target: StringName, source: StringName) -> bool:
	if UNTYPED.has(target) or UNTYPED.has(source):
		return true
	if target == source:
		return true
	# GDScript widens an int into a float and refuses the other direction, and
	# so does this: a wire that loses the fraction is one someone did not mean.
	if target == FLOAT and source == INT:
		return true
	return inherits(source, target)


## Why a wire was refused, in the words a person needs. Empty when it was not.
##
## Names both ends. "Incompatible types" sends someone to compare two ports by
## eye; naming them says which one to change.
static func refusal(target: StringName, source: StringName) -> String:
	if accepts(target, source):
		return ""
	return "%s does not fit %s" % [_spelled(source), _spelled(target)]


## Execution meets execution, data meets data, and an output feeds an input.
##
## Flow is horizontal so both families arrive on the same sides, and they are
## told apart by the shape drawn for them - which means nothing but this stops a
## person joining a value to a run of control.
static func ports_match(source: ComposerNode.Port, target: ComposerNode.Port) -> bool:
	if source == null or target == null:
		return false
	if source.kind != target.kind:
		return false
	if source.direction != ComposerNode.PortDirection.OUTPUT:
		return false
	if target.direction != ComposerNode.PortDirection.INPUT:
		return false
	if source.kind == ComposerNode.PortKind.EXECUTION:
		return true
	return accepts(target.type_name, source.type_name)


static func _spelled(type_name: StringName) -> String:
	return "an untyped value" if UNTYPED.has(type_name) else String(type_name)
#endregion


#region Resolving a name to a script
## The file a class name is declared in, or empty when the project declares no
## such class.
static func script_of(declared: StringName) -> String:
	return _script_paths().get(declared, "")


## Which script the receiver of `receiver.method()` is.
##
## Two shapes and no third: `GameplayTargetingService.overlap_2d(...)` names a
## class outright, and `owner_asc.add_tag(...)` names a property whose type the
## script declares. Both are read from the project rather than listed here, so
## nothing has to be updated when a property changes type.
##
## Empty when it cannot be told, and the caller then knows nothing about the
## call rather than guessing. Matching a catalog entry on the method name alone
## would label a game's own `add_tag` with the engine's parameters and go on to
## complain about an argument it never takes - a false error, which is the one
## thing worse than no help at all.
static func script_behind(receiver: String, path: String) -> String:
	if receiver.is_empty():
		return ""
	var named: String = script_of(StringName(receiver))
	if not named.is_empty():
		return named
	if not ResourceLoader.exists(path):
		return ""
	var script: GDScript = load(path) as GDScript
	if script == null:
		return ""
	for described: Dictionary in script.get_script_property_list():
		var property: String = described["name"]
		if property == receiver:
			var declared: String = described["class_name"]
			return script_of(StringName(declared))
	return ""


static func _script_paths() -> Dictionary[StringName, String]:
	if not _paths.is_empty():
		return _paths
	for described: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = described["class"]
		var path: String = described["path"]
		if not declared.is_empty() and not path.is_empty():
			_paths[StringName(declared)] = path
	return _paths
#endregion


#region Reading the hierarchy
## Whether `child` is `ancestor`, or descends from it.
##
## Walks the script classes the project declares until it reaches an engine
## class, then hands the rest to ClassDB. Two hierarchies meet in the middle
## here because Godot keeps them apart: a `class_name` in GDScript is not in
## ClassDB, and a Node is not in the global class list.
static func inherits(child: StringName, ancestor: StringName) -> bool:
	if child == ancestor:
		return true

	var walked: StringName = child
	var guard: int = 0
	while _script_bases().has(walked):
		walked = _script_bases()[walked]
		if walked == ancestor:
			return true
		# A base chain cannot be longer than the list itself; anything longer is
		# a cycle, and an editor panel is not the place to hang on one.
		guard += 1
		if guard > _script_bases().size():
			return false

	if not ClassDB.class_exists(walked) or not ClassDB.class_exists(ancestor):
		return false
	return ClassDB.is_parent_class(walked, ancestor)


## Every `class_name` the project declares, and what it extends.
##
## Read from the project rather than restated. It cannot change while the editor
## runs without a reload, so it is built once.
static func _script_bases() -> Dictionary[StringName, StringName]:
	if not _bases.is_empty():
		return _bases
	for described: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = described["class"]
		var base: String = described["base"]
		if declared.is_empty() or base.is_empty():
			continue
		_bases[StringName(declared)] = StringName(base)
	return _bases
#endregion
