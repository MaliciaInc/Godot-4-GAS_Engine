## The runtime debug overlay, instantiated inside this game.
##
## The overlay is the one piece of the addon a game puts in its own tree and
## draws over its own art, in its own theme. The Composer met this game's theme
## once and came out unusable (GAS-008), so the question is not academic: does
## the overlay show what the engine knows about a battler of this game, keep
## showing it while the game is paused, and survive the battler it is watching
## being freed?
##
## Headless: every answer here is a number or a row of text. Sizes are the
## theme's own, read off the controls, not measured from pixels.
##
## @meta_license: MIT
extends Node

const BEAR_ATTRIBUTES: String = "res://combat/battlers/bear/bear_attributes.tres"
const FOCUS: String = "res://combat/battlers/bear/focus_attack.tscn"
const PUNCH: String = "res://combat/battlers/bear/player_melee_action.tscn"
const COOLDOWN: String = "Cooldown.Punch"

## What Godot draws a Label at when nobody's theme says otherwise.
const ENGINE_FONT_SIZE: int = 16

const CASES: Array[String] = ["watch", "pages", "attributes", "effects", "cooldown", "paused", "theme", "freed"]

var _passed: int = 0
var _report: Array[String] = []
var _finished: Array[String] = []

var _overlay: GasDebugOverlay = null
var _baloo: Battler = null
var _dummy: Battler = null


func _ready() -> void:
	_baloo = _battler("Baloo", [FOCUS, PUNCH], 0.0)
	_dummy = _battler("Dummy", [], 600.0)
	_overlay = (load(GasDebugOverlay.SCENE) as PackedScene).instantiate() as GasDebugOverlay
	add_child(_overlay)
	await get_tree().process_frame

	await _case_watch()
	_case_pages()
	await _case_attributes()
	await _case_effects()
	await _case_cooldown()
	await _case_paused()
	_case_theme()
	await _case_freed()

	var missing: Array[String] = []
	for name: String in CASES:
		if not _finished.has(name):
			missing.append(name)
	_check("every case ran to its last line", missing.is_empty(), "stopped part way: %s" % ", ".join(missing))

	print("\n===== GAS DEBUG OVERLAY in THIS GAME =====")
	for line: String in _report:
		print(line)
	var failed: int = _report.size() - _passed
	print("%d checks, %d passed, %d to look at" % [_report.size(), _passed, failed])
	print("GAS_OVERLAY_RESULT: %s passed=%d failed=%d" % ["PASS" if failed == 0 else "FAIL", _passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-62s %s" % ["  ok " if held else "FAIL", what, detail])


func _finish(case_name: String) -> void:
	_finished.append(case_name)
#endregion


#region Reading the overlay
func _heading() -> Label:
	return _overlay.get_node("Panel/Body/Heading") as Label


func _table() -> Tree:
	return _overlay.get_node("Panel/Body/Table") as Tree


## Every row the page on screen would draw now, as its whole line.
func _page_lines(index: int) -> Array[String]:
	var lines: Array[String] = []
	for row: GasDebugPage.Row in _overlay.pages()[index].rows(_overlay.snapshot()):
		lines.append(row.said())
	return lines


## Every row the table actually holds, as the text of its cells.
func _drawn_lines() -> Array[String]:
	var lines: Array[String] = []
	var root: TreeItem = _table().get_root()
	if root == null:
		return lines
	for item: TreeItem in root.get_children():
		var cells: PackedStringArray = PackedStringArray()
		for column: int in _table().columns:
			cells.append(item.get_text(column))
		lines.append(" | ".join(cells))
	return lines


func _any_contains(lines: Array[String], wanted: String) -> bool:
	for line: String in lines:
		if line.contains(wanted):
			return true
	return false


## Long enough for one scheduled refresh to have happened.
func _one_refresh() -> void:
	var deadline: int = Time.get_ticks_msec() + int(_overlay.seconds_between_refreshes * 1000.0 * 3.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
#endregion


#region The game's side
func _battler(named: String, scenes: Array[String], x: float) -> Battler:
	var battler: Battler = Battler.new()
	battler.name = named
	battler.attributes = load(BEAR_ATTRIBUTES) as BattlerAttributes
	var loaded: Array[PackedScene] = []
	for path: String in scenes:
		loaded.append(load(path) as PackedScene)
	battler.ability_scenes = loaded
	battler.position = Vector2(x, 0.0)
	add_child(battler)
	return battler


func _act(caster: Battler, index: int, targets: Array[Battler]) -> void:
	var turns: Array[int] = [0]
	var counter: Callable = func _turned() -> void: turns[0] += 1
	caster.turn_finished.connect(counter)
	Engine.time_scale = 10.0
	caster.act(caster.granted[index], targets)
	var deadline: int = Time.get_ticks_msec() + 8000
	while turns[0] == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	caster.turn_finished.disconnect(counter)
#endregion


#region Cases
func _case_watch() -> void:
	_check("before anything is watched it says so", _heading().text == GasDebugOverlay.NOBODY, _heading().text)
	_check("it attaches to a battler of this game", _overlay.watch(_baloo.asc))
	_check("and names it", _heading().text == GasDebugOverlay.WATCHING % "Baloo", _heading().text)
	_finish("watch")


func _case_pages() -> void:
	var titles: PackedStringArray = PackedStringArray()
	for page: GasDebugPage in _overlay.pages():
		titles.append(page.title())
	_check("it offers its four pages", _overlay.pages().size() == 4, ", ".join(titles))
	_finish("pages")


func _case_attributes() -> void:
	_overlay.show_page(0)
	_check("the attributes page lists this game's attributes", _any_contains(_page_lines(0), "health") and _any_contains(_page_lines(0), "hit_chance"), "%d rows" % _page_lines(0).size())
	_check("and the table draws every row the page has", _drawn_lines().size() == _page_lines(0).size(), "%d drawn, %d on the page" % [_drawn_lines().size(), _page_lines(0).size()])
	_finish("attributes")


func _case_effects() -> void:
	await _act(_baloo, 0, [_baloo] as Array[Battler])
	_overlay.show_page(1)
	await _one_refresh()
	_check("after Focus, the effects page has a row for it", not _page_lines(1).is_empty() and _drawn_lines().size() == _page_lines(1).size(),
		"%s" % [_drawn_lines()])
	# The row has to say what it is. An effect built in code has no file to be
	# called by, and this game's went unnamed - a row with nothing where the name
	# goes, beside a number nobody could attribute.
	_check("and the row says it is Focus", _any_contains(_drawn_lines(), "Focus"), "%s" % [_drawn_lines()])
	_overlay.show_page(0)
	await _one_refresh()
	_check("and the attributes page shows attack at 20", _any_contains(_drawn_lines(), "20"), "%s" % [_drawn_lines()])
	_finish("effects")


func _case_cooldown() -> void:
	_baloo.asc.set_attribute_base(BattlerAttributes.ENERGY, 6.0)
	await _act(_baloo, 1, [_dummy] as Array[Battler])
	_overlay.show_page(3)
	await _one_refresh()
	_check("after Punch, the tags page shows its cooldown tag", _any_contains(_drawn_lines(), COOLDOWN), "%s" % [_drawn_lines()])
	_overlay.show_page(2)
	await _one_refresh()
	_check("and the abilities page still lists both abilities", _drawn_lines().size() == 2, "%s" % [_drawn_lines()])
	_finish("cooldown")


func _case_paused() -> void:
	_overlay.show_page(0)
	get_tree().paused = true
	_baloo.asc.set_attribute_base(BattlerAttributes.DEFENSE, 77.0)
	await _one_refresh()
	_check("with the game paused, it still shows a change", _any_contains(_drawn_lines(), "77"), "%s" % [_drawn_lines()])
	get_tree().paused = false
	_finish("paused")


func _case_theme() -> void:
	var heading: int = _heading().get_theme_font_size(&"font_size")
	var table: int = _table().get_theme_font_size(&"font_size")
	print("[overlay] font sizes in this game's theme: heading %d, table %d (engine default %d)" % [heading, table, ENGINE_FONT_SIZE])
	var panel: Control = _overlay.get_node("Panel") as Control
	var rows_that_fit: int = int(_table().size.y / maxf(float(table) * 1.5, 1.0))
	_check("the table has room for at least one row of this game's attributes", rows_that_fit >= 9,
		"table %.0f px tall holds about %d rows at font %d, panel %s" % [_table().size.y, rows_that_fit, table, panel.size])
	_finish("theme")


func _case_freed() -> void:
	_baloo.free()
	_baloo = null
	await _one_refresh()
	_check("freeing the watched battler does not take the overlay with it", is_instance_valid(_overlay) and _overlay.is_inside_tree())
	_overlay.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("and the overlay leaves the tree cleanly afterwards", not is_instance_valid(_overlay))
	_finish("freed")
#endregion
