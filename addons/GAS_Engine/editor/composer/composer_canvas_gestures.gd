## What a mouse event on the canvas meant, if it meant anything.
##
## Two gestures are the Composer's and everything else is the widget's: Alt-click
## clears a pin, Ctrl-drag moves what is on one. Reading them is a small state
## machine - a press remembers a pin, a release either lands on another or does
## not - and it lives here rather than in the canvas so the canvas is about
## drawing a graph.
##
## Nothing here emits, changes a file or touches a card. It is asked what an
## event meant and answers; the canvas decides what to say about it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCanvasGestures extends RefCounted

## What an event turned out to be.
##
## `TAKEN` is the one worth naming: a Ctrl-press starts a drag and produces no
## request at all, but the widget must not also treat it as the start of a card
## drag - so "nothing to report" and "nothing happened" have to be different
## answers.
enum Kind { NONE, TAKEN, BREAK, MOVE, NUDGE, FRAME }


class Reading extends RefCounted:
	var kind: ComposerCanvasGestures.Kind = ComposerCanvasGestures.Kind.NONE
	var from: ComposerPins.Pin = ComposerPins.Pin.new()
	var to: ComposerPins.Pin = ComposerPins.Pin.new()

	## How far a nudge moves what is picked, in graph units.
	var by: Vector2 = Vector2.ZERO

	## Whether the canvas should stop the widget seeing this event.
	func is_consumed() -> bool:
		return kind != ComposerCanvasGestures.Kind.NONE


## The pin a Ctrl-drag started on, while one is in progress. Held nowhere else
## and written to nothing: a cancelled drag must leave no trace.
var _moving: ComposerPins.Pin = ComposerPins.Pin.new()


## What this event means, given where the cards are.
##
## For an event the canvas itself received, which is one that landed on empty
## space. The pin is looked up and the answer is the same one a card's own
## event gets, from the same state machine: a Ctrl-drag begun on a card and
## let go over the canvas is one gesture, and two state machines would make it
## two halves of nothing.
func read(
	event: InputEvent, cards: Dictionary[StringName, ComposerCard], zoom: float
) -> ComposerCanvasGestures.Reading:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return ComposerCanvasGestures.Reading.new()
	return read_pin(button, ComposerPins.at(cards, zoom, button.position))


## What this event means, on a pin that has already been found.
##
## For an event a card received. The release is not asked to carry the
## modifier: somebody who lets go of Ctrl before the mouse button has still
## made the gesture, and the drag being in progress is what says so.
func read_pin(
	event: InputEventMouseButton, pin: ComposerPins.Pin
) -> ComposerCanvasGestures.Reading:
	var made: ComposerCanvasGestures.Reading = ComposerCanvasGestures.Reading.new()
	if event == null or event.button_index != MOUSE_BUTTON_LEFT:
		return made

	if event.pressed and event.alt_pressed:
		return _breaking(made, pin)
	if event.pressed and event.ctrl_pressed:
		return _starting(made, pin)
	if not event.pressed and _moving.is_found():
		return _finishing(made, pin)
	return made


func _breaking(
	made: ComposerCanvasGestures.Reading, pin: ComposerPins.Pin
) -> ComposerCanvasGestures.Reading:
	if not pin.is_found():
		return made
	made.kind = ComposerCanvasGestures.Kind.BREAK
	made.from = pin
	return made


## A press on a pin begins a move and says nothing yet. A press on nothing is not
## this gesture at all, and is handed straight back to the widget.
func _starting(
	made: ComposerCanvasGestures.Reading, pin: ComposerPins.Pin
) -> ComposerCanvasGestures.Reading:
	if not pin.is_found():
		return made
	_moving = pin
	made.kind = ComposerCanvasGestures.Kind.TAKEN
	return made


## The release ends the drag whatever it landed on. Only a landing that could
## mean a move is reported as one - the two pins have to face the same way, and
## be two - but the drag is over either way, or a later ordinary click would
## finish a gesture nobody was still making.
func _finishing(
	made: ComposerCanvasGestures.Reading, pin: ComposerPins.Pin
) -> ComposerCanvasGestures.Reading:
	var from: ComposerPins.Pin = _moving
	_moving = ComposerPins.Pin.new()
	made.kind = ComposerCanvasGestures.Kind.TAKEN
	if not pin.is_found() or pin.is_output != from.is_output or pin.is_same_as(from):
		return made
	made.kind = ComposerCanvasGestures.Kind.MOVE
	made.from = from
	made.to = pin
	return made


#region Keys
## How far an arrow moves what is picked, and how far it moves it with Shift.
const NUDGE: float = 1.0
const NUDGE_FAR: float = 10.0

const NUDGES: Dictionary[int, Vector2] = {
	KEY_LEFT: Vector2.LEFT,
	KEY_RIGHT: Vector2.RIGHT,
	KEY_UP: Vector2.UP,
	KEY_DOWN: Vector2.DOWN,
}


## What this key means, if it means anything here.
##
## A release and an auto-repeat are both ignored. Held down, an arrow would push
## a graph off the screen and leave somebody with as many things to undo as the
## keyboard managed to send.
static func read_key(event: InputEvent) -> ComposerCanvasGestures.Reading:
	var made: ComposerCanvasGestures.Reading = ComposerCanvasGestures.Reading.new()
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return made
	if key.keycode == KEY_HOME:
		made.kind = ComposerCanvasGestures.Kind.FRAME
		return made
	if not NUDGES.has(key.keycode):
		return made
	made.kind = ComposerCanvasGestures.Kind.NUDGE
	made.by = NUDGES[key.keycode] * (NUDGE_FAR if key.shift_pressed else NUDGE)
	return made
#endregion
