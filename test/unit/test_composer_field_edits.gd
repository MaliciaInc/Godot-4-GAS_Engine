## Changing a value on a card, in the file the card was read from.
##
## The claim under all of these is that the file is edited rather than reprinted:
## the statement that changed is replaced and nothing else in the file moves, so
## a person's header, exports, helpers, comments and the note at the end of the
## line they edited are all still there afterwards. A branch's condition is
## checked as hard as a call's argument, because before this phase a condition
## was something the Composer would show and never write - which is the whole
## reason this module exists.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/strike.gd"

const SOURCE: String = """## A hand-written ability.
class_name Strike extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> bool:
	# Aim before spending anything.
	if is_ready: # only once
		commit_ability()
	match state:
		State.READY:
			add_tag(&"striking")
	apply_gameplay_effect(
		burning,
		null,
		1.0
	)
	return true


func _on_removed() -> void:
	pass
"""

const HEADER: String = "## A hand-written ability."
const EXPORT: String = "@export var burning: GameplayEffect"
const TAIL: String = "func _on_removed() -> void:"

const BRANCH: String = "if is_ready:"
const SWITCH: String = "match state:"
const CALL: String = "apply_gameplay_effect("
const END: String = "return true"


func _read(source: String = SOURCE) -> ComposerGraph:
	return ComposerReader.read(source, PATH)


## The node whose statement says `said`, or a failure naming what there was.
func _at(graph: ComposerGraph, said: String) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if node.text.contains(said):
			return node
	var drawn: PackedStringArray = PackedStringArray()
	for node: ComposerNode in graph.nodes:
		drawn.append(node.text)
	fail_test("no statement saying `%s` in: %s" % [said, ", ".join(drawn)])
	return null


## One field of one statement, changed.
func _write(graph: ComposerGraph, said: String, position: int, written: String
) -> ComposerFieldEdits.Result:
	return ComposerFieldEdits.rewrite(
		SOURCE, graph, ComposerFieldEdits.Change.of(_at(graph, said).id, position, written)
	)


## The lines of `source` that belong to the body, stripped of their indentation.
func _body(source: String) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = source.split("\n")
	var span: ComposerSpan = ComposerSubset.body_span(lines)
	for line: int in range(span.first_line, span.last_line + 1):
		said.append(lines[line - 1].strip_edges())
	return said


#region The structural statements
## A branch's condition is written into the file it was read from.
func test_a_branch_condition_is_written_into_the_file() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), BRANCH, 0, "is_ready and has_target")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(
		done.source.contains("\tif is_ready and has_target: # only once"),
		"the condition changed and nothing else on the line did: %s" % _body(done.source)
	)
	assert_eq(
		_at(_read(done.source), "if is_ready").fields[0].display,
		"is_ready and has_target",
		"and reading it back says what was written"
	)


## An `elif` is rewritten as an `elif`. The keyword comes off the line rather
## than out of the node's kind, which is what keeps a chain a chain.
func test_an_elif_keeps_its_own_keyword() -> void:
	var source: String = SOURCE.replace("\tif is_ready: # only once", "\tif a:\n\t\tone()\n\telif b:")
	var graph: ComposerGraph = _read(source)
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite(
		source, graph, ComposerFieldEdits.Change.of(_at(graph, "elif b:").id, 0, "c")
	)

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(done.source.contains("\telif c:"), "still an elif: %s" % _body(done.source))
	assert_false(done.source.contains("\tif c:"), "and not turned into an if")


## A `match` value is written, and the cases under it are left where they are.
func test_a_match_value_is_written_and_its_cases_are_left_alone() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), SWITCH, 0, "next_state")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(done.source.contains("\tmatch next_state:"), "the value changed")
	assert_true(done.source.contains("\t\tState.READY:"), "the case is untouched")
	assert_true(done.source.contains("\t\t\tadd_tag(&\"striking\")"), "and so is its body")


## What a `return` hands back is a value like any other.
func test_a_return_value_is_written_into_the_file() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), END, 0, "false")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(done.source.contains("\treturn false"), "the end hands back what was written")
	assert_false(done.source.contains("\treturn true"), "and no longer what it did")


## A bare `return` carries no value, so there is nothing there to write into.
##
## Growing one here would let somebody hand a value back out of a method that
## returns nothing, which is a file that does not compile.
func test_a_bare_return_is_not_given_a_value() -> void:
	var source: String = SOURCE.replace("\treturn true", "\treturn")
	var graph: ComposerGraph = _read(source)
	var end: ComposerNode = _at(graph, "return")

	assert_eq(end.fields.size(), 0, "nothing to edit on a bare return")
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite(
		source, graph, ComposerFieldEdits.Change.of(end.id, 0, "true")
	)

	assert_false(done.ok, "and asking is refused")
	assert_eq(done.message, ComposerFieldEdits.NO_SUCH_FIELD, "saying which way it is refused")
	assert_true(done.source.is_empty(), "with no file handed back")
#endregion


#region What the file keeps
## Everything outside the body is the same bytes it was.
func test_the_file_outside_the_body_is_untouched() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), BRANCH, 0, "false")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(done.source.begins_with(HEADER), "the comment at the top")
	assert_true(done.source.contains(EXPORT), "the export")
	assert_true(done.source.contains(TAIL), "and the helper below the body")
	assert_eq(
		done.source.split("\n").size(),
		SOURCE.split("\n").size(),
		"and the file is as long as it was"
	)


## The comment above a statement and the note beside it both survive.
##
## They are two different things to the reader - one is a line the statement
## carried in, the other is the tail of the statement's own line - and a rewrite
## that forgot either would quietly delete something a person wrote.
func test_the_comment_above_and_the_note_beside_both_survive() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), BRANCH, 0, "false")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(
		done.source.contains("\t# Aim before spending anything.\n\tif false: # only once"),
		"the comment above it and the note on it: %s" % _body(done.source)
	)


## A statement written across several lines is edited as the one statement it is.
##
## Five lines become one, so this is also the case where every line below the
## call moves. What comes back is checked by length as well as by content: a
## rewrite that left the old argument lines behind would still contain the new
## statement and would say the file grew.
func test_a_wrapped_call_is_edited_as_one_statement() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), CALL, 2, "2.5")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_eq(
		done.source.split("\n").size(),
		SOURCE.split("\n").size() - 4,
		"the four lines the call was wrapped over are gone: %s" % _body(done.source)
	)
	assert_true(
		done.source.contains("\tapply_gameplay_effect(burning, null, 2.5)"),
		"onto one line, with its arguments in order"
	)
	assert_true(done.source.contains(TAIL), "while the rest of the file stays")
#endregion


#region Several at once
## Two values, one pass, one file handed back.
##
## The rows are the three shapes this has to work in: two statements where the
## first one shrinks (the call folds from five lines onto one, so the end below
## it has moved by four by the time it is checked), two statements where nothing
## changes length, and two values of the one statement - which has to come out as
## a single replacement, because rebuilding the same statement twice would write
## the second rewrite over lines the first had already replaced.
const TOGETHER: Array = [
	[
		"a call that shrinks, and the end below it",
		[[CALL, 2, "2.5"], [END, 0, "false"]],
		["\tapply_gameplay_effect(burning, null, 2.5)", "\treturn false"],
	],
	[
		"a branch and the switch under it",
		[[BRANCH, 0, "false"], [SWITCH, 0, "other"]],
		["\tif false: # only once", "\tmatch other:"],
	],
	[
		"two arguments of the one call",
		[[CALL, 0, "chilled"], [CALL, 2, "3.0"]],
		["\tapply_gameplay_effect(chilled, null, 3.0)"],
	],
]


func test_two_values_are_written_in_one_pass() -> void:
	var checked: int = 0
	for row: Array in TOGETHER:
		var described: String = row[0]
		var asked: Array = row[1]
		var expected: Array = row[2]

		var graph: ComposerGraph = _read()
		var changes: Array[ComposerFieldEdits.Change] = []
		for one: Array in asked:
			var said: String = one[0]
			var position: int = one[1]
			var written: String = one[2]
			changes.append(
				ComposerFieldEdits.Change.of(_at(graph, said).id, position, written)
			)

		var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite_many(
			SOURCE, graph, changes
		)

		assert_true(done.ok, "%s: it was written: %s" % [described, done.message])
		for wanted: String in expected:
			assert_true(
				done.source.contains(wanted),
				"%s: the file says `%s`: %s" % [described, wanted, _body(done.source)]
			)
		checked += 1
	assert_eq(checked, TOGETHER.size(), "every pair was tried")


## Nothing asked for changes nothing, and is not a failure.
func test_no_changes_hands_back_the_file_it_was_given() -> void:
	var none: Array[ComposerFieldEdits.Change] = []

	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite_many(SOURCE, _read(), none)

	assert_true(done.ok, "nothing to do is not a refusal")
	assert_eq(done.source, SOURCE, "and the file is the one it was handed")
#endregion


#region Refusals and what they leave behind
## A value that says nothing is refused by name rather than written as `if :`.
func test_a_value_that_says_nothing_is_refused() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), BRANCH, 0, "   ")

	assert_false(done.ok, "an empty condition is not a statement")
	assert_true(
		done.message.contains(ComposerNodeFields.CONDITION),
		"naming the value that was left blank: %s" % done.message
	)


## A field that is not on the card is refused, and no file comes back.
func test_a_field_that_is_not_there_is_refused() -> void:
	var done: ComposerFieldEdits.Result = _write(_read(), BRANCH, 97, "false")

	assert_false(done.ok, "there is no ninety-eighth value")
	assert_eq(done.message, ComposerFieldEdits.NO_SUCH_FIELD, "said the one way")
	assert_true(done.source.is_empty(), "and nothing was handed back")


## Asking about a card that is not in the graph is refused.
func test_a_card_that_is_not_there_is_refused() -> void:
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite(
		SOURCE, _read(), ComposerFieldEdits.Change.of(&"n9999", 0, "false")
	)

	assert_false(done.ok, "no such card")
	assert_eq(done.message, ComposerFieldEdits.NO_SUCH_CARD, "said the one way")


## Nothing here changes the graph it was handed.
##
## The caller shows that graph on a canvas. A renderer that marked a node dirty
## on the way past would leave a refused edit drawn on screen, which is the exact
## failure the staging in the controller exists to prevent.
func test_the_graph_it_was_given_is_not_touched() -> void:
	var graph: ComposerGraph = _read()
	var branch: ComposerNode = _at(graph, BRANCH)

	var done: ComposerFieldEdits.Result = _write(graph, BRANCH, 0, "false")

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_eq(branch.fields[0].display, "is_ready", "the field still says what the file says")
	assert_false(branch.dirty, "and nothing was marked as changed")
#endregion


#region Arguments the file never passed
## Filling in a missing argument writes the call that was short of one.
func test_filling_in_a_missing_argument_writes_the_call() -> void:
	var source: String = SOURCE.replace("\t\t\tadd_tag(&\"striking\")", "\t\t\tadd_tag()")
	var graph: ComposerGraph = _read(source)
	var short: ComposerNode = _at(graph, "add_tag(")

	assert_eq(short.fields.size(), 1, "the gap reached the card as a field")
	assert_eq(short.fields[0].source, ComposerNode.ValueSource.MISSING, "marked absent")
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite(
		source, graph, ComposerFieldEdits.Change.of(short.id, 0, "&\"burning\"")
	)

	assert_true(done.ok, "it was written: %s" % done.message)
	assert_true(done.source.contains("add_tag(&\"burning\")"), "and the call is whole")


## The other gaps of an edited call are written as something that compiles.
##
## An argument the file never passed has no text to print. Printing the empty
## string produces `set_attribute_base(, 12.0)`, which is not a statement - so
## the declared default, or the zero of the type, goes in instead and the call
## that comes back is one the language accepts.
func test_the_other_gaps_of_an_edited_call_are_filled_safely() -> void:
	var source: String = SOURCE.replace(
		"\t\t\tadd_tag(&\"striking\")", "\t\t\tset_attribute_base()"
	)
	var graph: ComposerGraph = _read(source)
	var short: ComposerNode = _at(graph, "set_attribute_base(")

	assert_eq(short.fields.size(), 2, "two arguments the file never passed")
	var done: ComposerFieldEdits.Result = ComposerFieldEdits.rewrite(
		source, graph, ComposerFieldEdits.Change.of(short.id, 1, "12.0")
	)

	assert_true(done.ok, "it was written: %s" % done.message)
	var written: ComposerNode = _at(_read(done.source), "set_attribute_base(")
	assert_eq(written.fields.size(), 2, "both arguments are there now")
	assert_eq(written.fields[1].display, "12.0", "the one that was typed")
	assert_false(
		written.fields[0].display.is_empty(), "and the other holds something rather than nothing"
	)
#endregion
