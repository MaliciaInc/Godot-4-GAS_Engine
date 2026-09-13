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

## Attribute base values.
var attributes: Dictionary[StringName, float] = {}

## The composed value each of those base values reads as right now - AUD-08.
##
## Sent alongside the base rather than instead of it, because the two answer
## different questions and a receiver that only had one would have to guess
## the other: `current` is what a health bar shows, and `base` is what a
## percentage-of-base cost or a `PRE_ATTRIBUTE_BASE_CHANGE` clamp needs to mean
## anything on the machine that predicted spending one. The client never
## derives `current` from `base` itself - it does not re-simulate, and under
## MIXED it is not even told the contributions that would let it - so a
## snapshot that named only `base` left every buff invisible until the next
## full one, however public the number it produced was.
var current_attributes: Dictionary[StringName, float] = {}

## Tag reference counts. Counts and not presence, because a tag held twice and
## released once is still held.
var tags: Dictionary[StringName, int] = {}

## The definitions this entity is granted, by net definition id.
var abilities: Array[int] = []

## Which of those grants are running right now.
##
## Only the ones whose grant says REPLICATE_YES, and only towards the peer
## that owns the entity. Most abilities are in neither list: what a melee
## swing is doing between starting and ending is nobody's business but the
## machine running it, and saying so every reading is bandwidth spent on
## something no other machine acts on.
##
## Ids rather than instances. A Node crossing a wire is a class name the
## receiver would have to construct, and a run named by the definition it is
## a run of is one both machines already agree about.
var running_abilities: Array[int] = []

## What is running on it.
var effects: Array[GameplayNetEffectState] = []

## The cue tags currently playing, for the persistent ones. A one-shot cue is
## an event rather than state and travels as its own message.
var cues: Array[StringName] = []

## What went away, on a delta. Empty on a snapshot, where the absence of a
## thing is already the whole of the news about it.
var removed_tags: Array[StringName] = []
var revoked_abilities: Array[int] = []
var stopped_abilities: Array[int] = []
var ended_effects: Array[int] = []
var ended_cues: Array[StringName] = []


#region The wire
## What each field is called on a wire, prefixed for the same reason the effect
## state prefixes its own.
const KIND_KEY: String = "state.kind"
const ATTRIBUTES_KEY: String = "state.attributes"
const CURRENT_ATTRIBUTES_KEY: String = "state.current_attributes"
const TAGS_KEY: String = "state.tags"
const ABILITIES_KEY: String = "state.abilities"
const RUNNING_ABILITIES_KEY: String = "state.running_abilities"
const EFFECTS_KEY: String = "state.effects"
const CUES_KEY: String = "state.cues"
const REMOVED_TAGS_KEY: String = "state.removed_tags"
const REVOKED_ABILITIES_KEY: String = "state.revoked_abilities"
const STOPPED_ABILITIES_KEY: String = "state.stopped_abilities"
const ENDED_EFFECTS_KEY: String = "state.ended_effects"
const ENDED_CUES_KEY: String = "state.ended_cues"


## This reading as primitives, and nothing else.
##
## Every StringName written as a String, every id as a number, and nothing
## nested that is not a Dictionary or an Array of them. What crosses a wire is
## read by a process that may be a different build of the game, and an object is
## the one thing a receiver must never be asked to construct from what it was
## sent.
func to_wire() -> Dictionary:
	var running: Array = []
	for effect: GameplayNetEffectState in effects:
		running.append(effect.to_wire())
	return {
		KIND_KEY: int(kind),
		ATTRIBUTES_KEY: _named_numbers(attributes),
		CURRENT_ATTRIBUTES_KEY: _named_numbers(current_attributes),
		TAGS_KEY: _named_numbers(tags),
		ABILITIES_KEY: abilities.duplicate(),
		RUNNING_ABILITIES_KEY: running_abilities.duplicate(),
		EFFECTS_KEY: running,
		CUES_KEY: GameplayWireReader.as_strings(cues),
		REMOVED_TAGS_KEY: GameplayWireReader.as_strings(removed_tags),
		REVOKED_ABILITIES_KEY: revoked_abilities.duplicate(),
		STOPPED_ABILITIES_KEY: stopped_abilities.duplicate(),
		ENDED_EFFECTS_KEY: ended_effects.duplicate(),
		ENDED_CUES_KEY: GameplayWireReader.as_strings(ended_cues),
	}


## One reading back, or null when the shape is not one.
##
## An effect entry that does not read as one takes the whole state with it: a
## state applied with one of its effects silently missing is a character the two
## processes disagree about, and disagreeing quietly is the failure this codec
## exists to prevent.
static func from_wire(wire: Variant) -> GameplayNetState:
	if not wire is Dictionary:
		return null
	var said: Dictionary = wire
	var made: GameplayNetState = GameplayNetState.new()
	made.kind = (
		Kind.DELTA
		if GameplayWireReader.number_in(said, KIND_KEY, 0) == int(Kind.DELTA)
		else Kind.SNAPSHOT
	)

	made.attributes.assign(_named_from(said.get(ATTRIBUTES_KEY, {})))
	made.current_attributes.assign(_named_from(said.get(CURRENT_ATTRIBUTES_KEY, {})))
	made.tags.assign(_named_from(said.get(TAGS_KEY, {})))
	made.abilities = _ints_from(said.get(ABILITIES_KEY, []))
	made.running_abilities = _ints_from(said.get(RUNNING_ABILITIES_KEY, []))
	made.cues = GameplayWireReader.tags_from(said.get(CUES_KEY, []))
	made.removed_tags = GameplayWireReader.tags_from(said.get(REMOVED_TAGS_KEY, []))
	made.revoked_abilities = _ints_from(said.get(REVOKED_ABILITIES_KEY, []))
	made.stopped_abilities = _ints_from(said.get(STOPPED_ABILITIES_KEY, []))
	made.ended_effects = _ints_from(said.get(ENDED_EFFECTS_KEY, []))
	made.ended_cues = GameplayWireReader.tags_from(said.get(ENDED_CUES_KEY, []))

	var running: Variant = said.get(EFFECTS_KEY, [])
	if not running is Array:
		return null
	var listed: Array = running
	for entry: Variant in listed:
		var effect: GameplayNetEffectState = GameplayNetEffectState.from_wire(entry)
		if effect == null:
			return null
		made.effects.append(effect)
	return made


## A name-to-number map as plain strings and numbers.
static func _named_numbers(from: Dictionary) -> Dictionary:
	var said: Dictionary = {}
	for name: StringName in from:
		said[String(name)] = from[name]
	return said


## A name-to-number map read back, with the names as names again.
##
## Untyped, and converted at the two call sites: the attributes are floats and
## the tag counts are integers, and one helper per type would be the same walk
## written twice for a difference the walk does not care about.
static func _named_from(value: Variant) -> Dictionary:
	var made: Dictionary = {}
	if not value is Dictionary:
		return made
	var said: Dictionary = value
	for name: Variant in said:
		made[StringName(str(name))] = said[name]
	return made


static func _ints_from(value: Variant) -> Array[int]:
	var made: Array[int] = []
	if not value is Array:
		return made
	var listed: Array = value
	for entry: Variant in listed:
		made.append(GameplayWireReader.number_from(entry))
	return made
#endregion


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
		and current_attributes.is_empty()
		and tags.is_empty()
		and abilities.is_empty()
		and running_abilities.is_empty()
		and stopped_abilities.is_empty()
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
	theirs.current_attributes = current_attributes.duplicate()
	theirs.tags = tags.duplicate()
	theirs.abilities = abilities.duplicate()
	theirs.running_abilities = running_abilities.duplicate()
	theirs.stopped_abilities = stopped_abilities.duplicate()
	theirs.cues = cues.duplicate()
	theirs.removed_tags = removed_tags.duplicate()
	theirs.revoked_abilities = revoked_abilities.duplicate()
	theirs.ended_effects = ended_effects.duplicate()
	theirs.ended_cues = ended_cues.duplicate()
	for one: GameplayNetEffectState in effects:
		theirs.effects.append(one.copied())
	return theirs
