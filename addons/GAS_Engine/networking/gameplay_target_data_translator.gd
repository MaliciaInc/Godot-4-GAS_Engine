## An aim turned into identities and numbers, and back again.
##
## What was hit crosses as the identity of the entity it belongs to; where it
## was hit crosses as the numbers a position and a normal are made of - two
## of them or three, never a Vector2 or a Vector3. This addon's wire is JSON
## and JSON has no vectors: one written to it arrives as the text `(3, 0, 0)`
## and is read back as a String, which is an aim that never arrived. A collider no registry knows is left out rather
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
	var listed: Array = wire[HITS_KEY]
	for entry: Variant in listed:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		var hit: Dictionary = entry
		if not _hit_from_wire(hit, data, registry):
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
		POSITION_2D_KEY: GameplayWireReader.numbers_of_2d(
			hit.position_2d if two_d else Vector2.ZERO
		),
		NORMAL_2D_KEY: GameplayWireReader.numbers_of_2d(
			hit.normal_2d if two_d else Vector2.ZERO
		),
		POSITION_3D_KEY: GameplayWireReader.numbers_of_3d(hit.position_3d),
		NORMAL_3D_KEY: GameplayWireReader.numbers_of_3d(hit.normal_3d),
	}


## Read one hit back onto `data`, or answer false when the wire disagrees about
## the contract.
static func _hit_from_wire(
	entry: Dictionary, data: GameplayAbilityTargetData, registry: GameplayNetRegistry
) -> bool:
	if not GameplayWireReader.has_shape(entry, _expected()):
		return false

	var two_d: bool = (
		GameplayWireReader.number_from(entry[SPACE_KEY])
		== int(GameplayTargetHit.SpaceKind.TWO_D)
	)
	var node: Node = GameplayNetNaming.avatar_of(
		GameplayWireReader.entity_from(entry[ENTITY_KEY]), registry
	)
	if node != null:
		return data.append_node(node)

	var placed: bool = entry[HAS_POSITION_KEY]
	if not placed:
		# Neither an entity this machine knows nor a place: nothing to record,
		# and nothing wrong with that - a hit on somebody who is not here is
		# still a hit that happened somewhere else.
		return true
	if two_d:
		var flat: PackedFloat64Array = GameplayWireReader.numbers_from(
			entry[POSITION_2D_KEY], 2
		)
		var facing: PackedFloat64Array = GameplayWireReader.numbers_from(
			entry[NORMAL_2D_KEY], 2
		)
		if flat.is_empty() or facing.is_empty():
			return false
		return data.append_location(
			Vector2(flat[0], flat[1]), Vector2(facing[0], facing[1])
		)

	var spot: PackedFloat64Array = GameplayWireReader.numbers_from(
		entry[POSITION_3D_KEY], 3
	)
	var up: PackedFloat64Array = GameplayWireReader.numbers_from(
		entry[NORMAL_3D_KEY], 3
	)
	if spot.is_empty() or up.is_empty():
		return false
	return data.append_location(
		Vector3(spot[0], spot[1], spot[2]), Vector3(up[0], up[1], up[2])
	)


## The type this contract declares for each key.
static func _expected() -> Dictionary[String, int]:
	return {
		SPACE_KEY: TYPE_INT,
		ENTITY_KEY: TYPE_INT,
		HAS_POSITION_KEY: TYPE_BOOL,
		POSITION_2D_KEY: TYPE_ARRAY,
		NORMAL_2D_KEY: TYPE_ARRAY,
		POSITION_3D_KEY: TYPE_ARRAY,
		NORMAL_3D_KEY: TYPE_ARRAY,
	}
