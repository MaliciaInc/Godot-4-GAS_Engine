## What a card puts on screen, and which pin is which.
##
## The pins are the part only this project can get wrong. GraphNode numbers the
## pins it draws, not the rows it holds, so a card whose second row carries no
## left pin has an input at index 1 that belongs to its third row. Every wire on
## the canvas is drawn through that numbering, and getting it wrong points every
## cable at the row above or below the one it belongs to - which looks entirely
## correct until somebody reads the file.
##
## The rest is what a person can and cannot touch: an argument fed by a cable
## offers nothing to type into, because the cable is the edit.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

var _types: ComposerPortTypes = null


func before_each() -> void:
	_types = ComposerPortTypes.new()


#region Getting there
## A card for one node of the sample, built and measured.
func _card(node: ComposerNode) -> ComposerCard:
	_types.rebuild(Sample.build())
	var card: ComposerCard = ComposerCard.new()
	add_child_autofree(card)
	card.build(node, _types)
	await get_tree().process_frame
	return card


func _node(id: StringName) -> ComposerNode:
	return Sample.build().find_node(id)


## A node with one argument, so a test can say what that argument holds.
## A node with two arguments, both holding `written`.
##
## Two rather than one so a test about which argument was edited can tell them
## apart: with a single field, an index the card reported wrongly would still be
## nought and the test would agree with it.
func _node_holding(type_name: StringName, written: String) -> ComposerNode:
	var node: ComposerNode = _node(Sample.APPLY)
	node.fields.clear()
	for label: String in ["Effect", "Level"]:
		var field: ComposerNode.Field = ComposerNode.Field.new()
		field.label = label
		field.type_name = type_name
		field.display = written
		node.fields.append(field)
	return node
#endregion


#region What a card is
func test_a_card_is_a_graph_node() -> void:
	var card: ComposerCard = await _card(_node(Sample.COMMIT))

	assert_true(card is GraphNode, "the card is the widget's own node")
	assert_eq(card.name, String(Sample.COMMIT), "named so the widget can find it")


## A card looks the same wherever it is standing.
##
## The rows are the card's own controls and carry their own font. The title is
## GraphNode's, drawn out of the ambient theme, so a card built inside a project
## whose theme says something loud about GraphNode titles came out with a title
## several times the size of the values under it - measured at 96 against the
## card's own 14. It looked right in the Godot editor by accident, because the
## editor's theme happened to be quiet.
func test_a_card_draws_its_title_at_its_own_size_whatever_the_host_says() -> void:
	var loud: Theme = Theme.new()
	loud.set_font_size(GASEditorTheme.TITLE_FONT_SIZE, "GraphNode", 96)
	var host: Control = Control.new()
	host.theme = loud
	add_child_autofree(host)

	var built: ComposerCard = ComposerCard.new()
	host.add_child(built)
	_types.rebuild(Sample.build())
	built.build(_node(Sample.COMMIT), _types)
	await get_tree().process_frame

	assert_eq(
		built.get_theme_font_size(GASEditorTheme.TITLE_FONT_SIZE),
		ComposerTheme.FONT_TITLE,
		"the card says how its title is drawn"
	)
	var bare: Control = Control.new()
	add_child_autofree(bare)
	bare.theme = loud
	assert_eq(
		bare.get_theme_font_size(GASEditorTheme.TITLE_FONT_SIZE, "GraphNode"), 96,
		"and the host really was saying something else"
	)


## The card is addressed by its node's id, which is how a wire finds it.
func test_a_card_carries_the_id_of_the_statement_it_draws() -> void:
	var card: ComposerCard = await _card(_node(Sample.CUE))

	assert_eq(card.node_id, Sample.CUE)
#endregion


#region Which pin is which
## Every pin the node declares is drawn, on the side it faces.
func test_every_declared_pin_is_drawn_on_its_own_side() -> void:
	var node: ComposerNode = _node(Sample.APPLY)
	var card: ComposerCard = await _card(node)

	assert_gte(card.left_index_for_port(ComposerReader.EXEC_IN), 0, "a way in")
	assert_gte(card.right_index_for_port(ComposerReader.EXEC_OUT), 0, "a way out")
	assert_gte(
		card.right_index_for_port(ComposerReader.VALUE_OUT), 0, "and a value out"
	)
	for position: int in node.fields.size():
		assert_gte(
			card.left_index_for_port(StringName(ComposerReader.ARGUMENT % position)),
			0,
			"argument %d has somewhere for a value to land" % position
		)


## A pin the node does not declare is not drawn.
##
## A `return` has no way out. Offering one would be the card promising something
## GDScript will not keep, and a wire dropped on it would be refused after the
## person had already drawn it.
func test_a_pin_the_node_does_not_declare_is_not_drawn() -> void:
	var node: ComposerNode = _node(Sample.COMMIT)
	node.ports = node.ports.filter(
		func _without_exit(pin: ComposerNode.Port) -> bool:
			return pin.id != ComposerReader.EXEC_OUT
	)

	var card: ComposerCard = await _card(node)

	assert_eq(card.right_index_for_port(ComposerReader.EXEC_OUT), -1, "no way out")
	assert_gte(card.left_index_for_port(ComposerReader.EXEC_IN), 0, "still a way in")


## Numbering counts drawn pins, not rows.
##
## The failure this exists for: a card whose rows do not all carry a pin. Every
## index the canvas hands back has to survive the round trip, or a cable lands
## on the wrong argument and looks right doing it.
func test_every_drawn_pin_answers_to_the_number_it_was_given() -> void:
	var card: ComposerCard = await _card(_node(Sample.CUE))

	var drawn: int = 0
	for position: int in 8:
		var named: StringName = card.left_port_of_drawn(position)
		if named.is_empty():
			continue
		assert_eq(
			card.left_index_for_port(named),
			position,
			"input %d is %s both ways round" % [position, named]
		)
		drawn += 1
	assert_gt(drawn, 1, "there was more than one input to get wrong")


## An index nothing was drawn at names nothing, rather than the nearest pin.
func test_an_index_with_no_pin_names_nothing() -> void:
	var card: ComposerCard = await _card(_node(Sample.COMMIT))

	assert_eq(card.left_port_of_drawn(97), &"", "no such input")
	assert_eq(card.right_port_of_drawn(97), &"", "no such output")
	assert_eq(card.port_id_for_left_index(97), &"", "and no such row")


## A pin has somewhere to be, so a wire has somewhere to attach.
func test_a_declared_pin_has_a_place_on_the_card() -> void:
	var card: ComposerCard = await _card(_node(Sample.APPLY))

	assert_ne(
		card.graph_port_position(ComposerReader.EXEC_IN),
		card.graph_port_position(ComposerReader.EXEC_OUT),
		"the way in and the way out are not the same place"
	)
	assert_eq(
		card.graph_port_position(&"nothing"), Vector2.ZERO, "and a pin that is not there"
	)
#endregion


#region What a person can touch
## An argument that holds a value gets a control that can show it.
func test_an_argument_holding_a_value_can_be_edited_in_place() -> void:
	var card: ComposerCard = await _card(_node_holding(&"float", "1.5"))

	var editors: Array[Node] = card.find_children("", "ComposerValueEditor", true, false)
	assert_eq(editors.size(), 2, "one control per argument")


## An argument fed by a cable offers nothing to type into.
##
## Two ways to set one argument is one too many: typing into a wired field would
## silently break the cable somebody can see attached to it.
func test_an_argument_fed_by_a_cable_has_no_editor() -> void:
	var node: ComposerNode = _node_holding(&"float", "strength")
	for field: ComposerNode.Field in node.fields:
		field.source = ComposerNode.ValueSource.WIRED

	var editable: ComposerCard = await _card(_node_holding(&"float", "1.5"))
	var card: ComposerCard = await _card(node)

	assert_gt(
		editable.find_children("", "SpinBox", true, false).size(),
		0,
		"the same argument unwired does offer a control"
	)
	assert_eq(
		card.find_children("", "LineEdit", true, false).size(), 0, "nothing to type into"
	)
	assert_eq(
		card.find_children("", "SpinBox", true, false).size(), 0, "and nothing to spin"
	)


## Finishing an edit in a row says which argument was set, and to what.
func test_editing_a_row_says_which_argument_it_was() -> void:
	var card: ComposerCard = await _card(_node_holding(&"float", "1.5"))
	watch_signals(card)
	var editors: Array[Node] = card.find_children("", "ComposerValueEditor", true, false)
	var editor: ComposerValueEditor = editors[1]

	editor.committed.emit("2.5")

	var said: Array = get_signal_parameters(card, "value_edited")
	var node_id: StringName = said[0]
	var position: int = said[1]
	var written: String = said[2]
	assert_eq(node_id, Sample.APPLY, "on this card")
	assert_eq(position, 1, "at the second argument, not merely at one")
	assert_eq(written, "2.5", "set to this")


## A required argument that is absent is said to be, and offers nothing.
func test_an_absent_argument_says_so_instead_of_offering_a_control() -> void:
	var card: ComposerCard = await _card(_node(Sample.CUE))

	var absent: bool = false
	for label: Node in card.find_children("", "Label", true, false):
		var shown: Label = label
		absent = absent or shown.text == ComposerCard.MISSING_LABEL
	assert_true(absent, "the missing argument is named as missing")
#endregion


#region Size
## Moving a card does not change how big it wants to be.
##
## Position and size are separate on a GraphNode, and were not on the Control
## this replaced: that one wrote its own size after measuring itself, so any
## code that moved it had to know to measure it again.
func test_moving_a_card_leaves_its_size_alone() -> void:
	var card: ComposerCard = await _card(_node(Sample.APPLY))
	var wanted: Vector2 = card.get_combined_minimum_size()

	card.position_offset += Vector2(120.0, 80.0)
	await get_tree().process_frame

	assert_eq(card.get_combined_minimum_size(), wanted, "the same size, somewhere else")


## A card is at least big enough to be read.
func test_a_card_is_never_smaller_than_it_can_be_read_at() -> void:
	var card: ComposerCard = await _card(_node(Sample.APPLY))

	assert_gt(card.size.x, 0.0, "it has a width")
	assert_gt(card.size.y, 0.0, "and a height")
#endregion


#region How much to draw
## Pulling back never renumbers a pin.
##
## The canvas fixes every wire's pin indices once, when the graph is drawn. A
## card that hid rows would drop them out of GraphNode's slot list, renumbering
## every pin below - so zooming out to look at an ability would silently
## re-point every cable on it, and zooming back in would not put them back.
func test_pulling_back_never_renumbers_a_pin() -> void:
	var card: ComposerCard = await _card(_node(Sample.CUE))
	var before: Dictionary[StringName, int] = {}
	for position: int in 8:
		var named: StringName = card.left_port_of_drawn(position)
		if not named.is_empty():
			before[named] = position
	assert_gt(before.size(), 1, "there is more than one pin to renumber")

	card.show_detail(ComposerCard.Detail.BLOCK)
	await get_tree().process_frame

	for named: StringName in before:
		assert_eq(
			card.left_index_for_port(named),
			before[named],
			"%s is still pin %d" % [named, before[named]]
		)


## Pulled back, a card keeps every row it had and stops showing them.
func test_pulling_back_keeps_the_rows_and_hides_what_they_say() -> void:
	var card: ComposerCard = await _card(_node(Sample.APPLY))
	var rows: int = card.get_child_count()

	card.show_detail(ComposerCard.Detail.BLOCK)
	await get_tree().process_frame

	assert_eq(card.get_child_count(), rows, "the rows are all still there")
	for child: Node in card.get_children():
		var row: Control = child
		assert_true(row.visible, "and none of them left the layout")
#endregion
