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
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagRuntime extends RefCounted

## What one mutation did, so the facade knows which signal to emit without
## re-deriving it by comparing counts.
enum Change { NONE, ADDED, INCREMENTED, DECREMENTED, REMOVED }

const SEPARATOR: String = GameplayTagFamily.SEPARATOR

var _counts: Dictionary[StringName, int] = {}


## The name a tag goes by now.
##
## Every door of this class, in and out, so a project that renamed a tag holds
## and answers about one name rather than two. An asset naming the old one still
## grants the tag the project has, and a query naming the old one still finds it
## - which is the whole point of a rename that does not rewrite anybody's files.
##
## Costs one lookup in an empty Dictionary for a project that has renamed
## nothing, which is almost all of them.
static func _current(tag: StringName) -> StringName:
	return GameplayTagRedirects.resolve(tag)


#region Mutation
## Increment a tag's reference count, adding it at 1 if absent.
func add(tag: StringName) -> GameplayTagRuntime.Change:
	if tag == &"":
		return Change.NONE
	var current: StringName = _current(tag)
	if _counts.has(current):
		_counts[current] += 1
		return Change.INCREMENTED
	_counts[current] = 1
	return Change.ADDED


## Decrement a tag's reference count, removing it at zero.
func remove(tag: StringName) -> GameplayTagRuntime.Change:
	var current: StringName = _current(tag)
	if not _counts.has(current):
		return Change.NONE
	_counts[current] -= 1
	if _counts[current] > 0:
		return Change.DECREMENTED
	_counts.erase(current)
	return Change.REMOVED


## Drop a tag whatever its count. Used by a cleanse, not by normal removal.
func clear(tag: StringName) -> GameplayTagRuntime.Change:
	var current: StringName = _current(tag)
	if not _counts.has(current):
		return Change.NONE
	_counts.erase(current)
	return Change.REMOVED


func clear_all() -> void:
	_counts.clear()


## How many times this exact tag is held.
##
## What every reference count in this engine is asking: a tag granted by two
## effects is held twice, and dropping one of them leaves it held once.
## `State` is not `State.Stunned` here, however many stunned things there are.
func count_exact(tag: StringName) -> int:
	return _counts.get(_current(tag), 0)


## How many times this tag or anything under it is held.
##
## The question a listener on `State` is actually asking. Two effects, one
## stunning and one rooting, are two things under `State` - so `State` is held
## twice, and losing one of them does not mean the character can move.
func count(tag: StringName) -> int:
	var total: int = 0
	var current: StringName = _current(tag)
	for active: StringName in _counts:
		if is_descendant_of(active, current):
			total += _counts[active]
	return total


## Every tag whose hierarchical count this one contributes to: itself, then
## each ancestor, nearest first.
##
## `State.Debuff.Stunned` is held by `State.Debuff` and by `State`, and by
## nothing else - a prefix that does not end at a separator is a different tag,
## for the reason `is_descendant_of` gives.
## Answered by GameplayTagFamily, which the cue manager also needs and
## cannot reach through this file: an autoload parses before the global
## class cache exists, so what it reaches must preload what it names.
static func ancestors_of(tag: StringName) -> Array[StringName]:
	return GameplayTagFamily.ancestors_of(tag)


func active_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	for tag: StringName in _counts.keys():
		tags.append(tag)
	return tags
#endregion


#region Queries
## True only for this exact tag. `Status` does not answer for `Status.Stunned`.
func has_exact(tag: StringName) -> bool:
	return _counts.has(_current(tag))


## True for this tag or any descendant of it.
func has(tag: StringName) -> bool:
	var current: StringName = _current(tag)
	if _counts.has(current):
		return true
	return tag_set_has(_counts.keys(), current)


## Whether any tag in `active_tags` is `requested_tag` or a descendant of it.
##
## The one hierarchical matcher, so `has()` and GameplayTagQuery can never
## disagree about what "holds a tag" means - each calls this instead of
## keeping its own copy of the loop.
static func tag_set_has(
	active_tags: Array[StringName], requested_tag: StringName
) -> bool:
	var current: StringName = _current(requested_tag)
	for active: StringName in active_tags:
		if is_descendant_of(active, current):
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
