## A MultiplayerPeer that is a table rather than a socket.
##
## `GameplayNetTransportMultiplayer` is the class a real game uses, and until
## this existed nothing in the suite ran it: every networking test handed
## messages between runtimes directly, so `SceneMultiplayer.send_bytes` and its
## `peer_packet` signal were exercised only by the two-process sample. One
## scenario over a socket is evidence; it is not coverage.
##
## So this is Godot's own multiplayer, with the network replaced by a
## dictionary. Everything above it is real - the SceneMultiplayer, its framing,
## the transport class, the codec - and the only thing that is not is the part
## that would need a port, a handshake and a frame to happen in.
##
## Peers are hooked up by hand rather than discovered, because a handshake is
## the thing being avoided. `join()` tells every peer about the new one and the
## new one about every peer, which is what a connection produces.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name LoopbackMultiplayerPeer extends MultiplayerPeerExtension

## The largest packet this pretends to carry. Larger than anything this addon
## sends, because a limit that bit would be this fixture inventing a failure.
const CAPACITY: int = 1 << 20

## Everyone reachable, by id. Shared between every peer in one switch, so a put
## on one is a get on another with nothing in between.
var switchboard: Dictionary[int, LoopbackMultiplayerPeer] = {}

var id: int = 1

var _inbox: Array[PackedByteArray] = []
var _from: Array[int] = []
var _target: int = 0
var _channel: int = 0
var _mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refusing: bool = false


## One peer, in the switch every other one shares. Not yet connected to them.
##
## Two steps rather than one, and this is the step that is easy to get wrong: a
## SceneMultiplayer learns about a peer by hearing `peer_connected` on the
## MultiplayerPeer it holds, so announcing a connection before the peer has
## been handed to one announces it to nobody. Every send afterwards is refused
## with "connected_peers does not have that peer", which reads as a broken
## transport rather than as a fixture that spoke too early.
static func of(
	switch: Dictionary[int, LoopbackMultiplayerPeer], peer_id: int
) -> LoopbackMultiplayerPeer:
	var made: LoopbackMultiplayerPeer = LoopbackMultiplayerPeer.new()
	made.id = peer_id
	made.switchboard = switch
	switch[peer_id] = made
	return made


## Introduce everybody to everybody, once they are all listening.
##
## Called after every peer has been given to its SceneMultiplayer. Both
## directions per pair, because a connection is not something one end has.
static func connect_all(switch: Dictionary[int, LoopbackMultiplayerPeer]) -> void:
	for one: int in switch:
		for other: int in switch:
			if one != other:
				switch[one].peer_connected.emit(other)


#region What a MultiplayerPeer has to answer
func _get_unique_id() -> int:
	return id


func _is_server() -> bool:
	return id == MultiplayerPeer.TARGET_PEER_SERVER


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return MultiplayerPeer.CONNECTION_CONNECTED


func _get_max_packet_size() -> int:
	return CAPACITY


func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _get_packet_channel() -> int:
	return _channel


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _poll() -> void:
	pass


func _close() -> void:
	switchboard.erase(id)
	_inbox.clear()
	_from.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	switchboard.erase(peer)
	peer_disconnected.emit(peer)
#endregion


#region Carrying
## Put a packet in whoever it was addressed to.
##
## Zero means everybody but the sender, which is what Godot's own peers mean by
## it; a negative id means everybody but that one. Both are spelled here rather
## than assumed, because a transport that broadcast to the sender as well would
## have every authority acting on its own messages.
func _put_packet_script(buffer: PackedByteArray) -> Error:
	if buffer.size() > CAPACITY:
		return ERR_OUT_OF_MEMORY
	for known_id: int in switchboard:
		if not _addressed(known_id):
			continue
		var known: LoopbackMultiplayerPeer = switchboard[known_id]
		known._inbox.append(buffer.duplicate())
		known._from.append(id)
	return OK


func _addressed(known_id: int) -> bool:
	if known_id == id:
		return false
	if _target == 0:
		return true
	if _target < 0:
		return known_id != -_target
	return known_id == _target


func _get_available_packet_count() -> int:
	return _inbox.size()


func _get_packet_script() -> PackedByteArray:
	if _inbox.is_empty():
		return PackedByteArray()
	_from.pop_front()
	return _inbox.pop_front()


func _get_packet_peer() -> int:
	return _from[0] if not _from.is_empty() else 0
#endregion
