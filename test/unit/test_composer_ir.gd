## What a script is made of, answered before anything decides how to draw it.
##
## There was no layer here. The reader went from lines straight to cards, which
## worked until it met a line it did not understand - and then it had exactly
## one move: refuse the file. A person with a `for` loop in their ability had no
## Composer at all, for a loop the tool only ever needed to leave alone.
##
## The IR is the smaller question asked first. Functions, and inside them the
## events they are made of: statements the tool knows, regions it does not,
## loops, and the points where the body stops and comes back. Knowing where a
## region ENDS is the whole difference - it is what turns "I cannot open this"
## into "I am leaving that part alone".
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/probe.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"


#region Getting there
## A script whose entry point is these lines, indented once.
func _script(body: Array) -> String:
	var text: String = HEAD
	for line: String in body:
		text += "\t" + line + "\n"
	return text


func _entry(body: Array) -> ComposerIRFunction:
	return ComposerIR.of(_script(body), PATH).entry()


func _texts_of(events: Array[ComposerIREvent]) -> Array[String]:
	var found: Array[String] = []
	for event: ComposerIREvent in events:
		found.append(event.text)
	return found
#endregion


#region What a file is made of
## Every function in the file, named, in the order they are written.
func test_the_ir_names_every_function_in_the_file() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\n"
		+ "func _activate_ability() -> bool:\n\treturn true\n\n\n"
		+ "func _pick_target() -> Node:\n\treturn null\n"
	)

	var ir: ComposerIR = ComposerIR.of(source, PATH)

	assert_eq(ir.functions.size(), 2, "both of them")
	assert_eq(ir.functions[0].declared_name, &"_activate_ability", "the entry point")
	assert_eq(ir.functions[1].declared_name, &"_pick_target", "and the helper beside it")
	assert_same(ir.entry(), ir.functions[0], "and the entry point is the one it draws")


## A helper is not an obstacle to drawing the entry point.
##
## It used to look like one, because the reader had no idea a file had more than
## one function in it and read whatever came after the body as part of it.
func test_a_helper_beside_the_entry_point_changes_nothing_about_it() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\n"
		+ "func _activate_ability() -> bool:\n\tcommit_ability()\n\treturn true\n\n\n"
		+ "func _pick_target() -> Node:\n\treturn null\n"
	)

	var entry: ComposerIRFunction = ComposerIR.of(source, PATH).entry()

	assert_eq(_texts_of(entry.events), ["commit_ability()", "return true"] as Array[String])
	assert_true(entry.is_fully_representable(), "and nothing in it was left alone")


## Its signature is read off the file rather than off the running class.
func test_a_function_carries_what_its_signature_says_it_returns() -> void:
	var ir: ComposerIR = ComposerIR.of(_script(["return true"]), PATH)

	assert_eq(ir.entry().returns, &"bool", "what the file says")
	assert_true(ir.entry().is_entry_point(), "and which function it is")


## A file with no entry point has an IR all the same. Nothing crashes on a file
## somebody is halfway through typing.
func test_a_file_with_no_entry_point_answers_with_nothing_rather_than_failing() -> void:
	var ir: ComposerIR = ComposerIR.of("extends GameplayAbility\n", PATH)

	assert_eq(ir.functions.size(), 0, "no functions")
	assert_null(ir.entry(), "and nothing to draw")
	assert_null(ir.function_named(&"_activate_ability"), "asked by name either")
#endregion


#region A region the tool does not read
## A loop is one event that reaches to the end of its body.
##
## The end is the point. A header on its own would leave the lines under it read
## as statements nobody can place; knowing where the block stops is what lets
## everything after it be ordinary again.
func test_a_loop_is_one_event_that_reaches_the_end_of_its_body() -> void:
	var entry: ComposerIRFunction = _entry([
		"commit_ability()",
		"for target: Node in targets:",
		"\tapply_gameplay_effect(burning, target)",
		"\tend_ability()",
		"return true",
	])

	assert_eq(entry.events.size(), 3, "the commit, the loop, and the return")
	var loop_event: ComposerIREvent = entry.events[1]
	assert_true(loop_event.is_opaque(), "the loop is a region")
	assert_eq(loop_event.span.first_line, 6, "starting at its header")
	assert_eq(loop_event.span.last_line, 8, "and ending under its last line")
	assert_eq(entry.events[2].text, "return true", "and what follows is a statement again")


## Both kinds, and each says which it is.
##
##     [what is written, which sort it is]
func _loops() -> Array:
	return [
		["for target: Node in targets:", "for"],
		["while running:", "while"],
	]


func test_both_kinds_of_loop_are_recognised_as_what_they_are() -> void:
	var rows: Array = _loops()
	var checked: int = 0
	for row: Array in rows:
		var header: String = row[0]
		var named: String = row[1]

		var entry: ComposerIRFunction = _entry([header, "\tend_ability()"])

		assert_eq(entry.loops.size(), 1, "%s: one loop" % named)
		assert_true(entry.loops[0].described().contains(named), "%s: named as itself" % named)
		assert_eq(entry.loops[0].header, header, "%s: with the line it was written as" % named)
		checked += 1
	assert_eq(checked, rows.size(), "both kinds were offered")


## A statement outside the subset that opens no block is one line, not a region
## that swallows what follows.
func test_something_outside_the_subset_that_opens_no_block_takes_only_its_line() -> void:
	var entry: ComposerIRFunction = _entry([
		"assert(ready)",
		"commit_ability()",
	])

	assert_eq(entry.events.size(), 2, "two events")
	assert_true(entry.events[0].is_opaque(), "the assertion is kept")
	assert_eq(entry.events[0].span.last_line, 5, "on its own line")
	assert_false(entry.events[1].is_opaque(), "and the commit is drawn as itself")


## The reason comes from the subset, which is the one place that says why.
func test_a_kept_region_carries_the_subset_s_own_reason() -> void:
	var entry: ComposerIRFunction = _entry(["for step: int in 3:", "\tend_ability()"])

	assert_false(entry.is_fully_representable(), "something was left alone")
	assert_eq(entry.opaque_events().size(), 1, "one region")
	assert_eq(
		entry.opaque_events()[0].reason,
		"a loop has no single place on a canvas",
		"in the subset's words, not a second set of them"
	)


## A comment above a region belongs to it, the way it belongs to a statement.
##
## Which is what lets the writer put it back where it was rather than above
## whatever ends up first.
func test_a_comment_above_a_region_is_carried_by_it() -> void:
	var entry: ComposerIRFunction = _entry([
		"# every one of them",
		"for target: Node in targets:",
		"\tend_ability()",
	])

	var kept: ComposerIREvent = entry.events[0]
	assert_true(kept.is_opaque(), "the region")
	assert_eq(kept.span.first_line, 5, "reaches up to the comment")
	assert_eq(kept.statement_line, 6, "while the loop itself starts below it")
#endregion


#region Where a body stops and comes back
## Every suspension is found, and says what it waits on.
func test_every_await_is_a_point_the_body_stops_at() -> void:
	var entry: ComposerIRFunction = _entry([
		"commit_ability()",
		"await wait_for_hit().finished",
		"return true",
	])

	assert_true(entry.suspends(), "it can stop")
	assert_eq(entry.async_exits.size(), 1, "once")
	assert_eq(
		entry.async_exits[0].awaited, "wait_for_hit().finished", "and says what it waits on"
	)


## A body that never waits says so, rather than saying nothing.
func test_a_body_that_never_waits_says_so() -> void:
	var entry: ComposerIRFunction = _entry(["commit_ability()", "return true"])

	assert_false(entry.suspends(), "nothing in it stops")
	assert_eq(entry.async_exits.size(), 0, "so there is nowhere it comes back to")


## What is waited on is what comes after the word, not the local it lands in.
func test_the_local_a_wait_lands_in_is_not_what_is_waited_on() -> void:
	var entry: ComposerIRFunction = _entry([
		"var hit: Node = await wait_for_hit().finished",
	])

	assert_eq(entry.async_exits.size(), 1, "it stops here")
	assert_eq(
		entry.async_exits[0].awaited,
		"wait_for_hit().finished",
		"the thing being waited on, not the declaration around it"
	)
#endregion
