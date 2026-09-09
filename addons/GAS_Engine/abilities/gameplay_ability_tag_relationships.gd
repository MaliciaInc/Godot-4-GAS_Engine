## Every rule about kinds of ability, in one place a person can read.
##
## Row order does not change the answer. Each row adds restrictions, and adding
## is commutative - which matters because a table whose meaning depended on the
## order somebody happened to append rows in is a table nobody can edit safely.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityTagRelationships extends Resource

@export var relationships: Array[GameplayAbilityTagRelationship] = []


## Whether the owner's tags let this ability start, by these rules alone.
##
## Only ever a refusal. Nothing here can allow something the ability's own
## declaration refused - that check has already happened and this runs after it.
func refusal_for(
	carried: Array[StringName], owned: GameplayTagRuntime
) -> AbilityRuntime.ActivationError:
	for row: GameplayAbilityTagRelationship in relationships:
		if not _is_about(row, carried):
			continue
		if AbilityRuntime.query_matches_runtime(row.blocked_by_query, owned):
			return AbilityRuntime.ActivationError.BLOCKED_TAG
		var required: GameplayTagQuery = row.requires_query
		if required != null and not required.is_empty() and not required.matches_runtime(owned):
			return AbilityRuntime.ActivationError.MISSING_TAG
	return AbilityRuntime.ActivationError.NONE


## What starting this ability cancels, and what it blocks while it runs, as one
## query each - or null when no row says anything about it.
func cancels_for(carried: Array[StringName]) -> Array[GameplayTagQuery]:
	return _collect(carried, true)


func blocks_for(carried: Array[StringName]) -> Array[GameplayTagQuery]:
	return _collect(carried, false)


func _collect(carried: Array[StringName], cancelling: bool) -> Array[GameplayTagQuery]:
	var found: Array[GameplayTagQuery] = []
	for row: GameplayAbilityTagRelationship in relationships:
		if not _is_about(row, carried):
			continue
		var query: GameplayTagQuery = row.cancels_query if cancelling else row.blocks_query
		if query != null and not query.is_empty():
			found.append(query)
	return found


## Whether a row is about an ability carrying these tags.
static func _is_about(
	row: GameplayAbilityTagRelationship, carried: Array[StringName]
) -> bool:
	if row == null or row.ability_query == null or row.ability_query.is_empty():
		return false
	return row.ability_query.matches_tags(carried)
