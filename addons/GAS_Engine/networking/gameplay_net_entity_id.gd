## Which entity, said in a way that survives the trip between two machines.
##
## Never `get_instance_id()`. An ObjectID is a slot in one process's object
## table: the same character is a different number on every machine, and the
## number is handed out again the moment something is freed. A message carrying
## one arrives meaning nothing, or - the failure that is worse because it looks
## like it worked - meaning something else.
##
## Assigned by the authority and mapped onto local nodes by each peer, rather
## than derived from anything a Node knows about itself. Derivation was tried in
## every engine that has done this and there is nothing to derive from: a scene
## path changes when a character is reparented, a name changes when two of them
## exist, and an avatar is swapped on respawn while the entity carrying the
## abilities is the same one it was.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetEntityId extends RefCounted

## The value that means "nobody", so an unset id is not an id for entity zero.
const NONE: int = 0

var value: int = NONE


static func of(assigned: int) -> GameplayNetEntityId:
	var made: GameplayNetEntityId = GameplayNetEntityId.new()
	made.value = assigned
	return made


func is_valid() -> bool:
	return value != NONE


## Two ids naming the same entity, compared by what they say rather than by
## which object is holding it: an id that came off the wire is a new object
## every time and identity would answer false to every question worth asking.
func same_as(other: GameplayNetEntityId) -> bool:
	return other != null and other.value == value and is_valid()


## What travels. An int rather than the object, because what a peer receives it
## has to build for itself: an object graph off the wire is a way to be handed
## a class you did not expect.
func to_wire() -> int:
	return value


static func from_wire(wire: int) -> GameplayNetEntityId:
	return GameplayNetEntityId.of(wire)
