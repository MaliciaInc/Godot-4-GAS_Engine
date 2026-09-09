## Which tags an effect's requirements are about, read without evaluating them.
##
## A tag changing on a character used to mean asking every active effect on it
## whether its ongoing and removal queries still hold - a thousand queries
## evaluated for one tag, almost none of which mention it. Almost all of them
## mention no tags at all: an effect with no requirements can never transition
## and was being asked anyway.
##
## Read rather than evaluated. What a query is *about* is a property of how it
## was authored and does not change with the character's state, so it is worked
## out once when the effect is published and never again.
##
## The hierarchy runs one way here, and getting it backwards is the whole trap.
## A query about `State` is affected when `State.Stunned` arrives, because
## holding a descendant satisfies an ancestor. A query about `State.Stunned` is
## not affected when a bare `State` arrives, because holding an ancestor
## satisfies nothing under it. So a changed tag reaches the queries that mention
## it *or any of its ancestors* - never the other way.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectRequirementDependencies extends RefCounted

## How deep a query is walked before this stops.
##
## A query whose expressions reach back into themselves is a corrupted
## definition the runtime already refuses to evaluate; this walks it to say what
## it is about, and a walk with no floor would hang on the same graph.
const MAX_DEPTH: int = 64


## Every tag the two requirement queries of this effect name.
##
## Both, because both decide a transition: the ongoing query says whether the
## effect is in force and the removal query says whether it is still there at
## all, and an index that carried one would leave the other reevaluating
## everything.
static func of(effect: GameplayEffect) -> Array[StringName]:
	var found: Array[StringName] = []
	if effect == null:
		return found
	_gather(effect.get_ongoing_query(), found)
	_gather(effect.get_removal_query(), found)
	return found


## Whether this effect can transition at all when a tag moves.
##
## False for the overwhelming majority: an effect with neither query is one no
## tag change can affect, and asking it is the cost this index removes.
static func has_requirements(effect: GameplayEffect) -> bool:
	if effect == null:
		return false
	return _asks_something(effect.get_ongoing_query()) or _asks_something(effect.get_removal_query())


## Every tag a query names, at any depth, each of them once.
##
## Terminal tags only: an expression is a shape over tags and contributes
## nothing of its own to what the query is about.
static func tags_in(query: GameplayTagQuery) -> Array[StringName]:
	var found: Array[StringName] = []
	_gather(query, found)
	return found


static func _asks_something(query: GameplayTagQuery) -> bool:
	return query != null and not query.is_empty()


static func _gather(query: GameplayTagQuery, into: Array[StringName]) -> void:
	if not _asks_something(query):
		return
	var visiting: Array[GameplayTagQueryExpression] = []
	_walk(query.root, visiting, into, MAX_DEPTH)


static func _walk(
	expression: GameplayTagQueryExpression,
	visiting: Array[GameplayTagQueryExpression],
	into: Array[StringName],
	depth: int
) -> void:
	if expression == null or depth <= 0 or visiting.has(expression):
		return
	visiting.append(expression)

	for tag: StringName in expression.tags:
		if tag != &"" and not into.has(tag):
			into.append(tag)
	for nested: GameplayTagQueryExpression in expression.expressions:
		_walk(nested, visiting, into, depth - 1)

	visiting.pop_back()
