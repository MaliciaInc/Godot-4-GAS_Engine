## An aim turned into identities and places, and back again.
##
## What was hit crosses as the identity of the entity it belongs to; where it
## was hit crosses as a place, quantized on the wire by GameplayNetQuantize. A
## collider no registry knows is left out rather than sent as its address: an
## ObjectID is a slot in one process's table, and a receiver resolving one would
## get whatever happens to be in that slot.
##
## A translator rather than two methods on GameplayAbilityTargetData, for a reason
## specific to this engine rather than taste. That payload sits inside the
## GameplayCueManager autoload's parse-time closure, and every type a file in
## that closure names has to arrive by preload rather than by global name - so a
## `registry: GameplayNetRegistry` parameter there would pull the whole network
## registry, and the ability system component behind it, into a closure Godot
## parses before any of it can resolve.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetDataTranslator extends RefCounted


## An aim as identities and places. Nothing here is an object.
static func to_aim(
	data: GameplayAbilityTargetData, registry: GameplayNetRegistry = null
) -> GameplayNetAim:
	var aim: GameplayNetAim = GameplayNetAim.new()
	if data == null:
		return aim
	for hit: GameplayTargetHit in data.get_all_hits():
		aim.hits.append(_hit_to_aim(hit, registry))
	return aim


## The aim back, resolved against this machine's registry, or null when a hit
## cannot be recorded.
##
## A hit whose entity this machine has never registered comes back as a place:
## it still knows where it happened, which is more than nothing and is honest
## about the part it cannot resolve. A hit that was a place to begin with comes
## back the same way.
static func from_aim(
	aim: GameplayNetAim, registry: GameplayNetRegistry = null
) -> GameplayAbilityTargetData:
	if aim == null:
		return null
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for hit: GameplayNetAim.Hit in aim.hits:
		if not _hit_from_aim(hit, data, registry):
			return null
	return data


static func _hit_to_aim(hit: GameplayTargetHit, registry: GameplayNetRegistry) -> GameplayNetAim.Hit:
	var made: GameplayNetAim.Hit = GameplayNetAim.Hit.new()
	made.space_kind = hit.space_kind
	var named: GameplayNetEntityId = GameplayNetNaming.entity_of(hit.collider, registry)
	made.entity = named.value if named != null else GameplayNetEntityId.NONE
	made.has_position = hit.has_position
	made.position_2d = hit.position_2d
	made.normal_2d = hit.normal_2d
	made.position_3d = hit.position_3d
	made.normal_3d = hit.normal_3d
	return made


## Record one hit onto `data`, or answer false when it will not take it.
static func _hit_from_aim(
	hit: GameplayNetAim.Hit, data: GameplayAbilityTargetData, registry: GameplayNetRegistry
) -> bool:
	if hit.names_somebody():
		var node: Node = GameplayNetNaming.avatar_of(GameplayNetEntityId.of(hit.entity), registry)
		if node != null:
			return data.append_node(node)
	if not hit.has_position:
		# Neither an entity this machine knows nor a place: nothing to record,
		# and nothing wrong with that - a hit on somebody who is not here is
		# still a hit that happened somewhere else.
		return true
	if hit.is_two_d():
		return data.append_location(hit.position_2d, hit.normal_2d)
	return data.append_location(hit.position_3d, hit.normal_3d)
