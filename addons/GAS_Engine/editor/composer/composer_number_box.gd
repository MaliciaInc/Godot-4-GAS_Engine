## How a number box is set up for the value a file holds.
##
## A `SpinBox` is a blunt instrument over a written number: it rounds to a
## multiple of its own step on every assignment, so a box stepping by hundredths
## turns the literal `0.7071` into `0.71` the moment it loads - a normalised
## direction quietly destroyed by opening the card that holds it. What the step,
## the rounding and the bounds have to be is decided here, off the text and off
## what the method declared, and nowhere else.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerNumberBox extends RefCounted

## As far as a step is allowed to shrink. A float carries about seven decimal
## digits, so a step below this is precision the number never had.
const MOST_DECIMALS: int = 6
const RANGE_PARTS: int = 3
const OR_GREATER: String = "or_greater"
const OR_LESS: String = "or_less"

## What a box steps by: one, for a whole number, and hundredths for a written
## one - which the text can then narrow further.
const WHOLE_STEP: float = 1.0
const FRACTION_STEP: float = 0.01
## The vector types written with whole components.
const INTEGER_VECTORS: Array[StringName] = [
	ComposerTypes.VECTOR2I, ComposerTypes.VECTOR3I, ComposerTypes.VECTOR4I,
]


## The smallest step that can still hold `written` exactly.
##
## Godot rounds a Range's value to a multiple of its step on every assignment, so
## a box stepping by 0.01 turns the literal 0.7071 into 0.71 the instant it is
## loaded - a normalised direction quietly destroyed by opening the card that
## holds it. The step follows the number the file actually contains; a range the
## method declared still overrides it afterwards.
static func step_for(written: String) -> float:
	var fraction: String = written.strip_edges().get_slice(".", 1)
	if fraction.is_empty():
		return FRACTION_STEP
	return minf(FRACTION_STEP, pow(0.1, mini(fraction.length(), MOST_DECIMALS)))


## Apply the range the engine declared, when it declared one.
##
## `or_greater` and `or_less` are what the declaring method said about its own
## bounds, so they are obeyed rather than assumed: a range without them means
## the author meant the limits.
static func ranged(spin: SpinBox, field: ComposerNode.Field) -> void:
	if field.hint != PROPERTY_HINT_RANGE:
		return
	var parts: PackedStringArray = field.hint_string.split(",")
	if parts.size() < RANGE_PARTS - 1:
		return
	if not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return
	spin.min_value = parts[0].to_float()
	spin.max_value = parts[1].to_float()
	if parts.size() >= RANGE_PARTS and parts[2].is_valid_float():
		spin.step = parts[2].to_float()
	spin.allow_greater = field.hint_string.contains(OR_GREATER)
	spin.allow_lesser = field.hint_string.contains(OR_LESS)


## Whether this argument holds whole numbers.
##
## Named against the actual integer vector types rather than tested for a
## trailing "i". A game is free to declare a class called `Yuki` or `Ashi`, and
## a spinner that rounded its value because of how the name ends is a control
## that quietly deletes the fraction of somebody's number.
static func holds_integers(type_name: StringName) -> bool:
	if type_name == ComposerTypes.INT:
		return true
	return INTEGER_VECTORS.has(type_name)
