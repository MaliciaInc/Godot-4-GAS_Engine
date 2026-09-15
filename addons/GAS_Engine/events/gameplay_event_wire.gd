## A gameplay event in the only shape a wire can carry.
##
## `GameplayEventData` holds Nodes and Objects, and neither crosses a network:
## an ObjectID is a slot in one process's table and means something else in the
## next one. This is the same event said in identities, tags and numbers, which
## every machine can agree about.
##
## It is a separate class rather than a method on the payload for one reason:
## turning a Node into an identity is something only `GameplayNetRegistry` can
## do, and a payload that reached for a network singleton would be a payload no
## single-player game could construct. The conversion lives with the network
## runtime; this is only the shape it converts into, and GameplayNetEventSerializer
## is how the shape crosses.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEventWire extends RefCounted

var event_tag: StringName = &""

## Who caused it and who it is about, as identities the receiving machine can
## resolve against its own registry. Null when the sender could not name them,
## which is not the same as naming nobody.
var instigator: GameplayNetEntityId = null
var target: GameplayNetEntityId = null

## The optional objects, but only when the registry could name them as
## definitions. An object it does not know is left out rather than turned into
## its own address or its name: a receiver resolving either would get something
## that is not the thing.
var optional_definition: GameplayNetDefinitionId = null
var optional_definition2: GameplayNetDefinitionId = null

## The two snapshots, which cross as themselves - tags are already names every
## machine agrees about.
var instigator_tags: Array[StringName] = []
var target_tags: Array[StringName] = []

var magnitude: float = 0.0
