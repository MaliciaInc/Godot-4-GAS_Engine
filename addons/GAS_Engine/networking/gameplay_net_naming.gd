## Turning what a game holds into what another machine recognises.
##
## A Node is a local fact and an Object is a slot in one process's table, so
## every codec in this addon has the same three questions to answer before it
## can send anything: which entity does this node belong to, what does that
## identity point at here, and does this object live somewhere a receiver could
## find it.
##
## Written once because two copies would be two answers to those questions, and
## the interesting failure is not that one is wrong - it is that they disagree,
## so an event and a cue about the same shot name different casters.
##
## Static, and handed the registry rather than holding one, so a test can name
## something without standing up an authority to do it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetNaming extends RefCounted


## The identity of whatever ability system this node belongs to, or null.
static func entity_of(node: Node, registry_of: GameplayNetRegistry) -> GameplayNetEntityId:
	if node == null or not is_instance_valid(node) or registry_of == null:
		return null
	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
	if asc == null:
		return null
	var id: GameplayNetEntityId = registry_of.entity_for(asc)
	return id if id != null and id.is_valid() else null


## What an identity points at here, as the node a game would recognise.
##
## Null for an identity this machine has never registered: something about
## somebody who is not here is still something, and inventing a stand-in would
## be worse than saying nobody.
static func avatar_of(id: GameplayNetEntityId, registry_of: GameplayNetRegistry) -> Node:
	if registry_of == null:
		return null
	var asc: AbilitySystemComponent = registry_of.asc_for(id)
	return asc.get_effect_target() if asc != null else null


## A definition id for an object, when the object is something with a place.
##
## Its identity is where it lives, so one built in memory has no name any other
## machine could resolve. Left out rather than sent as its address or its class:
## a receiver resolving either would get something that is not the thing, which
## is worse than getting nothing.
static func definition_of(object: Object) -> GameplayNetDefinitionId:
	var resource: Resource = object as Resource
	if resource == null:
		return null
	var id: GameplayNetDefinitionId = GameplayNetDefinitionId.of_resource(resource)
	return id if id.is_valid() else null
