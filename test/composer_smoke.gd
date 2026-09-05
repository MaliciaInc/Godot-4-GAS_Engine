## The Composer 3.2 smoke, driven by the mouse rather than by its handlers.
##
## The phase document makes this run mandatory and expects a person to do it,
## because Godot's `GraphEdit` reads picking, dragging, sweeping, panning and
## zooming inside `_gui_input` and no script can call that. What a script *can*
## do is put an event into the viewport the way the operating system does - and
## once the two coordinate problems are out of the way (see `composer_input.gd`)
## Godot routes it exactly as it routes a real one. Every gesture below is a
## real press, a real travel and a real release; nothing here calls a handler.
##
## It runs in this game and not in the engine's own project on purpose. The
## Composer is worth something only if it opens abilities somebody wrote for a
## real game, so the first file it opens is this game's own - and the game's
## own theme, camera and autoloads are part of what is being tested.
##
## Nothing writes to the game's source. Editing happens on copies under
## `user://`, and the last check is that the game's file is what it was.
##
## @meta_license: MIT
extends Node

const Input_ = preload("res://test/composer_input.gd")
const Wires = preload("res://test/composer_smoke_wires.gd")

const ABILITY: String = "res://src/combat/abilities/battler_ability.gd"
const MADE: String = "res://src/combat/abilities/_smoke_new_ability.gd"
const COPY: String = "user://composer_smoke_copy.gd"
const SHOTS: String = "user://composer_smoke"

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE: int = 4

## The call the document names in cases 3 and 10.
const A_WAIT: StringName = &"wait_delay"
const A_WAIT_TITLE: String = "Wait Delay"
const A_WAIT_SECONDS: String = "1.5"
const A_WAIT_WRITTEN: String = "await wait_delay(1.5)"

var screen: ComposerScreen = null
var hand: RefCounted = null

var _passed: int = 0
var _report: Array[String] = []

## What the screen last refused to do, and why.
var _last_refusal: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	get_window().size = WINDOW
	await _frames(SETTLE)

	# A layer of its own, because this game keeps a Camera2D and its canvas
	# transform moves anything outside a layer - drawn in one place, clicked in
	# another, and neither where the code thinks it is.
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	screen = ComposerScreen.new()
	screen.size = get_viewport().get_visible_rect().size
	layer.add_child(screen)
	hand = Input_.new(get_viewport(), get_tree())
	# A gesture that changes nothing is worth nothing to look at unless the
	# reason is beside it, and the screen already says the reason out loud.
	screen._routes.refused.connect(
		func _said(message: String) -> void: _last_refusal = message
	)
	await _frames(SETTLE)

	await _run()

	print("\n===== COMPOSER 3.2 SMOKE =====")
	for line: String in _report:
		print(line)
	print("%d checks, %d passed, %d to look at" % [
		_report.size(), _passed, _report.size() - _passed
	])
	print("shots: %s" % ProjectSettings.globalize_path(SHOTS))
	print("SMOKE_RESULT: %s passed=%d failed=%d" % [
		"PASS" if _passed == _report.size() else "FAIL",
		_passed, _report.size() - _passed
	])
	get_tree().quit(0)


func _run() -> void:
	var original: String = FileAccess.get_file_as_string(ABILITY)

	await case_1_startup()
	await case_2_new_ability()
	await case_3_wait_delay()
	await Wires.new(self).run()
	await case_10_right_click_blank()
	await case_11_multi_selection()
	await case_12_clipboard()
	await case_13_reload()

	check(
		"13 · the game's own file was never written to",
		FileAccess.get_file_as_string(ABILITY) == original
	)
	if FileAccess.file_exists(MADE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MADE))
	check(
		"13 · and the ability this run made is cleared away",
		not FileAccess.file_exists(MADE)
	)


#region Saying what happened
func check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	var said: String = detail
	if not held and not _last_refusal.is_empty():
		said = ("%s   refused: %s" % [detail, _last_refusal]).strip_edges()
	_report.append("%s %-62s %s" % ["  ok " if held else "FAIL", what, said])


## Forget what was refused, so the next check reports its own reason and not
## the one before it.
func clear_refusal() -> void:
	_last_refusal = ""


func _frames(count: int) -> void:
	for _step: int in count:
		await get_tree().process_frame


func shot(label: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [SHOTS, label])
#endregion


#region Reaching the graph
func canvas() -> ComposerCanvas:
	return screen.canvas()


## The nodes drawn as cards, in the order the graph holds them.
func drawn() -> Array[ComposerNode]:
	return screen.graph().visible_nodes()


## The statements, without the two the flow draws for Entry and End.
func statements() -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in drawn():
		if node.source_backed:
			found.append(node)
	return found


## A card, looked up now rather than remembered. Every edit repaints, and a
## card held across one is a freed object.
func card(node_id: StringName) -> ComposerCard:
	return canvas().card_for(node_id)


## The strip a person grabs a card by. Its middle is over whatever editor the
## card happens to hold, and clicking into a text box is not picking a card.
func grip(node_id: StringName) -> Vector2:
	var here: ComposerCard = card(node_id)
	if here == null:
		return Vector2.ZERO
	return hand.on(here.get_titlebar_hbox())


func node_titled(title: String) -> ComposerNode:
	for node: ComposerNode in drawn():
		if node.title.begins_with(title):
			return node
	return null


## Somewhere on the canvas no card is.
func empty_point() -> Vector2:
	var lowest: Vector2 = canvas().get_global_rect().position + Vector2(60.0, 60.0)
	for node: ComposerNode in drawn():
		var here: ComposerCard = card(node.id)
		if here != null:
			lowest = lowest.max(here.get_global_rect().end)
	return hand.at(lowest + Vector2(80.0, 60.0))


## A copy of an ability, opened for editing.
##
## The `class_name` line comes off on the way. A copy that kept it would declare
## a global class the original already holds, and Godot refuses the second one -
## which has nothing to do with the Composer and would fail every check that
## asks whether what was written still compiles. The body, which is the part
## being edited, is untouched.
func open_copy(from: String, into: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(from).split("
"):
		if not line.begins_with("class_name "):
			kept.append(line)
	var source: String = "
".join(kept)
	var out: FileAccess = FileAccess.open(into, FileAccess.WRITE)
	out.store_string(source)
	out.close()
	await screen.open(source, into)
	await _frames(SETTLE)
	return source
#endregion


#region Case 1 · Startup
## The Composer stands up in a real window and draws this game's own ability.
##
## The warning the document forbids - a Control with non-equal opposite anchors
## having its size overridden - is not visible from inside the process, so the
## runner greps this run's output for it. What is visible from here is the
## other half: the screen is laid out, sized, and everything it holds is inside
## it rather than spilling out of a container that was never told a size.
func case_1_startup() -> void:
	check("1 · the Composer stands up", screen.canvas() != null)
	check(
		"1 · and is laid out at the size it was given",
		screen.size == get_viewport().get_visible_rect().size, "%s" % screen.size
	)
	check(
		"1 · with a canvas inside it, not spilling out",
		screen.get_global_rect().encloses(canvas().get_global_rect()),
		"%s in %s" % [canvas().get_global_rect(), screen.get_global_rect()]
	)

	await screen.open(FileAccess.get_file_as_string(ABILITY), ABILITY)
	await _frames(SETTLE)
	check(
		"1 · this game's own ability opens", screen.graph().is_editable(),
		screen.graph().blocked_reason()
	)
	check("1 · with nothing to complain about", screen.graph().diagnostics.is_empty())
	await shot("01-startup")
#endregion


#region Case 2 · New Ability
## A new ability is Entry to End, End takes nothing further, and moving either
## of them moves them - it does not resize them, unhook a cable, or change what
## the ability does.
func case_2_new_ability() -> void:
	if FileAccess.file_exists(MADE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MADE))
	var refusal: String = ComposerAbilityTemplate.create(MADE)
	check("2 · New Ability writes a file", refusal.is_empty(), refusal)
	await screen.open(FileAccess.get_file_as_string(MADE), MADE)
	await _frames(SETTLE)

	var entry: ComposerNode = node_titled("Entry")
	var end: ComposerNode = node_titled("End")
	check("2 · a new ability is drawn as Entry and End", entry != null and end != null)
	if entry == null or end == null:
		return
	check(
		"2 · with one cable between them", screen.graph().connections.size() == 1,
		"%d wires" % screen.graph().connections.size()
	)
	var outputs: int = 0
	for port: ComposerNode.Port in end.ports:
		if port.is_execution() and port.direction == ComposerNode.PortDirection.OUTPUT:
			outputs += 1
	check("2 · and End takes nothing further", outputs == 0, "%d exec outputs" % outputs)
	await shot("02-new-ability")

	var before_size: Vector2 = card(entry.id).size
	var before_wires: int = screen.graph().connections.size()
	var before_body: String = ComposerLayoutMetadata.without_layout_text(screen.printed())

	await hand.drag(grip(entry.id), grip(entry.id) + Vector2(140.0, 180.0))
	await _frames(SETTLE)

	var moved: ComposerCard = card(entry.id)
	check("2 · dragging Entry moves it", moved != null and moved.position_offset != Vector2.ZERO,
		"%s" % [moved.position_offset if moved != null else "gone"])
	check("2 · without deforming the card", moved != null and moved.size == before_size,
		"%s -> %s" % [before_size, moved.size if moved != null else "gone"])
	check("2 · with its cable still on it",
		screen.graph().connections.size() == before_wires,
		"%d wires" % screen.graph().connections.size())
	check("2 · and the body untouched",
		ComposerLayoutMetadata.without_layout_text(screen.printed()) == before_body)
	await shot("03-entry-moved")

	var where: Vector2 = moved.position_offset
	await screen.save()
	await screen.open(FileAccess.get_file_as_string(MADE), MADE)
	await _frames(SETTLE)
	var reopened: ComposerCard = card(node_titled("Entry").id)
	check(
		"2 · closing and opening puts it back where it was",
		reopened != null and reopened.position_offset.is_equal_approx(where),
		"%s -> %s" % [where, reopened.position_offset if reopened != null else "gone"]
	)
#endregion


#region Case 3 · Wait Delay
## Made from the palette, with a real click on a real row; then its one value
## typed into the card, and read back out of the file as GDScript.
func case_3_wait_delay() -> void:
	var row: Button = _palette_row(A_WAIT_TITLE)
	check("3 · the palette offers Wait Delay", row != null)
	if row == null:
		return

	var before: int = statements().size()
	await hand.click(hand.on(row))
	await _frames(SETTLE)
	var made: ComposerNode = node_titled(A_WAIT_TITLE)
	check("3 · clicking it writes the statement", statements().size() == before + 1,
		"%d -> %d" % [before, statements().size()])
	check("3 · and the card is drawn", made != null and card(made.id) != null)
	if made == null:
		return
	check("3 · between Entry and End",
		_reaches(ComposerFlow.ENTRY_ID, made.id) and _reaches(made.id, node_titled("End").id),
		"fed by %s, feeding %s; wires: %s; body: %s" % [
			_feeding(made.id), _fed_by(made.id), _wiring(),
			screen.printed().replace("
", " / ")
		])
	check("3 · showing the seconds it waits", made.fields.size() == 1,
		"%d fields" % made.fields.size())
	await shot("04-wait-delay")

	screen._on_value_edited(made.id, 0, A_WAIT_SECONDS)
	await _frames(SETTLE)
	check("3 · a typed value reaches the file as GDScript",
		screen.printed().contains(A_WAIT_WRITTEN), A_WAIT_WRITTEN)
	check("3 · and the file still reads back", screen.graph().is_editable(),
		screen.graph().blocked_reason())
	await shot("05-wait-delay-edited")


func _palette_row(named: String) -> Button:
	return _button_titled(screen, named)


func _button_titled(under: Node, named: String) -> Button:
	for child: Node in under.get_children():
		var button: Button = child as Button
		if button != null and button.text == named and button.is_visible_in_tree():
			return button
		var found: Button = _button_titled(child, named)
		if found != null:
			return found
	return null


## Every cable, by the titles at its ends.
func _wiring() -> String:
	var said: PackedStringArray = PackedStringArray()
	for wire: ComposerGraph.Connection in screen.graph().connections:
		said.append("%s->%s" % [
			_title_of(StringName(wire.from_node)), _title_of(StringName(wire.to_node))
		])
	return ", ".join(said)


## What runs into this node, and what it runs into, by title rather than by an
## id nobody reading a report would recognise.
func _feeding(node_id: StringName) -> String:
	for wire: ComposerGraph.Connection in screen.graph().connections:
		if StringName(wire.to_node) == node_id:
			return _title_of(StringName(wire.from_node))
	return "nothing"


func _fed_by(node_id: StringName) -> String:
	for wire: ComposerGraph.Connection in screen.graph().connections:
		if StringName(wire.from_node) == node_id:
			return _title_of(StringName(wire.to_node))
	return "nothing"


func _title_of(node_id: StringName) -> String:
	var node: ComposerNode = screen.graph().find_node(node_id)
	return node.title if node != null else String(node_id)


## Whether execution runs from one node to another, directly.
func _reaches(from: StringName, to: StringName) -> bool:
	for wire: ComposerGraph.Connection in screen.graph().connections:
		if StringName(wire.from_node) == from and StringName(wire.to_node) == to:
			return true
	return false
#endregion


#region Case 10 · Right click on nothing
func case_10_right_click_blank() -> void:
	await open_copy(ABILITY, COPY)
	var before: int = statements().size()
	var where: Vector2 = empty_point()

	await hand.click(where, MOUSE_BUTTON_RIGHT)
	await _frames(SETTLE)
	var menu: ComposerActionMenu = _action_menu()
	check("10 · right-clicking nothing offers what can be made",
		menu != null and menu.visible)
	await shot("06-graph-menu")
	if menu == null or not menu.visible:
		return

	await hand.write(A_WAIT_TITLE.to_lower())
	await _frames(SETTLE)
	await hand.key(KEY_ENTER)
	await _frames(SETTLE)

	var made: ComposerNode = node_titled(A_WAIT_TITLE)
	check("10 · choosing one writes the statement", statements().size() == before + 1,
		"%d -> %d" % [before, statements().size()])
	check("10 · and the card is where it was asked for",
		made != null and made.has_layout_position, "%s" % [made != null])
	await shot("07-made-from-menu")


func _action_menu() -> ComposerActionMenu:
	for child: Node in screen._menus.get_children():
		var menu: ComposerActionMenu = child as ComposerActionMenu
		if menu != null:
			return menu
	return null
#endregion


#region Case 11 · Two cards, one gesture
func case_11_multi_selection() -> void:
	await open_copy(ABILITY, COPY)
	var first: ComposerNode = statements()[0]
	var second: ComposerNode = statements()[1]

	await hand.click(grip(first.id))
	await hand.click(grip(second.id), MOUSE_BUTTON_LEFT, Input_.CTRL)
	check("11 · Ctrl picks a second card as well", canvas().picked().size() == 2,
		"%d picked" % canvas().picked().size())
	await shot("08-two-picked")

	var steps: int = screen.history().depth()
	var order: String = ComposerLayoutMetadata.without_layout_text(screen.printed())
	var from: Vector2 = grip(statements()[0].id)
	await hand.drag(from, from + Vector2(60.0, 140.0))
	await _frames(SETTLE)

	check("11 · dragging one moves both", _placed_lines() == 2,
		"%d positions written" % _placed_lines())
	check("11 · as one thing to take back", screen.history().depth() == steps + 1,
		"%d -> %d" % [steps, screen.history().depth()])
	check("11 · and the body is untouched",
		ComposerLayoutMetadata.without_layout_text(screen.printed()) == order)

	await screen.undo()
	await _frames(SETTLE)
	check("11 · one undo puts both back", _placed_lines() == 0)
	await shot("09-both-moved-back")


func _placed_lines() -> int:
	return screen.printed().count(ComposerLayoutMetadata.PREFIX)
#endregion


#region Case 12 · Cut, copy, paste, duplicate, delete
## Every one of them through the widget's own shortcut, and after every one the
## same question: does the graph still say what the file says?
func case_12_clipboard() -> void:
	await open_copy(ABILITY, COPY)
	var before: int = statements().size()

	await _pick_first()
	await hand.key(KEY_D, Input_.CTRL)
	check("12 · Ctrl+D repeats a statement", statements().size() == before + 1,
		"%d -> %d" % [before, statements().size()])
	_check_agreement("12 · after duplicate")

	await _pick_first()
	await hand.key(KEY_DELETE)
	check("12 · Delete takes one out", statements().size() == before,
		"%d nodes" % statements().size())
	_check_agreement("12 · after delete")

	await _pick_first()
	await hand.key(KEY_X, Input_.CTRL)
	check("12 · Ctrl+X cuts one out", statements().size() == before - 1,
		"%d nodes" % statements().size())
	_check_agreement("12 · after cut")

	await hand.key(KEY_V, Input_.CTRL)
	check("12 · Ctrl+V puts it back", statements().size() == before,
		"%d nodes" % statements().size())
	_check_agreement("12 · after paste")

	await _pick_first()
	await hand.key(KEY_C, Input_.CTRL)
	await hand.key(KEY_V, Input_.CTRL)
	check("12 · Ctrl+C then Ctrl+V adds one", statements().size() == before + 1,
		"%d nodes" % statements().size())
	_check_agreement("12 · after copy and paste")
	await shot("10-clipboard")


func _pick_first() -> void:
	await hand.click(grip(statements()[0].id))


## The graph and the file agree: what is drawn is what reading the file gives.
func _check_agreement(named: String) -> void:
	var read: ComposerGraph = ComposerReader.read(screen.printed(), COPY)
	check(
		named + ": the graph is what the file says",
		read.visible_nodes().size() == drawn().size()
		and read.connections.size() == screen.graph().connections.size(),
		"file %d/%d, drawn %d/%d" % [
			read.visible_nodes().size(), read.connections.size(),
			drawn().size(), screen.graph().connections.size()
		]
	)
#endregion


#region Case 13 · Opening it all again
## Standing the screen up a second time, the way disabling and enabling the
## plugin does: the same file draws the same graph, nothing is left behind, and
## no handler ends up connected twice.
func case_13_reload() -> void:
	var before: String = ComposerWriter.signature(
		ComposerReader.read(FileAccess.get_file_as_string(ABILITY), ABILITY)
	)
	var orphans_before: int = _live_nodes()

	screen.get_parent().remove_child(screen)
	screen.queue_free()
	await _frames(SETTLE * 2)

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	screen = ComposerScreen.new()
	screen.size = get_viewport().get_visible_rect().size
	layer.add_child(screen)
	await _frames(SETTLE)
	await screen.open(FileAccess.get_file_as_string(ABILITY), ABILITY)
	await _frames(SETTLE)

	check(
		"13 · the same file draws the same graph",
		ComposerWriter.signature(screen.graph()) == before
	)
	check("13 · with nothing to complain about", screen.graph().diagnostics.is_empty())
	check(
		"13 · and no handler ended up connected twice",
		_doubly_connected().is_empty(), ", ".join(_doubly_connected())
	)
	check(
		"13 · nothing was left standing behind it",
		_live_nodes() <= orphans_before + _expected_growth(),
		"%d -> %d" % [orphans_before, _live_nodes()]
	)
	await shot("11-reloaded")


func _live_nodes() -> int:
	return get_tree().root.get_child_count(true)


## One CanvasLayer more than there was: the second screen's.
func _expected_growth() -> int:
	return 1


## Any signal on the canvas whose handlers are not all distinct.
func _doubly_connected() -> PackedStringArray:
	var doubled: PackedStringArray = PackedStringArray()
	for described: Dictionary in canvas().get_signal_list():
		var named: String = described["name"]
		var seen: Dictionary[String, int] = {}
		for link: Dictionary in canvas().get_signal_connection_list(named):
			var to: Callable = link["callable"]
			var key: String = "%d.%s" % [to.get_object_id(), to.get_method()]
			seen[key] = seen.get(key, 0) + 1
			if seen[key] > 1:
				doubled.append("%s -> %s" % [named, to.get_method()])
	return doubled
#endregion
