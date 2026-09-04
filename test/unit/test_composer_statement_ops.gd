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
