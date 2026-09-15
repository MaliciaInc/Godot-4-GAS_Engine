## Bits back off a wire, where the wire is allowed to be wrong.
##
## The other half of GameplayNetBitWriter, and the half that meets a sender it
## cannot trust. Every read is checked against what is left, every count
## against the bound its field declares, every name against the table it claims
## to come from, and every piece of text against the rules of UTF-8 before a
## String is made of it.
##
## A failure is sticky, the way the reference's archive error is: the first read
## that cannot be honoured marks the reader failed, every read after it answers
## a zero, and whoever is decoding asks once, at the end, whether any of it
## counted. A packet refused halfway is refused whole, never applied up to the
## point where it went wrong.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetBitReader extends RefCounted

## The most groups a packed integer spans: ten groups of seven bits cover 64.
const MAX_GROUPS: int = 10

## The longest a name may be. A tag is a few dozen bytes; a length prefix
## claiming more is a sender asking for an allocation.
const MAX_TEXT_BYTES: int = 1024

## The last group of a 64-bit pattern holds a single bit.
const LAST_GROUP_MOST: int = 1

## The names this machine agrees with its peers about.
var names: GameplayNetNames = null

var _bytes: PackedByteArray = PackedByteArray()
var _next_byte: int = 0
var _scratch: int = 0
var _scratch_bits: int = 0
var _failed: bool = false

## Names this packet spelled out, in the order it spelled them.
var _exports: Array[StringName] = []

var _float_bits: PackedByteArray = PackedByteArray()


func _init(bytes: PackedByteArray = PackedByteArray()) -> void:
	_bytes = bytes
	_float_bits.resize(8)


## Whether every read so far was honoured.
func is_ok() -> bool:
	return not _failed


## Refuse the whole packet, for a reason only the caller can see.
func fail() -> void:
	_failed = true


## Whether there is nothing left but the zero padding of the last byte.
##
## Asked once a message has been read. Bytes left over are bytes somebody put
## there, and a packet longer than the message it decodes to is not that message.
func is_exhausted() -> bool:
	return _next_byte == _bytes.size() and _scratch == 0


## How many bits are left to read - the ceiling on any count still to come,
## since every entry costs at least one.
func remaining_bits() -> int:
	return (_bytes.size() - _next_byte) * 8 + _scratch_bits


func read_bool() -> bool:
	return read_bits(1) == 1


## `count` bits as a whole number, low bit first.
func read_bits(count: int) -> int:
	if _failed:
		return 0
	if count <= 0 or count > GameplayNetBitWriter.MAX_BITS_PER_WRITE:
		_failed = true
		return 0
	while _scratch_bits < count:
		if _next_byte >= _bytes.size():
			_failed = true
			return 0
		_scratch |= _bytes[_next_byte] << _scratch_bits
		_next_byte += 1
		_scratch_bits += 8
	var value: int = _scratch & ((1 << count) - 1)
	_scratch = _scratch >> count
	_scratch_bits -= count
	return value


## Thirty-two bits as a whole number that is never negative.
func read_u32() -> int:
	return read_bits(32)


## A packed whole number that is never negative.
func read_packed() -> int:
	var pattern: int = _read_groups()
	if pattern < 0:
		_failed = true
		return 0
	return pattern


## A packed whole number of either sign.
func read_signed() -> int:
	var pattern: int = _read_groups()
	return ((pattern >> 1) & ~(1 << 63)) ^ -(pattern & 1)


## A count, refused past `most` and past what the packet has left to hold.
func read_count(most: int) -> int:
	var count: int = read_packed()
	if count > most or count > remaining_bits():
		_failed = true
		return 0
	return count


func read_float32() -> float:
	_float_bits.encode_u32(0, read_bits(32))
	return _float_bits.decode_float(0)


func read_float64() -> float:
	_float_bits.encode_u32(0, read_bits(32))
	_float_bits.encode_u32(4, read_bits(32))
	return _float_bits.decode_double(0)


## Text written by `write_text`, or nothing with the reader failed.
func read_text(most_bytes: int = MAX_TEXT_BYTES) -> String:
	var length: int = read_packed()
	align()
	if _failed:
		return ""
	if length > most_bytes or _next_byte + length > _bytes.size():
		_failed = true
		return ""
	var raw: PackedByteArray = _bytes.slice(_next_byte, _next_byte + length)
	_next_byte += length
	if not is_valid_utf8(raw):
		_failed = true
		return ""
	return raw.get_string_from_utf8()


## A name written by `write_name`.
func read_name() -> StringName:
	if read_bool():
		var shared: int = read_packed()
		if _failed or names == null or shared >= names.size():
			_failed = true
			return &""
		return names.name_at(shared)
	if read_bool():
		var exported: int = read_packed()
		if _failed or exported >= _exports.size():
			_failed = true
			return &""
		return _exports[exported]
	var text: String = read_text()
	if _failed or text.is_empty():
		_failed = true
		return &""
	var name: StringName = StringName(text)
	_exports.append(name)
	return name


## Names written by `write_names`, or none with the reader failed.
func read_names(most: int) -> Array[StringName]:
	var read: Array[StringName] = []
	var count: int = read_count(most)
	for _entry: int in count:
		read.append(read_name())
	if _failed:
		read.clear()
	return read


## Skip to the next whole byte. The padding a writer puts there is zero, and
## anything else in it is a packet somebody other than a writer made.
func align() -> void:
	var padding: int = _scratch_bits % 8
	if padding > 0 and read_bits(padding) != 0:
		_failed = true


## Whether these bytes are well-formed UTF-8 and hold no NUL.
##
## Asked before a String is made, not after. Godot repairs a malformed sequence
## into replacement characters and prints an error for each, so a sender could
## fill a log with them and have a name arrive as something it never sent -
## both of which a refusal avoids. Overlong forms, surrogates and code points
## past U+10FFFF are refused with everything else a writer never produces.
static func is_valid_utf8(raw: PackedByteArray) -> bool:
	var index: int = 0
	var size: int = raw.size()
	while index < size:
		var lead: int = raw[index]
		if lead == 0:
			return false
		if lead < 0x80:
			index += 1
			continue
		var extra: int = 0
		var smallest: int = 0
		var point: int = 0
		if lead >= 0xC2 and lead <= 0xDF:
			extra = 1
			smallest = 0x80
			point = lead & 0x1F
		elif lead >= 0xE0 and lead <= 0xEF:
			extra = 2
			smallest = 0x800
			point = lead & 0x0F
		elif lead >= 0xF0 and lead <= 0xF4:
			extra = 3
			smallest = 0x10000
			point = lead & 0x07
		else:
			return false
		if index + extra >= size:
			return false
		for offset: int in range(1, extra + 1):
			var follow: int = raw[index + offset]
			if (follow & 0xC0) != 0x80:
				return false
			point = (point << 6) | (follow & 0x3F)
		if point < smallest or point > 0x10FFFF or (point >= 0xD800 and point <= 0xDFFF):
			return false
		index += extra + 1
	return true


func _read_groups() -> int:
	var pattern: int = 0
	var shift: int = 0
	for group_index: int in MAX_GROUPS:
		var byte: int = read_bits(8)
		if _failed:
			return 0
		var group: int = byte & GameplayNetBitWriter.GROUP_MASK
		var more: bool = (byte & GameplayNetBitWriter.MORE) != 0
		if group_index == MAX_GROUPS - 1 and (more or group > LAST_GROUP_MOST):
			_failed = true
			return 0
		pattern |= group << shift
		if not more:
			return pattern
		shift += GameplayNetBitWriter.GROUP_BITS
	_failed = true
	return 0
