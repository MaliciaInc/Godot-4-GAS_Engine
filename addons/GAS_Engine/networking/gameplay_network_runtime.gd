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

## What each peer has been told about each entity.
var state: GameplayNetStateRuntime = GameplayNetStateRuntime.new()

## What a client may ask for beyond an activation, and what is done with it.
var requests: GameplayNetRequestRuntime = GameplayNetRequestRuntime.new()

var journal: GameplayPredictionJournal = GameplayPredictionJournal.new()

## The authority's count of runs per entity, which is what an activation id
## is made of.
var _runs: Dictionary[int, int] = {}

## What has already been acted on.
##
## Not a sequence number: a message is identified by what it says, so applying
## it twice is refused whether the duplicate arrived because the transport
## repeated it, because it was reordered around something else, or because a
## client retried a request it had not heard back about. A counter would only
## catch the first of those.
var _applied: Dictionary[String, bool] = {}


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


#region On and off the wire
## Announce a message, and put it on the wire when there is one.
##
## One funnel rather than a send beside each emit: there are four places that
## produce a message and a fifth would be written without the send.
func publish(message: GameplayNetMessage) -> void:
	message_ready.emit(message)
	if transport == null:
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
	for id: int in _recipients():
		transport.send(packet, id, _must_arrive(message))


func _recipients() -> Array[int]:
	if is_authority():
		return transport.peers()
	return [AUTHORITY_PEER] as Array[int]


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
func _on_packet_received(packet: PackedByteArray, _from_peer: int) -> void:
	var message: GameplayNetMessage = GameplayNetCodec.decode(packet)
	if message == null:
		message_refused.emit(null, GameplayNetCodec.last_refusal)
		return
	receive(message)
#endregion


func _init() -> void:
	requests.net = self
	state.net = self


func is_authority() -> bool:
	return role == GameplayNetAuthority.Role.AUTHORITY


#region Wiring
## Put a component on the network under an id, and tell it who to talk through.
##
## The component keeps exactly one reference to a runtime, or null. More than
## one would be a component two authorities disagree about; a reference held
## somewhere else would be a component whose network can be changed without it
## knowing.
func attach(
	asc: AbilitySystemComponent,
	id: GameplayNetEntityId,
	owner_peer: int = GameplayNetRegistry.NO_PEER
) -> bool:
	if not registry.register_entity(id, asc, owner_peer):
		return false
	asc.network = self
	return true


func detach(asc: AbilitySystemComponent) -> void:
	if asc == null:
		return
	registry.forget_entity(registry.entity_for(asc))
	if asc.network == self:
		asc.network = null


## Let go of everything. A runtime kept alive by a scene that has ended is a
## scene that cannot be freed.
func dispose() -> void:
	registry.clear()
	_applied.clear()
	state.forget()
	_runs.clear()
	journal.clear()
#endregion


#region What the authority says
## Grant an ability to an entity, and tell the peers.
##
## Refused on a client, and not politely: a client granting itself an ability
## is the bug this whole layer exists to make impossible, so it is refused at
## the one place a grant can be made rather than checked for afterwards.
func grant(id: GameplayNetEntityId, definition: Resource) -> bool:
	return _author(GameplayNetMessage.Kind.GRANT, id, definition)


func revoke(id: GameplayNetEntityId, definition: Resource) -> bool:
	return _author(GameplayNetMessage.Kind.REVOKE, id, definition)


func _author(
	kind: GameplayNetMessage.Kind, id: GameplayNetEntityId, definition: Resource
) -> bool:
	if not GameplayNetAuthority.may_author(role):
		return false
	var named: GameplayNetDefinitionId = registry.register_definition(definition)
	if not named.is_valid() or registry.asc_for(id) == null:
		return false

	var message: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	message.definition = named
	publish(message)
	return true
#endregion


#region What a client asks for
## Ask to activate, or run it, or neither - whichever the grant's policy says.
##
## Answers what was done rather than whether it worked, because "run it here"
## and "ask and wait" are both success and a caller that could not tell them
## apart would have to guess whether anything had happened yet.
func start(asc: AbilitySystemComponent, definition: Resource) -> GameplayNetAuthority.Start:
	var spec_policy: GameplayAbility.NetExecutionPolicy = _policy_of(definition)
	var decided: GameplayNetAuthority.Start = (
		GameplayNetAuthority.authority_start(spec_policy) if is_authority()
		else GameplayNetAuthority.client_start(spec_policy)
	)
	if decided == GameplayNetAuthority.Start.RUN_NOW or decided == GameplayNetAuthority.Start.REFUSED:
		return decided

	var id: GameplayNetEntityId = registry.entity_for(asc)
	var named: GameplayNetDefinitionId = registry.register_definition(definition)
	if not id.is_valid() or not named.is_valid():
		return GameplayNetAuthority.Start.REFUSED

	var asking: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
	)
	asking.definition = named
	# A request carries a key whichever way it was started. The predicting
	# client needs it to unwind by; the waiting one needs it because the
	# answer has to name which ask it is answering, and a client with two in
	# flight cannot tell them apart otherwise.
	asking.prediction_key = journal.next_key(peer)
	publish(asking)
	return decided


## The policy a definition was authored with, or LOCAL_ONLY for anything that
## is not an ability scene - an effect has no policy and asking one for it
## should answer the harmless value rather than fail.
func _policy_of(definition: Resource) -> GameplayAbility.NetExecutionPolicy:
	var scene: PackedScene = definition as PackedScene
	if scene == null:
		return GameplayAbility.NetExecutionPolicy.LOCAL_ONLY
	var state: SceneState = scene.get_state()
	for index: int in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == GameplayAbility.NET_EXECUTION_POLICY_FIELD:
			var authored: GameplayAbility.NetExecutionPolicy = state.get_node_property_value(0, index)
			return authored
	return GameplayAbility.NetExecutionPolicy.LOCAL_ONLY
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
## Act on a message, or say why not.
##
## One door, so every refusal is in one place and none of them is a check
## somebody remembered to write at a call site. Answers whether it was acted
## on; a refusal is announced through `message_refused` rather than returned in
## detail, because a caller carrying messages has nothing useful to do with the
## reason and a log does.
func receive(message: GameplayNetMessage) -> bool:
	if message == null or not message.is_complete():
		_refuse(message, REASON_INCOMPLETE)
		return false
	if not GameplayNetAuthority.accepts(role, message):
		_refuse(message, REASON_WRONG_DIRECTION)
		return false

	if message.is_state():
		return state.apply(message)

	var seen: String = _fingerprint(message)
	if _applied.has(seen):
		_refuse(message, REASON_ALREADY_APPLIED)
		return false

	if not _act_on(message):
		return false
	_applied[seen] = true
	return true


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
func _act_on(message: GameplayNetMessage) -> bool:
	var id: GameplayNetEntityId = message.entity
	if registry.asc_for(id) == null:
		_refuse(message, REASON_UNKNOWN_ENTITY)
		return false

	match message.kind:
		GameplayNetMessage.Kind.GRANT, GameplayNetMessage.Kind.REVOKE:
			return _announce_grant(message)
		GameplayNetMessage.Kind.ACTIVATION_REQUEST:
			return _honour_request(message)
		GameplayNetMessage.Kind.ACTIVATION_CONFIRM:
			journal.accept(message.prediction_key)
			activation_answered.emit(message.prediction_key, message.activation, true)
			return true
		GameplayNetMessage.Kind.ACTIVATION_REJECT:
			journal.reject(message.prediction_key, registry.asc_for(message.entity))
			activation_answered.emit(message.prediction_key, message.activation, false)
			return true
		GameplayNetMessage.Kind.TARGET_DATA:
			return requests.honour_target_data(message)
		GameplayNetMessage.Kind.GENERIC_CONFIRM:
			registry.asc_for(id).input_confirm()
			return true
		GameplayNetMessage.Kind.GENERIC_CANCEL:
			registry.asc_for(id).input_cancel()
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


func _honour_request(message: GameplayNetMessage) -> bool:
	var definition: Resource = registry.definition_for(message.definition)
	if definition == null:
		_refuse(message, REASON_UNKNOWN_DEFINITION)
		return false

	var asking: int = (
		message.prediction_key.peer if message.is_predicted()
		else registry.owner_of(message.entity)
	)
	var refusal: StringName = _why_not(message, asking, definition)
	if refusal != &"":
		_refuse(message, refusal)
		_answer(GameplayNetMessage.Kind.ACTIVATION_REJECT, message)
		return false
	_answer(GameplayNetMessage.Kind.ACTIVATION_CONFIRM, message)
	return true


## Why this request will not be honoured, or nothing when it will.
##
## Both refusals are answered rather than dropped in silence. The ordinary
## reason a well-formed request is refused is that something moved between
## the asking and the arrival - a character changed hands, a grant was
## revoked - and the client that asked is holding a guess it needs to unwind.
## Saying nothing would leave it holding that guess for ever.
func _why_not(
	message: GameplayNetMessage, asking: int, definition: Resource
) -> StringName:
	if not registry.is_owned_by(message.entity, asking):
		return REASON_NOT_OWNED
	if not GameplayNetAuthority.honours_request(true, _policy_of(definition)):
		return REASON_POLICY
	return &""


## Say yes or no to a request, naming the run and the guess it answers.
##
## The key is echoed rather than looked up: the machine that asked is the
## one holding the journal, and an answer that did not name the guess would
## leave a client with two casts in flight unwinding the wrong one.
func _answer(kind: GameplayNetMessage.Kind, asked: GameplayNetMessage) -> void:
	var id: GameplayNetEntityId = asked.entity
	_runs[id.value] = _runs.get(id.value, 0) + 1
	var answer: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	answer.activation = GameplayNetActivationId.of(id, _runs[id.value])
	answer.definition = asked.definition
	answer.prediction_key = asked.prediction_key
	publish(answer)


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
