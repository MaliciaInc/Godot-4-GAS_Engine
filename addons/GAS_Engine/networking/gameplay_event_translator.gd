## A gameplay event turned into identities, and back again.
##
## Its own file rather than another region of the network runtime, because it
## is a codec and the runtime is a state machine: one converts, the other
## decides. Static, and handed the registry rather than holding one, so a test
## can convert an event without standing up an authority to do it.
##
## Not on GameplayEventData either: only the registry can turn a Node into
## something another machine recognises, and a payload reaching for a network
## singleton would be one no single-player game could build.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEventTranslator extends RefCounted


## An event as identities, tags and numbers.
##
## Here rather than on GameplayEventData because only the registry can turn a
## Node into something another machine will recognise, and a payload that
## reached for a network singleton would be one no single-player game could
## build.
##
## An optional object survives only when it is a Resource saved somewhere: its
## identity is where it lives. One built in memory has no name any other machine
## could resolve, so it is left out rather than sent as its address or its
## class - a receiver resolving either would get something that is not the
## thing, which is worse than getting nothing.
static func to_wire(
	event: GameplayEventData, registry_of: GameplayNetRegistry
) -> GameplayEventWire:
	if event == null:
		return null

	var said: GameplayEventWire = GameplayEventWire.new()
	said.event_tag = event.event_tag
	said.instigator = _named_entity(event.instigator, registry_of)
	said.target = _named_entity(event.target, registry_of)
	said.optional_definition = _named_definition(event.optional_object)
	said.optional_definition2 = _named_definition(event.optional_object2)
	said.instigator_tags = event.instigator_tags.duplicate()
	said.target_tags = event.target_tags.duplicate()
	said.magnitude = event.magnitude
	return said


## The event back, resolved against this machine's registry.
##
## An identity this machine has never registered resolves to nothing, and the
## field stays null: an event about somebody who is not here is still an event,
## and inventing a stand-in would be worse than saying nobody.
static func from_wire(
	said: GameplayEventWire, registry_of: GameplayNetRegistry
) -> GameplayEventData:
	if said == null:
		return null

	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = said.event_tag
	event.instigator = _avatar_of(said.instigator, registry_of)
	event.target = _avatar_of(said.target, registry_of)
	event.optional_object = registry_of.definition_for(said.optional_definition)
	event.optional_object2 = registry_of.definition_for(said.optional_definition2)
	event.instigator_tags = said.instigator_tags.duplicate()
	event.target_tags = said.target_tags.duplicate()
	event.magnitude = said.magnitude
	return event


## The identity of whatever ability system this node belongs to, or null.
static func _named_entity(
	node: Node, registry_of: GameplayNetRegistry
) -> GameplayNetEntityId:
	if node == null or not is_instance_valid(node):
		return null
	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
	if asc == null:
		return null
	var id: GameplayNetEntityId = registry_of.entity_for(asc)
	return id if id != null and id.is_valid() else null


## What an identity points at here, as the node a game would recognise.
static func _avatar_of(id: GameplayNetEntityId, registry_of: GameplayNetRegistry) -> Node:
	var asc: AbilitySystemComponent = registry_of.asc_for(id)
	return asc.get_effect_target() if asc != null else null


## A definition id for an object, when the object is something with a place.
static func _named_definition(object: Object) -> GameplayNetDefinitionId:
	var resource: Resource = object as Resource
	if resource == null:
		return null
	var id: GameplayNetDefinitionId = GameplayNetDefinitionId.of_resource(resource)
	return id if id.is_valid() else null
