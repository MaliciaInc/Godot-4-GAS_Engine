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


func _open(statements: Array = RUNNING) -> ComposerEditingSession:
	var session: ComposerEditingSession = ComposerEditingSession.opened(statements)
	watch_signals(session.controller)
	return session


## The three shapes a path can leave from, beside the plain one.
const BRANCHING: Array = ["if ready:", "\tfire()", "after()", "return true"]
const CHOOSING: Array = [
	"if ready:", "\tfire()", "else:", "\theal()", "after()", "return true",
]
const MATCHING: Array = [
	"match state:", "\tState.A:", "\t\tone()", "\tState.B:", "\t\ttwo()",
	"after()", "return true",
]


## Ctrl-drag: every link on one pin goes to another pin.
func _move(
	session: ComposerEditingSession,
	from: String,
	from_pin: StringName,
	to: String,
	to_pin: StringName
) -> bool:
	return session.controller.move_connections(
		session.node(from).id, from_pin, session.node(to).id, to_pin
	)


## The file as it now stands, read back.
func _read(session: ComposerEditingSession) -> ComposerGraph:
	return ComposerReader.read(session.printed(), ComposerEditingSession.PATH)


## Whether the reread says one statement leaves by that pin into another.
func _runs(graph: ComposerGraph, from: String, pin: StringName, to: String) -> bool:
	var leaving: ComposerNode = _at(graph, from)
	var arriving: ComposerNode = _at(graph, to)
	if leaving == null or arriving == null:
		return false
	return graph.has_connection(
		ComposerReader.wire(leaving.id, pin, arriving.id, ComposerReader.EXEC_IN)
	)


func _at(graph: ComposerGraph, said: String) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if node.text.contains(said):
			return node
	return null


## The body as it now stands, one statement per entry, for a failure to print.
func _body(session: ComposerEditingSession) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for line: String in session.printed().split("\n"):
		if line.begins_with("\t"):
			said.append(line.strip_edges())
	return said


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
#endregion


#region Moving a run of control
## The link leaves the pin it was on and arrives on the one it was dropped on.
##
## Nothing is stored, so this is a statement that moved: `end_ability()` is
## written where it now runs, straight after the delay, and the cue that used to
## be there is below it.
func test_moving_linear_execution_output_moves_the_wire() -> void:
	var session: ComposerEditingSession = _open()

	var done: bool = _move(session, CUE, ComposerReader.EXEC_OUT, DELAY, ComposerReader.EXEC_OUT)

	assert_true(done, "the drag was taken")
	var read: ComposerGraph = _read(session)
	assert_true(
		_runs(read, DELAY, ComposerReader.EXEC_OUT, ENDING),
		"the delay runs into the ending: %s" % _body(session)
	)
	assert_false(
		_runs(read, CUE, ComposerReader.EXEC_OUT, ENDING), "and the cue no longer does"
	)


## Arriving on an occupied pin takes what was on it, in the one transaction.
##
## An execution pin holds one link. The link that was there is displaced as part
## of the same change, so there is never a moment - or an undo step - where the
## file holds both.
func test_moving_to_occupied_execution_output_displaces_the_old_wire_atomically() -> void:
	var session: ComposerEditingSession = _open([
		"commit_ability()", "execute_cue(&\"boom\")", "end_ability()", "await wait_delay(1.0)",
		"return true",
	])

	var done: bool = _move(
		session, ENDING, ComposerReader.EXEC_OUT, "commit_ability", ComposerReader.EXEC_OUT
	)

	assert_true(done, "the drag was taken")
	var read: ComposerGraph = _read(session)
	assert_true(
		_runs(read, "commit_ability", ComposerReader.EXEC_OUT, DELAY),
		"the delay is what the commit runs into now: %s" % _body(session)
	)
	assert_false(
		_runs(read, "commit_ability", ComposerReader.EXEC_OUT, CUE),
		"the link that was on that pin is gone"
	)
	assert_eq(session.depth(), 1, "and both halves are one step")


## Dragging an input's link hands the statement its predecessor.
func test_moving_execution_input_moves_its_predecessor() -> void:
	var session: ComposerEditingSession = _open()

	var done: bool = _move(session, CUE, ComposerReader.EXEC_IN, ENDING, ComposerReader.EXEC_IN)

	assert_true(done, "the drag was taken")
	var read: ComposerGraph = _read(session)
	var before: Array[ComposerNode] = ComposerFlow.predecessors_of(read, _at(read, ENDING).id)

	assert_eq(before.size(), 1, "the ending is arrived at from one place: %s" % _body(session))
	assert_true(before[0].text.contains(DELAY), "and it is the delay, which was the cue's")
	assert_false(
		_runs(read, CUE, ComposerReader.EXEC_OUT, ENDING), "the cue no longer runs into it"
	)


## One drag is one thing to take back.
func test_move_all_is_one_history_entry() -> void:
	var session: ComposerEditingSession = _open()

	assert_true(
		_move(session, CUE, ComposerReader.EXEC_OUT, DELAY, ComposerReader.EXEC_OUT),
		"the drag was taken"
	)

	assert_eq(session.depth(), 1, "one step for a move that rewrote two links")


## Taking it back puts the file back exactly.
##
## The strongest thing that can be said about a transformation: not that the
## graph looks the same afterwards, but that the bytes do.
func test_move_all_undo_restores_original_source_byte_for_byte() -> void:
	var session: ComposerEditingSession = _open()
	var before: String = session.printed()
	assert_true(
		_move(session, CUE, ComposerReader.EXEC_OUT, DELAY, ComposerReader.EXEC_OUT),
		"the drag was taken"
	)
	assert_ne(session.printed(), before, "and it changed the file")

	session.document.undo()

	assert_eq(session.printed(), before, "byte for byte what it was")


## A move that would make the ability run in a circle is refused, and writes
## nothing at all.
func test_move_all_cycle_is_refused_without_mutation() -> void:
	var session: ComposerEditingSession = _open()
	var before: String = session.printed()

	var done: bool = _move(session, DELAY, ComposerReader.EXEC_OUT, CUE, ComposerReader.EXEC_OUT)

	assert_false(done, "the cue would run itself")
	_assert_refused(session, before, 0, "a move that would loop")
	# The reason, not just the refusal: "this cannot be written" and "this would
	# run forever" send a person to two different places.
	assert_signal_emitted_with_parameters(
		session.controller, "refused", [ComposerFlowEdits.WOULD_LOOP], 0
	)
#endregion


#region Moving a structural path
## Dragging a structural pin moves that path and leaves the others alone.
##
## The three pins a path can leave a structural statement by, which section 40
## names as three cases and which are one fact: what was dropped runs where it
## was dropped, every other path out of the same statement is exactly what it
## was, and nothing is generated over something a person wrote.
##
## The last column is the difference between them. Emptying the true path leaves
## it leading nowhere, and nowhere is written down here as a marked stop inside
## the branch - so the body still parses and the path ends there instead of
## falling through to the statement below. The other two take their path out of
## an `else` and a case that were already written, so there is nothing to
## generate and the marks must be absent.
const STRUCTURAL: Array = [
	[
		"the true path",
		BRANCHING, ComposerReader.TRUE_OUT, "fire()",
		ComposerReader.FALSE_OUT, "after()",
		ComposerSubset.FLOW_STOP_MARK, true,
	],
	[
		"the false path",
		CHOOSING, ComposerReader.FALSE_OUT, "heal()",
		ComposerReader.TRUE_OUT, "fire()",
		ComposerSubset.FLOW_ELSE_MARK, false,
	],
	[
		"one arm of a match",
		MATCHING, StringName(ComposerReader.CASE_OUT % 0), "one()",
		StringName(ComposerReader.CASE_OUT % 1), "two()",
		ComposerSubset.FLOW_DEFAULT_MARK, false,
	],
]


func test_moving_a_structural_path_moves_only_that_path() -> void:
	var checked: int = 0
	for row: Array in STRUCTURAL:
		var described: String = row[0]
		var body: Array = row[1]
		var pin: StringName = row[2]
		var carried: String = row[3]
		var other_pin: StringName = row[4]
		var other_target: String = row[5]
		var mark: String = row[6]
		var marked: bool = row[7]

		var session: ComposerEditingSession = _open(body)
		var opener: Array = body
		var head: String = opener[0]

		var done: bool = _move(session, head, pin, "after()", ComposerReader.EXEC_OUT)

		assert_true(done, "%s: the drag was taken" % described)
		var read: ComposerGraph = _read(session)
		assert_true(
			_runs(read, "after()", ComposerReader.EXEC_OUT, carried),
			"%s: runs where it was dropped: %s" % [described, _body(session)]
		)
		assert_true(
			_runs(read, head, other_pin, other_target),
			"%s: and every other path out is what it was" % described
		)
		assert_false(
			_runs(read, head, pin, carried),
			"%s: the path it left no longer reaches it" % described
		)
		assert_eq(
			session.printed().contains(mark),
			marked,
			"%s: %s is %s" % [described, mark, "written" if marked else "not invented"]
		)
		checked += 1
	assert_eq(checked, STRUCTURAL.size(), "every structural pin was tried")
#endregion
