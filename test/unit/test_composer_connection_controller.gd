## Dragging a wire, and what the file says afterwards.
##
## A value connection in this projection is not a record kept beside the source
## - it *is* the argument text. So every test here reads the file back and asks
## what it now says, rather than asking the controller what it thinks it did.
## The two can only agree if the transformation was real.
##
## The other half is the history. One thing a person did has to be one thing to
## undo: a fanout broken into four commits leaves somebody pressing Ctrl-Z four
## times and watching their ability come back a quarter at a time.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
const REFUSING: GDScript = preload("res://test/fixtures/refusing_document.gd")

## The declared default of `apply_gameplay_effect`'s third argument, which is
## deliberately not the zero of its type: a disconnect that produced `0.0` would
## have silently changed what the ability does while claiming to unplug a wire.
const DECLARED_LEVEL: String = "1.0"
const ZERO_LEVEL: String = "0.0"

var _controller: ComposerConnectionController = null


#region Getting there
func _script(statements: Array) -> String:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return HEAD + body


func _open(statements: Array) -> ComposerDocument:
	return _bind(ComposerDocument.new(), statements)


## A fresh controller on a freshly opened document.
##
## Fresh per document rather than per test, because a table-driven test runs
## several documents through it and `assert_signal_emitted` only asks whether a
## signal has ever fired. On a controller kept across rows, the second row would
## pass on the first row's refusal - the vacuous pass that costs nothing to
## avoid and everything to notice later.
func _bind(document: ComposerDocument, statements: Array) -> ComposerDocument:
	document.open(_script(statements), PATH)
	_fresh().bind(document)
	return document


## A controller with nothing bound to it, listened to.
func _fresh() -> ComposerConnectionController:
	_controller = ComposerConnectionController.new()
	watch_signals(_controller)
	return _controller


## The node whose line contains `written`. By text, never by id: an id is
## derived from the line a statement sits on, so it moves when anything above it
## does, and a test that held one would be testing line numbers.
func _node(document: ComposerDocument, written: String) -> ComposerNode:
	for node: ComposerNode in ComposerProjection.statements(document.graph()):
		if node.text.contains(written):
			return node
	return null


## Ask the controller to send the local one statement declares into one
## argument of another, named the way a person would point at them.
##
## Every connecting test needs exactly this and then differs only in what it
## expects afterwards, so it is arranged once: four copies of the same six lines
## are four chances to test something subtly different while reading alike.
func _join(
	document: ComposerDocument, producer: String, consumer: String, slot: int
) -> bool:
	return _controller.connect_edge(
		ComposerReader.wire(
			_node(document, producer).id,
			ComposerReader.VALUE_OUT,
			_node(document, consumer).id,
			StringName(ComposerReader.ARGUMENT % slot)
		)
	)


## The one line of the body a statement occupies now.
func _line(document: ComposerDocument, written: String) -> String:
	for line: String in document.printed().split("\n"):
		if line.contains(written):
			return line.strip_edges()
	return ""
#endregion


#region Connecting
## What a made connection has to leave behind, whatever the drag was.
##
## Two rows because the interesting difference is what the argument held first:
## a literal has nothing to release, and a local has to stop being named. The
## assertions are the same for both, which is the point - a reconnect is not a
## second operation with its own rules, it is the same one over an argument that
## was not empty.
const MADE: Array = [
	[
		[
			"var caster: AbilitySystemComponent = owner_asc",
			"apply_gameplay_effect(burning, null, 1.0)",
		],
		"var caster", 1,
		"apply_gameplay_effect(burning, caster, 1.0)",
		"a literal argument becomes the local",
	],
	[
		[
			"var first: AbilitySystemComponent = owner_asc",
			"var second: AbilitySystemComponent = owner_asc",
			"apply_gameplay_effect(burning, first, 1.0)",
		],
		"var second", 1,
		"apply_gameplay_effect(burning, second, 1.0)",
		"an argument that named a local names the new one",
	],
]

## Everything that must be refused before a character is written, and why.
##
## Scope first: the reader will not draw a cable out of a local declared below,
## so a controller that wrote one would leave a file that parses, does not
## compile, and shows nothing wrong on the canvas.
const REFUSED: Array = [
	[
		[
			"apply_gameplay_effect(burning, null, 1.0)",
			"var caster: AbilitySystemComponent = owner_asc",
		],
		"var caster", 1,
		"a local declared below does not exist further up",
	],
	[
		[
			"var strength: float = 2.0",
			"apply_gameplay_effect(burning, null, 1.0)",
		],
		"var strength", 0,
		"a float is not an effect",
	],
]


## A wire that is made is written, read back as a cable, and undone in one step.
##
## The middle assertion is the one that carries weight. Text containing the name
## is not a connection: the reader has to agree that this argument *is* that
## local, and only then does the canvas draw a cable where somebody dropped one.
func test_a_connection_is_written_read_back_and_recorded_once() -> void:
	for row: Array in MADE:
		var statements: Array = row[0]
		var producer: String = row[1]
		var slot: int = row[2]
		var expected: String = row[3]
		var described: String = row[4]

		var document: ComposerDocument = _open(statements)
		var done: bool = _join(document, producer, "apply_gameplay_effect", slot)

		assert_true(done, described)
		assert_eq(_line(document, "apply_gameplay_effect"), expected, described)
		assert_eq(
			document.graph().data_connections().size(), 1, "%s: one cable" % described
		)
		assert_eq(document.history().depth(), 1, "%s: one step back" % described)


## A refused wire says why and leaves everything exactly where it was.
func test_a_refusal_says_why_and_changes_nothing() -> void:
	for row: Array in REFUSED:
		var statements: Array = row[0]
		var producer: String = row[1]
		var slot: int = row[2]
		var described: String = row[3]

		var document: ComposerDocument = _open(statements)
		var before: String = document.printed()
		var wires: int = document.graph().data_connections().size()

		var done: bool = _join(document, producer, "apply_gameplay_effect", slot)

		assert_false(done, described)
		assert_signal_emitted(_controller, "refused", "%s: said out loud" % described)
		assert_eq(document.printed(), before, "%s: the file is untouched" % described)
		assert_eq(
			document.graph().data_connections().size(), wires,
			"%s: so is the canvas" % described
		)
		assert_eq(document.history().depth(), 0, "%s: nothing to undo" % described)
#endregion


#region Disconnecting
## Unplugging restores what the method declares, not the zero of the type.
##
## `apply_gameplay_effect` declares its level as `1.0`. Writing `0.0` here would
## be the tool quietly halving an effect while reporting that it removed a wire
## - the kind of change nobody looks for, because they did not make it.
func test_unplugging_writes_back_the_declared_default() -> void:
	var document: ComposerDocument = _open([
		"var strength: float = 2.0",
		"apply_gameplay_effect(burning, null, strength)",
	])
	var wire: ComposerGraph.Connection = document.graph().data_connections()[0]

	var done: bool = _controller.disconnect_edge(wire)

	assert_true(done, "the wire came off")
	assert_eq(
		_line(document, "apply_gameplay_effect"),
		"apply_gameplay_effect(burning, null, %s)" % DECLARED_LEVEL,
		"the argument holds what the method declares"
	)
	assert_false(
		_line(document, "apply_gameplay_effect").contains(ZERO_LEVEL),
		"and not the zero of its type"
	)
	assert_eq(document.graph().data_connections().size(), 0, "the cable is gone")
	assert_eq(document.history().depth(), 1, "as one step")


## A cable the file already holds can always be taken off, types or not.
##
## The reader draws what somebody wrote, and what somebody wrote can be a local
## in an argument that does not fit it - that is a thing to warn about, not a
## thing to trap them in. Judging the types on the way out would leave a cable
## on the canvas that the tool refuses to unplug.
func test_a_cable_whose_types_disagree_can_still_be_unplugged() -> void:
	var document: ComposerDocument = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(caster, null, 1.0)",
	])
	var wires: Array[ComposerGraph.Connection] = document.graph().data_connections()
	assert_eq(wires.size(), 1, "the file says so, whatever the types say")

	var done: bool = _controller.disconnect_edge(wires[0])

	assert_true(done, "so it comes off")
	assert_eq(document.graph().data_connections().size(), 0, "and it is gone")


## An argument is never left empty. The wire *was* the argument.
func test_unplugging_leaves_a_call_that_still_reads() -> void:
	var document: ComposerDocument = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])

	assert_true(_controller.disconnect_edge(document.graph().data_connections()[0]))

	assert_eq(
		_line(document, "apply_gameplay_effect"),
		"apply_gameplay_effect(burning, null, 1.0)",
		"three arguments still, one of them a value"
	)
	assert_true(document.graph().is_editable(), document.graph().blocked_reason())
#endregion


#region Breaking everything on a pin
## A local feeding two statements is unplugged from both, once.
func test_breaking_a_fanout_is_one_commit() -> void:
	var document: ComposerDocument = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
		"apply_gameplay_effect(chilled, caster, 1.0)",
	])
	assert_eq(document.graph().data_connections().size(), 2, "two cables to start")
	var producer: ComposerNode = _node(document, "var caster")

	var done: bool = _controller.break_all(producer.id, ComposerReader.VALUE_OUT)

	assert_true(done, "both came off")
	assert_eq(document.graph().data_connections().size(), 0, "nothing is on the pin")
	assert_eq(document.history().depth(), 1, "and one undo puts both back")


## An undo after a fanout break restores every argument, because there was one
## commit to undo. This is what the history count is actually protecting.
func test_one_undo_puts_the_whole_fanout_back() -> void:
	var document: ComposerDocument = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
		"apply_gameplay_effect(chilled, caster, 1.0)",
	])
	var producer: ComposerNode = _node(document, "var caster")
	assert_true(_controller.break_all(producer.id, ComposerReader.VALUE_OUT))

	document.undo()

	assert_eq(document.graph().data_connections().size(), 2, "both cables are back")


## A pin with nothing on it is not a change, so it is not an undo either.
func test_breaking_an_empty_pin_records_nothing() -> void:
	var document: ComposerDocument = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, null, 1.0)",
	])
	var producer: ComposerNode = _node(document, "var caster")

	var done: bool = _controller.break_all(producer.id, ComposerReader.VALUE_OUT)

	assert_true(done, "there was nothing to refuse")
	assert_eq(document.history().depth(), 0, "and nothing to undo")
#endregion


#region Saying no
## A document that turns the commit down is not reported as a success.
##
## The controller cannot produce this failure itself - every transformation it
## writes reads back - so the document is stood in for. What is being tested is
## the controller's answer to a refusal, which is the only part it owns.
func test_a_refused_commit_is_not_reported_as_a_connection() -> void:
	var refusing: ComposerDocument = REFUSING.new()
	var document: ComposerDocument = _bind(refusing, [
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, null, 1.0)",
	])
	var before: String = document.printed()

	var done: bool = _join(document, "var caster", "apply_gameplay_effect", 1)

	assert_false(done, "the document said no, so the controller does too")
	assert_signal_emitted(_controller, "refused", "and passes the reason on")
	assert_eq(document.printed(), before, "with the file where it was")


## Asked about a pin that is not there, it says so rather than guessing.
func test_a_pin_that_is_gone_is_refused() -> void:
	var document: ComposerDocument = _open(["apply_gameplay_effect(burning, null, 1.0)"])
	var consumer: ComposerNode = _node(document, "apply_gameplay_effect")

	var done: bool = _controller.break_all(consumer.id, &"arg_97")

	assert_false(done, "there is no ninety-eighth argument")
	assert_signal_emitted(_controller, "refused")
	assert_eq(document.history().depth(), 0, "and nothing was written")


## With nothing open there is nothing to change, and nothing to crash on.
func test_nothing_open_refuses_instead_of_failing() -> void:
	var done: bool = _fresh().break_all(&"n5", ComposerReader.VALUE_OUT)

	assert_false(done)
	assert_signal_emitted(_controller, "refused")
#endregion


#region Moving a pin's wires
## Ctrl-drag moves every cable at once, or none of them.
func test_moving_a_fanout_re_points_all_of_it_in_one_commit() -> void:
	var document: ComposerDocument = _open([
		"var first: AbilitySystemComponent = owner_asc",
		"var second: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, first, 1.0)",
		"apply_gameplay_effect(chilled, first, 1.0)",
	])
	var origin: ComposerNode = _node(document, "var first")
	var destination: ComposerNode = _node(document, "var second")

	var done: bool = _controller.move_connections(
		origin.id, ComposerReader.VALUE_OUT, destination.id, ComposerReader.VALUE_OUT
	)

	assert_true(done, "both moved")
	assert_eq(
		_line(document, "burning"), "apply_gameplay_effect(burning, second, 1.0)"
	)
	assert_eq(
		_line(document, "chilled"), "apply_gameplay_effect(chilled, second, 1.0)"
	)
	assert_eq(document.history().depth(), 1, "as one motion")


## One endpoint the destination cannot take refuses the whole move.
##
## The half that would have fitted must not move either. A person who cancels a
## drag and finds one of their two cables re-pointed has been handed a file they
## did not ask for and cannot see the shape of.
func test_a_move_the_destination_cannot_take_moves_nothing() -> void:
	var document: ComposerDocument = _open([
		"var first: AbilitySystemComponent = owner_asc",
		"var second: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(first, null, 1.0)",
		"apply_gameplay_effect(burning, first, 1.0)",
	])
	var before: String = document.printed()
	var origin: ComposerNode = _node(document, "var first")
	var destination: ComposerNode = _node(document, "var second")

	var done: bool = _controller.move_connections(
		origin.id, ComposerReader.VALUE_OUT, destination.id, ComposerReader.VALUE_OUT
	)

	assert_false(done, "a system component does not fit an effect")
	assert_signal_emitted(_controller, "refused")
	assert_eq(document.printed(), before, "so neither cable moved")
	assert_eq(document.history().depth(), 0, "and there is nothing to undo")
#endregion
