## The canvas: model to layout to pixels, end to end.
##
## Everything below runs headless. The point is not that it looks right - that
## was settled against a rendered mock - but that the chain holds: a graph goes
## in, cards come out sized to their content, and nothing is left drawn at the
## wrong depth or at a size nobody set.
##
## @meta_license: GAS_Engine Community Use License 1.0
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

	assert_eq(_cards().size(), graph.visible_nodes().size(), "one card per node, no more")


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
		assert_gte(
			card.size.x, ComposerTheme.NODE_MIN_WIDTH, "and at least the narrowest width"
		)


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


#region Picking cards
func _click(at: Vector2, pressed: bool, adding: bool = false) -> void:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	button.shift_pressed = adding
	canvas._gui_input(button)


func _tap(at: Vector2, adding: bool = false) -> void:
	_click(at, true, adding)
	_click(at, false, adding)


func _middle(pressed: bool) -> void:
	var button: InputEventMouseButton = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_MIDDLE
	button.pressed = pressed
	canvas._gui_input(button)


func _drag_to(at: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.relative = Vector2(20.0, 12.0)
	canvas._gui_input(motion)


## Where a card is on screen, which is not where it is in the graph.
func _on_screen(card: ComposerCard) -> Vector2:
	return card.position * canvas.zoom() + canvas._world.position + card.size * 0.5


## A point with no card under it.
##
## Worked out rather than guessed: the first card sits at the origin of the
## world, so the obvious corner to click for "nothing here" is the one place
## there is always something.
func _empty_spot() -> Vector2:
	var lowest: Vector2 = Vector2.ZERO
	for card: ComposerCard in _cards():
		var corner: Vector2 = (
			(card.position + card.size) * canvas.zoom() + canvas._world.position
		)
		lowest = lowest.max(corner)
	return lowest + Vector2(40.0, 40.0)


func _shown() -> ComposerGraph:
	var graph: ComposerGraph = Sample.build()
	await canvas.show_graph(graph)
	return graph


func test_clicking_a_card_picks_it_and_clicking_away_lets_it_go() -> void:
	await _shown()
	var card: ComposerCard = _cards()[0]

	_tap(_on_screen(card))
	assert_eq(canvas.picked(), [card.node_id] as Array[StringName], "the one clicked")

	_tap(_empty_spot())
	assert_true(canvas.picked().is_empty(), "and nothing when the canvas is clicked")


## Holding shift adds, and adds the other way on a card already picked. Without
## the second half a person can grow a selection and never trim one.
func test_holding_shift_adds_a_card_and_takes_it_back_out() -> void:
	await _shown()
	var first: ComposerCard = _cards()[0]
	var second: ComposerCard = _cards()[1]

	_tap(_on_screen(first))
	_tap(_on_screen(second), true)
	assert_eq(canvas.picked().size(), 2, "both")

	_tap(_on_screen(second), true)
	assert_eq(canvas.picked(), [first.node_id] as Array[StringName], "and back to one")


## A card already in the selection is left alone on a plain click, so reaching
## for several of them does not throw the rest away first.
func test_clicking_one_of_several_picked_cards_keeps_the_others() -> void:
	await _shown()
	var first: ComposerCard = _cards()[0]
	var second: ComposerCard = _cards()[1]
	_tap(_on_screen(first))
	_tap(_on_screen(second), true)

	_tap(_on_screen(first))

	assert_eq(canvas.picked().size(), 2, "still both")


func test_a_box_dragged_over_the_graph_sweeps_what_it_covers() -> void:
	await _shown()

	var from: Vector2 = _empty_spot()
	_click(from, true)
	_drag_to(from - Vector2(4000.0, 4000.0))
	_click(from - Vector2(4000.0, 4000.0), false)

	assert_eq(canvas.picked().size(), _cards().size(), "a box over everything takes it all")


## Dragged back past where it started, a box sweeps the other way rather than
## collapsing to nothing.
func test_a_box_dragged_backwards_still_covers_ground() -> void:
	await _shown()
	var card: ComposerCard = _cards()[0]
	var at: Vector2 = _on_screen(card)

	_click(at + Vector2(60.0, 60.0), true)
	_drag_to(at - Vector2(60.0, 60.0))
	_click(at - Vector2(60.0, 60.0), false)

	assert_true(canvas.picked().has(card.node_id), "the card it was dragged across")


func test_the_selection_is_announced_once_it_changes() -> void:
	await _shown()
	var heard: Array[int] = []
	canvas.selection_changed.connect(
		func _on(ids: Array[StringName]) -> void: heard.append(ids.size())
	)

	_tap(_on_screen(_cards()[0]))

	assert_eq(heard.size(), 1, "said once")
	assert_eq(heard[0], 1, "and said what is picked")
#endregion


#region Getting about
func test_the_middle_button_drags_the_graph_about() -> void:
	await _shown()
	var before: Vector2 = canvas._world.position

	_middle(true)
	_drag_to(Vector2(300.0, 300.0))
	_middle(false)
	var after: Vector2 = canvas._world.position

	assert_ne(after, before, "the world moved")
	_drag_to(Vector2(600.0, 600.0))
	assert_eq(canvas._world.position, after, "and stopped when the button came up")


## The whole graph on screen, and never past the zoom a person can reach by
## hand - a frame that lands outside the range leaves them somewhere the wheel
## cannot get back to.
func test_framing_everything_puts_the_whole_graph_on_screen() -> void:
	var graph: ComposerGraph = await _shown()
	canvas._apply_zoom(2.0, Vector2.ZERO)

	canvas.frame_all()

	assert_between(
		canvas.zoom(), ComposerCanvas.ZOOM_MIN, ComposerCanvas.ZOOM_MAX, "within reach"
	)
	for card: ComposerCard in _cards():
		var at: Vector2 = card.position * canvas.zoom() + canvas._world.position
		assert_between(at.x, 0.0, canvas.size.x, "%s is on screen" % card.node_id)
		assert_between(at.y, 0.0, canvas.size.y, "%s is on screen" % card.node_id)
	assert_gt(graph.visible_nodes().size(), 1, "and there was more than one to fit")


func test_revealing_a_node_picks_it_and_brings_it_into_view() -> void:
	var graph: ComposerGraph = await _shown()
	var drawn: Array[ComposerNode] = graph.visible_nodes()
	var wanted: StringName = drawn[drawn.size() - 1].id
	canvas._apply_zoom(2.0, Vector2.ZERO)

	canvas.reveal(wanted)

	assert_eq(canvas.picked(), [wanted] as Array[StringName], "picked")
	var card: ComposerCard = _cards()[graph.visible_nodes().size() - 1]
	var at: Vector2 = card.position * canvas.zoom() + canvas._world.position
	assert_between(at.x, 0.0, canvas.size.x, "and on screen")
	assert_between(at.y, 0.0, canvas.size.y, "and on screen")


func test_revealing_a_node_that_is_not_drawn_does_nothing() -> void:
	await _shown()
	canvas.reveal(&"no_such_node")

	assert_true(canvas.picked().is_empty(), "nothing was picked")
#endregion


#region How much of a card is worth drawing
## The three bands, read off the thresholds rather than off numbers repeated
## here - a table that drifts from the canvas is a test of the table.
func test_the_detail_a_card_draws_follows_the_zoom() -> void:
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_FULL), ComposerCard.Detail.FULL,
		"at the full threshold, the whole card"
	)
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_TITLE), ComposerCard.Detail.TITLE,
		"lower down, the title alone"
	)
	assert_eq(
		ComposerCanvas.detail_at(ComposerCanvas.DETAIL_TITLE - 0.01),
		ComposerCard.Detail.BLOCK,
		"and below that, a block"
	)


## The card keeps its size as its contents go away. Shrinking it would move
## every port on it and the wires with them, and the graph would appear to
## rearrange itself while somebody was only pulling back to look at it.
func test_pulling_back_empties_a_card_without_resizing_it() -> void:
	await _shown()
	var card: ComposerCard = _cards()[0]
	var span: Vector2 = card.size

	canvas._apply_zoom(ComposerCanvas.DETAIL_TITLE - 0.05, Vector2.ZERO)

	assert_eq(card.size, span, "the card is the size it was")
	for row: Control in card._rows:
		assert_false(row.visible, "and its fields are not being drawn")
#endregion


## Opening an ability never opens it unreadable.
##
## Framing used to clamp at ZOOM_MIN, so any graph wider than the canvas landed
## below DETAIL_FULL and every card opened as a bare title - the Composer
## showing less than the file it had just read, which is the first thing anyone
## saw. Part of a readable graph beats all of an unreadable one.
func test_framing_never_opens_a_graph_below_the_level_that_shows_values() -> void:
	canvas.size = Vector2(420.0, 260.0)
	await canvas.show_graph(Sample.build())

	canvas.frame_all()

	assert_gte(
		canvas.zoom(), ComposerCanvas.DETAIL_FULL, "framed, and still showing its values"
	)
	assert_eq(
		ComposerCanvas.detail_at(canvas.zoom()), ComposerCard.Detail.FULL,
		"which is what that threshold means"
	)


## A selection is shaped like the thing it selects.
##
## It was a ReferenceRect, which can only draw a rectangle: a hard square around
## a rounded card. Reported as "a rectangle that should never appear", and that
## is a fair reading - a square outline on a rounded card looks like something
## the editor left behind rather than something anybody drew.
func test_the_edge_on_a_picked_card_has_the_card_s_corners() -> void:
	var edge: StyleBoxFlat = ComposerTheme.picked_box()

	assert_eq(
		edge.corner_radius_top_left, ComposerTheme.RADIUS_PANEL, "the card's own radius"
	)
	assert_eq(edge.bg_color.a, 0.0, "an edge, not a fill over the card")
	assert_eq(edge.border_color, ComposerTheme.ACCENT, "and it reads as a selection")
