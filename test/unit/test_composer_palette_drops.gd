## A call dragged from the palette lands where it was let go.
##
## It did not. Every way of choosing a call - clicking the palette, picking one
## out of the finder, dragging one onto the canvas - arrived at one handler that
## threw the position away, so a person dropped a card in the space they had made
## for it and watched it appear wherever the layout felt like putting it.
##
## The other half is what "one thing" means. The statement and where its card
## sits are written in the same commit: two would take two undos, and the first
## of them would leave a position recorded for a statement that no longer exists.
##
## `(0, 0)` gets a test of its own because it is a real place on a canvas. Any
## sentinel a person can drop a card exactly on is a sentinel that will one day
## be read as "they did not say".
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/fireball.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

const BODY: Array = ["commit_ability()", "return true"]

var _document: ComposerDocument = null
var _statements: ComposerStatementOps = null


func before_each() -> void:
	_document = ComposerDocument.new()
	var body: String = ""
	for statement: String in BODY:
		body += "\t" + statement + "\n"
	_document.open(HEAD + body, PATH)
	_statements = ComposerStatementOps.new()
	_statements.bind(_document)


#region Getting there
## A call the catalog really offers, named the way the palette names it.
##
## The key rather than the method: that is what a palette button carries and
## what every path into the ops takes, and a test that passed a method name
## would exercise a call nobody could have picked.
func _offered() -> StringName:
	var keys: Array[StringName] = []
	for key: StringName in ComposerCatalog.all():
		keys.append(key)
	keys.sort()
	return keys[0]


## What that call is written as, so a test can find it in the file.
func _written_as(key: StringName) -> String:
	return String(ComposerCatalog.find(key).type_id)


## The statement the drop made, read out of the file afterwards.
func _made(key: StringName) -> ComposerNode:
	return ComposerFlowProbe.at(
		ComposerReader.read(_document.printed(), PATH), _written_as(key)
	)


## Where the card of that statement was written to sit, or nothing.
func _placed_at(node: ComposerNode) -> Vector2:
	return node.layout_position if node.has_layout_position else Vector2.INF


func _nothing_picked() -> Array[StringName]:
	var none: Array[StringName] = []
	return none
#endregion


#region Where it lands
## The point somebody let go at is the point the card is written at.
##
## Three of them, and `(0, 0)` is one: it is a place like any other, and the
## whole reason this takes a separate method rather than a default argument.
const DROPPED: Array = [
	["out in the canvas", Vector2(320.0, 96.0)],
	["at the origin", Vector2.ZERO],
	["behind where the graph starts", Vector2(-48.0, -160.0)],
]


func test_a_dropped_call_is_written_where_it_was_let_go() -> void:
	var checked: int = 0
	for row: Array in DROPPED:
		var described: String = row[0]
		var at: Vector2 = row[1]

		before_each()
		var key: StringName = _offered()

		var refusal: ComposerGraph.Diagnostic = _statements.insert_call_at(
			_nothing_picked(), key, at
		)

		assert_null(refusal, "%s: it was written" % described)
		var made: ComposerNode = _made(key)
		assert_not_null(made, "%s: and the statement is in the file" % described)
		assert_eq(_placed_at(made), at, "%s: at the point it was dropped" % described)
		checked += 1
	assert_eq(checked, DROPPED.size(), "every drop was tried")


## The statement and its position are one entry in the history.
func test_the_call_and_its_position_are_one_step() -> void:
	var key: StringName = _offered()
	var before: String = _document.printed()

	_statements.insert_call_at(_nothing_picked(), key, Vector2(64.0, 64.0))

	assert_eq(_document.history().depth(), 1, "one step")
	assert_true(
		_document.printed().contains(ComposerLayoutMetadata.PREFIX),
		"the position was written: %s" % [ComposerFlowProbe.body_of(_document.printed())]
	)

	_document.undo()

	assert_eq(_document.printed(), before, "and taking it back removes both")


## A call nobody dropped is placed by the layout, and says nothing about where.
func test_a_clicked_call_carries_no_position_of_its_own() -> void:
	var key: StringName = _offered()

	_statements.insert_call(_nothing_picked(), key)

	assert_not_null(_made(key), "the statement is in the file")
	assert_false(
		_document.printed().contains(ComposerLayoutMetadata.PREFIX),
		"and nothing was written about where its card sits"
	)


## Two of the same call, dropped in two places, keep their own places.
##
## The new statement is found by the line it was written on. Found by what it
## calls, the second drop would have moved the first card and left its own
## wherever the layout put it.
func test_dropping_the_same_call_twice_places_each_one() -> void:
	var key: StringName = _offered()

	_statements.insert_call_at(_nothing_picked(), key, Vector2(100.0, 100.0))
	_statements.insert_call_at(_nothing_picked(), key, Vector2(400.0, 220.0))

	var placed: Array[Vector2] = []
	for node: ComposerNode in ComposerReader.read(_document.printed(), PATH).nodes:
		if node.source_backed and node.text.contains(_written_as(key)):
			placed.append(_placed_at(node))
	assert_eq(placed.size(), 2, "both are in the file")
	assert_true(
		placed.has(Vector2(100.0, 100.0)) and placed.has(Vector2(400.0, 220.0)),
		"and each sits where it was dropped: %s" % [placed]
	)
#endregion
