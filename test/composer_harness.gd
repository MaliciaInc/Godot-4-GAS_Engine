## Every function of the Ability Composer, in a real window with a real renderer.
##
## It runs in this game rather than in the engine's own project on purpose: the
## Composer is only worth anything if it opens abilities somebody wrote for a
## real game, so the first file it opens here is this game's own.
##
## **What this proves and what it does not.** Composer 3.2 put the graph on
## Godot's own `GraphEdit`, and that moved half of what this harness used to do
## out of reach. Hit-testing a card, dragging one, sweeping a box over several,
## panning and zooming are the widget's now, and it reads them inside
## `_gui_input` - a method a script cannot call, at a layer synthesised events
## never arrive at, with either `Viewport.push_input` or `Input.parse_input_event`,
## focused window or not. Proving those needs a hand on a mouse, which is what
## the manual smoke is for.
##
## What is still this harness's is everything the Composer itself decides: what
## a card is built out of, what the widget's reports do to the file, what a
## chord does, what a typed value does, what clearing a pin does - and the claim
## the whole phase turns on, that a card put down somewhere else changes where
## it is drawn and never what the ability does. All of it against a real
## renderer, at a real size, with every card measured by the font that draws it.
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

## Somewhere in the graph no card was laid out, so a placement is a placement.
const AWAY: Vector2 = Vector2(2400.0, 1600.0)
const ALONGSIDE: Vector2 = Vector2(320.0, 0.0)

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


#region Reaching the graph
func _canvas() -> ComposerCanvas:
	return _screen.canvas()


## The nodes actually drawn as cards, in the order the graph holds them.
func _drawn() -> Array[ComposerNode]:
	return _screen.graph().visible_nodes()


func _card(index: int) -> ComposerCard:
	var drawn: Array[ComposerNode] = _drawn()
	if index < 0 or index >= drawn.size():
		return null
	return _canvas().card_for(drawn[index].id)


func _cards() -> Array[ComposerCard]:
	var found: Array[ComposerCard] = []
	for child: Node in _canvas().get_children():
		var card: ComposerCard = child as ComposerCard
		if card != null:
			found.append(card)
	return found


## Pick cards the way the widget reports it. Clicking one is GraphEdit's own,
## and only a hand on a mouse reaches that; what the Composer sees either way is
## a node marked selected and a canvas passing on what is.
func _pick(indices: Array[int]) -> void:
	for card: ComposerCard in _cards():
		card.selected = false
	for index: int in indices:
		var card: ComposerCard = _card(index)
		if card != null:
			card.selected = true
	_canvas().selection_changed.emit(_canvas().picked())
	await _frames(1)


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
	for node: ComposerNode in _drawn():
		found.append(node.title)
	return found


## The statements, without the two the flow draws for Entry and End.
##
## Those two stand for no line of the file - which is what `source_backed` says
## - so they carry their position under a marker of their own, and a card that
## came from no line is not what "moving a card never reorders the body" is
## about.
func _statements() -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in _drawn():
		if node.source_backed:
			found.append(node)
	return found


func _placed_lines() -> int:
	return _screen.printed().count(ComposerLayoutMetadata.PREFIX)


func _virtual_lines() -> int:
	return _screen.printed().count(ComposerLayoutMetadata.VIRTUAL_PREFIX)
#endregion


#region The run
func _run() -> void:
	var original: String = FileAccess.get_file_as_string(ABILITY)

	await _this_games_ability(original)
	await _the_cards()
	await _zooming()
	await _picking()
	await _placement()
	await _placing_several()
	await _placing_what_stands_for_nothing()
	await _the_menu()
	await _editing()
	await _commands()
	await _finding()
	await _rewiring()
	await _breaking()
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
	_check("draws its statements", _drawn().size() > 1, "%d drawn" % _drawn().size())
	_check("and the cables between them",
		graph.connections.size() >= _drawn().size() - 1,
		"%d wires for %d nodes" % [graph.connections.size(), _drawn().size()])
	_check("with nothing to complain about", graph.diagnostics.is_empty(),
		"%d notes" % graph.diagnostics.size())
	_check("prints it back byte for byte",
		ComposerWriter.apply(graph, original).text == original)


## What a card is made of, measured by the renderer that draws it.
func _the_cards() -> void:
	var cards: Array[ComposerCard] = _cards()
	_check("one card per drawn node", cards.size() == _drawn().size(),
		"%d cards, %d nodes" % [cards.size(), _drawn().size()])

	var measured: int = 0
	var on_the_widget: int = 0
	var ported: int = 0
	for card: ComposerCard in cards:
		measured += 1 if card.size.y > ComposerTheme.PAD_Y * 2.0 else 0
		on_the_widget += 1 if card is GraphNode else 0
		ported += 1 if card.get_input_port_count() + card.get_output_port_count() > 0 else 0
	_check("every card measured itself against real type", measured == cards.size(),
		"%d of %d have height" % [measured, cards.size()])
	_check("every card is a node on the widget", on_the_widget == cards.size(),
		"%d of %d" % [on_the_widget, cards.size()])
	_check("and carries pins the widget can connect", ported == cards.size(),
		"%d of %d have ports" % [ported, cards.size()])

	# This game's theme says GraphNode titles are 96. The editor's says something
	# quiet, so a card that took the host's word for it looked right there and
	# nowhere else - which is the whole reason to draw one here.
	var titled: int = 0
	for card: ComposerCard in cards:
		titled += 1 if card.get_theme_font_size(
			GASEditorTheme.TITLE_FONT_SIZE
		) == ComposerTheme.FONT_TITLE else 0
	_check("and draws its title at the Composer's size, not this game's",
		titled == cards.size(), "%d of %d" % [titled, cards.size()])


## Zoom is the widget's. What the Composer decides is how much of a card is
## worth drawing at each end of it.
func _zooming() -> void:
	var canvas: ComposerCanvas = _canvas()

	canvas.zoom = ComposerCanvas.ZOOM_MIN * 0.1
	await _frames(SETTLE)
	_check("pulled past the floor, the widget stops at it",
		is_equal_approx(canvas.zoom, ComposerCanvas.ZOOM_MIN), "%.2f" % canvas.zoom)
	_check("and a card that far back is drawn as a block",
		ComposerCanvas.detail_at(canvas.zoom) == ComposerCard.Detail.BLOCK)
	await _shot("02-pulled-right-back")

	canvas.zoom = ComposerCanvas.ZOOM_MAX * 10.0
	await _frames(SETTLE)
	_check("pushed past the ceiling, it stops there",
		is_equal_approx(canvas.zoom, ComposerCanvas.ZOOM_MAX), "%.2f" % canvas.zoom)

	canvas.zoom = 1.0
	await _frames(SETTLE)
	_check("and back where it started a card shows its values",
		ComposerCanvas.detail_at(canvas.zoom) == ComposerCard.Detail.FULL)
	await _shot("03-back-to-one")


## Selection is the widget's too, and the canvas passes on what it says.
func _picking() -> void:
	await _pick([0])
	_check("one card selected is one card picked", _canvas().picked().size() == 1,
		"%d picked" % _canvas().picked().size())
	await _shot("04-one-picked")

	await _pick([0, 1])
	_check("two selected are two picked", _canvas().picked().size() == 2,
		"%d picked" % _canvas().picked().size())
	await _shot("05-two-picked")

	await _pick([])
	_check("and letting go picks nothing", _canvas().picked().is_empty())


## The claim the whole phase turns on: a card put down somewhere else is drawn
## somewhere else, and the ability does exactly what it did.
func _placement() -> void:
	var order: PackedStringArray = _titles()
	_check(
		"nothing is positioned by hand until somebody does it", _placed_lines() == 0
	)

	var moved: Dictionary[StringName, Vector2] = {}
	moved[_statements()[0].id] = AWAY
	_canvas().nodes_positioned.emit(moved)
	await _frames(SETTLE)

	_check("a card put down writes its position into the source", _placed_lines() == 1,
		"%d lines" % _placed_lines())
	_check("and moves nothing in the body", _titles() == order,
		"%s -> %s" % [order[0], _titles()[0]])
	await _shot("06-placed")

	var reopened: ComposerGraph = ComposerReader.read(_screen.printed(), ABILITY)
	var carried: int = 0
	for node: ComposerNode in reopened.nodes:
		if node.has_layout_position:
			carried += 1
	_check("and reading the file back finds it again", carried == 1, "%d carried" % carried)

	await _screen.undo()
	await _frames(SETTLE)
	_check("undo takes the position with it", _placed_lines() == 0)

	await _screen.redo()
	await _frames(SETTLE)
	_check("and redo brings it back", _placed_lines() == 1)

	await _screen.undo()
	await _frames(SETTLE)


## Several cards moved together is one thing somebody did, and one thing to
## take back. A step per card would be three more presses than the gesture.
func _placing_several() -> void:
	var order: PackedStringArray = _titles()
	var steps: int = _screen.history().depth()
	var both: Dictionary[StringName, Vector2] = {}
	both[_statements()[0].id] = AWAY
	both[_statements()[1].id] = AWAY + ALONGSIDE

	_canvas().nodes_positioned.emit(both)
	await _frames(SETTLE)

	_check("two cards put down write both positions", _placed_lines() == 2,
		"%d lines" % _placed_lines())
	_check("as one step to take back", _screen.history().depth() == steps + 1,
		"%d -> %d" % [steps, _screen.history().depth()])
	_check("and still nothing moved in the body", _titles() == order)

	await _screen.undo()
	await _frames(SETTLE)
	_check("one undo puts both back", _placed_lines() == 0)


## Entry and End stand for no line of the file, so where they sit is written
## with a marker of its own. Placing one must still be a placement.
func _placing_what_stands_for_nothing() -> void:
	var order: PackedStringArray = _titles()
	_check("nothing virtual is positioned by hand either", _virtual_lines() == 0)

	var moved: Dictionary[StringName, Vector2] = {}
	moved[_drawn()[0].id] = AWAY
	_canvas().nodes_positioned.emit(moved)
	await _frames(SETTLE)

	_check("Entry put down is written under its own marker", _virtual_lines() == 1,
		"%d virtual lines" % _virtual_lines())
	_check("and not mistaken for a statement's position", _placed_lines() == 0)
	_check("with the body still in the order it was", _titles() == order)

	var reopened: ComposerGraph = ComposerReader.read(_screen.printed(), ABILITY)
	_check("and it comes back where it was put",
		reopened.find_node(_drawn()[0].id) != null
		and reopened.find_node(_drawn()[0].id).has_layout_position)

	await _screen.undo()
	await _frames(SETTLE)
	_check("undo takes that one with it too", _virtual_lines() == 0)


func _the_menu() -> void:
	_screen._menus.open_for_card(_statements()[0].id, Vector2(400.0, 400.0))
	await _frames(SETTLE)
	_check("a card offers what can be done to it", _menu_is_open())
	await _shot("07-card-menu")

	_hide_menus()
	await _frames(SETTLE)
	_check("and the menu gets out of the way", not _menu_is_open())


func _menu_is_open() -> bool:
	for child: Node in _screen._menus.get_children():
		var menu: PopupMenu = child as PopupMenu
		if menu != null and menu.visible:
			return true
	return false


func _hide_menus() -> void:
	for child: Node in _screen._menus.get_children():
		var menu: PopupMenu = child as PopupMenu
		if menu != null:
			menu.hide()


## A copy, so nothing here can reach the game's own file.
func _editing() -> void:
	var source: String = FileAccess.get_file_as_string(WITH_ARGUMENTS)
	var out: FileAccess = FileAccess.open(COPY, FileAccess.WRITE)
	out.store_string(source)
	out.close()

	await _screen.open(source, COPY)
	await _frames(SETTLE)

	var node: ComposerNode = null
	for drawn: ComposerNode in _drawn():
		if not drawn.fields.is_empty():
			node = drawn
			break
	_check("an ability with arguments shows them", node != null,
		"%s" % [node.title if node != null else "none has any"])
	if node == null:
		return

	await _pick([_drawn().find(node)])
	await _shot("08-inspector")

	var typed: String = "harness_value"
	_screen._on_value_edited(node.id, 0, typed)
	await _frames(SETTLE)
	_check("a typed value reaches the file", _screen.printed().contains(typed))
	await _shot("09-edited")

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


## The widget's own shortcuts arrive as requests, and what each one does to the
## file is the screen's. That is why a key and a menu entry cannot come to mean
## two different things - there is one handler under both.
func _commands() -> void:
	var before: int = _drawn().size()

	await _pick([1])
	_canvas().duplicate_requested.emit()
	await _frames(SETTLE)
	_check("duplicate repeats a statement", _drawn().size() == before + 1,
		"%d -> %d" % [before, _drawn().size()])

	await _pick([1])
	_canvas().delete_requested.emit()
	await _frames(SETTLE)
	_check("delete takes one out", _drawn().size() == before,
		"%d nodes" % _drawn().size())

	await _pick([1])
	var copied: String = _screen.copy_picked()
	_check("copying takes the statement as text", not copied.strip_edges().is_empty(),
		copied.strip_edges())

	var took: bool = await _screen.paste_text(copied)
	await _frames(SETTLE)
	_check("and pasting puts it back in",
		took and _drawn().size() == before + 1,
		"%d nodes" % _drawn().size())
	await _screen.undo()
	await _frames(SETTLE)
	await _shot("10-after-commands")


func _finding() -> void:
	await _chord(KEY_SPACE)
	var finder: ComposerFinder = _screen._finder
	_check("Space opens the finder", finder != null and finder.visible)
	await _shot("11-finder")
	if finder == null or not finder.visible:
		return

	finder._on_typed("commit")
	await _frames(SETTLE)
	_check("typing narrows it down", not finder.here().is_empty(),
		ComposerCatalog.find(finder.here()).title if not finder.here().is_empty() else "")
	await _shot("12-finder-typed")

	var before: int = _drawn().size()
	finder._take()
	await _frames(SETTLE)
	_check("choosing one writes a statement", _drawn().size() == before + 1,
		"%d -> %d" % [before, _drawn().size()])
	_check("and the finder gets out of the way", not finder.visible)
	await _shot("13-node-placed")
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
	for node: ComposerNode in _drawn():
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


## Clearing a pin. The gesture that asks for it - Alt over a pin - is read by
## the canvas and needs a mouse; what it asks for is this, and what that does to
## the file is what a detached graph rests on.
func _breaking() -> void:
	var original: String = FileAccess.get_file_as_string(ABILITY)
	await _screen.open(original, ABILITY)
	await _frames(SETTLE)

	var wires: int = _screen.graph().connections.size()
	var node: ComposerNode = _statements()[0]
	var port: StringName = &""
	for offered: ComposerNode.Port in node.ports:
		if offered.is_execution() and offered.direction == ComposerNode.PortDirection.OUTPUT:
			port = offered.id
			break
	_check("a statement has an execution pin to clear", port != &"", String(port))
	if port == &"":
		return

	_canvas().break_all_requested.emit(node.id, port)
	await _frames(SETTLE)
	_check("clearing a pin takes its cables with it",
		_screen.graph().connections.size() < wires,
		"%d -> %d wires" % [wires, _screen.graph().connections.size()])
	_check("and what it left behind is still a file the Composer can read",
		_screen.graph().is_editable(), _screen.graph().blocked_reason())
	await _shot("14-broken")

	await _screen.undo()
	await _frames(SETTLE)
	_check("undo puts the cables back",
		_screen.graph().connections.size() == wires,
		"%d wires" % _screen.graph().connections.size())


func _leaving() -> void:
	var asked: Array[String] = []
	_screen.code_requested.connect(func _left(where: String) -> void: asked.append(where))
	_screen._on_code_pressed()
	await _frames(SETTLE)
	_check("the Code chip asks to be taken to the file", asked.size() == 1,
		asked[0] if not asked.is_empty() else "nothing")
	await _shot("15-final")
#endregion
