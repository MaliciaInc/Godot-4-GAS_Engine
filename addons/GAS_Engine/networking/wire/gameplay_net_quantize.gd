## Positions and normals, quantized the way the reference quantizes them.
##
## A position crosses as whole numbers rather than as floats. The reference's
## algorithm, component for component: scale, round, send only as many bits per
## component as the largest one needs behind a seven-bit header that says how
## many, and fall back to full precision - flagged in that same header - for a
## value too large for scaling to help. A spot ten metres from the origin is
## seven bits of header and eleven bits a side, where three floats are ninety-six.
##
## The reference's unit is a centimetre and scales a hit location by one; a unit
## here is a metre, so the scale is a hundred. That is the same physical
## precision, which is the thing the reference actually chose - a centimetre is
## past what anybody aiming at something can see.
##
## A normal crosses as sixteen fixed bits a component over [-1, 1], the
## reference's own layout: a direction has no magnitude to spend bits on. A
## component outside that range is clamped into it - to exactly one at either
## end, which the reference's own clamp misses by a step on the negative side.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetQuantize extends RefCounted

## Whole numbers per unit a position is rounded to.
const POSITION_SCALE: int = 100

## Six bits of component width, and one bit that means "scaled" beside a
## width, or "64-bit" beside a width of zero.
const HEADER_BITS: int = 7
const WIDTH_MASK: int = 63
const FLAG: int = 1 << 6

## Past 2^23 a 32-bit float has no fraction left for scaling to keep.
const MOST_WORTH_SCALING: float = 8388608.0

## Past 2^30 rounding a scaled component loses more than sending it whole.
const MOST_AFTER_SCALING: float = 1073741824.0

## The widest a component can need when every scaled value is under 2^30.
const MOST_WIDTH: int = 31

const NORMAL_BITS: int = 16
const NORMAL_STEPS: int = (1 << (NORMAL_BITS - 1)) - 1
const NORMAL_BIAS: int = 1 << (NORMAL_BITS - 1)
const NORMAL_MOST: int = (1 << NORMAL_BITS) - 1


#region Positions
static func write_position_3d(writer: GameplayNetBitWriter, value: Vector3) -> void:
	_write_components(writer, PackedFloat64Array([value.x, value.y, value.z]))


static func write_position_2d(writer: GameplayNetBitWriter, value: Vector2) -> void:
	_write_components(writer, PackedFloat64Array([value.x, value.y]))


static func read_position_3d(reader: GameplayNetBitReader) -> Vector3:
	var read: PackedFloat64Array = _read_components(reader, 3)
	if read.size() != 3:
		return Vector3.ZERO
	return Vector3(read[0], read[1], read[2])


static func read_position_2d(reader: GameplayNetBitReader) -> Vector2:
	var read: PackedFloat64Array = _read_components(reader, 2)
	if read.size() != 2:
		return Vector2.ZERO
	return Vector2(read[0], read[1])


## A position that is not finite is not a place, and the packet is refused on
## the machine that tried to send one.
static func _write_components(writer: GameplayNetBitWriter, components: PackedFloat64Array) -> void:
	var largest_scaled: float = 0.0
	var smallest: float = INF
	for component: float in components:
		if not is_finite(component):
			writer.fail()
			return
		largest_scaled = maxf(largest_scaled, absf(component * POSITION_SCALE))
		smallest = minf(smallest, absf(component))

	if largest_scaled >= MOST_AFTER_SCALING:
		writer.write_bits(0, HEADER_BITS)
		for component: float in components:
			writer.write_float32(component)
		return

	var scaled: bool = smallest < MOST_WORTH_SCALING
	var whole: PackedInt64Array = PackedInt64Array()
	var width: int = 1
	for component: float in components:
		var number: int = _rounded(component * POSITION_SCALE if scaled else component)
		whole.append(number)
		width = maxi(width, _width_of(number))
	writer.write_bits((FLAG if scaled else 0) | width, HEADER_BITS)
	for number: int in whole:
		writer.write_bits(number, width)


## The components back, or nothing with the reader failed.
static func _read_components(reader: GameplayNetBitReader, how_many: int) -> PackedFloat64Array:
	var header: int = reader.read_bits(HEADER_BITS)
	var width: int = header & WIDTH_MASK
	var flagged: bool = (header & FLAG) != 0
	var read: PackedFloat64Array = PackedFloat64Array()

	if width == 0:
		for _component: int in how_many:
			var whole_float: float = reader.read_float64() if flagged else reader.read_float32()
			if not is_finite(whole_float):
				reader.fail()
			read.append(whole_float)
		return read if reader.is_ok() else PackedFloat64Array()

	if width > MOST_WIDTH:
		reader.fail()
		return PackedFloat64Array()
	var sign_bit: int = 1 << (width - 1)
	for _component: int in how_many:
		var number: int = (reader.read_bits(width) ^ sign_bit) - sign_bit
		read.append(float(number) / POSITION_SCALE if flagged else float(number))
	return read if reader.is_ok() else PackedFloat64Array()


## Round half away from zero, the way the reference rounds before it packs.
static func _rounded(value: float) -> int:
	return int(value + signf(value) * 0.5)


## How many bits a signed whole number needs, the sign bit included.
static func _width_of(number: int) -> int:
	var magnitude: int = number ^ (number >> 63)
	var width: int = 1
	while magnitude > 0:
		magnitude = magnitude >> 1
		width += 1
	return width
#endregion


#region Normals
static func write_normal_3d(writer: GameplayNetBitWriter, value: Vector3) -> void:
	_write_fixed(writer, value.x)
	_write_fixed(writer, value.y)
	_write_fixed(writer, value.z)


static func write_normal_2d(writer: GameplayNetBitWriter, value: Vector2) -> void:
	_write_fixed(writer, value.x)
	_write_fixed(writer, value.y)


static func read_normal_3d(reader: GameplayNetBitReader) -> Vector3:
	return Vector3(_read_fixed(reader), _read_fixed(reader), _read_fixed(reader))


static func read_normal_2d(reader: GameplayNetBitReader) -> Vector2:
	return Vector2(_read_fixed(reader), _read_fixed(reader))


## Clamped to the steps either side of zero rather than to every pattern sixteen
## bits hold. The lowest pattern is one step past -1 - the bias is one more than
## the steps - so a component clamped into it would read back as -1.00003, a
## normal that is not quite a normal. Clamped to the symmetric range, a component
## past either end reads back as exactly one.
static func _write_fixed(writer: GameplayNetBitWriter, value: float) -> void:
	if not is_finite(value):
		writer.fail()
		return
	var delta: int = floori(NORMAL_STEPS * value + 0.5) + NORMAL_BIAS
	writer.write_bits(clampi(delta, NORMAL_BIAS - NORMAL_STEPS, NORMAL_MOST), NORMAL_BITS)


## The pattern below the symmetric range is one no writer produces, and a packet
## carrying one is refused.
static func _read_fixed(reader: GameplayNetBitReader) -> float:
	var delta: int = reader.read_bits(NORMAL_BITS)
	if delta < NORMAL_BIAS - NORMAL_STEPS:
		reader.fail()
	return float(delta - NORMAL_BIAS) / NORMAL_STEPS
#endregion
