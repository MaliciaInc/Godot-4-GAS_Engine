## Several messages that arrive together, gathered on one machine and applied
## whole on another.
##
## An activation is not one message. It is the activation, what it cost, what it
## put on cooldown and what it confirmed, and a peer that saw three of those
## four shows a character mid-cast with no cooldown - which corrects itself a
## frame later and looks like a bug the whole time.
##
## Composed into GameplayNetworkRuntime the way the request and state layers
## are. The runtime is still the one door to a network.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetBatchRuntime extends RefCounted

var net: GameplayNetworkRuntime = null

## What is being gathered, when anything is. Null when nothing is.
var _batch: GameplayNetBatch = null

## How many begins are open. Only the outermost one sends: an activation that
## batches, calling a commit that batches, is one group rather than two, and the
## inner one closing must not put half of it on the wire.
var _depth: int = 0


## Take one message into the batch, if one is open.
##
## Answers whether it was taken. False means the caller should send it now,
## which is what the runtime does with it.
func gather(message: GameplayNetMessage) -> bool:
	if _batch == null or message.kind == GameplayNetMessage.Kind.BATCH:
		return false
	_batch.messages.append(message)
	return true


## Start gathering, so what follows arrives together or not at all.
##
## Nested begins raise a depth rather than starting a second batch: an
## activation that groups its own messages, calling a commit that groups its
## own, is one group - and the inner close putting half of it on the wire is
## exactly the partially applied character the grouping exists to prevent.
func begin() -> void:
	_depth += 1
	if _batch == null:
		_batch = GameplayNetBatch.new()


## Stop gathering, and send what was gathered.
##
## Answers whether anything was sent. Nothing is sent from an inner close, and
## nothing is sent for a batch nobody put anything in - a sender that opened one
## and had nothing to say is not bandwidth worth spending.
func finish() -> bool:
	if _depth == 0:
		return false
	_depth -= 1
	if _depth > 0:
		return false

	var gathered: GameplayNetBatch = _batch
	_batch = null
	if gathered == null or not gathered.is_sendable():
		return false

	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.BATCH, gathered.messages[0].entity
	)
	message.payload[GameplayNetMessage.BATCH_KEY] = gathered.to_wire()
	message.payload[GameplayNetMessage.ATOMIC_KEY] = gathered.atomic
	net.publish(message)
	return true


func is_gathering() -> bool:
	return _depth > 0


## Close a batch somebody left open, from wherever this runtime is being
## ticked.
##
## One route, and it is this one: the runtime is a RefCounted with no frame of
## its own, and inventing a `_process` for it would make every game that holds
## one hold a Node. Whoever ticks the ability system calls this.
func flush() -> bool:
	if _depth == 0:
		return false
	_depth = 1
	return finish()
## A batch, read whole and checked whole before any of it is applied.
##
## Three passes rather than one loop, and the order is the point. The batch is
## read - one unreadable member refuses all of it. Every member is then judged
## for shape, direction and identity, with nothing applied yet: a batch whose
## third message is addressed to somebody who is not here must not have applied
## its first two. Only then is any of it applied.
##
## An atomic batch stops at the first member the game itself refuses, because
## the members are halves of one thing. A batch that said it is not atomic
## keeps going: its members are independent, and one being refused says nothing
## about the others.
func honour(
	message: GameplayNetMessage, from_peer: int = GameplayNetRegistry.NO_PEER
) -> bool:
	var atomic: bool = message.payload.get(GameplayNetMessage.ATOMIC_KEY, true) == true
	var batch: GameplayNetBatch = GameplayNetBatch.from_wire(
		message.payload.get(GameplayNetMessage.BATCH_KEY, []), atomic
	)
	if batch == null:
		net._refuse(message, GameplayNetBatch.REASON_MEMBER_REFUSED)
		return false

	for member: GameplayNetMessage in batch.messages:
		if not would_accept(member, from_peer):
			net._refuse(message, GameplayNetBatch.REASON_MEMBER_REFUSED)
			return false

	var applied: int = 0
	for member: GameplayNetMessage in batch.messages:
		if net.receive_from_peer(member, from_peer):
			applied += 1
		elif batch.atomic:
			# What is already applied stays: undoing an application is what the
			# prediction journal is for, and this is the authority speaking. The
			# rest of the batch does not happen.
			net._refuse(message, GameplayNetBatch.REASON_MEMBER_REFUSED)
			return false
	return applied > 0


## Whether this message would be judged worth acting on, without acting on it.
##
## The same three questions `net.receive` asks before it does anything: is it whole,
## is it travelling the way its kind travels, and is it about somebody this
## machine knows. Asked separately so that a batch can ask them of every member
## before applying the first.
func would_accept(
	message: GameplayNetMessage, from_peer: int = GameplayNetRegistry.NO_PEER
) -> bool:
	if message == null or not message.is_complete():
		return false
	if not GameplayNetAuthority.accepts(net.role, message):
		return false
	if not net._identified(message, from_peer):
		return false
	return net.registry.asc_for(message.entity) != null
