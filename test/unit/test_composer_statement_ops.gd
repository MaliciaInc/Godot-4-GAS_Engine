## What the selected statements can be made to do.
##
## The property worth holding is the order: a person picks cards in whatever
## order they click them, and every one of these operations works on lines. Copy
## three statements picked bottom-up and the text has to come back in the order
## they run, or somebody pastes their ability back inside out.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

var _ops: ComposerStatementOps = null
var _document: ComposerDocument = null


func before_each() -> void:
	_ops = ComposerStatementOps.new()
	_document = ComposerDocument.new()
	_ops.bind(_document)


func _open(statements: Array) -> void:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	_document.open(HEAD + body, PATH)


## The ids of the statements, in the order the file has them.
func _ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		found.append(node.id)
	return found


#region The order the file has them in
## Picked in any order, the spans come back in the order they run.
func test_the_spans_follow_the_file_and_not_the_clicking() -> void:
	_open(["execute_cue(&\"one\")", "execute_cue(&\"two\")", "execute_cue(&\"three\")"])
	var ids: Array[StringName] = _ids()
	var backwards: Array[StringName] = [ids[2], ids[0], ids[1]]

	var spans: Array[ComposerSpan] = _ops.spans_of(backwards)

	assert_eq(spans.size(), 3, "all three")
	assert_lt(spans[0].first_line, spans[1].first_line, "in the order they run")
	assert_lt(spans[1].first_line, spans[2].first_line, "all the way down")


## Copying picks up the text in that same order.
func test_copying_hands_back_the_statements_in_running_order() -> void:
	_open(["execute_cue(&\"one\")", "execute_cue(&\"two\")"])
	var ids: Array[StringName] = _ids()

	var taken: String = _ops.copy([ids[1], ids[0]] as Array[StringName])

	assert_lt(taken.find("one"), taken.find("two"), "first the first one")


## An id that names nothing is skipped rather than guessed at.
func test_an_id_that_names_nothing_is_left_out() -> void:
	_open(["execute_cue(&\"one\")"])

	var spans: Array[ComposerSpan] = _ops.spans_of(
		[&"nobody", _ids()[0]] as Array[StringName]
	)

	assert_eq(spans.size(), 1, "the one that exists")
#endregion


#region Nothing to do
## Nothing picked is nothing done, and nothing said about it.
func test_nothing_picked_changes_nothing() -> void:
	_open(["execute_cue(&\"one\")"])
	var before: String = _document.printed()
	var nothing: Array[StringName] = []

	assert_null(_ops.remove(nothing), "removing nothing is not a refusal")
	assert_null(_ops.repeat(nothing), "nor is repeating it")
	assert_eq(_ops.copy(nothing), "", "and copying it takes no text")
	assert_eq(_document.printed(), before, "the file is where it was")
	assert_eq(_document.history().depth(), 0, "with nothing to undo")


## Asked before anything is open, it answers rather than failing.
func test_with_nothing_open_it_answers_rather_than_crashing() -> void:
	assert_eq(_ops.spans_of([&"whoever"] as Array[StringName]).size(), 0)
	assert_eq(_ops.copy([&"whoever"] as Array[StringName]), "")
	assert_null(_ops.paste([] as Array[StringName], "\tend_ability()"))
#endregion


#region Doing it
## Pasting text puts it in after the selection, through the same door.
func test_pasting_puts_the_text_in_after_what_was_picked() -> void:
	_open(["execute_cue(&\"one\")", "return true"])
	var first: StringName = _ids()[0]

	var refusal: ComposerGraph.Diagnostic = _ops.paste(
		[first] as Array[StringName], "\texecute_cue(&\"two\")"
	)

	assert_null(refusal, "accepted")
	assert_lt(
		_document.printed().find("one"),
		_document.printed().find("two"),
		"after the one that was picked"
	)


## Text the file cannot take back is refused, and changes nothing.
func test_text_the_file_cannot_read_is_refused() -> void:
	_open(["execute_cue(&\"one\")"])
	var before: String = _document.printed()

	var refusal: ComposerGraph.Diagnostic = _ops.paste(
		[] as Array[StringName], "\tfor step: int in 3:\n\t\tend_ability()"
	)

	assert_not_null(refusal, "a loop is not in the subset")
	assert_eq(_document.printed(), before, "so the file is untouched")
#endregion


#region Where a call from the palette lands
## Nothing picked, so it goes at the end of the ability - which is before the
## return, not after it.
##
## The end of the *body* and the end of the *ability* are different lines, and
## the difference is the whole thing: everything after the return is unreachable,
## so a call written there is one somebody has to notice never ran. The graph
## showed it too, drawn hanging off nothing while execution went straight from
## Entry to End. It was the first thing anybody would do with a new ability -
## make one, then click a call in the palette.
func test_a_call_added_with_nothing_picked_lands_where_it_runs() -> void:
	_open(["commit_ability()", "return true"])
	var entry: ComposerCatalog.Entry = _a_call()
	assert_not_null(entry, "there is a call to add")

	assert_null(_ops.insert_call([] as Array[StringName], entry.key), "it was added")

	assert_lt(
		_line_of(String(entry.type_id)), _line_of("return true"),
		"the call is above the return"
	)
	assert_eq(
		ComposerFlow.predecessor_of(
			_document.graph(), ComposerFlow.main_end(_document.graph()).id
		).type_id,
		entry.type_id,
		"and execution reaches it on the way to the End"
	)


## And picking the End itself does not put one after it either.
func test_a_call_added_with_the_end_picked_still_lands_where_it_runs() -> void:
	_open(["commit_ability()", "return true"])
	var entry: ComposerCatalog.Entry = _a_call()
	var end: ComposerNode = ComposerFlow.main_end(_document.graph())

	assert_null(
		_ops.insert_call([end.id] as Array[StringName], entry.key), "it was added"
	)

	assert_lt(
		_line_of(String(entry.type_id)), _line_of("return true"),
		"still above the return"
	)


## A call that takes nothing and hands nothing back, so where it lands is all
## this is about.
func _a_call() -> ComposerCatalog.Entry:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if entry.parameters.is_empty() and not entry.awaits:
			return entry
	return null


func _line_of(written: String) -> int:
	var lines: PackedStringArray = _document.printed().split("\n")
	for number: int in lines.size():
		if lines[number].contains(written):
			return number
	return -1
#endregion
