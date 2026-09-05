## A hand on the mouse, as far as a script can be one.
##
## Composer 3.2 draws on Godot's `GraphEdit`, so picking a card, dragging one,
## sweeping a box, panning and zooming are the widget's and are read inside
## `_gui_input` - a method no script can call. The only way to exercise them is
## to put an event into the viewport the way the operating system does and let
## Godot route it.
##
## Two things have to be right or nothing lands, and both were measured here
## rather than reasoned about:
##
## 1. **`push_input` reads window pixels, not viewport pixels.** This game
##    stretches a 1920x1080 canvas into whatever window it is given, so a
##    control sitting at (200, 140) in the viewport is somewhere else on the
##    window. `at()` maps through `get_final_transform()`, which is the same
##    transform Godot applies to a real click on its way in.
##
## 2. **A Control outside a `CanvasLayer` is hit-tested through the camera.**
##    This game keeps a `Camera2D` autoload, and its canvas transform was
##    offsetting the default layer by (960, 560) - so the Composer was drawn
##    there, clicked at there, and neither matched where the code thought it
##    was. The harness puts the screen in a layer of its own.
##
## With those two, a pushed click hovers, presses, selects and drags exactly as
## a real one does. Everything above is the caller's to get right; this only
## puts events in.
##
## @meta_license: MIT
extends RefCounted

## How many steps a drag is broken into. GraphEdit begins a node move on the
## first motion with the button down, so a drag that jumped straight to its
## destination would be a press and a release in two different places.
const DRAG_STEPS: int = 8

var _viewport: Viewport = null
var _tree: SceneTree = null


func _init(viewport: Viewport, tree: SceneTree) -> void:
	_viewport = viewport
	_tree = tree


## Where a point inside the game's canvas is, in the pixels `push_input` reads.
func at(point: Vector2) -> Vector2:
	return _viewport.get_final_transform() * point


## The middle of a control, ready to be clicked.
func on(control: Control) -> Vector2:
	return at(control.get_global_rect().get_center())


func frames(count: int) -> void:
	for _step: int in count:
		await _tree.process_frame


#region Putting events in
func move(to: Vector2, held: MouseButtonMask = 0) -> void:
	var made: InputEventMouseMotion = InputEventMouseMotion.new()
	made.position = to
	made.global_position = to
	made.button_mask = held
	_viewport.push_input(made)
	await frames(1)


func press(where: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, mods: int = 0) -> void:
	_viewport.push_input(_button(where, button, true, mods))
	await frames(1)


func release(where: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, mods: int = 0) -> void:
	_viewport.push_input(_button(where, button, false, mods))
	await frames(2)


## Press and release in the same place, which is what a click is.
func click(
	where: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, mods: int = 0
) -> void:
	await hold(mods)
	await move(where)
	await press(where, button, mods)
	await release(where, button, mods)
	await let_go(mods)
	await frames(2)


## Press, travel, release. The travel is what tells the widget a drag began.
func drag(
	from: Vector2, to: Vector2, mods: int = 0, button: MouseButton = MOUSE_BUTTON_LEFT
) -> void:
	await hold(mods)
	await move(from)
	await press(from, button, mods)
	var held: MouseButtonMask = (
		MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	)
	var last: Vector2 = from
	for step: int in DRAG_STEPS:
		var here: Vector2 = from.lerp(to, float(step + 1) / float(DRAG_STEPS))
		var made: InputEventMouseMotion = InputEventMouseMotion.new()
		made.position = here
		made.global_position = here
		made.button_mask = held
		made.relative = here - last
		_apply(made, mods)
		_viewport.push_input(made)
		last = here
		await frames(1)
	await release(to, button, mods)
	await let_go(mods)
	await frames(2)


## A drag that is abandoned rather than finished: it is let go somewhere the
## gesture cannot mean anything.
##
## No Escape. Pressing it mid-drag left the widget believing a gesture was still
## in progress, and the next case's click went into that instead of onto the
## card it was aimed at - which looked exactly like the card ignoring it.
func drag_and_cancel(from: Vector2, to: Vector2, mods: int = 0) -> void:
	await drag(from, to, mods)


func wheel(where: Vector2, up: bool) -> void:
	var which: MouseButton = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	_viewport.push_input(_button(where, which, true))
	_viewport.push_input(_button(where, which, false))
	await frames(2)


func key(code: Key, mods: int = 0) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	_apply(down, mods)
	_viewport.push_input(down)
	await frames(2)

	var up: InputEventKey = InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	_apply(up, mods)
	_viewport.push_input(up)
	await frames(2)


## Type a word, one key event per character, the way a text field is filled in.
func write(written: String) -> void:
	for index: int in written.length():
		var made: InputEventKey = InputEventKey.new()
		made.pressed = true
		made.unicode = written.unicode_at(index)
		made.keycode = KEY_NONE
		_viewport.push_input(made)
		await frames(1)
	await frames(2)
#endregion


#region Modifiers
const ALT: int = 1
const CTRL: int = 2
const SHIFT: int = 4

## Which key each modifier is, for holding it down for real.
const KEYS: Dictionary[int, Key] = {
	ALT: KEY_ALT,
	CTRL: KEY_CTRL,
	SHIFT: KEY_SHIFT,
}


## Hold the modifier keys down the way a hand does.
##
## Setting `ctrl_pressed` on the event is not enough: a widget may ask `Input`
## whether the key is down rather than reading the event, and GraphEdit's
## additive selection does exactly that - measured, after a Ctrl-click that
## carried the flag on the event alone selected one card instead of two.
## `Input.parse_input_event` is what updates that state.
func hold(mods: int) -> void:
	for bit: int in KEYS:
		if (mods & bit) != 0:
			_state(KEYS[bit], true)
	if mods != 0:
		await frames(1)


func let_go(mods: int) -> void:
	for bit: int in KEYS:
		if (mods & bit) != 0:
			_state(KEYS[bit], false)
	if mods != 0:
		await frames(1)


func _state(code: Key, down: bool) -> void:
	var made: InputEventKey = InputEventKey.new()
	made.keycode = code
	made.physical_keycode = code
	made.pressed = down
	Input.parse_input_event(made)
	Input.flush_buffered_events()


func _apply(event: InputEventWithModifiers, mods: int) -> void:
	event.alt_pressed = (mods & ALT) != 0
	event.ctrl_pressed = (mods & CTRL) != 0
	event.shift_pressed = (mods & SHIFT) != 0


func _button(
	where: Vector2, button: MouseButton, down: bool, mods: int = 0
) -> InputEventMouseButton:
	var made: InputEventMouseButton = InputEventMouseButton.new()
	made.button_index = button
	made.button_mask = _mask_for(button) if down else 0
	made.pressed = down
	made.position = where
	made.global_position = where
	_apply(made, mods)
	return made


static func _mask_for(button: MouseButton) -> MouseButtonMask:
	match button:
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
		_:
			return MOUSE_BUTTON_MASK_LEFT
#endregion
