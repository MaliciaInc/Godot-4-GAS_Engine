## Where cards sit, written into the ability and taken back out of it.
##
## The placement is presentation and nothing else: it never changes what runs,
## and moving a statement moves its placement with it, because the comment lives
## on the line above the statement it belongs to. That is the whole reason it is
## stored this way rather than in a file beside the ability - there is no second
## thing to keep in step, and nothing to go stale when somebody edits the script
## by hand.
##
## The property under test is the batch: one drag is one change. A commit per
## moved card turns dragging four of them into four things to undo.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

var _document: ComposerDocument = null


func before_each() -> void:
	_document = ComposerDocument.new()


func _open(statements: Array) -> void:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	_document.open(HEAD + body, PATH)


func _ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		found.append(node.id)
	return found


## Where the graph says each card is now.
func _placed() -> Dictionary[StringName, Vector2]:
	var found: Dictionary[StringName, Vector2] = {}
	for node: ComposerNode in _document.graph().nodes:
		if node.has_layout_position:
			found[node.id] = node.layout_position
	return found


#region One drag, one change
## Moving several cards is one step, whatever it moved.
func test_placing_several_cards_is_one_step() -> void:
	_open(["commit_ability()", "execute_cue(&\"one\")", "return true"])
	var ids: Array[StringName] = _ids()
	var wanted: Dictionary[StringName, Vector2] = {
		ids[0]: Vector2(10.0, 20.0),
		ids[1]: Vector2(30.0, 40.0),
		ids[2]: Vector2(50.0, 60.0),
	}

	var refusal: ComposerGraph.Diagnostic = _document.place_many(wanted)

	assert_null(refusal, "accepted")
	assert_eq(_document.history().depth(), 1, "as one step")


## And every card ends up where it was put, not only the first.
##
## The pass writes from the bottom of the file upwards, because a comment written
## above a statement shifts every line below it. Done the other way, the second
## card's position lands against somebody else's statement - which reads back as
## a card that jumped somewhere nobody put it.
func test_every_card_lands_where_it_was_put() -> void:
	_open(["commit_ability()", "execute_cue(&\"one\")", "return true"])
	var ids: Array[StringName] = _ids()
	var wanted: Dictionary[StringName, Vector2] = {
		ids[0]: Vector2(10.0, 20.0),
		ids[1]: Vector2(30.0, 40.0),
		ids[2]: Vector2(50.0, 60.0),
	}

	_document.place_many(wanted)

	var placed: Dictionary[StringName, Vector2] = _placed()
	assert_eq(placed.size(), 3, "all three were placed")
	for node: ComposerNode in ComposerProjection.statements(_document.graph()):
		var line: String = node.text
		var was: Vector2 = wanted[_id_for(ids, line)] if _id_for(ids, line) != &"" else Vector2.ZERO
		assert_true(node.has_layout_position, "%s carries a position" % node.title)
		assert_eq(node.layout_position, was, "%s is where it was put" % node.title)


## The ids move between reads, so a statement is found by what it says.
func _id_for(_ids_before: Array[StringName], written: String) -> StringName:
	var order: Array[String] = ["commit_ability", "execute_cue", "return true"]
	for position: int in order.size():
		if written.contains(order[position]):
			return _ids_before[position]
	return &""


## Placing changes only the drawing, never the order things run in.
func test_placing_never_changes_what_runs() -> void:
	_open(["commit_ability()", "execute_cue(&\"one\")", "return true"])
	var before: String = ComposerWriter.signature(_document.graph())
	var ids: Array[StringName] = _ids()

	_document.place_many({ids[0]: Vector2(10.0, 20.0)} as Dictionary[StringName, Vector2])

	assert_eq(
		ComposerWriter.signature(_document.graph()),
		before,
		"the same statements, in the same order, wired the same way"
	)


## A position that is not a number is refused rather than written.
##
## Infinity is what dividing by a zoom of nought produces, and a card placed at
## one is a card nobody can scroll to.
func test_a_position_that_is_not_a_number_is_not_written() -> void:
	_open(["commit_ability()", "return true"])
	var ids: Array[StringName] = _ids()
	var before: String = _document.printed()

	_document.place_many({ids[0]: Vector2(INF, 0.0)} as Dictionary[StringName, Vector2])

	assert_eq(_document.printed(), before, "nothing was written")


## A card that is no longer there is skipped, not refused.
##
## The positions come from a canvas drawn a moment ago, and a redraw in between
## is not somebody's mistake.
func test_a_card_that_is_gone_is_skipped() -> void:
	_open(["commit_ability()", "return true"])
	var ids: Array[StringName] = _ids()

	var refusal: ComposerGraph.Diagnostic = _document.place_many({
		ids[0]: Vector2(10.0, 20.0), &"nobody": Vector2(1.0, 2.0),
	} as Dictionary[StringName, Vector2])

	assert_null(refusal, "the one that is there was still placed")
	assert_eq(_placed().size(), 1, "and only that one")
#endregion


#region The card that is not a statement
## Entry has nowhere to carry a comment, so its place is written against its id.
func test_entry_keeps_where_it_was_left() -> void:
	_open(["commit_ability()", "return true"])

	_document.place_many(
		{ComposerFlow.ENTRY_ID: Vector2(120.0, 80.0)} as Dictionary[StringName, Vector2]
	)

	var entry: ComposerNode = _document.graph().find_node(ComposerFlow.ENTRY_ID)
	assert_true(entry.has_layout_position, "Entry was placed")
	assert_eq(entry.layout_position, Vector2(120.0, 80.0), "where it was put")


## Placed twice, it leaves one line rather than two.
func test_placing_entry_again_leaves_one_line_for_it() -> void:
	_open(["commit_ability()", "return true"])

	_document.place_many(
		{ComposerFlow.ENTRY_ID: Vector2(10.0, 10.0)} as Dictionary[StringName, Vector2]
	)
	_document.place_many(
		{ComposerFlow.ENTRY_ID: Vector2(50.0, 60.0)} as Dictionary[StringName, Vector2]
	)

	var written: int = 0
	for line: String in _document.printed().split("\n"):
		if line.contains(ComposerLayoutMetadata.VIRTUAL_PREFIX):
			written += 1
	assert_eq(written, 1, "one line for one card")
	assert_eq(
		_document.graph().find_node(ComposerFlow.ENTRY_ID).layout_position,
		Vector2(50.0, 60.0),
		"and it says where it was last put"
	)


## Entry's placement is a comment, so it changes nothing about the ability.
func test_placing_entry_leaves_the_ability_reading_the_same() -> void:
	_open(["commit_ability()", "return true"])
	var before: String = ComposerWriter.signature(_document.graph())

	_document.place_many(
		{ComposerFlow.ENTRY_ID: Vector2(120.0, 80.0)} as Dictionary[StringName, Vector2]
	)

	assert_true(_document.graph().is_editable(), _document.graph().blocked_reason())
	assert_eq(ComposerWriter.signature(_document.graph()), before, "nothing else moved")
#endregion
