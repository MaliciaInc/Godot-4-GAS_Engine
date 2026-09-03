## The node vocabulary: which engine calls the Composer offers, and what they take.
##
## Split deliberately in two. **Which** methods are worth offering is a decision
## and is written here; **what they take** is a fact and is read from the engine
## with reflection. Retyping a signature beside the method it describes is how a
## catalog starts naming a parameter the API stopped having, and the node then
## prints an argument nobody accepts.
##
## The one hand-written half is held against the tree by a test: every method
## named here has to exist on the class it claims to be on. A curated name that
## has been renamed or removed fails there, not in front of someone.
##
## The categories live here rather than in the panel that draws them, so a view
## cannot quietly become a second opinion about what the Composer can express.
##
## A game may offer calls of its own through `register()`, and the vocabulary the
## engine ships is admitted through exactly the same door. Two doors would make
## one of them the real one and the other a courtesy, and a courtesy is what
## stops being tested.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCatalog extends RefCounted

const ABILITY: StringName = &"Ability"
const TASKS: StringName = &"Tasks"
const EFFECTS: StringName = &"Effects"
const TAGS: StringName = &"Tags"
const TARGETING: StringName = &"Targeting"
const EVENTS: StringName = &"Events"
const CUES: StringName = &"Cues"
const CONTEXT: StringName = &"Context"
const VALUES: StringName = &"Values"

## In the order a person reads them: what shapes a method first, then what it
## does, then what it reads.
##
## There was a `Flow` here, for Start, Branch, End and Sequence. No method can
## ever land in it: flow is statements, and a statement is not a call. It sat on
## the palette as a category that would stay empty for ever - which reads as a
## tool that has not finished rather than one that draws branches as branches.
const GROUPS: Array[StringName] = [
	ABILITY, TASKS, EFFECTS, TAGS, TARGETING, EVENTS, CUES, CONTEXT, VALUES,
]

## The classes whose public calls the Composer offers.
##
## Named as classes, not as file paths. A path written here is a path written
## twice - the file already says where it is - and the copy is what stops being
## true the day somebody moves a folder. The project is asked where each class
## lives, which is the same question Godot answers to load it.
const ABILITY_CLASS: StringName = &"GameplayAbility"
const ASC_CLASS: StringName = &"AbilitySystemComponent"
const TARGETING_CLASS: StringName = &"GameplayTargetingService"
const TASK_FACTORY_CLASS: StringName = &"AbilityTaskFactory"
const TARGET_DATA_CLASS: StringName = &"GameplayAbilityTargetData"

## Every script whose public calls the Composer offers.
##
## The whole hand-written half of the catalog, and it is a list of files rather
## than a list of methods. What each of them carries is read from the file: a
## method added to the engine is on the palette the next time the editor starts,
## and one that is renamed takes its node with it. A list of methods beside the
## methods is the thing that stops being true, and it stops being true silently.
const SOURCES: Array[StringName] = [
	ABILITY_CLASS, ASC_CLASS, TARGETING_CLASS, TASK_FACTORY_CLASS, TARGET_DATA_CLASS,
]

## What a method has to mention to belong to a category, in the order asked.
##
## A rule rather than a table. Assigning ninety-odd methods to categories by
## hand is ninety-odd chances to disagree with the next person who adds one, and
## the disagreement shows up as a node nobody can find. Order matters: an
## effect's tag is an effect before it is a tag.
const BY_NAME: Array[Array] = [
	["wait_", TASKS],
	["repeat", TASKS],
	["play_animation", TASKS],
	["cue", CUES],
	["effect", EFFECTS],
	["tag", TAGS],
	["target", TARGETING],
	["raycast", TARGETING],
	["overlap", TARGETING],
	["hit", TARGETING],
	["event", EVENTS],
	["attribute", VALUES],
	["cost", VALUES],
	["abilit", ABILITY],
	["cooldown", ABILITY],
	["input", ABILITY],
]

## The class an ability waits on. A call that hands one back is a call that
## suspends, which is a fact of the method rather than a decision about it - so
## it is read from the return type instead of being listed.
const TASK_CLASS: StringName = &"GameplayAbilityTask"

## What separates one script's call from another's with the same name.
const KEY_JOIN: String = "#"

## What a call being dragged out of the palette is carried under. Declared
## here because the palette writes it and the canvas reads it, and a payload
## key spelled twice is a drop that never matches and never says why.
const DRAGGED_CALL: StringName = &"gas_engine_call"

const NO_SCRIPT: String = "there is nothing at %s"
const NOT_A_SCRIPT: String = "%s is not a script"
const NOT_THERE: String = "%s() is not on %s"
const REFUSED: String = "GAS_Engine: the Composer refused a node - %s"

static var _cache: Dictionary[StringName, Entry] = {}
static var _built: bool = false
static var _revision: int = 0


## One offerable call: what it is, what it takes, where it belongs.
class Entry extends RefCounted:
	## Script and method together. The engine really does declare `execute_cue`
	## twice - once on the ability and once on the ability system - and a catalog
	## keyed by the method alone can hold only one of them, so one of the two is
	## a call the Composer could never draw. Which one was never a decision
	## anybody made; it was whichever was listed first.
	var key: StringName = &""

	var type_id: StringName = &""
	var group: StringName = &""
	var title: String = ""
	var awaits: bool = false

	## The script the signature was read from. Kept so a name claimed twice can
	## say who holds it: "already offered" without a source sends someone hunting
	## through their own project for a conflict they cannot see.
	var source: String = ""

	## Parameter names and types, read from the engine rather than restated.
	var parameters: Array[ComposerNode.Field] = []

	## How many of them a caller has to pass.
	##
	## The rest carry defaults, and a default is not a gap: a call that leaves
	## one out has said everything it needed to. Treating them the same would put
	## a warning on every correct statement in a file.
	var required: int = 0

	func parameter(position: int) -> ComposerNode.Field:
		if position < 0 or position >= parameters.size():
			return null
		return parameters[position]



#region What is offered
## Every offered call, built once and kept.
##
## Reflection is not free and the answer does not change on its own: the
## signatures come from scripts that would have to be reloaded to differ.
static func all() -> Dictionary[StringName, Entry]:
	if _built:
		return _cache
	# Raised before admitting, not after: `_admit` reaches back through here, and
	# a flag set late would send it around again.
	_built = true
	for declared: StringName in SOURCES:
		_admit_every_call_on(script_for(declared))
	return _cache


## Where the project says a class lives.
static func script_for(declared: StringName) -> String:
	return ComposerTypes.script_of(declared)


## Offer everything a script declares in public.
##
## Nothing is left out by opinion. A method the engine exposes is a statement
## somebody can write in an ability, and a palette that quietly omitted it would
## be answering a question - "is this worth drawing?" - that belongs to the
## person writing the ability, not to this file.
static func _admit_every_call_on(path: String) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_error(REFUSED % (NO_SCRIPT % path))
		return
	for described: Dictionary in script.get_script_method_list():
		var method: String = described["name"]
		# Leading marks are Godot's, not a person's: `_` is private and `@` is a
		# property setter wearing a method's shape.
		if method.begins_with("_") or method.begins_with("@"):
			continue
		var refused: String = _admit(method, group_of(method), path, _suspends(described))
		if not refused.is_empty():
			push_error(REFUSED % refused)


## Which category a call belongs to, worked out from its name.
static func group_of(method: String) -> StringName:
	for rule: Array in BY_NAME:
		var mark: String = rule[0]
		var group: StringName = rule[1]
		if method.contains(mark):
			return group
	return CONTEXT


## Whether a call hands back something an ability waits on.
static func _suspends(described: Dictionary) -> bool:
	var returned: Dictionary = described["return"]
	var declared: String = returned["class_name"]
	return ComposerTypes.inherits(StringName(declared), TASK_CLASS)


static func find(key: StringName) -> Entry:
	return all().get(key)


## The key a call is filed under.
static func key_for(source: String, method: StringName) -> StringName:
	return StringName("%s%s%s" % [source, KEY_JOIN, method])


## The call `method` on `source`, or null when that script does not offer one.
static func find_on(source: String, method: StringName) -> Entry:
	return find(key_for(source, method))


## Every script that offers a call by this name.
##
## More than one is not a mistake: `execute_cue` is on the ability and on the
## ability system, and they take different arguments. A caller with no receiver
## to go on can only use this when the answer is unambiguous.
static func sources_offering(method: StringName) -> Array[String]:
	var found: Array[String] = []
	for entry: Entry in all().values():
		if entry.type_id == method:
			found.append(entry.source)
	return found


## The categories to draw, the engine's own first and in their written order.
##
## Worked out from what is offered rather than kept in a list beside it. A second
## list would have to be told when a node is withdrawn, and the day it is not
## told the palette shows a category holding nothing.
static func groups() -> Array[StringName]:
	var found: Array[StringName] = GROUPS.duplicate()
	for entry: Entry in all().values():
		if not found.has(entry.group):
			found.append(entry.group)
	return found


static func entries(group: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for entry: Entry in all().values():
		if entry.group == group:
			found.append(entry.key)
	return found


## Changes whenever the vocabulary does, so a panel already on screen can tell
## whether what it drew is still what is offered.
static func revision() -> int:
	all()
	return _revision
#endregion


#region Which call a statement is
## The catalog entry a statement is, when the catalog can be sure it is that one.
##
## A bare call inside the body is a method on the ability itself, so the name is
## enough. A call on something else has to prove it: the receiver is resolved to
## the script it actually is, and an entry only matches when that is the very
## script its signature was read from.
static func entry_for(
	method: StringName, receiver: String, path: String,
	locals: Dictionary[String, StringName]
) -> Entry:
	if method.is_empty():
		return null
	if not receiver.is_empty():
		return find_on(_behind(receiver, path, locals), method)
	return _on_the_file_itself(method, path)


## Which script a receiver is.
##
## A local first: its written type is right there in the body, and a receiver is
## a local more often than it is anything else.
static func _behind(
	receiver: String, path: String, locals: Dictionary[String, StringName]
) -> String:
	var written: StringName = locals.get(receiver, &"")
	if not written.is_empty():
		return ComposerTypes.script_of(written)
	return ComposerTypes.script_behind(receiver, path)


## A call written with no receiver is a call on the file itself.
##
## Walked over the file's own base scripts, so `commit_ability()` in an ability
## finds the ability's method and not something with the same name elsewhere.
## When the file cannot be read - a body being tested on its own, a path that is
## not on disk - the answer is the one script that offers the name, and nothing
## at all when more than one does. Guessing between two would be the tool
## deciding which of a person's calls they meant.
static func _on_the_file_itself(method: StringName, path: String) -> Entry:
	if ResourceLoader.exists(path):
		var walked: GDScript = load(path) as GDScript
		while walked != null:
			var found: Entry = find_on(
				walked.resource_path, method
			)
			if found != null:
				return found
			walked = walked.get_base_script()
		return null

	var offering: Array[String] = sources_offering(method)
	return find_on(offering[0], method) if offering.size() == 1 else null
#endregion


#region A game's own calls
## Offer one more call, from a game or from an integration pack.
##
## This adds knowledge, never permission. A call nobody registered is drawn
## already - the reader shows it with its arguments numbered - because a graph
## that hid the lines it had no entry for would be a partial view of the file,
## which is the one thing it must never be. Registering names the arguments,
## types them, and lets the validator say when one is missing.
##
## There is no template to write and no pattern to teach. Every node prints as
## its own call and reads back the same way, the engine's and a game's alike, so
## a signature this can read is the whole of what a node is.
##
## Returns the reason it was refused, or an empty string. The reason is pushed as
## an error as well: a pack that ignores the return would otherwise vanish from
## the palette without ever saying why.
static func register(method: String, group: StringName, path: String, suspends: bool) -> String:
	# The engine's own vocabulary first, so a game cannot take a name before the
	# call it would have collided with has been offered at all.
	all()
	var refused: String = _admit(method, group, path, suspends)
	if not refused.is_empty():
		push_error(REFUSED % refused)
	return refused


## Take a call back out.
##
## An integration pack whose addon is switched off while the editor is running
## has to withdraw, or the palette keeps offering a call into a class that is no
## longer there and the file it writes will not compile.
static func forget(key: StringName) -> void:
	if not all().has(key):
		return
	_cache.erase(key)
	_revision += 1


## Let a call in, or say why not.
##
## The single admission. What the engine offers itself comes through here on the
## same terms a game does.
static func _admit(method: String, group: StringName, path: String, suspends: bool) -> String:
	var key: StringName = key_for(path, StringName(method))
	# The same call offered twice is not a conflict, and neither is one name on
	# two scripts - the engine itself declares `execute_cue` on the ability and
	# on the ability system, and the receiver tells them apart. Only the very
	# same call from the very same script is a repeat, and a pack registering
	# again after an editor reload should not be punished for being careful.
	if _cache.has(key):
		return ""

	# Asked before it is loaded, because the resource loader answers a missing
	# path with an error of its own, and a person then reads two complaints about
	# one typo - the second of which they cannot act on.
	if not ResourceLoader.exists(path):
		return NO_SCRIPT % path
	var script: GDScript = load(path) as GDScript
	if script == null:
		return NOT_A_SCRIPT % path

	var entry: Entry = _entry(method, group, script, suspends)
	if entry == null:
		return NOT_THERE % [method, path.get_file()]

	entry.source = path
	entry.key = key
	_cache[key] = entry
	_revision += 1
	return ""
#endregion


#region Reading the signature
## Build one entry by asking the script what the method takes.
##
## Returns null when the method is not there. That is not silently tolerated - a
## test walks the whole curated list and fails on any gap, and a registration
## says so out loud - but it keeps a stale name from crashing an editor that is
## only trying to draw a palette.
static func _entry(
	method: String, group: StringName, script: GDScript, suspends: bool
) -> Entry:
	for described: Dictionary in script.get_script_method_list():
		var name: String = described["name"]
		if name != method:
			continue
		var entry: Entry = Entry.new()
		entry.type_id = StringName(method)
		entry.group = group
		entry.title = method.capitalize()
		entry.awaits = suspends
		entry.parameters.assign(_parameters(described))
		# Defaults fill the last parameters, so the required ones are whatever is
		# left at the front. Read off the method rather than decided here.
		var defaults: Array = described["default_args"]
		entry.required = maxi(entry.parameters.size() - defaults.size(), 0)
		return entry
	return null


static func _parameters(described: Dictionary) -> Array[ComposerNode.Field]:
	var found: Array[ComposerNode.Field] = []
	var declared: Array = described["args"]
	for argument: Dictionary in declared:
		var field: ComposerNode.Field = ComposerNode.Field.new()
		var called: String = argument["name"]
		field.label = called.capitalize()
		field.type_name = StringName(_type_of(argument))
		found.append(field)
	return found


## The written type where there is one, the built-in name otherwise.
static func _type_of(argument: Dictionary) -> String:
	var declared: String = argument["class_name"]
	if not declared.is_empty():
		return declared
	var code: int = argument["type"]
	return type_string(code)
#endregion
