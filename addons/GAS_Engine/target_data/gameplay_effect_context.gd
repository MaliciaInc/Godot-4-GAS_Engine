## Where an effect came from and who it hit.
##
## Wraps instigator, causer and target data into one object that travels through
## the execution pipeline, so no stage has to reassemble it from loose arguments.
##
## Types come from `preload` rather than global class names: this file is
## reachable from the GameplayCueManager autoload, which Godot parses before a
## global class cache exists on a checkout that was never imported.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayEffectContext extends RefCounted

## This script's own type, preloaded rather than named.
##
## This file is in the GameplayCueManager autoload's parse-time closure, and
## Godot parses autoloads before it has scanned the project for class_name
## declarations. A global name - even this file's own - does not resolve
## there, so the reference is a preload and the type is its alias.
const Context = preload("res://addons/GAS_Engine/target_data/gameplay_effect_context.gd")


const TargetData = preload("res://addons/GAS_Engine/target_data/gameplay_ability_target_data.gd")
const Payload = preload("res://addons/GAS_Engine/target_data/gameplay_effect_context_payload.gd")
const AbilityHandle = preload("res://addons/GAS_Engine/abilities/gameplay_ability_handle.gd")

## The three actors a context names, kept behind their reading.
##
## A context is a RefCounted and the things it points at are Nodes, so it
## routinely outlives them: an effect keeps ticking on its target long after
## the caster was freed, and what is kept here becomes a dangling reference.
## Every consumer copies these onto another typed `Node` - cue params, event
## data, a query subject - and Godot refuses to assign a freed object to a
## typed property, so the copy failed at the assignment and the cue went out
## with whatever that field already held. Reading through a validity check
## makes "the caster is gone" an answer rather than a runtime error, and does
## it once, here, rather than at each of the places that read it.
var _instigator: Node = null
var _causer: Node = null
var _source_object: Node = null

## The entity that activated the ability, e.g. the player character.
var instigator: Node = null:
	set(value):
		_instigator = value
	get:
		return _instigator if is_instance_valid(_instigator) else null

## The entity that physically caused the effect, e.g. a fireball projectile.
## Defaults to the instigator when there is no secondary actor.
var causer: Node = null:
	set(value):
		_causer = value
	get:
		return _causer if is_instance_valid(_causer) else null

## Who, what and where the ability hit.
var target_data: TargetData = null

## The ability that produced this application, when one did - null for an
## effect applied outside any ability (a scripted DoT tick, a scenario
## trigger). Opaque, the same as everywhere else a handle travels: never the
## live GameplayAbility instance.
var ability_handle: AbilityHandle = null

## The physical item/object behind this application when one exists - a
## weapon, a thrown item - distinct from `causer` (which may be a spawned
## projectile with no inventory identity of its own). Read through the same
## validity check as the two above, and for the same reason: a thrown item is
## freed on impact while the effect it applied is still running.
var source_object: Node = null:
	set(value):
		_source_object = value
	get:
		return _source_object if is_instance_valid(_source_object) else null

## Game-defined metadata, typed and opaque to this addon. See
## GameplayEffectContextPayload.
var payloads: Array[Payload] = []


#region Initialization
func _init(in_instigator: Node = null, in_causer: Node = null) -> void:
	instigator = in_instigator
	causer = in_causer if in_causer != null else in_instigator
	target_data = TargetData.new()
#endregion


#region Application copy
## A context for one more target.
##
## The logical origin - who cast this, and with what - is preserved:
## instigator, causer, ability handle and source object all carry over
## unchanged, since they name the same real thing for every target. The
## target payload does NOT: each application resolves its own targets, and
## sharing the payload is how an AoE ends up applying target A's hits to
## target B. Payloads are deep-copied one by one - if any of them cannot be
## copied, this returns null rather than handing out a context missing part
## of what the original carried.
func create_application_copy() -> GameplayEffectContext:
	var copy: GameplayEffectContext = Context.new(instigator, causer)
	copy.ability_handle = ability_handle
	copy.source_object = source_object
	for payload: Payload in payloads:
		var payload_copy: Payload = payload.create_application_copy() if payload != null else null
		if payload_copy == null:
			return null
		copy.payloads.append(payload_copy)
	return copy


## This context, aimed at one target.
##
## `create_application_copy()` leaves target data empty on purpose: an
## application is one victim's, and the aim it came from was several victims'.
## This is how the one that belongs to this victim gets attached - the origin
## and the payloads carried over, and target data that is theirs alone.
##
## Never the object it was handed. Target data is mutable, and two applications
## holding one is either of them changing what the other sees.
func derive_for_target(data: TargetData) -> GameplayEffectContext:
	var copy: GameplayEffectContext = derive_child_context(self)
	if data == null:
		return copy
	copy.target_data = data.copied()
	return copy


## A context for a system-generated child application - an Additional
## Effects reaction, an overflow effect. A full application copy of
## `parent` when one exists and copies cleanly; a bare instigator/causer
## context otherwise. Never returns null: unlike create_application_copy(),
## refusing a whole reaction chain over one payload's copy bug is worse than
## the child losing that one payload. Shared by GameplayEffectChainRuntime
## and GameplayEffectStackingRuntime rather than each reimplementing the
## same fallback.
static func derive_child_context(parent: GameplayEffectContext) -> GameplayEffectContext:
	if parent == null:
		return Context.new()
	var copy: GameplayEffectContext = parent.create_application_copy()
	if copy != null:
		return copy
	return Context.new(parent.instigator, parent.causer)
#endregion


#region Payload Helpers
func has_targets() -> bool:
	return target_data != null and target_data.has_targets()


func get_target_nodes() -> Array[Node]:
	if target_data == null:
		return []
	return target_data.get_target_nodes()


## Attach one more payload. False only for null - nothing else about a
## payload disqualifies it; several payloads of the same script may coexist
## when a game's own design calls for it.
func add_payload(payload: Payload) -> bool:
	if payload == null:
		return false
	payloads.append(payload)
	return true


## The first attached payload built from `payload_script`, or null. Matched
## by script identity - a GDScript reflection boundary, not a design choice,
## and still a typed lookup rather than a string key or a Dictionary.
func find_payload(payload_script: Script) -> Payload:
	for payload: Payload in payloads:
		if payload != null and payload.get_script() == payload_script:
			return payload
	return null


func has_payload_script(payload_script: Script) -> bool:
	return find_payload(payload_script) != null
#endregion
