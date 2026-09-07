## Which definition, said the same way on every machine.
##
## Derived rather than assigned, because unlike an entity a definition is
## already the same on both sides: the ability the server granted and the one
## the client is predicting with are one file, shipped in one project, and the
## file is the only thing about them that is the same number everywhere.
##
## The path hashed rather than the path itself. A message carrying
## `res://abilities/fire/greater_fireball_of_considerable_size.tscn` pays for
## that string on every activation, and there are activations every frame.
##
## Hashing has one failure and it is a real one: two paths can answer the same
## number. That is why `GameplayNetworkRuntime` registers definitions rather
## than trusting the hash blindly - a collision is refused where the two paths
## are both known, at start-up, instead of surfacing as one ability quietly
## activating another halfway through a match.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetDefinitionId extends RefCounted

const NONE: int = 0

var value: int = NONE


## The id for a resource path.
##
## An empty path is not a definition: a Resource built in memory and never
## saved cannot be named to another machine, and answering an id for it would
## let it be sent as if it could.
static func of_path(path: String) -> GameplayNetDefinitionId:
	var made: GameplayNetDefinitionId = GameplayNetDefinitionId.new()
	made.value = path.hash() if not path.is_empty() else NONE
	return made


## The id for a resource, which is the id for where it lives.
static func of_resource(resource: Resource) -> GameplayNetDefinitionId:
	if resource == null:
		return GameplayNetDefinitionId.new()
	return GameplayNetDefinitionId.of_path(resource.resource_path)


func is_valid() -> bool:
	return value != NONE


func same_as(other: GameplayNetDefinitionId) -> bool:
	return other != null and other.value == value and is_valid()


func to_wire() -> int:
	return value


static func from_wire(wire: int) -> GameplayNetDefinitionId:
	var made: GameplayNetDefinitionId = GameplayNetDefinitionId.new()
	made.value = wire
	return made
