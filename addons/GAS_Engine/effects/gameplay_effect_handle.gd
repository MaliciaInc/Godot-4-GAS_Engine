## A stable, durable reference to one active gameplay effect - the identity
## a caller keeps instead of holding an ActiveGameplayEffect reference
## directly.
##
## Identity is (owner_instance_id, id): a handle from one ASC never resolves
## on another, even if both happen to hold an id of 1 - each ASC's ids are
## monotonic and never reused only within its own life, not globally.
## Removal does not mutate the handle object a caller kept: it becomes a
## stale identity, useful for logs, that no longer resolves to anything.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectHandle extends RefCounted

const INVALID_ID: int = 0

var owner_instance_id: int = 0
var id: int = INVALID_ID


func is_valid() -> bool:
	return id != INVALID_ID


func same_as(other: GameplayEffectHandle) -> bool:
	if other == null:
		return false
	return owner_instance_id == other.owner_instance_id and id == other.id
