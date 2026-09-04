## The keys, and the one place each of them goes.
##
## The rule this holds to is that no shortcut has two handlers. GraphEdit asks
## about Delete, Ctrl-C, Ctrl-X, Ctrl-V and Ctrl-D itself, so those arrive as the
## widget's own requests and this project's chord table must not list them - a
## key bound twice deletes two statements where somebody deleted one.
##
## Nudging is the other half: one press is one placement and one thing to undo,
## however many cards moved, and a key held down produces repeats that must be
## ignored or a lean on the arrow key becomes a graph nobody can put back.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

var canvas: ComposerCanvas = null


func before_each() -> void:
	canvas = ComposerCanvas.new()
	canvas.size = Vector2(1280.0, 720.0)
	add_child_autofree(canvas)


func after_each() -> void:
	canvas = null


func _shown() -> void:
	await canvas.show_graph(Sample.build())


func _key(code: Key, shift: bool = false, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	event.shift_pressed = shift
	return event


#region What a key means
## Arrows nudge, Shift nudges further, and everything else means nothing here.
const READINGS: Array = [
	[KEY_LEFT, false, ComposerCanvasGestures.Kind.NUDGE, "left"],
	[KEY_RIGHT, false, ComposerCanvasGestures.Kind.NUDGE, "right"],
	[KEY_UP, false, ComposerCanvasGestures.Kind.NUDGE, "up"],
	[KEY_DOWN, false, ComposerCanvasGestures.Kind.NUDGE, "down"],
	[KEY_HOME, false, ComposerCanvasGestures.Kind.FRAME, "home"],
	[KEY_F5, false, ComposerCanvasGestures.Kind.NONE, "a key this does not answer for"],
]


func test_each_key_means_what_it_should() -> void:
	for row: Array in READINGS:
		var code: Key = row[0]
		var shift: bool = row[1]
		var wanted: ComposerCanvasGestures.Kind = row[2]
		var described: String = row[3]

		assert_eq(
			ComposerCanvasGestures.read_key(_key(code, shift)).kind, wanted, described
		)


## Shift moves it further, in the same direction.
func test_shift_nudges_further_the_same_way() -> void:
	var near: ComposerCanvasGestures.Reading = ComposerCanvasGestures.read_key(
		_key(KEY_RIGHT)
	)
	var far: ComposerCanvasGestures.Reading = ComposerCanvasGestures.read_key(
		_key(KEY_RIGHT, true)
	)

	assert_eq(near.by, Vector2.RIGHT * ComposerCanvasGestures.NUDGE, "one unit")
	assert_eq(far.by, Vector2.RIGHT * ComposerCanvasGestures.NUDGE_FAR, "and ten")
	assert_gt(far.by.x, near.by.x, "further, and the same way")


## A key coming back up, and a key repeating, are not presses.
func test_only_a_key_going_down_nudges() -> void:
	var released: InputEventKey = _key(KEY_RIGHT)
	released.pressed = false

	assert_eq(
		ComposerCanvasGestures.read_key(released).kind,
		ComposerCanvasGestures.Kind.NONE,
		"a release moves nothing"
	)
	assert_eq(
		ComposerCanvasGestures.read_key(_key(KEY_RIGHT, false, true)).kind,
		ComposerCanvasGestures.Kind.NONE,
		"and neither does a repeat"
	)
#endregion


#region Nudging on the canvas
## One press moves everything picked, and reports it once.
func test_one_press_reports_one_placement_for_every_picked_card() -> void:
	await _shown()
	canvas.card_for(Sample.APPLY).selected = true
	canvas.card_for(Sample.CUE).selected = true
	watch_signals(canvas)
	var was: Vector2 = canvas.card_for(Sample.APPLY).position_offset

	canvas._on_key(_key(KEY_RIGHT))

	assert_signal_emit_count(canvas, "nodes_positioned", 1, "reported once")
	var said: Array = get_signal_parameters(canvas, "nodes_positioned")
	var moved: Dictionary = said[0]
	assert_eq(moved.size(), 2, "both picked cards")
	var landed: Vector2 = moved[Sample.APPLY]
	assert_eq(
		landed, was + Vector2.RIGHT * ComposerCanvasGestures.NUDGE, "one unit right"
	)


## With nothing picked there is nothing to move, and nothing is reported.
func test_nudging_nothing_reports_nothing() -> void:
	await _shown()
	watch_signals(canvas)

	canvas._on_key(_key(KEY_RIGHT))

	assert_signal_not_emitted(canvas, "nodes_positioned")
#endregion


#region One handler per shortcut
## Every shortcut the widget asks about is passed on as an intention.
##
## What each one does to the file is the screen's, so a menu item and a key
## cannot end up meaning two different things.
func test_the_widgets_shortcuts_are_passed_on_as_requests() -> void:
	await _shown()
	watch_signals(canvas)

	canvas.delete_nodes_request.emit([] as Array)
	canvas.copy_nodes_request.emit()
	canvas.cut_nodes_request.emit()
	canvas.paste_nodes_request.emit()
	canvas.duplicate_nodes_request.emit()

	for reported: String in [
		"delete_requested",
		"copy_requested",
		"cut_requested",
		"paste_requested",
		"duplicate_requested",
	]:
		assert_signal_emitted(canvas, reported, "%s was passed on" % reported)


## The chord table lists none of the keys the widget already asks about.
##
## The gate this task exists for: a key bound in both places fires twice, and
## Delete pressed once removes two statements.
func test_no_shortcut_the_widget_asks_about_is_also_a_chord() -> void:
	var screen: ComposerScreen = ComposerScreen.new()
	screen.size = Vector2(1280.0, 720.0)
	add_child_autofree(screen)
	await get_tree().process_frame

	var taken: int = 0
	for code: int in [
		KEY_DELETE,
		KEY_C | KEY_MASK_CTRL,
		KEY_X | KEY_MASK_CTRL,
		KEY_V | KEY_MASK_CTRL,
		KEY_D | KEY_MASK_CTRL,
	]:
		assert_false(
			screen.chords().has(code),
			"the widget asks about this one, so the chord table must not"
		)
		taken += 1
	assert_eq(taken, 5, "every one of them was checked")


## The keys the widget does not ask about are still bound.
func test_the_keys_the_widget_ignores_are_still_bound() -> void:
	var screen: ComposerScreen = ComposerScreen.new()
	screen.size = Vector2(1280.0, 720.0)
	add_child_autofree(screen)
	await get_tree().process_frame

	for code: int in [
		KEY_S | KEY_MASK_CTRL, KEY_Z | KEY_MASK_CTRL, KEY_Y | KEY_MASK_CTRL, KEY_SPACE
	]:
		assert_true(screen.chords().has(code), "still reachable")
#endregion
