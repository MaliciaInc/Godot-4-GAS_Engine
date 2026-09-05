## What a branch, a match and an end put on screen.
##
## A structural statement is not an ordinary card with a different word on it. It
## has no single way out - a branch leaves by True or by False, a match by one of
## its arms - and what it carries is a value like any argument, on a pin that is
## not called `arg_0`. Until this phase the card drew all three as if they were
## calls: one generic output that no path used, and a value row whose pin was
## named for an argument the statement does not have, so nothing could land on
## it.
##
## The numbering is the part only this project can get wrong. GraphNode numbers
## the pins it draws, not the rows it holds, so a card whose title row carries no
## right pin has its first output at index 0 belonging to a row further down.
## Every cable on the canvas is drawn through that numbering.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PATH: String = "res://abilities/probe.gd"
const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"

const BRANCHING: Array = ["if ready:", "\tfire()", "after()", "return true"]
const MATCHING: Array = [
	"match state:", "\tState.A:", "\t\tone()", "\tState.B:", "\t\ttwo()",
	"after()", "return true",
]

var _types: ComposerPortTypes = null


func before_each() -> void:
	_types = ComposerPortTypes.new()


#region Getting there
func _read(statements: Array) -> ComposerGraph:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	return ComposerReader.read(HEAD + body, PATH)


## A card for the statement saying `said`, built and measured.
func _card(statements: Array, said: String) -> ComposerCard:
	var graph: ComposerGraph = _read(statements)
	var node: ComposerNode = ComposerFlowProbe.at(graph, said)
	assert_not_null(node, "there is a statement saying `%s`" % said)
	_types.rebuild(graph)
	var card: ComposerCard = ComposerCard.new()
	add_child_autofree(card)
	card.build(node, _types)
	await get_tree().process_frame
	return card


## Every drawn pin on one side, in the order GraphNode numbers them.
func _drawn(card: ComposerCard, on_the_left: bool) -> Array[StringName]:
	var found: Array[StringName] = []
	var index: int = 0
	while true:
		var pin: StringName = (
			card.left_port_of_drawn(index) if on_the_left
			else card.right_port_of_drawn(index)
		)
		if pin.is_empty():
			break
		found.append(pin)
		index += 1
	return found
#endregion


#region The pins each structural statement draws
## The three statements, the pins they draw, and the order they draw them in.
##
## Stated as the whole list rather than pin by pin: what goes wrong here is an
## extra pin or a missing one, and an assertion that only asks about the pins it
## expects cannot see either.
const DRAWN: Array = [
	[
		"a branch",
		BRANCHING, "if ready:",
		[ComposerReader.EXEC_IN, ComposerReader.CONDITION_IN],
		[ComposerReader.TRUE_OUT, ComposerReader.FALSE_OUT],
	],
	[
		"a match",
		MATCHING, "match state:",
		[ComposerReader.EXEC_IN, ComposerReader.MATCH_VALUE_IN],
		[
			StringName(ComposerReader.CASE_OUT % 0),
			StringName(ComposerReader.CASE_OUT % 1),
			ComposerReader.UNMATCHED_OUT,
		],
	],
	[
		"an end",
		BRANCHING, "return true",
		[ComposerReader.EXEC_IN, ComposerReader.RETURN_VALUE_IN],
		[],
	],
]


func test_a_structural_card_draws_exactly_its_own_pins() -> void:
	var checked: int = 0
	for row: Array in DRAWN:
		var described: String = row[0]
		var body: Array = row[1]
		var said: String = row[2]
		var on_the_left: Array = row[3]
		var on_the_right: Array = row[4]

		var card: ComposerCard = await _card(body, said)

		assert_eq(
			Array(_drawn(card, true)), on_the_left, "%s: the pins on its left" % described
		)
		assert_eq(
			Array(_drawn(card, false)), on_the_right, "%s: and on its right" % described
		)
		checked += 1
	assert_eq(checked, DRAWN.size(), "every structural statement was drawn")


## A branch's paths are named for a person to read, not for the file.
func test_the_paths_are_named_the_way_they_are_read() -> void:
	var card: ComposerCard = await _card(BRANCHING, "if ready:")

	assert_eq(
		card.right_index_for_port(ComposerReader.TRUE_OUT), 0, "True is the first way out"
	)
	assert_eq(
		card.right_index_for_port(ComposerReader.FALSE_OUT), 1, "and False the second"
	)
	assert_eq(
		card.left_index_for_port(ComposerReader.CONDITION_IN),
		1,
		"the condition takes a cable below the run of control"
	)


## An arm keeps the words the person wrote it with.
func test_a_match_arm_is_labelled_with_its_own_pattern() -> void:
	var graph: ComposerGraph = _read(MATCHING)
	var switch: ComposerNode = ComposerFlowProbe.at(graph, "match state:")

	assert_eq(
		switch.find_port(StringName(ComposerReader.CASE_OUT % 0)).label,
		"State.A",
		"the first arm says what it matches"
	)
	assert_eq(
		switch.find_port(ComposerReader.UNMATCHED_OUT).label,
		ComposerFlowBuilder.NO_MATCH_LABEL,
		"and the way out when none of them do"
	)
#endregion


#region Pulling back does not renumber anything
## Every pin means the same thing at every level of detail.
##
## The rows are faded rather than hidden on purpose: a hidden child leaves
## GraphNode's slot list and every pin below it renumbers, while the canvas has
## already fixed its wire indices. Pulling back to look at an ability would
## silently re-point every cable on it.
func test_the_pins_mean_the_same_at_every_level_of_detail() -> void:
	var card: ComposerCard = await _card(MATCHING, "match state:")
	var before_left: Array[StringName] = _drawn(card, true)
	var before_right: Array[StringName] = _drawn(card, false)
	var checked: int = 0

	for level: ComposerCard.Detail in [
		ComposerCard.Detail.TITLE, ComposerCard.Detail.BLOCK, ComposerCard.Detail.FULL
	]:
		card.show_detail(level)
		await get_tree().process_frame

		assert_eq(Array(_drawn(card, true)), Array(before_left), "left pins, level %d" % level)
		assert_eq(
			Array(_drawn(card, false)), Array(before_right), "right pins, level %d" % level
		)
		checked += 1
	assert_eq(checked, 3, "every level was pulled back to")
#endregion
