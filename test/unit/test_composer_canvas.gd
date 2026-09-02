## The canvas: model to layout to pixels, end to end.
##
## Everything below runs headless. The point is not that it looks right - that
## was settled against a rendered mock - but that the chain holds: a graph goes
## in, cards come out sized to their content, and nothing is left drawn at the
## wrong depth or at a size nobody set.
##
## @meta_license: MIT
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

var canvas: ComposerCanvas = null


func before_each() -> void:
	canvas = ComposerCanvas.new()
	canvas.size = Vector2(1280.0, 720.0)
	add_child_autofree(canvas)


func after_each() -> void:
	canvas = null


func _cards() -> Array[ComposerCard]:
	var found: Array[ComposerCard] = []
	for layer: Node in canvas.get_children():
		for child: Node in layer.get_children():
			for card: Node in child.get_children():
				if card is ComposerCard:
					found.append(card)
	return found


#region Drawing a graph
func test_every_node_becomes_exactly_one_card() -> void:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)

	assert_eq(_cards().size(), graph.nodes.size(), "one card per node, no more")


## The two-step measure, seen from outside.
##
## A card cannot know its height until it is in the tree with a theme resolved,
## so `show_graph` places it and trims it a frame later. If that frame were
## skipped every card would stay at its placeholder height and the field boxes
## would hang outside the panel.
func test_cards_are_cut_to_their_content_rather_than_left_at_a_placeholder() -> void:
	await canvas.show_graph(Sample.build())

	for card: ComposerCard in _cards():
		assert_gt(card.size.y, ComposerTheme.PAD_Y * 2.0, "%s has real height" % card.node_id)
		assert_eq(card.size.x, ComposerTheme.NODE_WIDTH, "and the one width every card has")


## A card with two fields is taller than one with none. Without this, a height
## that happened to be constant would satisfy the test above and still be wrong.
func test_a_card_with_more_fields_is_taller() -> void:
	await canvas.show_graph(Sample.build())

	var heights: Dictionary[StringName, float] = {}
	for card: ComposerCard in _cards():
		heights[card.node_id] = card.size.y

	assert_gt(
		heights[Sample.APPLY], heights[Sample.COMMIT],
		"two fields take more room than none"
	)


func test_a_graph_with_wires_draws_them_and_their_beads() -> void:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)

	var wires: int = 0
	var beads: int = 0
	for layer: Node in canvas.get_children():
		for child: Node in layer.get_children():
			if child.get_child_count() == 0:
				continue
			for drawn: Node in child.get_children():
				if drawn is Line2D:
					wires += 1
				elif drawn is Panel or drawn is TextureRect:
					beads += 1

	assert_eq(wires, graph.connections.size() * 2, "a glow and a line for each wire")
	assert_gt(beads, 0, "and a bead where each one lands")
#endregion


#region Layers
## Draw order is a fact of the tree, not of the order things were created.
##
## Wires must sit behind the cards and beads in front, but neither can be
## positioned until the cards have measured themselves. Anything relying on
## creation order ends up drawing a cable across a card or burying a bead under
## one - which is exactly what the first version of this did.
func test_the_layers_stand_in_the_order_that_makes_the_drawing_correct() -> void:
	await canvas.show_graph(Sample.build())

	var world: Control = canvas.get_child(1) as Control
	assert_eq(world.get_child_count(), 4, "glow, wires, cards, beads")

	var cards_at: int = -1
	var wires_at: int = -1
	var beads_at: int = -1
	for index: int in world.get_child_count():
		for child: Node in world.get_child(index).get_children():
			if child is ComposerCard:
				cards_at = index
			elif child is Line2D:
				wires_at = index
			elif child is TextureRect and index != 0:
				beads_at = index

	assert_lt(wires_at, cards_at, "a cable passes under a card")
	assert_lt(cards_at, beads_at, "and a bead sits on the edge it attaches to")
#endregion


#region Zoom
func test_zoom_starts_at_one_and_is_held_between_its_bounds() -> void:
	assert_almost_eq(canvas.zoom(), 1.0, 0.0001, "a file opens at its own size")

	for _step: int in 40:
		canvas._apply_zoom(canvas.zoom() * 2.0, Vector2.ZERO)
	assert_almost_eq(canvas.zoom(), ComposerCanvas.ZOOM_MAX, 0.0001, "and cannot pass the ceiling")

	for _step: int in 40:
		canvas._apply_zoom(canvas.zoom() * 0.5, Vector2.ZERO)
	assert_almost_eq(canvas.zoom(), ComposerCanvas.ZOOM_MIN, 0.0001, "nor the floor")


## Anchored at the pointer, not at the centre.
##
## Zooming from the centre drags whatever you were looking at out of view, which
## is the difference between a zoom that feels right and one that fights. The
## check is that the world point under the anchor is the same before and after.
func test_zooming_keeps_the_point_under_the_pointer_where_it_was() -> void:
	var anchor: Vector2 = Vector2(400.0, 300.0)
	var world: Control = canvas.get_child(1) as Control
	var before: Vector2 = (anchor - world.position) / canvas.zoom()

	canvas._apply_zoom(1.5, anchor)

	var after: Vector2 = (anchor - world.position) / canvas.zoom()
	assert_almost_eq(after.x, before.x, 0.01, "the same spot is still under the cursor")
	assert_almost_eq(after.y, before.y, 0.01, "on both axes")
#endregion


func test_showing_nothing_clears_the_canvas() -> void:
	await canvas.show_graph(Sample.build())
	assert_gt(_cards().size(), 0, "something was drawn")

	canvas.show_graph(null)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_cards().size(), 0, "and then it was not")
