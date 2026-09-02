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
const SUSPENDS: Array[StringName] = [
	&"wait_delay", &"wait_target_data", &"wait_gameplay_event",
	&"wait_input_pressed", &"wait_input_released", &"apply_effect_to_targets",
]

static var _cache: Dictionary[StringName, Entry] = {}


## One offerable call: what it is, what it takes, where it belongs.
class Entry extends RefCounted:
	var type_id: StringName = &""
	var group: StringName = &""
	var title: String = ""
	var awaits: bool = false

	## Parameter names and types, read from the engine rather than restated.
	var parameters: Array[ComposerNode.Field] = []

	func parameter(position: int) -> ComposerNode.Field:
		if position < 0 or position >= parameters.size():
			return null
		return parameters[position]


#region Reading the engine
## Every offered call, built once and kept.
##
## Reflection is not free and the answer cannot change while the editor runs:
## the signatures come from scripts that would have to be reloaded to differ.
static func all() -> Dictionary[StringName, Entry]:
	if not _cache.is_empty():
		return _cache
	for row: Array in OFFERED:
		var entry: Entry = _entry(row[0], row[1], row[2])
		if entry != null:
			_cache[entry.type_id] = entry
	return _cache


static func find(type_id: StringName) -> Entry:
	return all().get(type_id)


static func entries(group: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for row: Array in OFFERED:
		if row[1] == group:
			found.append(StringName(row[0]))
	return found


## Build one entry by asking the script what the method takes.
##
## Returns null when the method is not there. That is not silently tolerated -
## a test walks the whole curated list and fails on any gap - but it keeps a
## stale name from crashing an editor that is only trying to draw a palette.
static func _entry(method: String, group: StringName, path: String) -> Entry:
	var script: GDScript = load(path) as GDScript
	if script == null:
		return null

	for described: Dictionary in script.get_script_method_list():
		var name: String = described["name"]
		if name != method:
			continue
		var entry: Entry = Entry.new()
		entry.type_id = StringName(method)
		entry.group = group
		entry.title = method.capitalize()
		entry.awaits = SUSPENDS.has(entry.type_id)
		entry.parameters.assign(_parameters(described))
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
