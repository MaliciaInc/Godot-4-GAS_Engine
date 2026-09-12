## Every attribute this project declares, and which set declares it.
##
## What a picker offers. Found rather than typed: an attribute name written by
## hand is a name nobody checks, and the first person to notice a typo is
## whoever wondered why the effect did nothing.
##
## Read off the sets themselves. An AttributeSet says which attributes it has by
## carrying `AttributeData` properties, and that is the same question the runtime
## asks - so the picker cannot offer an attribute the runtime would not find, and
## cannot miss one it would.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeCatalog extends RefCounted

## The base every attribute set extends.
const SET_CLASS: String = "AttributeSet"

## How one attribute is written for a person: the set it lives in, then its own
## name. Two sets that both declare `health` are two entries, and which is meant
## is the whole reason the typed reference exists.
const SHOWN: String = "%s.%s"


## One attribute somebody can pick.
class Entry extends RefCounted:
	## The set's script file name without its extension, which is what a person
	## recognises: `player_attributes`, not `res://.../player_attributes.gd`.
	var set_name: StringName = &""
	var attribute_name: StringName = &""

	func shown() -> String:
		return SHOWN % [set_name, attribute_name]

	## The reference this entry stands for, built fresh each time: a picker
	## handing out one shared Resource would have every effect in a project
	## pointing at the same object.
	func as_reference() -> GameplayAttributeRef:
		var made: GameplayAttributeRef = GameplayAttributeRef.new()
		made.set_name = set_name
		made.attribute_name = attribute_name
		return made


## What the last look found, and whether one has happened.
##
## Remembered because a project's scripts do not change while somebody is
## picking an attribute, and thrown away whenever the editor says the filesystem
## moved - the cost of forgetting too often is one scan, and the cost of
## forgetting too rarely is somebody's new attribute being unpickable.
static var _remembered: Array[Entry] = []
static var _looked: bool = false


## Look again next time.
static func forget() -> void:
	_looked = false
	_remembered = []


## Start listening for somebody's word that files moved, exactly once.
##
## Connecting twice is an error in Godot rather than a no-op, and
## disable-then-enable is the documented way to reload a plugin after its files
## change - so a plugin that connects on enable and never lets go has connected
## twice by its second enable.
static func listen_to(source: Object, moved: StringName) -> void:
	if not source.is_connected(moved, forget):
		source.connect(moved, forget)


static func stop_listening_to(source: Object, moved: StringName) -> void:
	if source.is_connected(moved, forget):
		source.disconnect(moved, forget)


## Every attribute in the project, remembered.
static func entries() -> Array[Entry]:
	if not _looked:
		_remembered = scan()
		_looked = true
	return _remembered


## The look itself, without the remembering.
##
## A set that cannot be built is skipped rather than fatal: a project mid-edit
## has scripts that do not compile, and a picker that refused to open until they
## did would be a picker nobody can use while they are working.
static func scan() -> Array[Entry]:
	var found: Array[Entry] = []
	for path: String in GDScriptClassScan.scripts_extending(SET_CLASS):
		var script: GDScript = load(path) as GDScript
		if script == null:
			continue
		var built: Object = script.new()
		var made: AttributeSet = built as AttributeSet
		if made == null:
			continue
		var set_name: StringName = StringName(path.get_file().get_basename())
		for attribute_name: StringName in made.get_attribute_names():
			var entry: Entry = Entry.new()
			entry.set_name = set_name
			entry.attribute_name = attribute_name
			found.append(entry)
	return found


## Whether anything in the project declares this attribute.
##
## By name alone when the reference does not say which set, because that is
## what such a reference means: the attribute called this, wherever it lives.
## A reference naming a set is checked against that set.
static func knows(reference: GameplayAttributeRef) -> bool:
	if reference == null or not reference.is_valid():
		return false
	for entry: Entry in entries():
		if entry.attribute_name != reference.attribute_name:
			continue
		if reference.set_name == &"" or reference.set_name == entry.set_name:
			return true
	return false


## Whether a reference somebody already authored is one the picker has to show
## as wrong.
##
## Its own question rather than `not knows(...)`: an empty reference is not
## wrong, it is unfilled, and a picker that coloured every blank field red
## would be shouting at somebody who has not started yet.
##
## Here rather than on the EditorProperty because Godot refuses to instantiate
## one outside the editor - so a rule living there is a rule nothing can check.
static func is_unknown(reference: GameplayAttributeRef) -> bool:
	if reference == null or not reference.is_valid():
		return false
	return not knows(reference)
