## What each peer has been told about each entity, and what it is told next.
##
## Three things that belong together and to nothing else: the reading a peer is
## sent, the last one it was sent - which is the only way a delta can be
## computed - and which reading it was, so that an older one arriving after a
## newer one is ignored rather than putting a character back the way it was half
## a second ago.
##
## Composed into GameplayNetworkRuntime the way GameplayNetRequestRuntime is.
## The runtime is still the one door to a network.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetStateRuntime extends RefCounted

var net: GameplayNetworkRuntime = null

## What each peer was last told about each entity, so a delta is what changed
## since rather than what changed since anybody was told anything.
var _told: Dictionary[String, GameplayNetState] = {}

## Which reading this is, counted per entity by the authority.
var _counted: Dictionary[int, int] = {}

## The newest reading applied per entity, so a late one is ignored.
var _applied_sequence: Dictionary[int, int] = {}


## Forget everything about one entity, or about all of them.
func forget(id: GameplayNetEntityId = null) -> void:
	if id == null:
		_told.clear()
		_counted.clear()
		_applied_sequence.clear()
		return
	_counted.erase(id.value)
	_applied_sequence.erase(id.value)
	for remembered: String in _told.keys():
		if remembered.begins_with("%d|" % id.value):
			_told.erase(remembered)


## Everything this peer may be told about an entity, as a message.
##
## A late joiner gets one of these and then deltas, and the two are the same
## shape on purpose: a peer whose whole state is news and a peer whose news
## is small are the same peer told different amounts.
func snapshot_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return _message(GameplayNetMessage.Kind.STATE_SNAPSHOT, id, to_peer)


## What changed since that peer was last told, or null when nothing did.
##
## Null rather than an empty message, because a delta computed every frame is
## mostly empty and sending one is bandwidth spent to say nothing happened.
func delta_for(id: GameplayNetEntityId, to_peer: int) -> GameplayNetMessage:
	return _message(GameplayNetMessage.Kind.STATE_DELTA, id, to_peer)


func _message(
	kind: GameplayNetMessage.Kind, id: GameplayNetEntityId, to_peer: int
) -> GameplayNetMessage:
	var asc: AbilitySystemComponent = net.registry.asc_for(id)
	if asc == null or not GameplayNetAuthority.may_author(net.role):
		return null

	# What this entity asked for, or the runtime's default when it asked for
	# nothing: a boss and a villager are two different amounts of network, and a
	# runtime with one setting makes a game choose the expensive one for both.
	var mode: GameplayNetReplication.Mode = net.registry.replication_mode_for(
		id, net.replication_mode
	)
	var now: GameplayNetState = GameplayNetReplication.snapshot_of(
		asc, net.registry, mode, net.registry.is_owned_by(id, to_peer)
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
	message.to_peer = to_peer
	net.publish(message)
	return message


## Write a reading of an entity onto it, if it is news.
##
## `commit` false asks the same three questions - a known entity, a sequence
## newer than the last one written, a delta with a snapshot under it - and
## writes nothing - R7-01. A state reading can reach a batch the same way any
## other message does, through `publish()`, and `would_apply` needs its
## answer settled before an atomic batch applies anything, not discovered by
## trying it after something else in the same batch already has.
func apply(message: GameplayNetMessage, commit: bool = true) -> bool:
	var asc: AbilitySystemComponent = net.registry.asc_for(message.entity)
	if asc == null:
		if commit:
			net._refuse(message, GameplayNetworkRuntime.REASON_UNKNOWN_ENTITY)
		return false
	if message.sequence <= _applied_sequence.get(message.entity.value, 0):
		if commit:
			net._refuse(message, GameplayNetworkRuntime.REASON_OUT_OF_ORDER)
		return false
	if message.state.is_delta() and not _applied_sequence.has(message.entity.value):
		if commit:
			net._refuse(message, GameplayNetworkRuntime.REASON_NOTHING_TO_UPDATE)
		return false
	if not commit:
		return true

	GameplayNetReplication.apply(message.state, asc)
	_applied_sequence[message.entity.value] = message.sequence
	_announce_activations(message)
	net.state_applied.emit(message.entity, message.state)
	return true


## Say which of this entity's activations started and which stopped.
##
## Announced rather than applied: a client that started an ability because
## the state said one was running would be a client running an ability the
## authority never asked it to, which is the whole thing the authority is
## for. What this is is a UI being told, and a UI is the reason an ability
## says REPLICATE_YES at all.
func _announce_activations(message: GameplayNetMessage) -> void:
	for value: int in message.state.running_abilities:
		net.activation_replicated.emit(
			message.entity, GameplayNetDefinitionId.from_wire(value), true
		)
	for value: int in message.state.stopped_abilities:
		net.activation_replicated.emit(
			message.entity, GameplayNetDefinitionId.from_wire(value), false
		)
