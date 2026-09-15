## The names two machines agree about before either of them sends one.
##
## A tag on a wire is text: `Status.Debuff.Slowed` is twenty bytes every time a
## reading mentions it, and a reading mentions the same few names every time it
## is sent. The reference never sends a tag's text when both sides can index it -
## both load one sorted table of every tag the project declares, and a tag
## crosses as its position in it. This is that table.
##
## Built from the project's own tag file, which two builds of one project share,
## plus whatever names a game adds on both sides - its attribute names, say.
## Sorted by text, never by insertion, so the order is a property of the names
## rather than of the order somebody added them in.
##
## Two tables that differ are two machines that disagree about what every index
## means, and the failure mode is every tag arriving as a different tag. So the
## table has a fingerprint, a packet written against one says which, and a
## packet written against a different one is refused as a protocol mismatch
## rather than read.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetNames extends RefCounted

## What separates two names inside the text the fingerprint is taken over. A
## name never holds one, so two different tables can never spell the same text.
const SEPARATOR: String = "\n"

## The project's tags, read once for every runtime this process builds.
static var _project: Array[StringName] = []
static var _project_read: bool = false

## Every name, sorted by text.
var _names: Array[StringName] = []

## Where each name sits in `_names`.
var _positions: Dictionary[StringName, int] = {}

## A 32-bit fingerprint of the whole table.
var fingerprint: int = 0


## A table holding every tag this project declares.
static func from_project() -> GameplayNetNames:
	if not _project_read:
		_project.assign(GameplayTagGenerator.tags_in_file())
		_project_read = true
	var made: GameplayNetNames = GameplayNetNames.new()
	made.add(_project)
	return made


## Read the project's tags again the next time a table is built from them.
static func forget_project() -> void:
	_project.clear()
	_project_read = false


## A table holding exactly these names, for a game or a test that builds its own.
static func of(listed: Array[StringName]) -> GameplayNetNames:
	var made: GameplayNetNames = GameplayNetNames.new()
	made.add(listed)
	return made


## Add names to the table. Both machines have to add the same ones: the
## fingerprint is what tells them when they did not.
func add(more: Array[StringName]) -> void:
	for name: StringName in more:
		if name == &"" or _positions.has(name):
			continue
		_positions[name] = -1
		_names.append(name)
	_names.sort_custom(_by_text)
	var text: PackedStringArray = PackedStringArray()
	for position: int in _names.size():
		_positions[_names[position]] = position
		text.append(String(_names[position]))
	fingerprint = SEPARATOR.join(text).hash()


func size() -> int:
	return _names.size()


## Where a name sits, or -1 when this table does not hold it.
func index_of(name: StringName) -> int:
	var found: Variant = _positions.get(name, -1)
	var position: int = found
	return position


func name_at(position: int) -> StringName:
	return _names[position]


## Compared by text rather than as StringNames, whose order is the order Godot
## happened to intern them in - which is a fact about one process, and the one
## thing this table exists not to depend on.
static func _by_text(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
