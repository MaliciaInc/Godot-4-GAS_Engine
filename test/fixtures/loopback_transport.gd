## Two transports wired to each other, in one process.
##
## What everything from the codec up needs to be tested without two machines:
## a packet sent by one arrives at the other, byte for byte, through the same
## `GameplayNetTransport` door a real one uses. Nothing is stubbed - the runtime
## encodes, this carries bytes, the runtime decodes.
##
## It is not a claim about transport. F6.6.7's two-process test is the one that
## says the real thing works; this is what lets everything else be checked
## without paying for two processes per assertion.
##
## Delivery is immediate and in order. A test that needed loss or reordering
## would say so by holding packets itself rather than by this being unreliable
## on its own account - a fixture that dropped packets at random is a fixture
## whose failures are somebody else's afternoon.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name LoopbackTransport extends GameplayNetTransport

## Who this end is, and who the other end is.
var peer_id: int = 0
var other: LoopbackTransport = null

## Every packet this end sent, in order, for a test asking what went out rather
## than what arrived.
var sent: Array[PackedByteArray] = []

## Set false to make this end drop everything it is asked to send, which is how
## a test says "the far side never heard".
var delivers: bool = true


## Two ends, each knowing the other.
##
## The authority is peer 1 because that is the peer a client addresses, and a
## fixture that used any other number would be testing addressing that no real
## transport performs.
static func pair() -> Array[LoopbackTransport]:
	var authority: LoopbackTransport = LoopbackTransport.new()
	authority.peer_id = 1
	var client: LoopbackTransport = LoopbackTransport.new()
	client.peer_id = 2

	authority.other = client
	client.other = authority
	return [authority, client]


func send(
	packet: PackedByteArray,
	_to_peer: int,
	_reliable: bool = true,
	_channel: int = 0
) -> bool:
	sent.append(packet)
	if not delivers or other == null:
		return false
	# Emitted from the far end, so a listener hears it the way it would hear a
	# real one: the signal belongs to the transport that received it.
	other.packet_received.emit(packet, peer_id)
	return true


func local_peer() -> int:
	return peer_id


func peers() -> Array[int]:
	return [other.peer_id] if other != null else [] as Array[int]


func is_connected_to_network() -> bool:
	return other != null
