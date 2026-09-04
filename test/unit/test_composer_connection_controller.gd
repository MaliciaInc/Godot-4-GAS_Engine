## Dragging a value from one statement into another's argument.
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

const REFUSING: GDScript = preload("res://test/fixtures/refusing_document.gd")
const CONSUMER: String = "apply_gameplay_effect"

## The declared default of `apply_gameplay_effect`'s third argument, which is
## deliberately not the zero of its type: a disconnect that produced `0.0` would
## have silently changed what the ability does while claiming to unplug a wire.
const DECLARED_LEVEL: String = "1.0"
const ZERO_LEVEL: String = "0.0"


#region Getting there
## An ability open in front of a watched controller.
##
## Watched per session rather than per test, because a table-driven test runs
## several through here and `assert_signal_emitted` only asks whether a signal
## has ever fired. On a controller kept across rows, the second row would pass
## on the first row's refusal.
func _open(statements: Array, on: ComposerDocument = null) -> ComposerEditingSession:
	var session: ComposerEditingSession = ComposerEditingSession.opened(statements, on)
	watch_signals(session.controller)
	return session
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

		var session: ComposerEditingSession = _open(statements)
		var done: bool = session.controller.connect_edge(
			session.value_into(producer, CONSUMER, slot)
		)

		assert_true(done, described)
		assert_eq(session.line(CONSUMER), expected, described)
		assert_eq(session.cables(), 1, "%s: one cable" % described)
		assert_eq(session.depth(), 1, "%s: one step back" % described)


## A refused wire says why and leaves everything exactly where it was.
func test_a_refusal_says_why_and_changes_nothing() -> void:
	for row: Array in REFUSED:
		var statements: Array = row[0]
		var producer: String = row[1]
		var slot: int = row[2]
		var described: String = row[3]

		var session: ComposerEditingSession = _open(statements)
		var before: String = session.printed()
		var cables: int = session.cables()

		var done: bool = session.controller.connect_edge(
			session.value_into(producer, CONSUMER, slot)
		)

		assert_false(done, described)
		assert_signal_emitted(
			session.controller, "refused", "%s: said out loud" % described
		)
		assert_eq(session.printed(), before, "%s: the file is untouched" % described)
		assert_eq(session.cables(), cables, "%s: so is the canvas" % described)
		assert_eq(session.depth(), 0, "%s: nothing to undo" % described)
#endregion


#region Disconnecting
## Unplugging restores what the method declares, not the zero of the type.
##
## `apply_gameplay_effect` declares its level as `1.0`. Writing `0.0` here would
## be the tool quietly halving an effect while reporting that it removed a wire
## - the kind of change nobody looks for, because they did not make it.
func test_unplugging_writes_back_the_declared_default() -> void:
	var session: ComposerEditingSession = _open([
		"var strength: float = 2.0",
		"apply_gameplay_effect(burning, null, strength)",
	])

	var done: bool = session.controller.disconnect_edge(
		session.document.graph().data_connections()[0]
	)

	assert_true(done, "the wire came off")
	assert_eq(
		session.line(CONSUMER),
		"apply_gameplay_effect(burning, null, %s)" % DECLARED_LEVEL,
		"the argument holds what the method declares"
	)
	assert_false(
		session.line(CONSUMER).contains(ZERO_LEVEL), "and not the zero of its type"
	)
	assert_eq(session.cables(), 0, "the cable is gone")
	assert_eq(session.depth(), 1, "as one step")


## A cable the file already holds can always be taken off, types or not.
##
## The reader draws what somebody wrote, and what somebody wrote can be a local
## in an argument that does not fit it - that is a thing to warn about, not a
## thing to trap them in. Judging the types on the way out would leave a cable
## on the canvas that the tool refuses to unplug.
func test_a_cable_whose_types_disagree_can_still_be_unplugged() -> void:
	var session: ComposerEditingSession = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(caster, null, 1.0)",
	])
	assert_eq(session.cables(), 1, "the file says so, whatever the types say")

	var done: bool = session.controller.disconnect_edge(
		session.document.graph().data_connections()[0]
	)

	assert_true(done, "so it comes off")
	assert_eq(session.cables(), 0, "and it is gone")


## An argument is never left empty. The wire *was* the argument.
func test_unplugging_leaves_a_call_that_still_reads() -> void:
	var session: ComposerEditingSession = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])

	assert_true(
		session.controller.disconnect_edge(
			session.document.graph().data_connections()[0]
		)
	)

	assert_eq(
		session.line(CONSUMER),
		"apply_gameplay_effect(burning, null, 1.0)",
		"three arguments still, one of them a value"
	)
	assert_true(
		session.document.graph().is_editable(),
		session.document.graph().blocked_reason()
	)
#endregion


#region Breaking everything on a pin
## One local feeding two statements: the shape a fanout test needs.
const FANOUT: Array = [
	"var caster: AbilitySystemComponent = owner_asc",
	"apply_gameplay_effect(burning, caster, 1.0)",
	"apply_gameplay_effect(chilled, caster, 1.0)",
]


## A local feeding two statements is unplugged from both, once.
func test_breaking_a_fanout_is_one_commit() -> void:
	var session: ComposerEditingSession = _open(FANOUT)
	assert_eq(session.cables(), 2, "two cables to start")

	var done: bool = session.controller.break_all(
		session.node("var caster").id, ComposerReader.VALUE_OUT
	)

	assert_true(done, "both came off")
	assert_eq(session.cables(), 0, "nothing is on the pin")
	assert_eq(session.depth(), 1, "and one undo puts both back")


## An undo after a fanout break restores every argument, because there was one
## commit to undo. This is what the history count is actually protecting.
func test_one_undo_puts_the_whole_fanout_back() -> void:
	var session: ComposerEditingSession = _open(FANOUT)
	assert_true(
		session.controller.break_all(
			session.node("var caster").id, ComposerReader.VALUE_OUT
		)
	)

	session.document.undo()

	assert_eq(session.cables(), 2, "both cables are back")


## A pin with nothing on it is not a change, so it is not an undo either.
func test_breaking_an_empty_pin_records_nothing() -> void:
	var session: ComposerEditingSession = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, null, 1.0)",
	])

	var done: bool = session.controller.break_all(
		session.node("var caster").id, ComposerReader.VALUE_OUT
	)

	assert_true(done, "there was nothing to refuse")
	assert_eq(session.depth(), 0, "and nothing to undo")
#endregion


#region Saying no
## A document that turns the commit down is not reported as a success.
##
## The controller cannot produce this failure itself - every transformation it
## writes reads back - so the document is stood in for. What is being tested is
## the controller's answer to a refusal, which is the only part it owns.
func test_a_refused_commit_is_not_reported_as_a_connection() -> void:
	var refusing: ComposerDocument = REFUSING.new()
	var session: ComposerEditingSession = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, null, 1.0)",
	], refusing)
	var before: String = session.printed()

	var done: bool = session.controller.connect_edge(
		session.value_into("var caster", CONSUMER, 1)
	)

	assert_false(done, "the document said no, so the controller does too")
	assert_signal_emitted(session.controller, "refused", "and passes the reason on")
	assert_eq(session.printed(), before, "with the file where it was")


## Asked about a pin that is not there, it says so rather than guessing.
func test_a_pin_that_is_gone_is_refused() -> void:
	var session: ComposerEditingSession = _open([
		"apply_gameplay_effect(burning, null, 1.0)",
	])

	var done: bool = session.controller.break_all(session.node(CONSUMER).id, &"arg_97")

	assert_false(done, "there is no ninety-eighth argument")
	assert_signal_emitted(session.controller, "refused")
	assert_eq(session.depth(), 0, "and nothing was written")


## With nothing open there is nothing to change, and nothing to crash on.
func test_nothing_open_refuses_instead_of_failing() -> void:
	var loose: ComposerConnectionController = ComposerConnectionController.new()
	watch_signals(loose)

	var done: bool = loose.break_all(&"n5", ComposerReader.VALUE_OUT)

	assert_false(done)
	assert_signal_emitted(loose, "refused")
#endregion


#region Moving a pin's wires
## Ctrl-drag moves every cable at once, or none of them.
func test_moving_a_fanout_re_points_all_of_it_in_one_commit() -> void:
	var session: ComposerEditingSession = _open([
		"var first: AbilitySystemComponent = owner_asc",
		"var second: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, first, 1.0)",
		"apply_gameplay_effect(chilled, first, 1.0)",
	])

	var done: bool = session.controller.move_connections(
		session.node("var first").id,
		ComposerReader.VALUE_OUT,
		session.node("var second").id,
		ComposerReader.VALUE_OUT
	)

	assert_true(done, "both moved")
	assert_eq(session.line("burning"), "apply_gameplay_effect(burning, second, 1.0)")
	assert_eq(session.line("chilled"), "apply_gameplay_effect(chilled, second, 1.0)")
	assert_eq(session.depth(), 1, "as one motion")


## One endpoint the destination cannot take refuses the whole move.
##
## The half that would have fitted must not move either. A person who cancels a
## drag and finds one of their two cables re-pointed has been handed a file they
## did not ask for and cannot see the shape of.
func test_a_move_the_destination_cannot_take_moves_nothing() -> void:
	var session: ComposerEditingSession = _open([
		"var first: AbilitySystemComponent = owner_asc",
		"var second: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(first, null, 1.0)",
		"apply_gameplay_effect(burning, first, 1.0)",
	])
	var before: String = session.printed()

	var done: bool = session.controller.move_connections(
		session.node("var first").id,
		ComposerReader.VALUE_OUT,
		session.node("var second").id,
		ComposerReader.VALUE_OUT
	)

	assert_false(done, "a system component does not fit an effect")
	assert_signal_emitted(session.controller, "refused")
	assert_eq(session.printed(), before, "so neither cable moved")
	assert_eq(session.depth(), 0, "and there is nothing to undo")
#endregion


#region Typing a value into an argument
## What typing into an argument has to leave behind.
##
## The second row is the one worth having: typing the value that is already there
## is not a change, and recording it would give somebody an undo that appears to
## do nothing and puts the edit they meant one step further away.
const TYPED: Array = [
	["2.5", "apply_gameplay_effect(burning, null, 2.5)", 1, "a new value is written"],
	["1.0", "apply_gameplay_effect(burning, null, 1.0)", 0, "the same value is not"],
]


func test_typing_a_value_writes_it_once_and_only_when_it_changed() -> void:
	for row: Array in TYPED:
		var written: String = row[0]
		var expected: String = row[1]
		var steps: int = row[2]
		var described: String = row[3]

		var session: ComposerEditingSession = _open([
			"apply_gameplay_effect(burning, null, 1.0)",
		])

		var done: bool = session.controller.rewrite_field(
			session.node(CONSUMER).id, 2, written
		)

		assert_true(done, described)
		assert_eq(session.line(CONSUMER), expected, "%s: the file says so" % described)
		assert_eq(session.depth(), steps, "%s: %d step" % [described, steps])


## A refused value leaves the file AND the graph the canvas is drawing alone.
##
## The screen used to do this itself, writing straight into the document's live
## graph before finding out whether the result could be committed. A refusal then
## left the card and the Inspector showing text the file did not contain, until
## something else happened to redraw them.
func test_a_refused_value_leaves_the_drawn_graph_untouched() -> void:
	var session: ComposerEditingSession = _open([
		"apply_gameplay_effect(burning, null, 1.0)",
	])
	var before: String = session.printed()
	var shown: String = session.node(CONSUMER).fields[2].display

	var done: bool = session.controller.rewrite_field(session.node(CONSUMER).id, 97, "2.5")

	assert_false(done, "there is no ninety-eighth argument")
	assert_signal_emitted(session.controller, "refused")
	assert_eq(session.printed(), before, "the file is untouched")
	assert_eq(
		session.node(CONSUMER).fields[2].display,
		shown,
		"and so is the graph the canvas draws"
	)
	assert_eq(session.depth(), 0, "with nothing to undo")


## A statement this tool cannot print back is not written into.
func test_a_statement_with_no_call_in_it_is_not_written_into() -> void:
	var session: ComposerEditingSession = _open([
		"var caster: AbilitySystemComponent = owner_asc",
		"apply_gameplay_effect(burning, caster, 1.0)",
	])
	var before: String = session.printed()
	var local: ComposerNode = session.node("var caster")
	assert_eq(local.fields.size(), 0, "a plain local has no arguments to write")

	var done: bool = session.controller.rewrite_field(local.id, 0, "owner_asc")

	assert_false(done, "there is no argument there")
	assert_signal_emitted(session.controller, "refused")
	assert_eq(session.printed(), before, "and nothing was written")


#endregion
