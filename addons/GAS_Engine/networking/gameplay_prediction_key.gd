## One thing a client did before it was allowed to, and everything that
## followed from it.
##
## Prediction is a client applying a cost, starting a cooldown and playing a cue
## on the strength of a guess, then finding out. Being told "no" is the easy
## half; the hard half is that by then other things have been done on top of the
## guess, and undoing the first without the second leaves a character holding a
## cooldown for an ability that never fired.
##
## So a key is not a number, it is a place in a chain. Every predictive
## operation carries the key it was done under, and a key done because of
## another one names its parent. Rejecting a key rejects everything derived from
## it, and `depends_on` is how the journal knows what that is.
##
## The peer travels with it because two clients count from one independently,
## and a server hearing key 7 from each of them is hearing about two different
## guesses.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPredictionKey extends RefCounted

const NONE: int = 0

## Which machine guessed, and its own count of guesses.
var peer: int = 0
var value: int = NONE

## What this guess was made on top of, or null when it was made on nothing.
var parent: GameplayPredictionKey = null


static func of(from_peer: int, counted: int) -> GameplayPredictionKey:
	var made: GameplayPredictionKey = GameplayPredictionKey.new()
	made.peer = from_peer
	made.value = counted
	return made


## A key for something done because of this one.
##
## The child counts on with its own number and remembers what it stood on, so
## the journal can reverse a whole guess in the order it was built.
func deriving(counted: int) -> GameplayPredictionKey:
	var child: GameplayPredictionKey = GameplayPredictionKey.of(peer, counted)
	child.parent = self
	return child


func is_valid() -> bool:
	return value != NONE


func same_as(other: GameplayPredictionKey) -> bool:
	return other != null and other.peer == peer and other.value == value and is_valid()


## Whether this key stands on `other`, however far down.
##
## Walks up rather than down, because a key knows what it was built on and not
## what was built on it - which is the direction that costs nothing to keep.
func depends_on(other: GameplayPredictionKey) -> bool:
	if other == null:
		return false
	var standing: GameplayPredictionKey = parent
	while standing != null:
		if standing.same_as(other):
			return true
		standing = standing.parent
	return false


## This key and everything it stands on, nearest first - the order a rejection
## is reversed in, since the newest guess has to come off before the one it was
## made on top of.
func chain() -> Array[GameplayPredictionKey]:
	var standing: Array[GameplayPredictionKey] = []
	var here: GameplayPredictionKey = self
	while here != null:
		standing.append(here)
		here = here.parent
	return standing


## Two ints. A parent is not sent: the peer that receives a rejection reverses
## its own journal, which is where the chain already is, and shipping a linked
## list would let a sender describe a shape the receiver never built.
func to_wire() -> PackedInt64Array:
	return PackedInt64Array([peer, value])


static func from_wire(wire: PackedInt64Array) -> GameplayPredictionKey:
	if wire.size() != 2:
		return GameplayPredictionKey.new()
	return GameplayPredictionKey.of(wire[0], wire[1])
