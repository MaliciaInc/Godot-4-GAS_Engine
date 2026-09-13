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

## The guesses anything recorded right now belongs to, nearest first.
##
## A window is the boundary a rejection unwinds. Everything between the open
## and the close is one guess's doing, so a game that predicts five things
## does not have to carry the key through five call sites - and what a
## refusal has to take back is an unambiguous set, in the order it was
## written and no other.
##
## A stack rather than one key: a guess predicted while an earlier one is
## still waiting on its answer is a guess made because of that one, not a
## second, unrelated boundary competing for the same slot. Nesting it - with
## `next_key_in_window` supplying the parent - is what lets rejecting the
## outer guess take the inner one's doing with it, the same way rejecting any
## key already takes what stands on it; refusing the second open would only
## have hidden that the two were ever related.
var _window_stack: Array[GameplayPredictionKey] = []


## The next key for this peer, standing on `parent` when it stands on anything.
func next_key(peer: int, parent: GameplayPredictionKey = null) -> GameplayPredictionKey:
	_counted += 1
	if parent != null:
		return parent.deriving(_counted)
	return GameplayPredictionKey.of(peer, _counted)


## The innermost open window, or null when none is.
func current_window() -> GameplayPredictionKey:
	return null if _window_stack.is_empty() else _window_stack[-1]


## The next key for `peer`, standing on whichever window is open right now -
## or on nothing, when none is.
##
## The convenience `next_key` itself does not give: a caller nesting a guess
## inside another one wants the window it is nesting under supplied for it,
## not remembered and passed back in by hand at every call site that predicts
## while something else is still in flight.
func next_key_in_window(peer: int) -> GameplayPredictionKey:
	return next_key(peer, current_window())


## Start attributing whatever happens next to this guess, nested inside
## whichever window is already open.
##
## Answers whether it opened - always, for a valid key, now that a second one
## nests rather than being refused. A key built by `next_key_in_window`
## already stands on the window it is nesting inside of, so what pushing it
## here adds is only that later work attributes to the new, innermost guess
## until it closes - not that the two guesses become related, which the key
## itself already made true.
func open_window(key: GameplayPredictionKey) -> bool:
	if key == null or not key.is_valid():
		return false
	_window_stack.append(key)
	return true


## Stop this window. Answers whether it was actually open.
##
## Found by identity rather than required to be innermost: each window is one
## guess's own round trip to the authority, concurrent nested guesses answer
## in whichever order their own network traffic happens to, and an outer
## guess answered before the inner one it is standing under has nothing to
## wait for - the inner is still exactly as open, and still `current_window`,
## once the outer is gone. Only a key nothing here ever opened fails to be
## found at all, which is the one shape closing somebody else's window ever
## took.
func close_window(key: GameplayPredictionKey) -> bool:
	if key == null:
		return false
	for index: int in range(_window_stack.size()):
		if _window_stack[index].same_as(key):
			_window_stack.remove_at(index)
			return true
	return false


## Write down one thing this machine did ahead of the answer.
##
## An operation that names no guess of its own belongs to the innermost open
## window, which is what a window is for. One that names a guess keeps it: an
## operation deriving from a key inside somebody else's window is still that
## key's, and quietly re-parenting it would unwind it at the wrong time.
func record(operation: GameplayPredictionOperation) -> void:
	if operation == null:
		return
	if operation.key == null or not operation.key.is_valid():
		operation.key = current_window()
	if operation.key == null or not operation.key.is_valid():
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
	_forget(bound, key)
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
	_forget(owed, key)
	return reversed_count


## Drop what has been answered for, and close the window it was open under.
##
## Closing it here is what makes a second answer harmless: a window left open
## under a guess that has been settled would go on attributing later work to
## a key nothing is waiting on, and the next rejection would unwind it.
func _forget(
	operations: Array[GameplayPredictionOperation], key: GameplayPredictionKey
) -> void:
	for operation: GameplayPredictionOperation in operations:
		_written.erase(operation)
	close_window(key)


## How much this machine still owes an answer on.
func size() -> int:
	return _written.size()


func is_empty() -> bool:
	return _written.is_empty()


func clear() -> void:
	_written.clear()
	_window_stack.clear()
