## One active effect, as it looks to another machine.
##
## Not the effect. What travels is what a second machine can act on without
## re-running the simulation that produced it: which definition, how many of
## it, how long is left, and whether it is currently doing anything. A client
## re-simulating what the authority already simulated would arrive at a second
## answer, and the two would drift apart the first time a tick landed on a
## different frame.
##
## The id is assigned by the authority and mapped, not converted. A
## GameplayEffectHandle names an object in one process; this names the same
## application on every machine that heard about it, and the table between them
## is the registry's.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetEffectState extends RefCounted

const NONE: int = 0

## Which application, and of what.
var id: int = NONE
var definition: int = GameplayNetDefinitionId.NONE

## How many of it are on the target.
var stack_count: int = 1

## How long is left, for a duration effect. Zero for infinite ones, which is
## not the same as expired: an infinite effect has no remaining time to send.
var time_remaining: float = 0.0

## How many turns are left, for a TURN_BASED effect. Turns and seconds are two
## different clocks and an effect uses one of them; sending both and letting
## the receiver guess which is real is how a turn-based buff ends up ticking
## down on a wall clock.
var remaining_turns: int = 0

## Whether it is currently suppressed - its modifiers off, its tags gone, and
## itself still there waiting to come back. A client that did not know would
## show a buff that is doing nothing.
var inhibited: bool = false


static func of(assigned: int, definition_id: int) -> GameplayNetEffectState:
	var made: GameplayNetEffectState = GameplayNetEffectState.new()
	made.id = assigned
	made.definition = definition_id
	return made


func is_valid() -> bool:
	return id != NONE and definition != GameplayNetDefinitionId.NONE


#region The wire
## What each field is called on a wire.
##
## Prefixed, the way the target-data contract prefixes its own: a bare
## `definition` or `turns` is a word half this addon uses for something else,
## and two contracts spelling one key the same way look interchangeable when
## they are not.
const ID_KEY: String = "effect.id"
const DEFINITION_KEY: String = "effect.definition"
const STACKS_KEY: String = "effect.stacks"
const SECONDS_KEY: String = "effect.seconds"
const TURNS_KEY: String = "effect.turns"
const INHIBITED_KEY: String = "effect.inhibited"


## This reading as primitives, and nothing else.
##
## Six numbers and a flag. No object, no Variant that could arrive as one: a
## receiver that decoded an object would be running whatever a sender named.
func to_wire() -> Dictionary:
	return {
		ID_KEY: id,
		DEFINITION_KEY: definition,
		STACKS_KEY: stack_count,
		SECONDS_KEY: time_remaining,
		TURNS_KEY: remaining_turns,
		INHIBITED_KEY: inhibited,
	}


## One reading back, or null when the shape is not one.
##
## Null rather than a half-built state: a caller handed something with an id and
## nothing else would apply an effect with no definition behind it, and the
## reader that noticed would be the furthest from where it went wrong.
static func from_wire(wire: Variant) -> GameplayNetEffectState:
	if not wire is Dictionary:
		return null
	var said: Dictionary = wire
	var made: GameplayNetEffectState = GameplayNetEffectState.new()
	made.id = int(said.get(ID_KEY, NONE))
	made.definition = int(said.get(DEFINITION_KEY, GameplayNetDefinitionId.NONE))
	made.stack_count = int(said.get(STACKS_KEY, 1))
	made.time_remaining = float(said.get(SECONDS_KEY, 0.0))
	made.remaining_turns = int(said.get(TURNS_KEY, 0))
	made.inhibited = said.get(INHIBITED_KEY, false) == true
	return made if made.is_valid() else null
#endregion


## Whether two readings of this application say the same thing.
##
## What a delta is computed from. Identity is not enough - the same effect with
## one more stack on it is news - and neither is equality of everything, since
## two readings of one effect are always two objects.
func same_as(other: GameplayNetEffectState) -> bool:
	if other == null:
		return false
	return (
		other.id == id
		and other.definition == definition
		and other.stack_count == stack_count
		and is_equal_approx(other.time_remaining, time_remaining)
		and other.remaining_turns == remaining_turns
		and other.inhibited == inhibited
	)


func copied() -> GameplayNetEffectState:
	var theirs: GameplayNetEffectState = GameplayNetEffectState.of(id, definition)
	theirs.stack_count = stack_count
	theirs.time_remaining = time_remaining
	theirs.remaining_turns = remaining_turns
	theirs.inhibited = inhibited
	return theirs
