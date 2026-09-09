## An aim turned into identities and numbers, and back again.
##
## What was hit crosses as the identity of the entity it belongs to; where it
## was hit crosses as the position and normal themselves, which are numbers
## every machine agrees about. A collider no registry knows is left out rather
## than sent as its address: an ObjectID is a slot in one process's table, and a
## receiver resolving one would get whatever happens to be in that slot.
##
## A codec rather than two methods on GameplayAbilityTargetData, for a reason
## specific to this engine rather than taste. That payload sits inside the
## GameplayCueManager autoload's parse-time closure, and every type a file in
## that closure names has to arrive by preload rather than by global name -
## so a `registry: GameplayNetRegistry` parameter there would pull the whole
## network registry, and the ability system component behind it, into a closure
## Godot parses before any of it can resolve. The functions have the shapes the
## phase document names; they live where naming a registry is allowed.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetDataTranslator extends RefCounted

const HITS_KEY: String = "aim.hits"
const SPACE_KEY: String = "hit.space"
const ENTITY_KEY: String = "hit.entity"
const HAS_POSITION_KEY: String = "hit.has_position"
const POSITION_2D_KEY: String = "hit.position_2d"
const NORMAL_2D_KEY: String = "hit.normal_2d"
const POSITION_3D_KEY: String = "hit.position_3d"
const NORMAL_3D_KEY: String = "hit.normal_3d"


## An aim as primitives. Nothing here is an object.
static func to_wire(
	data: GameplayAbilityTargetData, registry: GameplayNetRegistry = null
) -> Dictionary:
	var hits: Array = []
	if data != null:
		for hit: GameplayTargetHit in data.get_all_hits():
			hits.append(_hit_to_wire(hit, registry))
	return {HITS_KEY: hits}


## The aim back, resolved against this machine's registry.
##
## A hit whose entity this machine has never registered comes back as a place:
## it still knows where it happened, which is more than nothing and is honest
## about the part it cannot resolve. A hit that was a place to begin with comes
## back the same way.
static func from_wire(
	wire: Dictionary, registry: GameplayNetRegistry = null
) -> GameplayAbilityTargetData:
	if not wire.has(HITS_KEY) or typeof(wire[HITS_KEY]) != TYPE_ARRAY:
		return null

	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for entry: Variant in (wire[HITS_KEY] as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		if not _hit_from_wire(entry as Dictionary, data, registry):
			return null
	return data


static func _hit_to_wire(hit: GameplayTargetHit, registry: GameplayNetRegistry) -> Dictionary:
	var two_d: bool = hit.space_kind == GameplayTargetHit.SpaceKind.TWO_D
	return {
		SPACE_KEY: int(hit.space_kind),
		ENTITY_KEY: GameplayWireReader.entity_said(
			GameplayNetNaming.entity_of(hit.collider, registry)
		),
		HAS_POSITION_KEY: hit.has_position,
		POSITION_2D_KEY: hit.position_2d if two_d else Vector2.ZERO,
		NORMAL_2D_KEY: hit.normal_2d if two_d else Vector2.ZERO,
		POSITION_3D_KEY: hit.position_3d,
		NORMAL_3D_KEY: hit.normal_3d,
	}


## Read one hit back onto `data`, or answer false when the wire disagrees about
## the contract.
static func _hit_from_wire(
	entry: Dictionary, data: GameplayAbilityTargetData, registry: GameplayNetRegistry
) -> bool:
	if not GameplayWireReader.has_shape(entry, _expected()):
		return false

	var two_d: bool = int(entry[SPACE_KEY]) == int(GameplayTargetHit.SpaceKind.TWO_D)
	var node: Node = GameplayNetNaming.avatar_of(
		GameplayWireReader.entity_from(entry[ENTITY_KEY]), registry
	)
	if node != null:
		return data.append_node(node)

	if not bool(entry[HAS_POSITION_KEY]):
		# Neither an entity this machine knows nor a place: nothing to record,
		# and nothing wrong with that - a hit on somebody who is not here is
		# still a hit that happened somewhere else.
		return true
	if two_d:
		return data.append_location(entry[POSITION_2D_KEY], entry[NORMAL_2D_KEY])
	return data.append_location(entry[POSITION_3D_KEY], entry[NORMAL_3D_KEY])


## The type this contract declares for each key.
static func _expected() -> Dictionary[String, int]:
	return {
		SPACE_KEY: TYPE_INT,
		ENTITY_KEY: TYPE_INT,
		HAS_POSITION_KEY: TYPE_BOOL,
		POSITION_2D_KEY: TYPE_VECTOR2,
		NORMAL_2D_KEY: TYPE_VECTOR2,
		POSITION_3D_KEY: TYPE_VECTOR3,
		NORMAL_3D_KEY: TYPE_VECTOR3,
	}
