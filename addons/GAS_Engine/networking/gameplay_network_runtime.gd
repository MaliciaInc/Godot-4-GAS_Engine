## The one place the ability system talks to another machine.
##
## Everything that crosses a network goes through here: grants, revokes, a
## client asking to activate, the authority answering, and the state that
## follows. Nothing in `effects/` or `abilities/` sends anything, and that is
## the point rather than a tidiness preference - RPCs scattered through a
## system are a system whose network behaviour can only be read by reading all
## of it, and whose authority rules end up written slightly differently in
## eleven places.
##
## It owns no transport. Messages come out of `message_ready` and go in through
## `receive()`, and how they travel is the game's business: this addon has no
## opinion about ENet, Steam, WebRTC or a recording of yesterday's match, and a
## runtime that picked one would be untestable without it.
##
## What it does own is the refusals. Every message is checked for direction,
## for ownership and for having been seen before, and a message that fails any
## of those is dropped rather than half-applied.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetworkRuntime extends RefCounted

## A message this machine wants sent. The game carries it.
signal message_ready(message: GameplayNetMessage)

## A message that arrived and was not acted on, and why. For a game that wants
## to log it and for the tests that assert the refusals happened.
signal message_refused(message: GameplayNetMessage, reason: StringName)

## An entity was granted an ability by the authority, on this machine.
signal ability_granted_by_authority(entity: GameplayNetEntityId, definition: Resource)

## An entity's grant was taken away.
signal ability_revoked_by_authority(entity: GameplayNetEntityId, definition: Resource)

## The authority answered a request this machine made, and which run it is.
##
## Emitted rather than acted on directly, because what waits for an answer is
## not the runtime: it is whatever the ability arranged - a sync point, a
## cast bar, a game's own code - and each of those knows which guess is its
## own. The runtime knowing them all would be the runtime knowing about
## abilities.
signal activation_answered(
	key: GameplayPredictionKey, activation: GameplayNetActivationId, accepted: bool
)

## An activation on another machine started or stopped, and this machine was
## told about it.
##
## Only for the grants whose ReplicationPolicy says REPLICATE_YES, and only on
## the peer that owns the entity - what most abilities are doing between
## starting and ending is nobody else's business. Announced rather than acted
## on: a client that started an ability because it was told one was running
## would be a client running what the authority never asked it to. This is a
## cast bar being told, which is the reason an ability says REPLICATE_YES.
signal activation_replicated(
	entity: GameplayNetEntityId, definition: GameplayNetDefinitionId, running: bool
)

## A request this machine accepted, for whoever runs abilities here.
##
## The authority answers requests; it does not activate anything, because what
## activating means - which grant, with what context, aimed at what - belongs to
## the game rather than to a networking layer. So an acceptance is announced and
## the game acts on it, exactly the way a client acts on the answer to its own
## guess. Without this the authority says yes to a request and then nothing
## happens on the machine that said it, which reads as a dropped packet.
signal activation_requested(
	entity: GameplayNetEntityId, definition: Resource, key: GameplayPredictionKey
)

## A reading of an entity's state was written onto it. Carries the state as
## well as the entity, because what a game shows - which buffs, how long left
## - is in the reading and deliberately not written into the component.
signal state_applied(entity: GameplayNetEntityId, state: GameplayNetState)

const REASON_WRONG_DIRECTION: StringName = &"wrong_direction"
## The codec already has a word for a message missing what its kind
## requires, and one refusal deserves one word: a caller matching on the
## reason should not have to know which layer noticed.
const REASON_INCOMPLETE: StringName = GameplayNetCodec.REASON_INCOMPLETE
const REASON_UNKNOWN_ENTITY: StringName = &"unknown_entity"
const REASON_UNKNOWN_DEFINITION: StringName = &"unknown_definition"
const REASON_NOT_OWNED: StringName = &"not_owned"
const REASON_POLICY: StringName = &"policy_refuses"
const REASON_ALREADY_APPLIED: StringName = &"already_applied"
const REASON_OUT_OF_ORDER: StringName = &"out_of_order"
const REASON_NOTHING_TO_UPDATE: StringName = &"nothing_to_update"

## A message asking on behalf of an entity this machine did not hear it from.
##
## The one check a message's own content can never answer, because the
## content is exactly what a forger controls. The transport that carried the
## packet knows who sent it - a real socket cannot be told to lie about that -
## and this is the peer that answer names, checked against what the message
## itself claims: a prediction key naming somebody else, or an entity this
## peer does not own.
const REASON_PEER_MISMATCH: StringName = &"peer_mismatch"

## Why an aim was not accepted. Three, because they are three different
## things a client can be wrong about and a game reacting to a refusal
## wants to know which: somebody who is not here, somebody who is here and
## out of reach, and a claim no provider could have produced.
const REASON_TARGET_UNKNOWN: StringName = &"target_unknown"
const REASON_TARGET_UNREACHABLE: StringName = &"target_unreachable"
const REASON_TARGET_INVALID: StringName = &"target_invalid"

## Which peer a client talks to. Godot's own convention, and the only peer a
## client is entitled to say anything to.
const AUTHORITY_PEER: int = 1

var role: GameplayNetAuthority.Role = GameplayNetAuthority.Role.CLIENT

## This machine's own peer number, as its transport calls it.
var peer: int = GameplayNetRegistry.NO_PEER

var registry: GameplayNetRegistry = GameplayNetRegistry.new()

## How much of an entity's state a peer is told.
##
## MIXED by default, which is what most games want and is also most of the
## bandwidth: what a character is doing is public, the twelve modifiers
## behind it are the owner's business.
var replication_mode: GameplayNetReplication.Mode = GameplayNetReplication.Mode.MIXED

## What each peer was last told about each entity, so the next delta knows
## what changed. Keyed by entity and peer together: two peers are told
## different things under MIXED, so one record of "what was sent" would make
## the second peer's delta a diff against the first peer's news.

## The last reading of each entity this machine has applied, so an older one
## arriving late is ignored rather than undoing a newer one.

## What this machine did before it was allowed to, and still owes an answer
## on. Empty on an authority, which never predicts because it never asks.
## How packets leave and arrive, when anything is carrying them.
##
## Null in a single-player game and in every test that drives two runtimes
## directly, and that is the baseline rather than a degraded mode: `message_ready`
## still announces everything, and a caller carrying messages itself is what the
## suite has always done.
var transport: GameplayNetTransport = null

## Several messages gathered to arrive together.
var batching: GameplayNetBatchRuntime = GameplayNetBatchRuntime.new()

## What each peer has been told about each entity.
var state: GameplayNetStateRuntime = GameplayNetStateRuntime.new()

## What a client may ask for beyond an activation, and what is done with it.
var requests: GameplayNetRequestRuntime = GameplayNetRequestRuntime.new()

## Granting an ability, asking to run one, and answering that ask.
var activation: GameplayNetActivationRuntime = GameplayNetActivationRuntime.new()

var journal: GameplayPredictionJournal = GameplayPredictionJournal.new()

## What has already been acted on.
##
## Not a sequence number: a message is identified by what it says, so applying
## it twice is refused whether the duplicate arrived because the transport
## repeated it, because it was reordered around something else, or because a
## client retried a request it had not heard back about. A counter would only
## catch the first of those.
var _applied: Dictionary[String, bool] = {}

## Which fingerprints in `_applied` are about which entity, so forgetting an
## entity can take its own fingerprints with it rather than leaving them to
## collide with whoever is given that id next. `_applied` itself stays keyed
## by fingerprint, unchanged, because that is the lookup every message makes;
## this is the index the one caller that needs to walk it backwards uses.
var _applied_by_entity: Dictionary[int, Array] = {}


## Start carrying messages over this transport, and stop using the last one.
##
## Disconnected before connected: binding twice used to leave two connections to
## the same signal, and every packet then arrived twice - which for an
## activation request is one ability activating twice.
func set_transport(value: GameplayNetTransport) -> void:
	if transport != null and transport.packet_received.is_connected(_on_packet_received):
		transport.packet_received.disconnect(_on_packet_received)
	transport = value
	if transport != null:
		transport.packet_received.connect(_on_packet_received)


#region Several messages that arrive together
## The rules live in GameplayNetBatchRuntime; these are the names a caller
## knows.
func begin_batch() -> void:
	batching.begin()


func end_batch() -> bool:
	return batching.finish()


func is_batching() -> bool:
	return batching.is_gathering()


## Close a batch somebody left open, from wherever this runtime is being ticked.
##
## One route, and it is this one: the runtime is a RefCounted with no frame of
## its own, and inventing a `_process` for it would make every game that holds
## one hold a Node. Whoever ticks the ability system calls this.
func flush_deferred_batch() -> bool:
	return batching.flush()
#endregion


#region On and off the wire
## Announce a message, and put it on the wire when there is one.
##
## One funnel rather than a send beside each emit: there are four places that
## produce a message and a fifth would be written without the send.
func publish(message: GameplayNetMessage) -> void:
	message_ready.emit(message)
	if transport == null:
		return
	# Gathered rather than sent while a batch is open. Announced either way:
	# a listener on this machine is watching what happened, not what left.
	if batching.gather(message):
		return
	_send(message)


## One message to whoever should hear it.
##
## An authority tells everybody, because state is about an entity rather than
## about a conversation. A client tells the authority, because there is nobody
## else it is entitled to say anything to.
func _send(message: GameplayNetMessage) -> void:
	var packet: PackedByteArray = GameplayNetCodec.encode(message)
	if packet.is_empty():
		return
	for id: int in _recipients(message):
		transport.send(packet, id, _must_arrive(message))


## Who this message goes to.
##
## A client says everything to the authority and to nobody else. An authority
## says most things to everybody - and a state reading to the one peer it was
## computed for, because what a peer may be told about an entity depends on
## whether it owns it, and broadcasting the owner's reading is broadcasting the
## owner's answer to everybody.
func _recipients(message: GameplayNetMessage) -> Array[int]:
	if not is_authority():
		return [AUTHORITY_PEER] as Array[int]
	if message.to_peer != GameplayNetMessage.EVERYBODY:
		return [message.to_peer] as Array[int]
	return transport.peers()


## Whether losing this message matters.
##
## A snapshot may be dropped: the next one says everything the lost one did. A
## delta may not - it carries what changed, and what changed is gone once the
## packet is. Everything else is an event, and an event that never arrives is an
## ability that never ran.
func _must_arrive(message: GameplayNetMessage) -> bool:
	return message.kind != GameplayNetMessage.Kind.STATE_SNAPSHOT


## A packet arrived. Whatever it decodes to goes through the one door.
##
## A packet that does not decode is refused with the codec's own reason rather
## than dropped: a peer sending a version this build does not speak is a thing
## somebody has to be able to find out.
func _on_packet_received(packet: PackedByteArray, from_peer: int) -> void:
	var message: GameplayNetMessage = GameplayNetCodec.decode(packet)
	if message == null:
		message_refused.emit(null, GameplayNetCodec.last_refusal)
		return
	receive_from_peer(message, from_peer)
#endregion


func _init() -> void:
	requests.net = self
	state.net = self
	batching.net = self
	activation.net = self


func is_authority() -> bool:
	return role == GameplayNetAuthority.Role.AUTHORITY


#region Wiring
## Put a component on the network under an id, and tell it who to talk through.
##
## The component keeps exactly one reference to a runtime, or null. More than
## one would be a component two authorities disagree about; a reference held
## somewhere else would be a component whose network can be changed without it
## knowing. Refused outright, before the registry is ever touched, when
## another runtime already holds that reference: registering the entity first
## and setting the reference after would leave this registry believing it owns
## an entity a second runtime's registry believes the same thing about.
func attach(
	asc: AbilitySystemComponent,
	id: GameplayNetEntityId,
	owner_peer: int = GameplayNetRegistry.NO_PEER
) -> bool:
	if asc != null and asc.network != null and asc.network != self:
		return false
	if not registry.register_entity(id, asc, owner_peer):
		return false
	asc.network = self
	return true


## Let go of one entity: the reference back to this runtime, and everything
## this runtime itself remembers about it. An id reused for a different
## character afterward starts from nothing rather than inheriting a run
## counter, a duplicate-message fingerprint or a stale reading that were
## really about whoever had it before.
func detach(asc: AbilitySystemComponent) -> void:
	if asc == null:
		return
	var id: GameplayNetEntityId = registry.entity_for(asc)
	_purge_entity_bookkeeping(id)
	if asc.network == self:
		asc.network = null


func _purge_entity_bookkeeping(id: GameplayNetEntityId) -> void:
	if id == null or not id.is_valid():
		return
	registry.forget_entity(id)
	state.forget(id)
	activation.forget(id)
	for seen: String in _applied_by_entity.get(id.value, []):
		_applied.erase(seen)
	_applied_by_entity.erase(id.value)


## Let go of everything. A runtime kept alive by a scene that has ended is a
## scene that cannot be freed.
##
## In this order: every component still pointing here is told first, while the
## registry that answers `registered_ascs()` still can - clearing the registry
## before that would let go of the very list this loop reads. The transport is
## unbound next, so a packet arriving after this call cannot invoke a runtime
## that is in the middle of forgetting itself. Only then are the caches
## cleared, which is safe to do in any order once nothing outside this object
## still has a reason to ask them anything.
func dispose() -> void:
	for asc: AbilitySystemComponent in registry.registered_ascs():
		if is_instance_valid(asc) and asc.network == self:
			asc.network = null
	set_transport(null)
	registry.clear()
	_applied.clear()
	_applied_by_entity.clear()
	state.forget()
	activation.clear()
	journal.clear()
#endregion


#region What the authority says
## Grant an ability to an entity, and tell the peers. Lives in
## `GameplayNetActivationRuntime` with the rest of the conversation it opens.
func grant(id: GameplayNetEntityId, definition: Resource) -> bool:
	return activation.grant(id, definition)


func revoke(id: GameplayNetEntityId, definition: Resource) -> bool:
	return activation.revoke(id, definition)
#endregion


#region What a client asks for
## Ask to activate, or run it, or neither - whichever the grant's policy says.
## Lives in `GameplayNetActivationRuntime`; this is the name a caller knows.
func start(asc: AbilitySystemComponent, definition: Resource) -> GameplayNetAuthority.Start:
	return activation.start(asc, definition)


## Letting go of an ability that replicates its input directly.
##
## Its own door because an activation request has no opposite, and an ability
## whose meaning is in the release - a charge, a hold - needs one. The rule
## lives in GameplayNetRequestRuntime with the rest of what a client asks for.
func release(asc: AbilitySystemComponent, definition: Resource) -> bool:
	return requests.release(asc, definition)
#endregion


#region What the peers are told about state
## Everything about an entity, as this peer may be told it.
func snapshot_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return state.snapshot_for(id, to_peer)


## What changed since that peer was last told, or null when nothing did.
func delta_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return state.delta_for(id, to_peer)
#endregion


#region What a client sends beyond a request
## The five of them live in GameplayNetRequestRuntime; these are the names a
## caller already knows, kept so that moving the layer moved nothing else.
func send_target_data(
	id: GameplayNetEntityId,
	data: GameplayAbilityTargetData,
	activation: GameplayNetActivationId = null,
	key: GameplayPredictionKey = null
) -> GameplayNetMessage:
	return requests.target_data(id, data, activation, key)


func send_generic_confirm(id: GameplayNetEntityId) -> GameplayNetMessage:
	return requests.generic_confirm(id)


func send_generic_cancel(id: GameplayNetEntityId) -> GameplayNetMessage:
	return requests.generic_cancel(id)


func send_gameplay_event(
	id: GameplayNetEntityId, event: GameplayEventData
) -> GameplayNetMessage:
	return requests.gameplay_event(id, event)


func send_input(
	id: GameplayNetEntityId, definition: Resource, input_id: int, pressed: bool
) -> GameplayNetMessage:
	return requests.input(id, definition, input_id, pressed)
#endregion


#region What arrives
## Act on a message that arrived with nobody vouching for who sent it.
##
## The direct-call door every test in this addon has always used: a caller
## that already knows which machine is which - because it is holding both
## runtimes itself - carries a message across without a transport, and there
## is nothing here for a transport to have told this machine. Real delivery
## goes through `receive_from_peer` instead, which is the one that checks.
func receive(message: GameplayNetMessage) -> bool:
	return _receive(message, GameplayNetRegistry.NO_PEER)


## Act on a message this machine's own transport says arrived from `from_peer`.
##
## The door a real packet reaches. `from_peer` is the one fact in this call a
## sender cannot forge - a socket does not let the far side claim to be
## somebody else - so it is what an asking message's own claims are checked
## against, rather than the other way round. `receive()` is the same door with
## nothing to check against, and exists for the callers that are the transport.
func receive_from_peer(message: GameplayNetMessage, from_peer: int) -> bool:
	return _receive(message, from_peer)


## One door, so every refusal is in one place and none of them is a check
## somebody remembered to write at a call site. Answers whether it was acted
## on; a refusal is announced through `message_refused` rather than returned in
## detail, because a caller carrying messages has nothing useful to do with the
## reason and a log does.
func _receive(message: GameplayNetMessage, from_peer: int) -> bool:
	if message == null or not message.is_complete():
		_refuse(message, REASON_INCOMPLETE)
		return false
	if not GameplayNetAuthority.accepts(role, message):
		_refuse(message, REASON_WRONG_DIRECTION)
		return false
	if not _identified(message, from_peer):
		_refuse(message, REASON_PEER_MISMATCH)
		return false

	if message.is_state():
		return state.apply(message)

	var seen: String = _fingerprint(message)
	if _applied.has(seen):
		_refuse(message, REASON_ALREADY_APPLIED)
		return false

	if not _act_on(message, from_peer):
		return false
	_applied[seen] = true
	var carried: Array = _applied_by_entity.get(message.entity.value, [])
	carried.append(seen)
	_applied_by_entity[message.entity.value] = carried
	return true


## Whether this message is who it claims to be, against the one thing its own
## content cannot lie about.
##
## Skipped outright when nobody is vouching for a sender - `from_peer` is
## `NO_PEER` for every direct call this addon's own suite makes, and for those
## the ownership rules below are the check, exercised without a transport in
## the loop at all. Checked only at the authority: a client hears grants and
## readings about entities it may not own at all, and REPLICATE_YES already
## restricts what a client is told about somebody else's run.
##
## Two questions, both answered against `from_peer` rather than against
## anything the message says about itself. A prediction key names the peer
## that minted it, and a key naming somebody else is a client asking on a
## stranger's guess. Ownership is checked for every kind a client asks the
## authority for, on top of that and not instead of it: a well-formed key for
## this peer's own earlier guess about somebody else's character is still
## somebody else's character.
##
## Not asked of an activation request: that kind already answers wrong-owner
## and forged-key requests with an explicit `ACTIVATION_REJECT`, in
## `_why_not`, which is where a client's guess is unwound from - a request
## silently dropped here instead would leave that guess waiting for ever.
func _identified(message: GameplayNetMessage, from_peer: int) -> bool:
	if from_peer == GameplayNetRegistry.NO_PEER or not is_authority():
		return true
	if message.kind == GameplayNetMessage.Kind.ACTIVATION_REQUEST:
		return true
	if not GameplayNetAuthority.ASKED_OF_THE_AUTHORITY.has(message.kind) and message.kind != GameplayNetMessage.Kind.GAMEPLAY_EVENT:
		return true
	if message.is_predicted() and message.prediction_key.peer != from_peer:
		return false
	return registry.is_owned_by(message.entity, from_peer)


## A reading of an entity's state, written on if it is news.
##
## Ordered rather than deduplicated. A state message is safe to apply twice -
## it carries values, not increments - so what has to be refused is not the
## repeat but the older reading arriving after a newer one, which would put a
## character back the way it was and leave it there.
##
## And a delta before any snapshot is refused outright: a delta is what
## changed, and a peer with nothing for it to have changed from would apply
## half a character and believe it had all of one. That is the late joiner,
## and the answer is that it is sent a snapshot first.
func _act_on(message: GameplayNetMessage, from_peer: int = GameplayNetRegistry.NO_PEER) -> bool:
	var id: GameplayNetEntityId = message.entity
	if registry.asc_for(id) == null:
		_refuse(message, REASON_UNKNOWN_ENTITY)
		return false

	match message.kind:
		GameplayNetMessage.Kind.GRANT, GameplayNetMessage.Kind.REVOKE:
			return _announce_grant(message)
		GameplayNetMessage.Kind.ACTIVATION_REQUEST:
			return activation.honour_request(message, from_peer)
		GameplayNetMessage.Kind.ACTIVATION_CONFIRM:
			journal.accept(message.prediction_key)
			activation_answered.emit(message.prediction_key, message.activation, true)
			return true
		GameplayNetMessage.Kind.ACTIVATION_REJECT:
			journal.reject(message.prediction_key, registry.asc_for(message.entity))
			activation_answered.emit(message.prediction_key, message.activation, false)
			return true
		GameplayNetMessage.Kind.BATCH:
			return batching.honour(message, from_peer)
		GameplayNetMessage.Kind.TARGET_DATA:
			return requests.honour_target_data(message)
		GameplayNetMessage.Kind.GENERIC_CONFIRM:
			registry.asc_for(id).input_confirm()
			return true
		GameplayNetMessage.Kind.GENERIC_CANCEL:
			# The generic no names no ability, so the refusal cannot be the
			# message: it is per-activation, and the ASC applies it.
			registry.asc_for(id).input_cancel(true)
			return true
		GameplayNetMessage.Kind.GAMEPLAY_EVENT:
			return requests.honour_event(message)
		GameplayNetMessage.Kind.INPUT_PRESSED, GameplayNetMessage.Kind.INPUT_RELEASED:
			return requests.honour_input(message)
		_:
			return true


func _announce_grant(message: GameplayNetMessage) -> bool:
	var definition: Resource = registry.definition_for(message.definition)
	if definition == null:
		_refuse(message, REASON_UNKNOWN_DEFINITION)
		return false
	if message.kind == GameplayNetMessage.Kind.GRANT:
		ability_granted_by_authority.emit(message.entity, definition)
	else:
		ability_revoked_by_authority.emit(message.entity, definition)
	return true


## What makes two messages the same message.
##
## Everything that decides what acting on it would do, and nothing else: the
## same grant sent twice is one grant, and a request retried because its answer
## was lost is one request.
func _fingerprint(message: GameplayNetMessage) -> String:
	var parts: PackedStringArray = PackedStringArray([
		str(message.kind),
		str(message.entity.to_wire()),
		str(message.definition.to_wire()) if message.definition != null else "",
		str(message.activation.sequence) if message.activation != null else "",
		str(message.prediction_key.value) if message.prediction_key != null else "",
	])
	return "|".join(parts)


func _refuse(message: GameplayNetMessage, reason: StringName) -> void:
	message_refused.emit(message, reason)
#endregion
