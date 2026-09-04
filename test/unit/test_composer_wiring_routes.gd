## Every gesture that changes a wire, and what it says afterwards.
##
## The routes are thin on purpose - the controller decides, and these carry the
## answer. So what is worth testing is the carrying: that `changed` is said when
## and only when the file moved, that a refusal reaches somebody, and that
## unplugging an argument from the Inspector finds the same cable pulling it off
## the canvas would.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"
const CONSUMER: String = "apply_gameplay_effect"

var _routes: ComposerWiringRoutes = null
var _document: ComposerDocument = null


func before_each() -> void:
	_routes = ComposerWiringRoutes.new()
	_document = ComposerDocument.new()
	_routes.bind(_document)
	watch_signals(_routes)


func _open(statements: Array) -> void:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	_document.open(HEAD + body, PATH)


func _node(written: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		if node.text.contains(written):
			return node
	return null


## What a gesture that moved the file owes: it says it worked, it is one step to
## take back, and it is announced exactly once. Stated here because it is one
## contract, not one per gesture.
func _assert_one_step(done: bool, described: String) -> void:
	assert_true(done, described)
	assert_eq(_document.history().depth(), 1, "%s: one step" % described)
	assert_signal_emit_count(_routes, "changed", 1, "%s: announced once" % described)


#region Saying what happened
## A gesture that moved the file says so, once.
func test_a_gesture_that_moved_the_file_says_so() -> void:
	_open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])

	var done: bool = _routes.break_pin(
		_node("var caster").id, ComposerReader.VALUE_OUT
	)

	_assert_one_step(done, "the cable came off")
	assert_eq(_document.graph().data_connections().size(), 0, "and is gone")


## A gesture that changed nothing says nothing.
##
## A canvas redrawn for every gesture that did nothing is a canvas that flickers
## while somebody clicks around, and a screen that cannot tell the two apart.
func test_a_gesture_that_changed_nothing_announces_nothing() -> void:
	_open(["apply_gameplay_effect(burning, null, 1.0)"])

	var done: bool = _routes.break_pin(_node(CONSUMER).id, ComposerReader.VALUE_OUT)

	assert_false(done, "that card declares no value to break")
	assert_signal_not_emitted(_routes, "changed")


## A refusal reaches somebody who can read it.
func test_a_refusal_is_passed_on_rather_than_swallowed() -> void:
	_open(["apply_gameplay_effect(burning, null, 1.0)"])

	var done: bool = _routes.rewrite_field(_node(CONSUMER).id, 97, "2.5")

	assert_false(done, "there is no ninety-eighth argument")
	assert_signal_emitted(_routes, "refused", "and the reason was passed on")
	assert_signal_not_emitted(_routes, "changed", "with nothing announced as changed")
#endregion


#region Unplugging one argument
## The Inspector's Disconnect takes off the same cable the canvas would.
func test_unplugging_an_argument_takes_off_its_cable() -> void:
	_open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])
	assert_eq(_document.graph().data_connections().size(), 1, "one to take off")

	var done: bool = _routes.unplug_argument(_node(CONSUMER).id, 1)

	_assert_one_step(done, "the cable came off")
	assert_eq(_document.graph().data_connections().size(), 0, "and is gone")


## An argument with no cable on it is not unplugged, and nothing is announced.
func test_unplugging_an_argument_with_no_cable_does_nothing() -> void:
	_open(["apply_gameplay_effect(burning, null, 1.0)"])
	var before: String = _document.printed()

	var done: bool = _routes.unplug_argument(_node(CONSUMER).id, 1)

	assert_false(done, "there was nothing on it")
	assert_eq(_document.printed(), before, "so the file is untouched")
	assert_signal_not_emitted(_routes, "changed")


## Asked before anything is open, it answers rather than failing.
func test_unplugging_with_nothing_open_answers_no() -> void:
	assert_false(_routes.unplug_argument(&"whoever", 0))
#endregion


#region Moving what is on a pin
## Ctrl-drag moves every cable on the pin, as one step.
func test_moving_a_pin_moves_all_of_it_at_once() -> void:
	_open([
		"var first: AbilitySystemComponent = owner_asc",
		"var second: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, first, 1.0)",
		"apply_gameplay_effect(chilled, first, 1.0)",
	])

	var done: bool = _routes.move_pin(
		_node("var first").id,
		ComposerReader.VALUE_OUT,
		_node("var second").id,
		ComposerReader.VALUE_OUT
	)

	_assert_one_step(done, "both cables moved")
	assert_true(
		_document.printed().contains("second"), "onto the local they were moved to"
	)
#endregion


#region Wired to the canvas
## A wire dropped on the canvas reaches the file.
##
## End to end, through the same connection the screen makes. Each half of this
## is tested on its own above and in the canvas's own tests, and neither would
## notice if `listen_to` stopped connecting one of them - a gesture that reaches
## nothing looks exactly like a gesture the file refused.
func test_a_wire_dropped_on_the_canvas_reaches_the_file() -> void:
	_open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, null, 1.0)",
	])
	var canvas: ComposerCanvas = ComposerCanvas.new()
	canvas.size = Vector2(1280.0, 720.0)
	add_child_autofree(canvas)
	await canvas.show_graph(_document.graph())
	_routes.listen_to(canvas)

	var producer: ComposerCard = canvas.card_for(_node("var caster").id)
	var consumer: ComposerCard = canvas.card_for(_node(CONSUMER).id)
	canvas.connection_request.emit(
		producer.name,
		producer.right_index_for_port(ComposerReader.VALUE_OUT),
		consumer.name,
		consumer.left_index_for_port(StringName(ComposerReader.ARGUMENT % 1))
	)

	assert_eq(
		_document.graph().data_connections().size(), 1, "the file holds the cable now"
	)
	assert_signal_emitted(_routes, "changed", "and the screen was told to redraw")


## Alt-clicking a pin on the canvas reaches the file too.
func test_alt_clicking_a_pin_on_the_canvas_reaches_the_file() -> void:
	_open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])
	var canvas: ComposerCanvas = ComposerCanvas.new()
	canvas.size = Vector2(1280.0, 720.0)
	add_child_autofree(canvas)
	await canvas.show_graph(_document.graph())
	_routes.listen_to(canvas)

	canvas.break_all_requested.emit(_node("var caster").id, ComposerReader.VALUE_OUT)

	assert_eq(_document.graph().data_connections().size(), 0, "the cable came off")
	assert_signal_emitted(_routes, "changed")
#endregion
