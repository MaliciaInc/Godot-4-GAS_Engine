## Bits on their way to a wire, packed the way the reference packs them.
##
## A packet is a stream of bits, not of bytes and not of text. A flag costs one
## bit, a count that is never above sixty-four costs a byte, and a field that
## says nothing costs nothing at all, because a presence bit in front of it
## already said so. Bytes would round every one of those up, and text would
## spell each of them out.
##
## Written low bit first into a small scratch and flushed a byte at a time, so a
## packet of any length is one append per byte and nothing allocated per field.
##
## A write that cannot be honoured - a value no bit pattern here carries, a
## packet past its size, a list past its bound - marks the whole packet failed
## rather than writing something close. `finish()` then answers nothing, which
## is the one answer a caller cannot mistake for a packet.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetBitWriter extends RefCounted

## The most bits one call writes. A scratch holding fewer than eight pending
## bits plus this many stays well inside a 64-bit integer.
const MAX_BITS_PER_WRITE: int = 32

## The most bytes one packet may grow to. Past this the writer refuses rather
## than grows: nothing this addon builds comes close, and a reading that would
## not fit a datagram is a sender's bug to find here rather than on the far side.
const MAX_BYTES: int = 1 << 16

## A group of seven bits, and the flag in the eighth that says another follows.
const GROUP_BITS: int = 7
const GROUP_MASK: int = 0x7F
const MORE: int = 0x80

## What is left of a zig-zagged value once a group is shifted off it. GDScript's
## `>>` is arithmetic, so the sign bit copies itself into every shift and a
## negative pattern would never reach zero; masking it back out is the logical
## shift the format means.
const AFTER_A_GROUP: int = 0x01FFFFFFFFFFFFFF

## The largest value thirty-two bits hold.
const MOST_U32: int = 0xFFFFFFFF

## The names both machines already agree about. Null writes every name out.
var names: GameplayNetNames = null

## Whether any name went out as a position in `names`, which is what obliges the
## packet to say which table it was written against.
var used_shared_names: bool = false

var _bytes: PackedByteArray = PackedByteArray()
var _scratch: int = 0
var _scratch_bits: int = 0
var _failed: bool = false

## Names this packet has already spelled out, by the order it spelled them in.
var _exported: Dictionary[StringName, int] = {}

## Reused to turn a float into its bits, so writing one allocates nothing.
var _float_bits: PackedByteArray = PackedByteArray()


func _init() -> void:
	_float_bits.resize(8)


## Whether everything written so far was honoured.
func is_ok() -> bool:
	return not _failed


## Refuse the whole packet.
##
## Public because most refusals belong to whoever knows what is being written: a
## state knows its lists are bounded, a vector knows it has to be finite.
func fail() -> void:
	_failed = true


func write_bool(value: bool) -> void:
	write_bits(1 if value else 0, 1)


## The low `count` bits of `value`.
func write_bits(value: int, count: int) -> void:
	if _failed:
		return
	if count <= 0 or count > MAX_BITS_PER_WRITE:
		_failed = true
		return
	_scratch |= (value & ((1 << count) - 1)) << _scratch_bits
	_scratch_bits += count
	while _scratch_bits >= 8:
		if _bytes.size() >= MAX_BYTES:
			_failed = true
			return
		_bytes.append(_scratch & 0xFF)
		_scratch = _scratch >> 8
		_scratch_bits -= 8


## A whole number in [0, 2^32), in exactly thirty-two bits.
##
## What a definition crosses as. Its identity is a hash of where it lives, so it
## is spread over the whole range and packing it would cost more than it saves.
func write_u32(value: int) -> void:
	if value < 0 or value > MOST_U32:
		_failed = true
		return
	write_bits(value, 32)


## A whole number that is never negative, in as many groups of seven as it needs.
##
## The reference's packed integer: a count of five is one byte, an identity in
## the millions is four, and nothing is spent on digits a value does not have. A
## negative number is not a count, and asking to write one is refused.
func write_packed(value: int) -> void:
	if value < 0:
		_failed = true
		return
	_write_groups(value, false)


## A whole number of either sign, zig-zagged so that small magnitudes stay small.
func write_signed(value: int) -> void:
	_write_groups((value << 1) ^ (value >> 63), true)


## A count that may not pass `most`. Refused rather than clipped: a reading sent
## with its last entries quietly missing is two machines disagreeing about a
## character with nothing to say so.
func write_count(count: int, most: int) -> void:
	if count > most:
		_failed = true
		return
	write_packed(count)


## A 32-bit float, bit for bit - the width the reference replicates an
## attribute, a duration and a magnitude at.
func write_float32(value: float) -> void:
	_float_bits.encode_float(0, value)
	write_bits(_float_bits.decode_u32(0), 32)


## A 64-bit float, for numbers that belong to the game and are not this
## addon's to round.
func write_float64(value: float) -> void:
	_float_bits.encode_double(0, value)
	write_bits(_float_bits.decode_u32(0), 32)
	write_bits(_float_bits.decode_u32(4), 32)


## Text as its UTF-8 bytes, behind a packed length.
##
## Aligned to a byte first, so the bytes go on in one append rather than one
## call each - a padding of at most seven bits, spent only where text is.
func write_text(text: String) -> void:
	var encoded: PackedByteArray = text.to_utf8_buffer()
	write_packed(encoded.size())
	align()
	if _failed:
		return
	if _bytes.size() + encoded.size() > MAX_BYTES:
		_failed = true
		return
	_bytes.append_array(encoded)


## A name, as cheaply as the two machines allow.
##
## A name in the shared table is its position there - the reference's network
## index for a tag. One that is not is spelled out the first time this packet
## needs it and pointed back at every time after, which is the reference's
## export of a name it has no index for, kept to one packet: a packet here may
## be lost or reordered, and an export another packet was meant to carry is a
## name nobody can read.
func write_name(name: StringName) -> void:
	if name == &"":
		_failed = true
		return
	var shared: int = names.index_of(name) if names != null else -1
	if shared >= 0:
		write_bool(true)
		write_packed(shared)
		used_shared_names = true
		return
	write_bool(false)
	if _exported.has(name):
		write_bool(true)
		write_packed(_exported[name])
		return
	write_bool(false)
	var spelled: String = String(name)
	if spelled.to_utf8_buffer().size() > GameplayNetBitReader.MAX_TEXT_BYTES:
		_failed = true
		return
	var position: int = _exported.size()
	_exported[name] = position
	write_text(spelled)


## Names behind their count, refused past `most`.
func write_names(listed: Array[StringName], most: int) -> void:
	write_count(listed.size(), most)
	for name: StringName in listed:
		write_name(name)


## Pad with zero bits to the next whole byte.
func align() -> void:
	if _scratch_bits > 0:
		write_bits(0, 8 - _scratch_bits)


## The packet, padded to a whole byte, or nothing when anything written was refused.
func finish() -> PackedByteArray:
	align()
	if _failed:
		return PackedByteArray()
	return _bytes


func _write_groups(pattern: int, signed: bool) -> void:
	var rest: int = pattern
	while not _failed:
		var group: int = rest & GROUP_MASK
		rest = (rest >> GROUP_BITS) & AFTER_A_GROUP if signed else rest >> GROUP_BITS
		if rest == 0:
			write_bits(group, 8)
			return
		write_bits(group | MORE, 8)
