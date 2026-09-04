## Which key means which operation.
##
## The table itself is not worth a test - it is a list, and a test asserting the
## list contains what the list contains proves nothing. What is worth testing is
## what a key event has to be before it counts, because getting that wrong turns
## one press into two operations: two statements deleted where somebody deleted
## one, and an undo that only puts half of it back.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

var _chords: ComposerChords = null


func before_each() -> void:
	_chords = ComposerChords.new()


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


#region What counts as a press
## A key going down is the press. Everything else is not.
##
## Both rows matter and neither is hypothetical: a release arrives for every
## press, and holding a key produces a stream of repeats. Acting on either
## repeats the operation.
const NOT_A_PRESS: Array = [
	[false, false, "a key coming back up"],
	[true, true, "a key held down and repeating"],
]


func test_only_a_key_going_down_spells_a_chord() -> void:
	assert_ne(
		ComposerChords.chord_of(_key(KEY_DELETE)),
		ComposerChords.NOTHING,
		"a press spells one"
	)
	for row: Array in NOT_A_PRESS:
		var pressed: bool = row[0]
		var echo: bool = row[1]
		var described: String = row[2]

		assert_eq(
			ComposerChords.chord_of(_key(KEY_DELETE, pressed, echo)),
			ComposerChords.NOTHING,
			described
		)


## Something that is not a key spells nothing rather than crashing.
func test_an_event_that_is_not_a_key_spells_nothing() -> void:
	assert_eq(
		ComposerChords.chord_of(InputEventMouseButton.new()), ComposerChords.NOTHING
	)


## The modifiers are part of the chord, so Ctrl-Z is not Z.
func test_the_modifiers_are_part_of_the_chord() -> void:
	var bare: InputEventKey = _key(KEY_Z)
	var held: InputEventKey = _key(KEY_Z)
	held.ctrl_pressed = true
	var both: InputEventKey = _key(KEY_Z)
	both.ctrl_pressed = true
	both.shift_pressed = true

	var plain: int = ComposerChords.chord_of(bare)
	var undo: int = ComposerChords.chord_of(held)
	var redo: int = ComposerChords.chord_of(both)

	assert_ne(plain, undo, "Z is not Ctrl-Z")
	assert_ne(undo, redo, "and Ctrl-Z is not Ctrl-Shift-Z")
#endregion


#region Doing what it means
## A bound chord is answered, and an unbound one is not.
func test_a_bound_chord_is_answered_and_an_unbound_one_is_not() -> void:
	var done: Array[String] = []
	_chords.bind({
		KEY_DELETE: func _removed() -> void: done.append("remove"),
	})

	var bound: int = ComposerChords.chord_of(_key(KEY_DELETE))
	var loose: int = ComposerChords.chord_of(_key(KEY_F5))

	assert_true(_chords.has(bound), "Delete is spoken for")
	assert_false(_chords.has(loose), "F5 is not")
	await _chords.perform(bound)
	assert_eq(done, ["remove"] as Array[String], "and Delete did its one thing")


## Nothing at all is not a chord, whatever the table holds.
func test_nothing_is_never_a_bound_chord() -> void:
	_chords.bind({ComposerChords.NOTHING: func _never() -> void: pass})

	assert_false(
		_chords.has(ComposerChords.NOTHING),
		"a key event that spelled nothing performs nothing"
	)
#endregion
