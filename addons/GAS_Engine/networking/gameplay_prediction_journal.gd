## Everything this machine did before it was allowed to, in the order it did it.
##
## A client that predicts is a client with a small pile of unauthorised changes
## on it. The pile is not the problem - being wrong about one frame is the whole
## point of predicting - the problem is unwinding it. Things were done because
## of other things: the cooldown went on because the cost was paid, the spark
## played because the cooldown started. Undoing the cost and leaving the
## cooldown is a character that cannot cast an ability it never cast.
##
## So a key is a place in a chain and the journal unwinds by that chain, newest
## first. Rejecting a guess rejects everything that stood on it.
##
## The journal never travels. It is this machine's record of what it owes, and
## the only thing that comes back from the authority is which key was accepted
## or refused - the peer that predicted is the peer that knows what it did.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPredictionJournal extends RefCounted

## What was done, in the order it happened.
var _written: Array[GameplayPredictionOperation] = []

## This machine's own count of guesses, so two of them are never one.
var _counted: int = 0


## The next key for this peer, standing on `parent` when it stands on anything.
func next_key(peer: int, parent: GameplayPredictionKey = null) -> GameplayPredictionKey:
	_counted += 1
	if parent != null:
		return parent.deriving(_counted)
	return GameplayPredictionKey.of(peer, _counted)


func record(operation: GameplayPredictionOperation) -> void:
	if operation == null or operation.key == null or not operation.key.is_valid():
		return
	_written.append(operation)


## Everything done under a key or because of it, newest first.
##
## Newest first because that is the order it has to come off in: the spark
## before the cooldown, the cooldown before the cost. Undoing them in the order
## they were written would take the ground out before what was standing on it.
func under(key: GameplayPredictionKey) -> Array[GameplayPredictionOperation]:
	var standing: Array[GameplayPredictionOperation] = []
	if key == null:
		return standing
	for index: int in range(_written.size() - 1, -1, -1):
		var operation: GameplayPredictionOperation = _written[index]
		if operation.key.same_as(key) or operation.key.depends_on(key):
			standing.append(operation)
	return standing


## The authority agreed. The guess is now everybody's state.
##
## The operations are marked and dropped rather than replayed. Replaying them
## against the authoritative answer that follows would apply everything twice,
## which is the double cost this whole layer exists to make impossible; marking
## them first means a rejection arriving afterwards - a duplicate, a reorder -
## cannot reverse what has already been agreed.
func accept(key: GameplayPredictionKey) -> int:
	var bound: Array[GameplayPredictionOperation] = under(key)
	for operation: GameplayPredictionOperation in bound:
		operation.accepted = true
	_forget(bound)
	return bound.size()


## The authority refused. Put back everything that stood on the guess.
##
## In dependency order, and only the parts still owed: an operation already
## accepted is not this machine's to take back, and reversing it would undo
## state the authority itself sent.
func reject(key: GameplayPredictionKey, asc: AbilitySystemComponent) -> int:
	var owed: Array[GameplayPredictionOperation] = under(key)
	var reversed_count: int = 0
	for operation: GameplayPredictionOperation in owed:
		if operation.reverse(asc):
			reversed_count += 1
	_forget(owed)
	return reversed_count


func _forget(operations: Array[GameplayPredictionOperation]) -> void:
	for operation: GameplayPredictionOperation in operations:
		_written.erase(operation)


## How much this machine still owes an answer on.
func size() -> int:
	return _written.size()


func is_empty() -> bool:
	return _written.is_empty()


func clear() -> void:
	_written.clear()
