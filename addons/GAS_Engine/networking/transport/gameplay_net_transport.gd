## How packets leave and arrive, said once so the runtime does not know which
## way they went.
##
## The addon has one door to a network and this is it. A game with its own
## socket layer, a test with two runtimes in one process, and Godot's own
## SceneMultiplayer are three things that move bytes, and the ability system
## should not be able to tell them apart - so it asks this and nothing else.
##
## The base answers "nothing is connected" to everything. That is not a stub: a
## runtime with no transport is exactly what a single-player game has, and every
## call below has to be safe there rather than guarded at each call site.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetTransport extends RefCounted

## A packet arrived, and from whom.
##
## Bytes rather than a message: what a packet decodes to is the codec's
## question, and a transport that decoded would be a transport that has to know
## what version the far side speaks.
signal packet_received(packet: PackedByteArray, from_peer: int)


## Send bytes to one peer. False when there is nothing to send them over.
##
## Reliability and channel are asked for rather than assumed: state that arrives
## late is worse than state that never arrives, and an activation that never
## arrives is worse than one that arrives late. Those are different answers and
## a transport that picked one would be picking it for both.
func send(
	_packet: PackedByteArray,
	_to_peer: int,
	_reliable: bool = true,
	_channel: int = 0
) -> bool:
	return false


## Which peer this process is. `NO_PEER` when it is not on a network.
func local_peer() -> int:
	return GameplayNetRegistry.NO_PEER


## Everybody else, as ids. Empty off a network.
func peers() -> Array[int]:
	return []


func is_connected_to_network() -> bool:
	return false
