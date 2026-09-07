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
const REASON_INCOMPLETE: StringName = &"incomplete"
const REASON_UNKNOWN_ENTITY: StringName = &"unknown_entity"
const REASON_UNKNOWN_DEFINITION: StringName = &"unknown_definition"
const REASON_NOT_OWNED: StringName = &"not_owned"
const REASON_POLICY: StringName = &"policy_refuses"
const REASON_ALREADY_APPLIED: StringName = &"already_applied"
const REASON_OUT_OF_ORDER: StringName = &"out_of_order"
const REASON_NOTHING_TO_UPDATE: StringName = &"nothing_to_update"

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
var _told: Dictionary[String, GameplayNetState] = {}
var _counted: Dictionary[int, int] = {}

## The last reading of each entity this machine has applied, so an older one
## arriving late is ignored rather than undoing a newer one.
var _applied_sequence: Dictionary[int, int] = {}

## What this machine did before it was allowed to, and still owes an answer
## on. Empty on an authority, which never predicts because it never asks.
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
	_told.clear()
	_counted.clear()
	_applied_sequence.clear()
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
	message_ready.emit(message)
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
	message_ready.emit(asking)
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
## Everything this peer may be told about an entity, as a message.
##
## A late joiner gets one of these and then deltas, and the two are the same
## shape on purpose: a peer whose whole state is news and a peer whose news
## is small are the same peer told different amounts.
func snapshot_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return _state_message(GameplayNetMessage.Kind.STATE_SNAPSHOT, id, to_peer)


## What changed since that peer was last told, or null when nothing did.
##
## Null rather than an empty message, because a delta computed every frame is
## mostly empty and sending one is bandwidth spent to say nothing happened.
func delta_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return _state_message(GameplayNetMessage.Kind.STATE_DELTA, id, to_peer)


func _state_message(
	kind: GameplayNetMessage.Kind, id: GameplayNetEntityId, to_peer: int
) -> GameplayNetMessage:
	var asc: AbilitySystemComponent = registry.asc_for(id)
	if asc == null or not GameplayNetAuthority.may_author(role):
		return null

	var now: GameplayNetState = GameplayNetReplication.snapshot_of(
		asc, registry, replication_mode, registry.is_owned_by(id, to_peer)
	)
	var remembered: String = "%d|%d" % [id.value, to_peer]
	var sending: GameplayNetState = now
	if kind == GameplayNetMessage.Kind.STATE_DELTA:
		var before: GameplayNetState = _told.get(remembered)
		if before == null:
			return null
		sending = GameplayNetReplication.delta_between(before, now)
		if sending.is_empty():
			return null

	_told[remembered] = now.copied()
	_counted[id.value] = _counted.get(id.value, 0) + 1
	var message: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	message.state = sending
	message.sequence = _counted[id.value]
	message_ready.emit(message)
	return message
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
		return _apply_state(message)

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
func _apply_state(message: GameplayNetMessage) -> bool:
	var asc: AbilitySystemComponent = registry.asc_for(message.entity)
	if asc == null:
		_refuse(message, REASON_UNKNOWN_ENTITY)
		return false
	if message.sequence <= _applied_sequence.get(message.entity.value, 0):
		_refuse(message, REASON_OUT_OF_ORDER)
		return false
	if message.state.is_delta() and not _applied_sequence.has(message.entity.value):
		_refuse(message, REASON_NOTHING_TO_UPDATE)
		return false

	GameplayNetReplication.apply(message.state, asc)
	_applied_sequence[message.entity.value] = message.sequence
	state_applied.emit(message.entity, message.state)
	return true


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
	message_ready.emit(answer)


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
