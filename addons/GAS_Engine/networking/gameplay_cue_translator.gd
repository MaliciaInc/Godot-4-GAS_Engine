## A cue turned into identities, and back again.
##
## Its own file rather than a method on GameplayCueParams, for the reason the
## event translator is: only the registry can turn a Node into something another
## machine recognises, and params that reached for a network singleton would be
## params no single-player game could construct.
##
## The line this codec is careful about is which fields do not travel.
## `source_object` and `causer` are a local Object and a local Node; what
## crosses is the identity of the entity each belongs to. A peer that cannot
## resolve one gets null, which is the honest answer - a stand-in would be a cue
## about the wrong character.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueTranslator extends RefCounted


## A cue as identities, tags and numbers.
static func to_wire(
	params: GameplayCueParams, registry_of: GameplayNetRegistry
) -> GameplayCueWire:
	if params == null:
		return null

	var said: GameplayCueWire = GameplayCueWire.new()
	said.cue_tag = params.cue_tag
	said.matched_cue_tag = params.matched_cue_tag
	said.instigator = GameplayNetNaming.entity_of(params.instigator, registry_of)
	said.target = GameplayNetNaming.entity_of(params.target, registry_of)
	# The two that stand in for what cannot cross. A named entity the params
	# already carry wins over one derived here: whoever built them may know
	# something the tree no longer does, such as a causer that has been freed.
	said.source_entity = (
		params.source_entity
		if params.source_entity != null
		else GameplayNetNaming.entity_of(params.source_object as Node, registry_of)
	)
	said.causer_entity = (
		params.causer_entity
		if params.causer_entity != null
		else GameplayNetNaming.entity_of(params.causer, registry_of)
	)
	said.raw_magnitude = params.raw_magnitude
	said.normalized_magnitude = params.normalized_magnitude
	said.effect_level = params.effect_level
	said.ability_level = params.ability_level
	said.stack_count = params.stack_count
	said.source_tags = params.source_tags.duplicate()
	said.target_tags = params.target_tags.duplicate()
	said.location = params.location
	said.has_location = params.has_location
	return said


## The cue back, resolved against this machine's registry.
##
## `source_object` and `causer` come back as nulls unless the identities resolve
## here, and `causer` resolves to the avatar rather than to whatever object sent
## it: what a receiving machine can act on is a node in its own tree.
static func from_wire(
	said: GameplayCueWire, registry_of: GameplayNetRegistry
) -> GameplayCueParams:
	if said == null:
		return null

	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = said.cue_tag
	params.matched_cue_tag = said.matched_cue_tag
	params.instigator = GameplayNetNaming.avatar_of(said.instigator, registry_of)
	params.target = GameplayNetNaming.avatar_of(said.target, registry_of)
	params.source_entity = said.source_entity
	params.causer_entity = said.causer_entity
	params.causer = GameplayNetNaming.avatar_of(said.causer_entity, registry_of)
	params.raw_magnitude = said.raw_magnitude
	params.magnitude = said.raw_magnitude
	params.normalized_magnitude = said.normalized_magnitude
	params.effect_level = said.effect_level
	params.ability_level = said.ability_level
	params.stack_count = said.stack_count
	params.source_tags = said.source_tags.duplicate()
	params.target_tags = said.target_tags.duplicate()
	params.location = said.location
	params.has_location = said.has_location
	return params
