## An aim in the only shape a wire can carry: identities and places.
##
## What was hit crosses as the identity of the entity it belongs to, and where
## it was hit crosses as a place. A collider no registry knows is left out
## rather than sent as its address: an ObjectID is a slot in one process's table,
## and a receiver resolving one would get whatever happens to be in that slot.
##
## A shape rather than two methods on GameplayAbilityTargetData, for a reason
## specific to this engine. That payload sits inside the GameplayCueManager
## autoload's parse-time closure, and every type a file there names has to
## arrive by preload rather than by global name - a registry parameter on it
## would pull the whole network registry into a closure Godot parses before any
## of it can resolve. GameplayTargetDataTranslator turns one into the other.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetAim extends RefCounted

## The most hits one aim carries - the reference's own ceiling for the actors a
## piece of target data names.
const MOST_HITS: int = 31


## One hit, as another machine can be told about it.
class Hit extends RefCounted:
	## The entity that was hit, or NONE when the hit is a place.
	var entity: int = GameplayNetEntityId.NONE

	var space_kind: GameplayTargetHit.SpaceKind = GameplayTargetHit.SpaceKind.THREE_D

	## Whether this hit knows where it happened. A hit at the origin and a hit
	## with no position are different things, and only this can tell them apart.
	var has_position: bool = false

	var position_2d: Vector2 = Vector2.ZERO
	var normal_2d: Vector2 = Vector2.ZERO
	var position_3d: Vector3 = Vector3.ZERO
	var normal_3d: Vector3 = Vector3.ZERO

	func is_two_d() -> bool:
		return space_kind == GameplayTargetHit.SpaceKind.TWO_D

	func names_somebody() -> bool:
		return entity != GameplayNetEntityId.NONE


var hits: Array[GameplayNetAim.Hit] = []


## Whether any hit names an entity - which a receiver that resolved none of them
## needs to know, because a hit on somebody it has never registered comes back
## as a place and the fact that somebody was named is only here.
func names_somebody() -> bool:
	for hit: GameplayNetAim.Hit in hits:
		if hit.names_somebody():
			return true
	return false
