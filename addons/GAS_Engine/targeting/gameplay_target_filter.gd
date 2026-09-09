## Which of the things a physics query found are worth targeting.
##
## Physics answers with geometry, and geometry is not a target list: the query
## returns walls, the caster's own hitbox, allies a spell should not reach, and
## enemies already immune to it. Deciding that per call site meant every ability
## re-derived the same rules and a few of them forgot to exclude the caster.
##
## The count limit is deliberately not decided here. A filter is asked about one
## candidate at a time and cannot know how many have already been accepted; the
## service that is keeping the running total applies it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetFilter extends RefCounted

## The candidate must have all of these.
var required_tags: Array[StringName] = []

## The candidate must have none of these.
var blocked_tags: Array[StringName] = []

## On by default. Almost every ability that sweeps an area around the caster
## means "around me, not me", and remembering to say so each time is the kind of
## thing that gets forgotten once and then ships.
var exclude_source: bool = true

## How many targets to keep. Zero means all of them. Applied by the service.
var max_targets: int = 0


## Whether this candidate is worth targeting at all.
##
## Something with neither an ability system nor an opinion of its own is not a
## target: nothing could receive the effect. That is a refusal here rather than
## an error, because a sweep across a room is expected to touch scenery - and a
## door that is Locked is scenery with tags, which is why the opinion counts.
func accepts(source_asc: AbilitySystemComponent, candidate: Node) -> bool:
	if candidate == null:
		return false

	var candidate_asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(candidate)
	# Something with neither an ability system nor an opinion of its own is
	# not a target: nothing could receive the effect. A refusal rather than
	# an error, because a sweep across a room is expected to touch scenery.
	if candidate_asc == null and not GameplayTagOwner.speaks_for_itself(candidate):
		return false
	if exclude_source and candidate_asc != null and candidate_asc == source_asc:
		return false

	# Both sources of tags, because a node that has an ability system AND
	# answers for itself is saying both things: dropping either would be this
	# filter deciding which of somebody's two answers was the real one.
	var carried: Array[StringName] = GameplayTagOwner.tags_of(candidate)
	for wanted: StringName in required_tags:
		if not carried.has(wanted):
			return false
	for refused: StringName in blocked_tags:
		if carried.has(refused):
			return false
	return true
