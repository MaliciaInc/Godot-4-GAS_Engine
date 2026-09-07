## The wire between machines, and everything a wire does.
##
## The engine's network layer owns no transport on purpose, which leaves a hole
## exactly the shape of this: something that carries messages from one runtime
## to the others and can be told to misbehave. A real socket does all of this
## without being asked - it repeats, it reorders, it loses things, it takes
## time - and none of those are reachable from a suite that hands messages
## straight across.
##
## Every machine hears everything, the way a broadcast does - the sender
## included. Who acts on what is not this fixture's business: the direction
## rules already refuse a client that is sent a request and an authority that
## is sent a grant, so everything a machine could hand itself is refused by
## the engine before it reaches anything. A link that skipped the sender
## would look more like a socket and prove less, because the skip would be
## doing work nothing could tell had been done.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name NetLink extends RefCounted

## Deliver everything twice.
var duplicates: bool = false

## Deliver what is held in the opposite order.
var reorders: bool = false

## Swallow this many messages before carrying any.
var drops_next: int = 0

## Hold everything until `flush()`, which is what latency looks like from
## inside a test: the sender has sent and nobody has received.
var holds: bool = false

## How many messages have actually been handed to a receiver.
var delivered: int = 0

## How many were swallowed, so a test can say the drop happened rather than
## assuming it from the silence.
var dropped: int = 0

## Who is being handed messages, and who is wired up at all. Two lists
## because a machine can be out of earshot without being disconnected -
## which is what a late joiner is, and the only way to produce one.
var _machines: Array[GameplayNetworkRuntime] = []
var _connected: Array[GameplayNetworkRuntime] = []
var _waiting: Array[GameplayNetMessage] = []


func join(runtime: GameplayNetworkRuntime) -> void:
	if runtime == null or _machines.has(runtime):
		return
	_machines.append(runtime)
	if _connected.has(runtime):
		return
	_connected.append(runtime)
	runtime.message_ready.connect(_carry.bind(runtime))


## Stop handing this machine anything, without unwiring it.
##
## A machine that joins the game after something has already happened is a
## machine that missed it, and missing something is the only way to be a late
## joiner. It can still send.
func leave(runtime: GameplayNetworkRuntime) -> void:
	_machines.erase(runtime)


## Take a message from one machine. Delivered now, or held for `flush()`.
func _carry(message: GameplayNetMessage, _from: GameplayNetworkRuntime) -> void:
	if drops_next > 0:
		drops_next -= 1
		dropped += 1
		return
	_waiting.append(message)
	if not holds:
		flush()


## Hand over everything that is waiting, and say how many were handed over.
func flush() -> int:
	var carried: Array[GameplayNetMessage] = _waiting.duplicate()
	_waiting.clear()

	var order: Array[int] = []
	for index: int in carried.size():
		order.append(index)
	if reorders:
		order.reverse()

	var handed: int = 0
	for index: int in order:
		handed += _hand(carried[index])
		if duplicates:
			handed += _hand(carried[index])
	return handed


func _hand(message: GameplayNetMessage) -> int:
	var handed: int = 0
	for machine: GameplayNetworkRuntime in _machines:
		machine.receive(message)
		delivered += 1
		handed += 1
	return handed


## Carry everything, including whatever the carrying produces.
##
## An answer is a message too. A test that flushed once would deliver the
## request and stop, leaving the reply sitting on the wire - which looks
## exactly like an authority that never answered.
func drain(rounds: int = 8) -> void:
	var left: int = rounds
	while not is_quiet() and left > 0:
		flush()
		left -= 1


func is_quiet() -> bool:
	return _waiting.is_empty()
