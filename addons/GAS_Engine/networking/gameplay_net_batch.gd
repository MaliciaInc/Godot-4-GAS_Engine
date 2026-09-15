## Several messages that arrive together, and either all happen or none do.
##
## An activation is not one message. It is the activation, what it cost, what it
## put on cooldown and what it confirmed, and a client that saw three of those
## four is a client showing a character mid-cast with no cooldown - which
## corrects itself a frame later and looks like a bug the whole time.
##
## Atomic by default. A batch that applied what it could would be a batch whose
## failure mode is a partially applied character, which is worse than nothing
## having arrived: nothing having arrived is a state the next snapshot repairs.
## A game grouping genuinely independent operations says so by setting it false.
##
## How a batch crosses is the codec's: its atomicity, a count, and each member
## written the way a message is.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetBatch extends RefCounted

## How many messages one batch may carry.
##
## A limit rather than none, because a batch is read whole before any of it is
## applied: an unbounded one is an unbounded allocation a peer can ask for, and
## the number of messages one action produces is small and known.
const MAX_MESSAGES: int = 64

## Why a batch was not applied.
const REASON_TOO_MANY: StringName = &"batch_too_large"
const REASON_EMPTY: StringName = &"batch_empty"
const REASON_MEMBER_REFUSED: StringName = &"batch_member_refused"

var messages: Array[GameplayNetMessage] = []

## Whether the whole batch stands or falls together.
##
## True for the groups F6 makes - an activation with its cost, its cooldown and
## its confirmation - because those are four halves of one thing. False is for a
## game that batched independent operations to save packets, where one being
## refused says nothing about the others.
var atomic: bool = true


## Whether this batch is one a peer may be asked to apply.
##
## Empty is not: a batch that says nothing is a sender that opened one and never
## put anything in it, and sending it is bandwidth spent on nothing.
func is_sendable() -> bool:
	return not messages.is_empty() and messages.size() <= MAX_MESSAGES


## Whether a receiver may start judging this batch at all: within its bounds,
## and every member a message that is not itself a batch.
##
## All or nothing at this stage too: a batch with one member that is not a
## message is refused whole rather than applied without it, because "without
## it" is exactly the partially applied character the atomicity is for.
func is_readable() -> bool:
	if not is_sendable():
		return false
	for message: GameplayNetMessage in messages:
		if message == null or message.kind == GameplayNetMessage.Kind.BATCH:
			return false
	return true
