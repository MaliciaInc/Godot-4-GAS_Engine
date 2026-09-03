## How big a card is, and why.
##
## Height always followed what a card held. Width did not: it was fixed at 232
## in five places, and the value inside a field was clipped, so a long one was
## cut without ever being able to widen the card holding it - reported from the
## editor as nodes that "only say one thing".
##
## The trap worth naming, because it is the one a title-sized card falls into: a
## node can have a six-letter title and an argument called `Blocked By Tag Query
## On Target`. Sizing to the title would cut the argument and look right doing
## it, so what a card measures is everything inside it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest


## A card grows sideways for what it holds, not only downwards.
##
## Height already followed its content. Width was fixed at 232 in five places,
## and the value inside a field was clipped, so a long one was cut without ever
## being able to widen the card that held it. The trap worth naming: a node can
## have a six-letter title and an argument called `Blocked By Tag Query`, so
## sizing to the title would cut the argument and look correct doing it.
func _card_for(field_text: String, label_text: String) -> ComposerCard:
	var node: ComposerNode = ComposerNode.new()
	node.id = &"probe"
	node.title = "End"

	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.label = label_text
	field.type_name = &"float"
	field.display = field_text
	node.fields.append(field)

	var card: ComposerCard = ComposerCard.new()
	add_child_autofree(card)
	card.build(node)
	await get_tree().process_frame
	card.fit()
	return card


func test_a_long_value_widens_the_card_that_holds_it() -> void:
	var narrow: ComposerCard = await _card_for("1.0", "Level")
	var wide: ComposerCard = await _card_for(
		"res://abilities/very/long/path_to_a_thing.gd", "Level"
	)

	assert_gt(wide.size.x, narrow.size.x, "the long value made room for itself")


## The argument's name counts too, which is the half a title-sized card misses.
func test_a_long_argument_name_widens_the_card_as_well() -> void:
	var narrow: ComposerCard = await _card_for("1.0", "Level")
	var wide: ComposerCard = await _card_for("1.0", "Blocked By Tag Query On Target Before Activation")

	assert_gt(wide.size.x, narrow.size.x, "a long argument name is not cut to fit a short title")


## Growing has an end. One node carrying a very long path should not push a
## whole column across the canvas.
func test_a_card_stops_growing_and_starts_trimming() -> void:
	var huge: ComposerCard = await _card_for("x".repeat(400), "Level")

	assert_lte(huge.size.x, ComposerTheme.NODE_MAX_WIDTH, "bounded")
	assert_gte(huge.size.x, ComposerTheme.NODE_MIN_WIDTH, "and never below the minimum")
