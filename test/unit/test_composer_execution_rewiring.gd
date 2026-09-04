## Changing what runs after what, through the controller.
##
## Execution is written in the file, so every one of these is a source
## transformation with an undo. The tests ask the file what it says afterwards
## rather than asking the controller what it did, and they count the steps: one
## thing somebody did has to be one thing to take back.
##
## What is being guarded is honesty about running. A statement that stops
## running must be shown to have stopped - wrapped, drawn apart, still there to
## edit. Silently leaving one in the body doing nothing is the failure this
## whole mechanism exists to prevent.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## The body every test here cuts and mends.
##
## Four statements so there is something in front of the cut and something
## behind it: a two-line body cannot tell "the tail was detached" from "the
## whole thing was".
const RUNNING: Array = [
	"await wait_delay(1.0)",
	"execute_cue(&\"boom\")",
	"end_ability()",
	"return true",
]

const CUE: String = "execute_cue"
const ENDING: String = "end_ability"
const DELAY: String = "wait_delay"


func _open() -> ComposerEditingSession:
	var session: ComposerEditingSession = ComposerEditingSession.opened(RUNNING)
	watch_signals(session.controller)
	return session


## The same ability with the cue's link to the ending already taken out.
func _cut() -> ComposerEditingSession:
	var session: ComposerEditingSession = _open()
	assert_true(session.controller.disconnect_edge(session.run_after(CUE, ENDING)), "cut")
	return session


## What every refusal owes: a reason, a file nobody touched, and no new step to
## take back. Stated once because it is one contract, not one per operation.
##
## The file is the whole check. Everything the canvas shows - the cards, the
## cables, what runs after what - is worked out from the text every time it is
## read, so identical text is an identical drawing and a second assertion about
## the order would be the same fact asked twice.
func _assert_refused(
	session: ComposerEditingSession, before: String, steps: int, described: String
) -> void:
	assert_signal_emitted(session.controller, "refused", "%s: said so" % described)
	assert_eq(session.printed(), before, "%s: the file is untouched" % described)
	assert_eq(session.depth(), steps, "%s: nothing new to undo" % described)


#region Cutting and mending
## Cutting a link marks what it was carrying, in one step.
func test_cutting_a_link_marks_the_tail_and_records_one_step() -> void:
	var session: ComposerEditingSession = _open()

	var done: bool = session.controller.disconnect_edge(session.run_after(CUE, ENDING))

	assert_true(done, "the link came out")
	assert_true(
		session.printed().contains(ComposerSubset.DETACHED_MARK),
		"and what it carried is marked as detached"
	)
	assert_true(session.printed().contains("end_ability()"), "and still in the file")
	assert_eq(session.depth(), 1, "as one step")


## Unplug, plug back, and the file is exactly what it was.
##
## The strongest thing that can be said about a pair of transformations. It
## caught the machinery `return` a cut adds and a reconnect used to leave
## behind: every unplug-and-replug cycle deposited another dead line, and no
## assertion about marks or counts would ever have noticed.
func test_plugging_a_link_back_restores_the_file_exactly() -> void:
	var session: ComposerEditingSession = _cut()

	var done: bool = session.controller.connect_edge(session.run_after(CUE, ENDING))

	assert_true(done, "mended")
	assert_eq(
		session.printed(),
		ComposerEditingSession.script_of(RUNNING),
		"byte for byte what it was"
	)
	assert_eq(session.depth(), 2, "two steps, both undoable")


## Breaking an execution pin is one step, like any other.
func test_breaking_an_execution_pin_is_one_commit() -> void:
	var session: ComposerEditingSession = _open()

	var done: bool = session.controller.break_all(
		session.node(CUE).id, ComposerReader.EXEC_OUT
	)

	assert_true(done, "the pin is clear")
	assert_true(
		session.printed().contains(ComposerSubset.DETACHED_MARK), "the tail is marked"
	)
	assert_eq(session.depth(), 1, "as one step")
#endregion


#region What it will not write
## Every execution change the tool will not write, and what it does instead.
##
## Most come down to one thing: "runs after" is "is written after" here, so
## re-pointing a statement that already runs means moving it, which is a
## different operation with a different undo. The last is different in kind -
## the shape is expressible, and expressing it would push a live statement past
## a `return` and stop it running. All four get the same answer, which is why
## they are one test: a refusal is a refusal, and the contract does not soften
## because the reason was more interesting.
const CUT_FIRST: bool = true
const JOIN: bool = true

const IMPOSSIBLE: Array = [
	[not CUT_FIRST, JOIN, DELAY, ENDING, 0, "that statement already runs somewhere"],
	[not CUT_FIRST, JOIN, ENDING, DELAY, 0, "nothing runs after the end"],
	[CUT_FIRST, JOIN, DELAY, ENDING, 1, "the cue would be written past the island's return"],
	[not CUT_FIRST, not JOIN, DELAY, ENDING, 0, "those two do not run one after the other"],
]


func test_an_execution_change_this_cannot_write_is_refused() -> void:
	for row: Array in IMPOSSIBLE:
		var cut: bool = row[0]
		var joining: bool = row[1]
		var before_text: String = row[2]
		var after_text: String = row[3]
		var steps: int = row[4]
		var described: String = row[5]

		var session: ComposerEditingSession = _cut() if cut else _open()
		var before: String = session.printed()
		var asked: ComposerGraph.Connection = session.run_after(before_text, after_text)

		var done: bool = (
			session.controller.connect_edge(asked)
			if joining
			else session.controller.disconnect_edge(asked)
		)

		assert_false(done, described)
		_assert_refused(session, before, steps, described)


## Moving a run of control is said to be impossible rather than approximated.
func test_moving_execution_wires_is_refused_rather_than_guessed() -> void:
	var session: ComposerEditingSession = _open()
	var before: String = session.printed()

	var done: bool = session.controller.move_connections(
		session.node(DELAY).id,
		ComposerReader.EXEC_OUT,
		session.node(CUE).id,
		ComposerReader.EXEC_OUT
	)

	assert_false(done, "not something this can write")
	_assert_refused(session, before, 0, "moving a run of control")
#endregion
