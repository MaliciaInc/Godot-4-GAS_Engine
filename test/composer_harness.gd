## Every function of the Ability Composer, in a real window with a real renderer.
##
## It runs in this game rather than in the engine's own project on purpose: the
## Composer is only worth anything if it opens abilities somebody wrote for a
## real game, so the first file it opens here is this game's own.
##
## **What this proves and what it does not.** Every gesture is handed to the
## handler the way the viewport hands it over - a real event, at a point worked
## out from where the card actually is on screen. That exercises hit-testing,
## the layout, the fonts, the card sizing and the drawing, none of which
## headless can show. It does not exercise the step before that, where the
## operating system gives a click to Godot and Godot decides which control gets
## it: synthesised events do not reach the GUI layer at all, with either
## `Viewport.push_input` or `Input.parse_input_event`, focused window or not.
## That step is the ordinary `mouse_filter` mechanism every Godot control uses,
## and proving it needs a hand on a mouse.
##
## Nothing writes to the game's source. Editing happens on a copy under
## `user://`, and the last check is that the game's file is what it was.
##
## @meta_license: MIT
extends Node

const ABILITY: String = "res://src/combat/abilities/battler_ability.gd"
const WITH_ARGUMENTS: String = "res://addons/GAS_Engine/reference/timed_buff.gd"

## The only reference ability whose body actually feeds one statement from
## another. See the note on `_rewiring`.
const WITH_A_CABLE: String = "res://addons/GAS_Engine/reference/sweeping_volley.gd"
const COPY: String = "user://composer_harness_ability.gd"
const SHOTS: String = "user://composer_harness"

const SCREEN: Vector2 = Vector2(1920.0, 1080.0)
const SETTLE: int = 3

var _screen: ComposerScreen = null
var _passed: int = 0
var _report: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))

	# The window is asked for, and the screen is sized to the viewport that
	# results - not to a number of my own. A game stretches its canvas to
	# whatever it declares, so a Control given some other size is drawn in a
	# corner of the window and the pictures show a corner of the Composer.
	get_window().size = Vector2i(SCREEN)
	await _frames(SETTLE)

	_screen = ComposerScreen.new()
	_screen.size = get_viewport().get_visible_rect().size
	add_child(_screen)
	await _frames(SETTLE)

	await _run()

	print("\n===== COMPOSER HARNESS =====")
	for line: String in _report:
		print(line)
	print("%d checks, %d passed, %d to look at" % [
		_report.size(), _passed, _report.size() - _passed
	])
	print("shots: %s" % ProjectSettings.globalize_path(SHOTS))
	get_tree().quit(0)


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-48s %s" % ["  ok " if held else "FAIL", what, detail])


func _frames(count: int) -> void:
	for _step: int in count:
		await get_tree().process_frame


func _shot(label: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [SHOTS, label])
#endregion


#region Gestures, at the point the card actually occupies
func _canvas() -> ComposerCanvas:
	return _screen.canvas()


## Where a card sits, in the canvas's own coordinates.
func _on_card(index: int) -> Vector2:
	var canvas: ComposerCanvas = _canvas()
	var wanted: StringName = _screen.graph().nodes[index].id
	for child: Node in canvas._card_layer.get_children():
		var card: ComposerCard = child as ComposerCard
		if card != null and card.node_id == wanted:
			return canvas._world.position + (card.position + card.size * 0.5) * canvas.zoom()
	return Vector2.ZERO


func _nowhere() -> Vector2:
	var lowest: Vector2 = Vector2.ZERO
	var canvas: ComposerCanvas = _canvas()
	for child: Node in canvas._card_layer.get_children():
		var card: ComposerCard = child as ComposerCard
		if card != null:
			lowest = lowest.max(
				canvas._world.position + (card.position + card.size) * canvas.zoom()
			)
	return lowest + Vector2(40.0, 40.0)


func _button(at: Vector2, index: int, pressed: bool, shift: bool = false) -> void:
	var made: InputEventMouseButton = InputEventMouseButton.new()
	made.button_index = index
	made.pressed = pressed
	made.position = at
	made.shift_pressed = shift
	_canvas()._gui_input(made)
	await _frames(1)


func _tap(at: Vector2, index: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await _button(at, index, true, shift)
	await _button(at, index, false, shift)


func _drag(from: Vector2, to: Vector2, index: int = MOUSE_BUTTON_LEFT) -> void:
	await _button(from, index, true)
	var moved: InputEventMouseMotion = InputEventMouseMotion.new()
	moved.position = to
	moved.relative = to - from
	_canvas()._gui_input(moved)
	await _frames(1)
	await _button(to, index, false)


func _wheel(at: Vector2, up: bool) -> void:
	await _button(at, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true)


func _chord(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var made: InputEventKey = InputEventKey.new()
	made.keycode = code
	made.pressed = true
	made.ctrl_pressed = ctrl
	made.shift_pressed = shift
	await _screen._shortcut_input(made)
	await _frames(SETTLE)


func _titles() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for node: ComposerNode in _screen.graph().nodes:
		found.append(node.title)
	return found
#endregion


#region The run
func _run() -> void:
	var original: String = FileAccess.get_file_as_string(ABILITY)

	await _this_games_ability(original)
	await _getting_about()
	await _picking()
	await _menu_and_drag()
	await _editing()
	await _commands()
	await _finding()
	await _rewiring()
	await _free_placement()
	await _leaving()

	_check(
		"the game's own file was never written to",
		FileAccess.get_file_as_string(ABILITY) == original
	)


func _this_games_ability(original: String) -> void:
	await _screen.open(original, ABILITY)
	await _frames(SETTLE)
	await _shot("01-this-games-ability")

	var graph: ComposerGraph = _screen.graph()
	_check("opens an ability written for this game", graph.is_editable(),
		graph.blocked_reason())
	_check("draws every statement", graph.nodes.size() == 7, "%d nodes" % graph.nodes.size())
	_check("and the cables between them", graph.connections.size() >= 6,
		"%d wires" % graph.connections.size())
	_check("with nothing to complain about", graph.diagnostics.is_empty(),
		"%d notes" % graph.diagnostics.size())
	_check("prints it back byte for byte",
		ComposerWriter.apply(graph, original).text == original)

	var cards: int = 0
	var measured: int = 0
	for child: Node in _canvas()._card_layer.get_children():
		var card: ComposerCard = child as ComposerCard
		if card == null:
			continue
		cards += 1
		measured += 1 if card.size.y > ComposerTheme.PAD_Y * 2.0 else 0
	_check("one card per statement", cards == graph.nodes.size(), "%d cards" % cards)
	_check("every card measured itself against real type", measured == cards,
		"%d of %d have height" % [measured, cards])


func _getting_about() -> void:
	var canvas: ComposerCanvas = _canvas()
	var middle: Vector2 = canvas.size * 0.5

	var before: float = canvas.zoom()
	await _wheel(middle, true)
	_check("the wheel zooms in", canvas.zoom() > before, "%.2f" % canvas.zoom())

	# Enough to reach the floor from anywhere in range, so the check is about
	# the clamp rather than about how many turns of a wheel I felt like.
	for _step: int in 40:
		await _wheel(middle, false)
	_check("and out, stopping at the floor",
		is_equal_approx(canvas.zoom(), ComposerCanvas.ZOOM_MIN), "%.2f" % canvas.zoom())
	_check("a card is drawn as a block when pulled back",
		ComposerCanvas.detail_at(canvas.zoom()) == ComposerCard.Detail.BLOCK)
	await _shot("02-pulled-right-back")

	var world: Vector2 = canvas._world.position
	await _drag(middle, middle + Vector2(120.0, 60.0), MOUSE_BUTTON_MIDDLE)
	_check("the middle button drags the graph about", canvas._world.position != world)

	canvas.frame_all()
	await _frames(SETTLE)
	_check("framing everything stays within reach of the wheel",
		canvas.zoom() >= ComposerCanvas.ZOOM_MIN and canvas.zoom() <= ComposerCanvas.ZOOM_MAX,
		"%.2f" % canvas.zoom())
	await _shot("03-framed")


func _picking() -> void:
	var canvas: ComposerCanvas = _canvas()

	await _tap(_on_card(0))
	_check("clicking a card picks it", canvas.picked().size() == 1,
		"%d picked" % canvas.picked().size())
	await _shot("04-one-picked")

	await _tap(_on_card(2), MOUSE_BUTTON_LEFT, true)
	_check("shift picks another as well", canvas.picked().size() == 2,
		"%d picked" % canvas.picked().size())
	await _shot("05-two-picked")

	await _tap(_on_card(2), MOUSE_BUTTON_LEFT, true)
	_check("and shift takes one back out", canvas.picked().size() == 1,
		"%d picked" % canvas.picked().size())

	await _tap(_nowhere())
	_check("clicking the canvas lets go of everything", canvas.picked().is_empty())

	await _drag(_nowhere(), Vector2(-4000.0, -4000.0))
	_check("a box sweeps everything it covers",
		canvas.picked().size() == _screen.graph().nodes.size(),
		"%d of %d" % [canvas.picked().size(), _screen.graph().nodes.size()])
	await _shot("06-box-selected")
	await _tap(_nowhere())


func _menu_and_drag() -> void:
	await _tap(_on_card(1), MOUSE_BUTTON_RIGHT)
	_check("right-click offers what can be done to a card",
		_screen._menu != null and _screen._menu.visible)
	await _shot("07-context-menu")
	if _screen._menu != null:
		_screen._menu.hide()
	await _frames(SETTLE)

	var before: PackedStringArray = _titles()
	var last: int = _screen.graph().nodes.size() - 1
	await _drag(_on_card(last), _on_card(0))
	await _frames(SETTLE)
	_check("dragging one card onto another reorders the body", _titles() != before,
		"%s -> %s" % [before[0], _titles()[0]])
	await _shot("08-reordered")

	await _screen.undo()
	await _frames(SETTLE)
	_check("and undo puts the order back", _titles() == before)


## A copy, so nothing here can reach the game's own file.
func _editing() -> void:
	var source: String = FileAccess.get_file_as_string(WITH_ARGUMENTS)
	var out: FileAccess = FileAccess.open(COPY, FileAccess.WRITE)
	out.store_string(source)
	out.close()

	await _screen.open(source, COPY)
	await _frames(SETTLE)

	var node: ComposerNode = null
	for drawn: ComposerNode in _screen.graph().nodes:
		if not drawn.fields.is_empty():
			node = drawn
			break
	_check("an ability with arguments shows them", node != null,
		"%s" % [node.title if node != null else "none has any"])
	if node == null:
		return

	await _tap(_on_card(_screen.graph().nodes.find(node)))
	await _frames(SETTLE)
	await _shot("09-inspector")

	var typed: String = "harness_value"
	_screen._on_value_edited(node.id, 0, typed)
	await _frames(SETTLE)
	_check("a typed value reaches the file", _screen.printed().contains(typed))
	await _shot("10-edited")

	await _chord(KEY_S, true)
	_check("Ctrl+S writes it to disk",
		FileAccess.get_file_as_string(COPY).contains(typed))
	_check("and Godot still compiles what was written", (load(COPY) as GDScript) != null)

	await _screen.undo()
	await _frames(SETTLE)
	_check("undo takes the edit back", not _screen.printed().contains(typed))
	await _screen.redo()
	await _frames(SETTLE)
	_check("redo puts it back", _screen.printed().contains(typed))
	await _screen.undo()
	await _frames(SETTLE)


func _commands() -> void:
	var before: int = _screen.graph().nodes.size()

	await _tap(_on_card(0))
	await _chord(KEY_D, true)
	_check("Ctrl+D repeats a statement", _screen.graph().nodes.size() == before + 1,
		"%d -> %d" % [before, _screen.graph().nodes.size()])

	await _tap(_on_card(0))
	await _chord(KEY_DELETE)
	_check("Delete takes one out", _screen.graph().nodes.size() == before,
		"%d nodes" % _screen.graph().nodes.size())

	await _tap(_on_card(0))
	var copied: String = _screen.copy_picked()
	_check("copying takes the statement as text", not copied.strip_edges().is_empty(),
		copied.strip_edges())

	var took: bool = await _screen.paste_text(copied)
	await _frames(SETTLE)
	_check("and pasting puts it back in",
		took and _screen.graph().nodes.size() == before + 1,
		"%d nodes" % _screen.graph().nodes.size())
	await _screen.undo()
	await _frames(SETTLE)
	await _shot("11-after-commands")


func _finding() -> void:
	await _chord(KEY_SPACE)
	var finder: ComposerFinder = _screen._finder
	_check("Space opens the finder", finder != null and finder.visible)
	await _shot("12-finder")
	if finder == null or not finder.visible:
		return

	finder._on_typed("commit")
	await _frames(SETTLE)
	_check("typing narrows it down", not finder.here().is_empty(),
		ComposerCatalog.find(finder.here()).title if not finder.here().is_empty() else "")
	await _shot("13-finder-typed")

	var before: int = _screen.graph().nodes.size()
	finder._take()
	await _frames(SETTLE)
	_check("choosing one writes a statement",
		_screen.graph().nodes.size() == before + 1,
		"%d -> %d" % [before, _screen.graph().nodes.size()])
	_check("and the finder gets out of the way", not finder.visible)
	await _shot("14-node-placed")
	await _screen.undo()
	await _frames(SETTLE)


## Rewiring, on the one ability in the whole reference set that has a cable.
##
## Nine locals across the six of them and two cables drawn, both here. The rest
## reach into their locals - `pick.target_data`, `paid.is_ok()`, `travel.finished`
## - and an argument that is not exactly the local's name is not a cable. That is
## the reader being right rather than lazy: what flows is a property of the
## local, not the local. It does mean the data half of the canvas is nearly
## empty on real code, which is worth knowing.
func _rewiring() -> void:
	var source: String = FileAccess.get_file_as_string(WITH_A_CABLE)
	var out: FileAccess = FileAccess.open(COPY, FileAccess.WRITE)
	out.store_string(source)
	out.close()
	await _screen.open(source, COPY)
	await _frames(SETTLE)

	var wired: ComposerNode = null
	var position: int = -1
	for node: ComposerNode in _screen.graph().nodes:
		for index: int in node.fields.size():
			if node.fields[index].source == ComposerNode.ValueSource.WIRED:
				wired = node
				position = index
	_check("a value fed by a cable is marked as one", wired != null,
		"%s" % [wired.title if wired != null else "none in this ability"])
	if wired == null:
		return

	_check("and it is not offered as free text", not wired.may_type(wired.fields[position]))
	_screen._on_value_edited(wired.id, position, "1.0")
	await _frames(SETTLE)

	var after: ComposerNode = _screen.graph().find_node(wired.id)
	_check("writing a value takes the cable off",
		after != null and after.fields[position].source == ComposerNode.ValueSource.LITERAL)
	await _screen.undo()
	await _frames(SETTLE)


func _leaving() -> void:
	var asked: Array[String] = []
	_screen.code_requested.connect(func _left(where: String) -> void: asked.append(where))
	_screen._on_code_pressed()
	await _frames(SETTLE)
	_check("the Code chip asks to be taken to the file", asked.size() == 1,
		asked[0] if not asked.is_empty() else "nothing")
	await _shot("15-final")


## Dragging a card to empty space is a visual position, not a reorder.
##
## The unit tests cover reading and writing the comment. What only a real canvas
## can show is the gesture reaching it: press, move, release over nothing, and a
## line appearing in the source that survives being read back.
func _free_placement() -> void:
	var before: String = _screen.printed()
	var order: PackedStringArray = _titles()
	_check(
		"nothing is positioned by hand until somebody does it",
		not before.contains(ComposerLayoutMetadata.PREFIX)
	)

	await _drag(_on_card(0), _nowhere())
	await _frames(SETTLE)
	var placed: String = _screen.printed()

	_check(
		"dragging a card into empty space writes its position into the source",
		placed.contains(ComposerLayoutMetadata.PREFIX)
	)
	_check("and moves nothing in the body", _titles() == order)
	_check(
		"one position line, not one per drag",
		placed.count(ComposerLayoutMetadata.PREFIX) == 1
	)
	await _shot("16-free-placement")

	var reopened: ComposerGraph = ComposerReader.read(placed, ABILITY)
	var carried: int = 0
	for node: ComposerNode in reopened.nodes:
		if node.has_layout_position:
			carried += 1
	_check("and reading the file back finds it again", carried == 1)

	await _screen.undo()
	await _frames(SETTLE)
	_check(
		"undo takes the position with it",
		not _screen.printed().contains(ComposerLayoutMetadata.PREFIX)
	)

	await _screen.redo()
	await _frames(SETTLE)
	_check(
		"and redo brings it back",
		_screen.printed().contains(ComposerLayoutMetadata.PREFIX)
	)
#endregion
