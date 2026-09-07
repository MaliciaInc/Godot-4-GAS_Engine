## What one entity's ability system looks like, as something that can travel.
##
## A snapshot and a delta are the same shape, which is deliberate: a late
## joiner is a peer whose whole state is news, and a peer that has been here all
## along is one whose news happens to be small. Two shapes would be two readers,
## and the second one is where a late joiner ends up with half a character.
##
## What is in it is the seven things the phase names - attributes, tags,
## abilities, active effects, stacks, remaining duration and turns, cues - and a
## delta is the same object holding only what changed, plus what went away.
## Removals are separate because an absence cannot be expressed by a value: a
## tag that is gone and a tag nobody mentioned look identical in a dictionary.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetState extends RefCounted

## Whether this is everything about an entity or only what changed.
##
## Carried rather than inferred, because the difference is not visible in the
## data: a full state that happens to be empty is a character with nothing on
## it, and a delta that happens to be empty is nothing having happened.
enum Kind { SNAPSHOT, DELTA }

var kind: GameplayNetState.Kind = Kind.SNAPSHOT

## Attribute base values. Base and not current: current is composed from the
## effects, and sending the composed answer as well would be sending the same
## fact twice for the two to disagree about.
var attributes: Dictionary[StringName, float] = {}

## Tag reference counts. Counts and not presence, because a tag held twice and
## released once is still held.
var tags: Dictionary[StringName, int] = {}

## The definitions this entity is granted, by net definition id.
var abilities: Array[int] = []

## What is running on it.
var effects: Array[GameplayNetEffectState] = []

## The cue tags currently playing, for the persistent ones. A one-shot cue is
## an event rather than state and travels as its own message.
var cues: Array[StringName] = []

## What went away, on a delta. Empty on a snapshot, where the absence of a
## thing is already the whole of the news about it.
var removed_tags: Array[StringName] = []
var revoked_abilities: Array[int] = []
var ended_effects: Array[int] = []
var ended_cues: Array[StringName] = []


static func snapshot() -> GameplayNetState:
	return GameplayNetState.new()


static func delta() -> GameplayNetState:
	var made: GameplayNetState = GameplayNetState.new()
	made.kind = Kind.DELTA
	return made


func is_delta() -> bool:
	return kind == Kind.DELTA


## Whether this says nothing at all.
##
## Worth asking before sending: a delta computed every frame is mostly empty,
## and sending an empty one is bandwidth spent to say that nothing happened.
func is_empty() -> bool:
	return (
		attributes.is_empty()
		and tags.is_empty()
		and abilities.is_empty()
		and effects.is_empty()
		and cues.is_empty()
		and removed_tags.is_empty()
		and revoked_abilities.is_empty()
		and ended_effects.is_empty()
		and ended_cues.is_empty()
	)


## The effect with this id, or null.
func effect(id: int) -> GameplayNetEffectState:
	for one: GameplayNetEffectState in effects:
		if one.id == id:
			return one
	return null


## A copy nothing else holds a piece of.
##
## A snapshot is kept as "what the peer was last told" and compared against the
## next one; sharing the effect objects between the two would leave the
## comparison asking whether an object equals itself.
func copied() -> GameplayNetState:
	var theirs: GameplayNetState = GameplayNetState.new()
	theirs.kind = kind
	theirs.attributes = attributes.duplicate()
	theirs.tags = tags.duplicate()
	theirs.abilities = abilities.duplicate()
	theirs.cues = cues.duplicate()
	theirs.removed_tags = removed_tags.duplicate()
	theirs.revoked_abilities = revoked_abilities.duplicate()
	theirs.ended_effects = ended_effects.duplicate()
	theirs.ended_cues = ended_cues.duplicate()
	for one: GameplayNetEffectState in effects:
		theirs.effects.append(one.copied())
	return theirs
