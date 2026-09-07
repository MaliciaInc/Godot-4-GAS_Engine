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
