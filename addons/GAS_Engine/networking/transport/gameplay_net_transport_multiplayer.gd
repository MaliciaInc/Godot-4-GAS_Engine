## The transport over Godot's own SceneMultiplayer.
##
## `send_bytes` and `peer_packet`, which is the raw-packet half of Godot's
## networking rather than the RPC half. RPCs are a Node-shaped API: they need a
## node path both peers agree on, and the ability system is a component that may
## live anywhere in anybody's scene. Bytes need nobody to agree about a tree.
##
## Object decoding is never enabled. Godot can put an Object in a packet and
## take one out again, and a peer that allowed it would be constructing whatever
## class the far side named. This addon's codec builds messages by hand from
## numbers and strings, and this transport does not undo that.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetTransportMultiplayer extends GameplayNetTransport

## Godot's own multiplayer, or null before anybody bound one.
var api: SceneMultiplayer = null


## Start using this SceneMultiplayer, and stop using whatever was there.
##
## Disconnected before connected, and the same way round every time: binding
## twice used to leave two connections to `peer_packet`, and every packet then
## arrived twice - which for an activation request is one ability activating
## twice and for a state delta is nothing at all, so it was only ever noticed by
## the half that hurt.
func bind(scene_multiplayer: SceneMultiplayer) -> bool:
	_unbind()
	api = scene_multiplayer
	if api == null:
		return false
	# Never enabled, and said out loud here so that a project that turned it on
	# elsewhere is turning it off for this transport rather than inheriting it.
	api.allow_object_decoding = false
	api.peer_packet.connect(_on_peer_packet)
	return true


## Let go of the multiplayer this was using.
##
## A transport that outlives its SceneMultiplayer and still holds a callable
## into it is the leak shape the dispose work in F5.1.2 was about.
func unbind() -> void:
	_unbind()


func send(
	packet: PackedByteArray,
	to_peer: int,
	reliable: bool = true,
	channel: int = 0
) -> bool:
	if api == null or packet.is_empty():
		return false
	# Ordered even when unreliable: a state reading that arrives after a newer
	# one is worse than one that never arrives, and the message's own sequence
	# is the last line of defence rather than the first.
	var mode: MultiplayerPeer.TransferMode = (
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	return api.send_bytes(packet, to_peer, mode, channel) == OK


func local_peer() -> int:
	if api == null:
		return GameplayNetRegistry.NO_PEER
	return api.get_unique_id()


func peers() -> Array[int]:
	var found: Array[int] = []
	if api == null:
		return found
	for id: int in api.get_peers():
		found.append(id)
	return found


## Whether this is actually on a network.
##
## A SceneMultiplayer with nobody on the far side still has a peer - Godot fits
## an offline one so that single-player code paths work unchanged - so "has a
## peer" answers yes off a network. What is asked is whether the peer is a real
## one.
func is_connected_to_network() -> bool:
	if api == null or api.multiplayer_peer == null:
		return false
	return not (api.multiplayer_peer is OfflineMultiplayerPeer)


func _on_peer_packet(id: int, packet: PackedByteArray) -> void:
	packet_received.emit(packet, id)


func _unbind() -> void:
	if api != null and api.peer_packet.is_connected(_on_peer_packet):
		api.peer_packet.disconnect(_on_peer_packet)
	api = null
