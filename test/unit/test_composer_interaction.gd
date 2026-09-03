## What the Composer's panels do when a person uses them.
##
## Its sibling, test_composer_chrome.gd, is about what those panels *say*. What
## they *do* turned out to be a different question with different answers: three
## of the interactions below were reported from a real editor as doing nothing,
## and each was a wire that existed at one end only. A method public, tested and
## unreachable. A signal emitted with the wrong type, refused by the engine
## before it arrived anywhere that could report it. A drag the layout invited
## and nothing implemented.
##
## The rule this file holds to, and the reason it exists apart: every test goes
## through the wire rather than around it. Calling a handler directly is what
## let all three hide.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

const PANEL_WIDTH: float = 290.0
const PANEL_HEIGHT: float = 400.0


func _mounted(control: Control, span: Vector2) -> Control:
	control.size = span
	add_child_autofree(control)
	return control


## The header row carrying this group's name, wherever the palette put it.
func _header_for(parent: Node, group: StringName) -> Control:
	for child: Node in parent.get_children():
		if child is HBoxContainer:
			for inner: Node in child.get_children():
				if inner is Label and (inner as Label).text == String(group):
					return child as Control
		var deeper: Control = _header_for(child, group)
		if deeper != null:
			return deeper
	return null


## Press the button carrying this exact text, wherever it is.
func _press_titled(parent: Node, title: String) -> bool:
	for child: Node in parent.get_children():
		if child is Button and (child as Button).text == title:
			(child as Button).pressed.emit()
			return true
		if _press_titled(child, title):
			return true
	return false


## What a palette row actually emits when it is pressed.
##
## The suite called the screen's handler directly, which proved the handler and
## never the wire between them. The wire was broken the whole time: the row
## emitted the catalog entry where the signal declares a StringName, so Godot
## refused the call at the connection and every palette click did nothing at
## all - silently, because the refusal happened before any code that could have
## reported it. A click reported from a real editor is what found it.
func test_pressing_a_palette_row_emits_a_key_the_catalog_can_find() -> void:
	var palette: ComposerPalette = _mounted(
		ComposerPalette.new(), Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	) as ComposerPalette
	await get_tree().process_frame

	var wanted: StringName = ComposerCatalog.all().keys()[0]
	var row: Button = palette._entry_row(wanted) as Button
	add_child_autofree(row)

	var heard: Array = []
	palette.node_picked.connect(func _picked(what: Variant) -> void: heard.append(what))
	row.pressed.emit()

	assert_eq(heard.size(), 1, "the press was heard")
	assert_eq(
		typeof(heard[0]), TYPE_STRING_NAME, "as the StringName the signal declares"
	)
	# Guarded, because the second claim only means anything once the first holds:
	# with the defect present this array held an Object, and looking a key up
	# from one would fail as a crash rather than as a message.
	if typeof(heard[0]) == TYPE_STRING_NAME:
		var emitted: StringName = heard[0]
		assert_not_null(ComposerCatalog.find(emitted), "and the catalog knows it")


## A refusal offers the way out, it does not only describe it.
##
## Telling somebody who arrived through a menu to go and open a file themselves
## is telling them the tool cannot do what they just asked for. The screen
## forwards the request rather than answering it, because choosing a file is
## the editor's business and this view knows nothing about docks.
func test_a_refusal_offers_to_open_one_and_the_screen_passes_that_on() -> void:
	var screen: ComposerScreen = _mounted(
		ComposerScreen.new(), Vector2(1280.0, 720.0)
	) as ComposerScreen
	await get_tree().process_frame
	await screen.show_refusal("the script editor has nothing open")

	var asked: Array[bool] = []
	screen.open_requested.connect(func _heard() -> void: asked.append(true))

	assert_true(_press_titled(screen, ComposerTopBar.OPEN_ONE), "the offer is on screen")
	assert_eq(asked.size(), 1, "and pressing it reaches whoever owns the editor")


## Mounted the way the editor mounts it: inside a container.
##
## `EditorInterface.get_editor_main_screen()` is a container, and a container
## sizes its children by their size flags and ignores their anchors completely.
## The screen was added with an anchors preset and no flags, so it was given its
## minimum height - a strip - and everything inside it went where a strip puts
## things: the palette overflowed its own bounds, the canvas was a sliver, and
## the Output panel was laid out at the top of the window instead of the bottom.
## From the editor it read as most of the interface being missing.
##
## Every other test here sets `size` by hand, which is why none of them could
## have caught it. This one refuses to, and asks the container instead.
func test_mounted_in_a_container_the_screen_is_given_the_whole_of_it() -> void:
	var mount: VBoxContainer = VBoxContainer.new()
	add_child_autofree(mount)
	mount.size = Vector2(1280.0, 900.0)

	var screen: ComposerScreen = ComposerScreen.new()
	mount.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_almost_eq(screen.size.y, 900.0, 4.0, "the height it was offered")
	assert_almost_eq(screen.size.x, 1280.0, 4.0, "and the width")


## A group header is something a person can click.
##
## It is a row of two labels, and nothing was ever connected to it: `open_group()`
## existed, was public, was tested - and could only be reached from a test. In
## the editor no group could be opened or closed at all. Producer with no
## consumer, in the one place a person meets first.
func test_clicking_a_group_header_opens_it_and_clicking_again_closes_it() -> void:
	var palette: ComposerPalette = _mounted(
		ComposerPalette.new(), Vector2(250.0, PANEL_HEIGHT)
	) as ComposerPalette
	await get_tree().process_frame

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	var header: Control = _header_for(palette, ComposerCatalog.EFFECTS)
	assert_not_null(header, "the header is on screen")
	header.gui_input.emit(click)
	assert_eq(palette.open_group_name(), ComposerCatalog.EFFECTS, "it opened")

	_header_for(palette, ComposerCatalog.EFFECTS).gui_input.emit(click)
	assert_eq(palette.open_group_name(), &"", "and clicking it again closed it")


## A call can be carried from the palette to the canvas.
##
## Dragging was never implemented: the palette offered no drag data and the
## canvas answered no drop, so a person dragging a node onto the grid watched
## nothing happen and had no way to tell that from a broken tool.
func test_a_call_dragged_from_the_palette_is_taken_by_the_canvas() -> void:
	var wanted: StringName = ComposerCatalog.all().keys()[0]
	var carried: Dictionary = ComposerPalette.carried_call(wanted)

	var canvas: ComposerCanvas = _mounted(
		ComposerCanvas.new(), Vector2(700.0, 500.0)
	) as ComposerCanvas
	await canvas.show_graph(Sample.build())

	assert_true(canvas._can_drop_data(Vector2.ZERO, carried), "the canvas takes a call")
	assert_false(
		canvas._can_drop_data(Vector2.ZERO, {"something else": 1}),
		"and refuses what it does not understand"
	)

	var asked: Array[StringName] = []
	canvas.node_requested.connect(func _heard(id: StringName) -> void: asked.append(id))
	canvas._drop_data(Vector2.ZERO, carried)

	assert_eq(asked, [wanted] as Array[StringName], "and reports the call that landed")
