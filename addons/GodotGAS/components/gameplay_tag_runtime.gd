## Reference-counted gameplay tag state and the queries over it.
##
## Two upstream contracts were wrong and both are fixed here:
##
##   has_all_tags([])  returned false. "The target has every tag in an empty
##                     set" is vacuously true, and returning false made every
##                     ability with no required tags fail its own gate.
##
##   has_tag(A)        matched by bare prefix, so `Damage.Fire` matched
##                     `Damage.Firestorm` and `A` matched `AB`. The separator is
##                     part of the rule, not decoration.
##
## This class emits nothing. It reports what changed and the ASC facade emits
## from that, so a query can never fire a signal.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayTagRuntime extends RefCounted

## What one mutation did, so the facade knows which signal to emit without
## re-deriving it by comparing counts.
enum Change { NONE, ADDED, INCREMENTED, DECREMENTED, REMOVED }

const SEPARATOR: String = "."

var _counts: Dictionary[StringName, int] = {}


#region Mutation
## Increment a tag's reference count, adding it at 1 if absent.
func add(tag: StringName) -> Change:
	if tag == &"":
		return Change.NONE
	if _counts.has(tag):
		_counts[tag] += 1
		return Change.INCREMENTED
	_counts[tag] = 1
	return Change.ADDED


## Decrement a tag's reference count, removing it at zero.
func remove(tag: StringName) -> Change:
	if not _counts.has(tag):
		return Change.NONE
	_counts[tag] -= 1
	if _counts[tag] > 0:
		return Change.DECREMENTED
	_counts.erase(tag)
	return Change.REMOVED


## Drop a tag whatever its count. Used by a cleanse, not by normal removal.
func clear(tag: StringName) -> Change:
	if not _counts.has(tag):
		return Change.NONE
	_counts.erase(tag)
	return Change.REMOVED


func clear_all() -> void:
	_counts.clear()


func count(tag: StringName) -> int:
	return _counts.get(tag, 0)


func active_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	for tag: StringName in _counts.keys():
		tags.append(tag)
	return tags
#endregion


#region Queries
## True only for this exact tag. `Status` does not answer for `Status.Stunned`.
func has_exact(tag: StringName) -> bool:
	return _counts.has(tag)


## True for this tag or any descendant of it.
func has(tag: StringName) -> bool:
	if _counts.has(tag):
		return true
	return tag_set_has(_counts.keys(), tag)


## Whether any tag in `active_tags` is `requested_tag` or a descendant of it.
##
## The one hierarchical matcher, so `has()` and GameplayTagQuery can never
## disagree about what "holds a tag" means - each calls this instead of
## keeping its own copy of the loop.
static func tag_set_has(
	active_tags: Array[StringName], requested_tag: StringName
) -> bool:
	for active: StringName in active_tags:
		if is_descendant_of(active, requested_tag):
			return true
	return false


## True when at least one of the tags matches, hierarchically.
##
## An empty set contains nothing, so nothing matches: false.
func has_any(tags: Array[StringName]) -> bool:
	for tag: StringName in tags:
		if has(tag):
			return true
	return false


## True when every tag matches, hierarchically.
##
## An empty set is vacuously satisfied: true. Upstream returned false here,
## which made "no requirements" the strictest possible requirement.
func has_all(tags: Array[StringName]) -> bool:
	for tag: StringName in tags:
		if not has(tag):
			return false
	return true


## Whether `candidate` is `parent` or lives under it.
##
## The separator is required: `Damage.Firestorm` is not under `Damage.Fire`,
## and `AB` is not under `A`. A bare `begins_with` gets both of those wrong.
static func is_descendant_of(candidate: StringName, parent: StringName) -> bool:
	if candidate == parent:
		return true
	return String(candidate).begins_with(String(parent) + SEPARATOR)
#endregion
