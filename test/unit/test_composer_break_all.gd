## Taking every cable off one pin, whatever family the pin belongs to.
##
## One gesture, two quite different meanings. On a value output it is a fanout:
## one local feeding four arguments, and every one of them goes back to the
## value it would have been created holding. On an execution input it is a
## merge: several runs of control arriving at one statement, and what has to
## happen is that the statement stops being reached at all.
##
## They are tested together because the promise is one promise - nothing is left
## on that pin, and one undo puts all of it back - and because keeping them
## apart is exactly how the execution half went uncovered. There was a battery
## proving a merge exists and a battery proving Break All works, and no test
## that crossed them.
##
## The last one is made by a hand rather than by a method call, because those
## are not the same claim: a controller that clears the pin perfectly and an
## event that never reaches the canvas look identical from everywhere else.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends "res://test/fixtures/composer_viewport_case.gd"

## The call every fanout row feeds, named once.
const CONSUMER: String = "apply_gameplay_effect"


#region Breaking everything on a pin
## One local feeding two statements: the shape a fanout test needs.
const FANOUT: Array = [
	"var caster: AbilitySystemComponent = owner_asc",
	"apply_gameplay_effect(burning, caster, 1.0)",
	"apply_gameplay_effect(chilled, caster, 1.0)",
]


## A local feeding two statements is unplugged from both, once.
func test_breaking_a_fanout_is_one_commit() -> void:
	var session: ComposerEditingSession = ComposerEditingSession.opened(FANOUT)
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
	var session: ComposerEditingSession = ComposerEditingSession.opened(FANOUT)
	assert_true(
		session.controller.break_all(
			session.node("var caster").id, ComposerReader.VALUE_OUT
		)
	)

	session.document.undo()

	assert_eq(session.cables(), 2, "both cables are back")


## A branch whose body and whose false path both run into what follows.
##
## Every ability with an `if` in it that carries on afterwards is this shape.
const MERGE: Array = [
	"if ready:", "\texecute_cue(hit)", "end_ability()", "return true",
]


## Break All on an execution input takes every cable, in one commit.
##
## It used to take the first and leave the rest, because the controller read
## `every input takes one wire` - true of a data argument, and not of a run of
## control, which converges. The gesture said it had cleared the pin and the
## person was left looking at a cable that was still there.
##
## Data fanout was covered and this was not, which is how it survived: the
## flow battery proved a merge exists, the controller battery proved Break All
## works, and nobody crossed the two.
func test_breaking_an_execution_merge_takes_every_wire_in_one_commit() -> void:
	var session: ComposerEditingSession = ComposerEditingSession.opened(MERGE)
	assert_eq(session.arriving("end_ability"), 2, "two paths arrive to start")

	var done: bool = session.controller.break_all(
		session.node("end_ability").id, ComposerReader.EXEC_IN
	)

	assert_true(done, "the pin was cleared")
	assert_eq(
		session.arriving("end_ability"),
		0,
		"and nothing runs into it: %s" % [session.printed()]
	)
	assert_eq(session.depth(), 1, "as one thing to undo")

	session.document.undo()

	assert_eq(
		session.arriving("end_ability"), 2, "which puts both paths back"
	)


## A pin with nothing on it is not a change, so it is not an undo either.
func test_breaking_an_empty_pin_records_nothing() -> void:
	var session: ComposerEditingSession = ComposerEditingSession.opened([
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
## Asked about a pin that is not there, it says so rather than guessing.
func test_a_pin_that_is_gone_is_refused() -> void:
	var session: ComposerEditingSession = ComposerEditingSession.opened([
		"apply_gameplay_effect(burning, null, 1.0)",
	])
	watch_signals(session.controller)

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


#region What a whole pin means, one file at a time
## Below the gesture: the transformation itself, asked directly, so a refusal
## can be told from a gesture that never arrived.
## Two arms of one branch, both running into the statement after it.
##
## The other shape a merge comes in, and the one no single cut can express:
## neither arm keeps the continuation reached on its own.
const TWO_ARMS: Array = [
	"if ready:", "\tfire()", "else:", "\theal()", "after()", "return true",
]


## Neither cable can come off on its own, and that is not a bug in the cut.
##
## `fire()` and `heal()` both run into `after()`, so taking either link out
## leaves the other one still reaching it: nothing stops being reached, there
## is nothing to set aside, and the transformation has nothing to write. The
## refusal is the honest answer to a question about one link. It is also why
## Break All cannot be a loop over this - there is no order that works, and a
## loop would have written half of a thing nobody asked for.
func test_neither_half_of_a_merge_can_be_cut_on_its_own() -> void:
	var source: String = ComposerEditingSession.script_of(TWO_ARMS)
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var wires: Array[ComposerGraph.Connection] = graph.connections_for(
		ComposerFlowProbe.at(graph, "after()").id, ComposerReader.EXEC_IN
	)
	assert_eq(wires.size(), 2, "two paths arrive at it")

	for wire: ComposerGraph.Connection in wires:
		var alone: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_flow(
			source, graph, wire
		)
		assert_false(
			alone.ok,
			"%s alone strands nothing, so there is nothing to write"
			% [wire.from_node]
		)


## Asked about the pin, the same two come off together.
func test_a_whole_pin_comes_off_when_the_set_is_asked_for() -> void:
	var source: String = ComposerEditingSession.script_of(TWO_ARMS)
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var target: ComposerNode = ComposerFlowProbe.at(graph, "after()")

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_all(
		source, graph, graph.connections_for(target.id, ComposerReader.EXEC_IN)
	)

	assert_true(done.ok, "the pin was cleared: %s" % done.message)
	var after: ComposerGraph = ComposerReader.read(done.source, PATH)
	assert_true(after.is_editable(), after.blocked_reason())
	assert_eq(
		after.connections_for(
			ComposerFlowProbe.at(after, "after()").id,
			ComposerReader.EXEC_IN
		).size(),
		0,
		"and nothing runs into it: %s" % [ComposerFlowProbe.body_of(done.source)]
	)
	assert_true(
		done.source.contains("after()"),
		"with what stopped running still in the file"
	)


## A `match` set aside goes with its arms, headers and all.
##
## The wrapper takes lines, so what decides whether it may go round a region
## is what else is inside it - and an arm of a match is a line no card covers.
## The check counted cards against lines instead, so a region holding an arm
## never added up and the cut came back saying the shape was outside the
## subset. It was not: the shape is ordinary, and the answer was about the
## arithmetic. Found by pushing a real Alt-click at a pin whose statements
## happened to include a match.
func test_setting_aside_a_match_takes_its_arms_with_it() -> void:
	var source: String = ComposerEditingSession.script_of([
		"var ready: bool = can_activate()", "if ready:", "	fire()",
		"match state:", "	State.A:", "		one()", "after()", "return true",
	])
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var switch: ComposerNode = ComposerFlowProbe.at(graph, "match state:")

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_all(
		source, graph, graph.connections_for(switch.id, ComposerReader.EXEC_IN)
	)

	assert_true(done.ok, "the match was set aside: %s" % done.message)
	var after: ComposerGraph = ComposerReader.read(done.source, PATH)
	assert_true(after.is_editable(), after.blocked_reason())
	assert_eq(
		ComposerFlowChecks.island_of(
			after, ComposerFlowProbe.at(after, "one()")
		).is_empty(),
		false,
		"with what was inside the arm inside the island: %s"
		% [ComposerFlowProbe.body_of(done.source)]
	)
	assert_true(
		ComposerFlowProbe.at(after, "fire()") != null
		and after.is_reachable_from_entry(ComposerFlowProbe.at(after, "fire()").id),
		"and what still runs still running"
	)


## Links that do not share a pin are not a Break All, and are not guessed at.
func test_links_from_two_different_pins_are_refused() -> void:
	var source: String = ComposerEditingSession.script_of(TWO_ARMS)
	var graph: ComposerGraph = ComposerReader.read(source, PATH)
	var mixed: Array[ComposerGraph.Connection] = []
	mixed.append_array(
		graph.connections_for(
			ComposerFlowProbe.at(graph, "after()").id,
			ComposerReader.EXEC_IN
		)
	)
	mixed.append_array(
		graph.connections_for(
			ComposerFlowProbe.at(graph, "if ready:").id,
			ComposerReader.TRUE_OUT
		)
	)

	var done: ComposerFlowEdits.Result = ComposerFlowEdits.disconnect_all(
		source, graph, mixed
	)

	assert_false(done.ok, "that is not one pin's worth")
	assert_eq(done.source, "", "and nothing was written")
#endregion

#region All the way through a viewport
## A branch, then a match, then what follows both.
##
## `match state:` is reached twice over - the branch's body runs into it, and so
## does the path around the branch - which is the shape the bug lived in.
const CONVERGING: Array = [
	"var ready: bool = can_activate()",
	"if ready:",
	"\tfire()",
	"match state:",
	"\tState.A:",
	"\t\tone()",
	"after()",
	"return true",
]


## How many runs of control arrive at that statement, as the file stands.
func _arriving(document: ComposerDocument, said: String) -> int:
	var graph: ComposerGraph = ComposerReader.read(document.printed(), PATH)
	var into: ComposerNode = ComposerFlowProbe.at(graph, said)
	if into == null:
		return 0
	return graph.connections_for(into.id, ComposerReader.EXEC_IN).size()


## A real Alt-click on a merged execution pin leaves nothing on it.
##
## The gate for this bug. Everything above it calls the controller; this pushes
## one event into a viewport at the point the pin is actually drawn at, lets
## Godot route it through the card and the canvas, and then asks the file. That
## is what "Break All works" has to mean on a pin somebody can actually click.
func test_alt_clicking_a_merged_execution_pin_clears_every_path() -> void:
	var document: ComposerDocument = ComposerDocument.new()
	var body: String = ""
	for statement: String in CONVERGING:
		body += "\t" + statement + "\n"
	document.open(HEAD + body, PATH)
	assert_eq(_arriving(document, "match state:"), 2, "two paths arrive to start")

	var routes: ComposerWiringRoutes = ComposerWiringRoutes.new()
	routes.bind(document)
	await _draw(CONVERGING)
	routes.listen_to(_canvas)
	await _bring_into_view("match state:")

	await _push(
		_pin_point("match state:", ComposerReader.EXEC_IN, false), true, KEY_ALT
	)

	assert_eq(
		_arriving(document, "match state:"),
		0,
		"and none afterwards: %s" % [ComposerFlowProbe.body_of(document.printed())]
	)
	assert_eq(document.history().depth(), 1, "as one step")
#endregion
