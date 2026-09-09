## Several messages that arrive together, and either all happen or none do.
##
## An activation is not one message: it is the activation, what it cost, what it
## put on cooldown and what it confirmed. A peer that saw three of those four
## shows a character mid-cast with no cooldown, which corrects itself a frame
## later and looks like a bug the whole time.
##
## What is checked is the order the receiver does things in. A batch is read
## whole, then judged whole, and only then applied - because a batch whose third
## message is addressed to somebody who is not here must not have applied its
## first two.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ENTITY: int = 31
const OWNING_PEER: int = 2

var authority: NetBench = null
var client: GameplayNetworkRuntime = null
var wires: Array[LoopbackTransport] = []
var refusals: Array[StringName] = []


func before_each() -> void:
	refusals = []
	authority = NetBench.built(self, "Batched")
	autofree(authority.fixture.owner)
	authority.runtime.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			refusals.append(reason)
	)

	client = authority.client()
	wires = LoopbackTransport.pair()
	client.set_transport(wires[1])


func after_each() -> void:
	authority.dispose()
	client.dispose()
	authority = null
	client = null
	wires = []


#region Gathering
## Nothing leaves while a batch is open, and one packet leaves when it closes.
func test_what_is_gathered_leaves_as_one_packet() -> void:
	client.begin_batch()
	assert_true(client.is_batching(), "a batch is open")

	client.send_generic_confirm(authority.entity)
	client.send_generic_cancel(authority.entity)
	assert_eq(wires[1].sent.size(), 0, "and nothing has left")

	assert_true(client.end_batch(), "closing it sent something")
	assert_eq(wires[1].sent.size(), 1, "one packet, not two")

	var sent: GameplayNetMessage = GameplayNetCodec.decode(wires[1].sent[0])
	assert_eq(sent.kind, GameplayNetMessage.Kind.BATCH, "and it is a batch")


## Everything gathered is still announced on the machine that gathered it.
##
## A listener here is watching what happened rather than what left, and a game
## that batched would otherwise stop seeing its own messages.
func test_what_is_gathered_is_still_announced_here() -> void:
	var heard: Array[GameplayNetMessage] = []
	client.message_ready.connect(func(message: GameplayNetMessage) -> void:
		heard.append(message)
	)

	client.begin_batch()
	client.send_generic_confirm(authority.entity)
	client.end_batch()

	assert_eq(heard.size(), 2, "the confirm, and the batch that carried it")


## Two begins deep with something gathered at each, which is the state both
## the nesting rule and the flush door are about.
func _nested_with_one_at_each_depth() -> void:
	client.begin_batch()
	client.send_generic_confirm(authority.entity)
	client.begin_batch()
	client.send_generic_cancel(authority.entity)


## A nested begin is one batch, and the inner close sends nothing.
##
## An activation that groups its own messages, calling a commit that groups its
## own, is one group - and the inner close putting half of it on the wire is
## exactly what the grouping exists to prevent.
func test_a_nested_batch_is_one_batch() -> void:
	_nested_with_one_at_each_depth()

	assert_false(client.end_batch(), "the inner close sent nothing")
	assert_eq(wires[1].sent.size(), 0, "and nothing left")
	assert_true(client.is_batching(), "the batch is still open")

	assert_true(client.end_batch(), "the outer one sent it")
	assert_eq(wires[1].sent.size(), 1, "as one packet")


## A batch nobody put anything in is not sent.
func test_an_empty_batch_is_not_sent() -> void:
	client.begin_batch()

	assert_false(client.end_batch(), "there was nothing to send")
	assert_eq(wires[1].sent.size(), 0, "so nothing was")


## Closing a batch nobody opened does nothing.
func test_closing_a_batch_nobody_opened_does_nothing() -> void:
	assert_false(client.end_batch(), "there was nothing open")
	assert_false(client.is_batching(), "and there still is not")


## Whoever ticks the ability system can close one somebody left open.
##
## One route rather than a `_process` of its own: the runtime is a RefCounted
## with no frame, and giving it one would make every game that holds one hold a
## Node.
func test_a_batch_left_open_can_be_flushed_by_whoever_ticks() -> void:
	_nested_with_one_at_each_depth()

	assert_true(client.flush_deferred_batch(), "it was flushed however deep it was")
	assert_false(client.is_batching(), "and is no longer open")
	assert_eq(wires[1].sent.size(), 1, "with one packet out")


## Flushing when nothing is open does nothing.
func test_flushing_nothing_does_nothing() -> void:
	assert_false(client.flush_deferred_batch(), "there was nothing to flush")
#endregion


#region Applying
## Everything in a batch is applied.
func test_everything_in_a_batch_is_applied() -> void:
	var confirmed: Array[bool] = []
	var cancelled: Array[bool] = []
	authority.asc().generic_confirmed.connect(func() -> void: confirmed.append(true))
	authority.asc().generic_cancelled.connect(func() -> void: cancelled.append(true))

	assert_true(authority.runtime.receive(_a_batch_of([
		GameplayNetMessage.Kind.GENERIC_CONFIRM,
		GameplayNetMessage.Kind.GENERIC_CANCEL,
	])), "the batch was applied")

	assert_eq(confirmed.size(), 1, "the confirm happened")
	assert_eq(cancelled.size(), 1, "and so did the cancel")


## A batch with one member addressed to nobody applies none of it.
##
## The rule with teeth. Judged whole before any of it is applied, so a batch
## whose second message is about somebody who is not here does not leave the
## first one applied.
func test_a_batch_with_one_bad_member_applies_none_of_it() -> void:
	var confirmed: Array[bool] = []
	authority.asc().generic_confirmed.connect(func() -> void: confirmed.append(true))

	var batch: GameplayNetBatch = GameplayNetBatch.new()
	batch.messages = [
		GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, authority.entity),
		GameplayNetMessage.of(
			GameplayNetMessage.Kind.GENERIC_CANCEL, GameplayNetEntityId.of(9999)
		),
	]

	assert_false(authority.runtime.receive(_wrapping(batch)), "the batch was refused")
	assert_eq(confirmed.size(), 0, "and the member that would have worked did not run")
	assert_eq(
		refusals, [GameplayNetBatch.REASON_MEMBER_REFUSED] as Array[StringName],
		"saying which kind of refusal it was"
	)


## A batch carrying something that is not a message is refused whole.
func test_a_batch_carrying_something_unreadable_is_refused_whole() -> void:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.BATCH, authority.entity
	)
	message.payload[GameplayNetMessage.BATCH_KEY] = [{"not": "a message"}]

	assert_false(authority.runtime.receive(message), "it was refused")
	assert_eq(refusals, [GameplayNetBatch.REASON_MEMBER_REFUSED] as Array[StringName])


## A batch bigger than the limit is refused.
##
## A limit rather than none, because a batch is read whole before any of it is
## applied: an unbounded one is an unbounded allocation a peer can ask for.
func test_a_batch_past_the_limit_is_refused() -> void:
	var batch: GameplayNetBatch = GameplayNetBatch.new()
	for _index: int in GameplayNetBatch.MAX_MESSAGES + 1:
		batch.messages.append(
			GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, authority.entity)
		)

	assert_false(batch.is_sendable(), "it is not one to send")
	assert_null(
		GameplayNetBatch.from_wire(batch.to_wire()), "nor one to read"
	)


##     [what the batch says of itself, atomic, what still ran, was any applied]
func _atomicity_cases() -> Array:
	return [
		["one whose members are independent", false, 1, true],
		["one that stands or falls together", true, 0, false],
	]


## What a member the game refused does to the members after it.
##
## A batch that said it is not atomic keeps going: its members are independent
## operations, one being refused says nothing about the others, and saying so
## is the only reason a sender would mark one. An atomic batch stops there,
## because its members are halves of one thing.
##
## Refused by the game rather than by shape, both times: a request for a
## definition the authority has never registered gets past every check that
## reads a message and is turned down by the one that acts on it, which is the
## only refusal that happens mid-application.
func test_atomicity_decides_what_happens_after_a_refused_member() -> void:
	var rows: Array = _atomicity_cases()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var atomic: bool = row[1]
		var still_ran: int = row[2]
		var any_applied: bool = row[3]

		before_each()
		var confirmed: Array[bool] = []
		authority.asc().generic_confirmed.connect(func() -> void: confirmed.append(true))

		var batch: GameplayNetBatch = GameplayNetBatch.new()
		batch.atomic = atomic
		batch.messages = [
			_a_request_for_nothing(),
			GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, authority.entity),
		]

		assert_eq(authority.runtime.receive(_wrapping(batch)), any_applied, described)
		assert_eq(
			confirmed.size(), still_ran,
			"%s: what ran after the refusal" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "both kinds of batch were offered")
#endregion


#region Getting there
func _a_batch_of(kinds: Array) -> GameplayNetMessage:
	var batch: GameplayNetBatch = GameplayNetBatch.new()
	for kind: GameplayNetMessage.Kind in kinds:
		batch.messages.append(GameplayNetMessage.of(kind, authority.entity))
	return _wrapping(batch)


func _wrapping(batch: GameplayNetBatch) -> GameplayNetMessage:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.BATCH, authority.entity
	)
	message.payload[GameplayNetMessage.BATCH_KEY] = batch.to_wire()
	message.payload[GameplayNetMessage.ATOMIC_KEY] = batch.atomic
	return message


## A request the authority will refuse: it names a definition nobody registered.
func _a_request_for_nothing() -> GameplayNetMessage:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, authority.entity
	)
	message.definition = GameplayNetDefinitionId.from_wire(4242)
	return message
#endregion
