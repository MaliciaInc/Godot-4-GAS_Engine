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
## @meta_license: MIT
class_name ComposerCatalog extends RefCounted

const FLOW: StringName = &"Flow"
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
const GROUPS: Array[StringName] = [
	FLOW, ABILITY, TASKS, EFFECTS, TAGS, TARGETING, EVENTS, CUES, CONTEXT, VALUES,
]

const ABILITY_SCRIPT: String = "res://addons/GAS_Engine/abilities/gameplay_ability.gd"
const ASC_SCRIPT: String = "res://addons/GAS_Engine/components/ability_system_component.gd"
const TARGETING_SCRIPT: String = "res://addons/GAS_Engine/targeting/gameplay_targeting_service.gd"

## Curated: the calls worth a node, and where each belongs.
##
## Not every public method is a node. The facade carries fifty-odd, and offering
## all of them would hand someone a palette they have to read rather than one
## they can scan. What is here is what an ability body actually does.
##
## `[method, group, source script]`.
const OFFERED: Array[Array] = [
	["commit_ability", ABILITY, ABILITY_SCRIPT],
	["abort_ability", ABILITY, ABILITY_SCRIPT],
	["end_ability", ABILITY, ABILITY_SCRIPT],
	["get_ability_level", ABILITY, ABILITY_SCRIPT],
	["get_cooldown_state", ABILITY, ABILITY_SCRIPT],

	["wait_delay", TASKS, ABILITY_SCRIPT],
	["wait_target_data", TASKS, ABILITY_SCRIPT],
	["wait_gameplay_event", TASKS, ABILITY_SCRIPT],
	["wait_input_pressed", TASKS, ABILITY_SCRIPT],
	["wait_input_released", TASKS, ABILITY_SCRIPT],

	["apply_effect_to_targets", EFFECTS, ABILITY_SCRIPT],
	["apply_gameplay_effect", EFFECTS, ASC_SCRIPT],
	["remove_effects_with_tag", EFFECTS, ASC_SCRIPT],
	["count_active_effects", EFFECTS, ASC_SCRIPT],

	["add_tag", TAGS, ASC_SCRIPT],
	["remove_tag", TAGS, ASC_SCRIPT],
	["has_tag", TAGS, ASC_SCRIPT],
	["has_tag_exact", TAGS, ASC_SCRIPT],

	["raycast_2d", TARGETING, TARGETING_SCRIPT],
	["raycast_3d", TARGETING, TARGETING_SCRIPT],
	["overlap_2d", TARGETING, TARGETING_SCRIPT],
	["overlap_3d", TARGETING, TARGETING_SCRIPT],

	["send_gameplay_event", EVENTS, ASC_SCRIPT],

	["execute_cue", CUES, ABILITY_SCRIPT],
	["activate_persistent_cue", CUES, ASC_SCRIPT],
	["deactivate_persistent_cue", CUES, ASC_SCRIPT],

	["get_ability_handle", CONTEXT, ABILITY_SCRIPT],
	["find_asc_on", CONTEXT, ABILITY_SCRIPT],

	["get_attribute_base", VALUES, ASC_SCRIPT],
	["get_attribute_current", VALUES, ASC_SCRIPT],
	["has_attribute", VALUES, ASC_SCRIPT],
]

## Statements that suspend the ability. The card says the word, and the writer
## prints the keyword; both read this rather than guessing from the name.
##
## A decision, not a fact - reflection cannot tell whether a method suspends - so
## a game offering a call of its own answers the same question for itself.
##
## Held against the engine all the same: every call here returns a task, because
## a task is the thing an ability waits on. `apply_effect_to_targets` was on this
## list and returns a result, not a task, and never suspends anything - the card
## said `await` over a call that does not, and a node placed from the palette
## would have printed one.
const SUSPENDS: Array[StringName] = [
	&"wait_delay", &"wait_target_data", &"wait_gameplay_event",
	&"wait_input_pressed", &"wait_input_released",
]

const NO_SCRIPT: String = "there is nothing at %s"
const NOT_A_SCRIPT: String = "%s is not a script"
const NOT_THERE: String = "%s() is not on %s"
const TAKEN: String = "%s is already offered from %s"
const REFUSED: String = "GAS_Engine: the Composer refused a node - %s"

static var _cache: Dictionary[StringName, Entry] = {}
static var _built: bool = false
static var _revision: int = 0


## One offerable call: what it is, what it takes, where it belongs.
class Entry extends RefCounted:
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
	for row: Array in OFFERED:
		var method: String = row[0]
		var group: StringName = row[1]
		var path: String = row[2]
		var refused: String = _admit(method, group, path, SUSPENDS.has(StringName(method)))
		if not refused.is_empty():
			push_error(REFUSED % refused)
	return _cache


static func find(type_id: StringName) -> Entry:
	return all().get(type_id)


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
			found.append(entry.type_id)
	return found


## Changes whenever the vocabulary does, so a panel already on screen can tell
## whether what it drew is still what is offered.
static func revision() -> int:
	all()
	return _revision
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
static func forget(type_id: StringName) -> void:
	if not all().has(type_id):
		return
	_cache.erase(type_id)
	_revision += 1


## Let a call in, or say why not.
##
## The single admission. What the engine offers itself comes through here on the
## same terms a game does.
static func _admit(method: String, group: StringName, path: String, suspends: bool) -> String:
	var type_id: StringName = StringName(method)
	var taken: Entry = _cache.get(type_id)
	if taken != null:
		# The same call offered twice is not a conflict. A pack that registers
		# again after an editor reload should not be punished for being careful.
		if taken.source == path:
			return ""
		# Two packs claiming one name is a conflict only a person can settle.
		# Letting the last one win would make the palette depend on load order.
		return TAKEN % [method, taken.source]

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
	_cache[type_id] = entry
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
		field.label = String(argument["name"]).capitalize()
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
