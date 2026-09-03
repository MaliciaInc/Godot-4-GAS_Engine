## What was granted, independent of whatever Node is running it right now.
##
## Identity is the pair `(owner_instance_id, id)`, not `id` alone: two ASCs
## granting abilities concurrently both start counting from 1, and a handle
## from one must never resolve against the other's registry by coincidence of
## that shared number. Every lookup checks `owner_instance_id` first for
## exactly that reason.
##
## `id` is monotonic within one ASC and never reused for its lifetime, so a
## handle for an ability that has since been removed answers `is_valid()` but
## resolves to nothing, rather than silently landing on whatever now holds the
## number it used to.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityHandle extends RefCounted

const INVALID_ID: int = 0

var owner_instance_id: int = 0
var id: int = INVALID_ID


func is_valid() -> bool:
	return owner_instance_id != 0 and id != INVALID_ID


func same_as(other: GameplayAbilityHandle) -> bool:
	if other == null:
		return false
	return owner_instance_id == other.owner_instance_id and id == other.id
