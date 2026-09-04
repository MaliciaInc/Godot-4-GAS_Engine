## Which key means which operation, and nothing else.
##
## A table rather than a chain of branches: the chords are what somebody reading
## this came to find, and a list of them is the answer. Kept apart from the
## screen because "what Ctrl-D does" is a question with one answer, and a screen
## that both owns the answer and performs it is a screen where the two can
## disagree - a chord wired to one method and a menu item to another.
##
## Nothing here decides whether an operation is allowed. It matches a key to a
## call and makes it; every guard lives where the operation does.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerChords extends RefCounted

## A key press this holds no answer for.
const NOTHING: int = 0

var _bound: Dictionary[int, Callable] = {}


## Learn the table. The values are the methods themselves rather than their
## names: a name in a table goes stale the day a method is renamed, and nothing
## says so until somebody presses the key.
func bind(bound: Dictionary[int, Callable]) -> void:
	_bound = bound


## The chord a key event spells, or nothing when it spells none.
##
## Only a real press counts. A release and an auto-repeat both arrive as key
## events, and acting on either turns one press into two operations - two
## statements deleted where somebody deleted one.
static func chord_of(event: InputEvent) -> int:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return NOTHING
	var chord: int = key.keycode
	if key.ctrl_pressed:
		chord |= KEY_MASK_CTRL
	if key.shift_pressed:
		chord |= KEY_MASK_SHIFT
	return chord


func has(chord: int) -> bool:
	return chord != NOTHING and _bound.has(chord)


## Do what that chord means. The caller has already asked `has()`.
func perform(chord: int) -> void:
	await _bound[chord].call()
