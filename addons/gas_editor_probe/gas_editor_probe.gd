## The two editor surfaces GAS_Engine adds, checked inside a real Godot editor.
##
## The engine's suite proves the Gameplay Effect panel and the Debugger tab by
## driving their parts headless and by reading that its plugin wires them in,
## because an EditorPlugin refuses to exist outside an editor. The one thing no
## suite can show is an editor actually showing them - so this is a plugin. It
## is enabled in this project and does nothing unless the editor was started for
## it:
##
##     godot --editor --path . -- --gas-editor-probe
##
## It opens an effect in the Inspector and looks for the panel, plays this game's
## own GAS probe and watches the Debugger tab fill in and keep being sent the
## running entities, prints a line a runner can read, and closes the editor.
##
## @meta_license: MIT
@tool
extends EditorPlugin

const FLAG: String = "--gas-editor-probe"
const PLAYED: String = "res://test/gas_probe.tscn"
const SHOTS: String = "user://gas_editor_probe"
const ATTRIBUTE: StringName = &"health"
const EFFECT_NAME: String = "Editor probe"
const DEBUGGER_DOCK_CLASS: String = "EditorDebuggerNode"

## How long the editor gets to settle, and a played game to report, before a
## check stops waiting and fails rather than hanging the run.
const SETTLE_SECONDS: float = 3.0
const REPORT_TIMEOUT_SECONDS: float = 45.0
const WATCH_SECONDS: float = 2.0
const POLL_SECONDS: float = 0.1

## Snapshots of one entity that must arrive inside WATCH_SECONDS for "sent again
## while the game runs" to hold. The channel resends four times a second, so a
## tab that saw fewer than three in two seconds was not being resent to.
const RESENT_AT_LEAST: int = 3

const EFFECT_CASE: String = "effect panel"
const DEBUGGER_CASE: String = "debugger tab"
const CASES: Array[String] = [EFFECT_CASE, DEBUGGER_CASE]

var _passed: int = 0
var _report: Array[String] = []
var _finished: Array[String] = []


func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has(FLAG):
		_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	await _settle()
	await _case_effect_panel()
	await _case_debugger_tab()
	_say_and_close()


#region The Gameplay Effect panel
func _case_effect_panel() -> void:
	var effect: GameplayEffect = _effect_named_by_picker()
	EditorInterface.edit_resource(effect)
	await _wait(0.5)

	var screen: GameplayEffectEditor = _effect_screen()
	_check("the Gameplay Effect panel is in the editor", screen != null)
	if screen != null:
		_check("it shows the effect the Inspector opened", screen.document.effect == effect)
		_check("and it is on screen", screen.is_visible_in_tree())
		var rows: int = _modifier_rows(screen)
		_check("with the effect's modifier on a row", rows == 1, "%d rows" % rows)
		_check("naming the attribute the picker chose", _shows_text(screen, String(ATTRIBUTE)))
		await _shot("effect-panel")
	_finished.append(EFFECT_CASE)


## One modifier naming its attribute the way the Inspector's picker does: by
## reference, with the bare name beside it left empty.
func _effect_named_by_picker() -> GameplayEffect:
	var reference: GameplayAttributeRef = GameplayAttributeRef.new()
	reference.attribute_name = ATTRIBUTE
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute = reference
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = EFFECT_NAME
	effect.policy = GameplayEffect.DurationPolicy.INFINITE
	var modifiers: Array[GameplayEffectModifier] = [modifier]
	effect.modifiers = modifiers
	return effect


func _effect_screen() -> GameplayEffectEditor:
	for node: Node in _descendants(EditorInterface.get_base_control()):
		var screen: GameplayEffectEditor = node as GameplayEffectEditor
		if screen != null:
			return screen
	return null


func _modifier_rows(screen: GameplayEffectEditor) -> int:
	var rows: int = 0
	for node: Node in _descendants(screen):
		if node is EffectModifierRow:
			rows += 1
	return rows


func _shows_text(under: Node, text: String) -> bool:
	for node: Node in _descendants(under):
		var field: LineEdit = node as LineEdit
		if field != null and field.text == text:
			return true
	return false
#endregion


#region The Debugger tab
func _case_debugger_tab() -> void:
	EditorInterface.play_custom_scene(PLAYED)
	var panel: GasRuntimeDebuggerPanel = await _reporting_panel()
	_check("a GAS_Engine tab is in the Debugger dock", panel != null)
	if panel != null:
		panel.refresh()
		var named: PackedStringArray = panel.entity_names()
		_check("the running game's entities are listed", named.size() > 0, ", ".join(named))
		var resent: int = await _most_snapshots_of_one_entity(panel)
		_check(
			"an entity is sent again while the game runs",
			resent >= RESENT_AT_LEAST,
			"%d snapshots in %.0f s" % [resent, WATCH_SECONDS]
		)
		panel.refresh()
		var rows: int = _rows_drawn(panel)
		_check("the chosen entity's page is drawn", rows > 0, "%d rows" % rows)
		var events: int = panel.event_lines().size()
		_check("and what happened to it is listed", events > 0, "%d events" % events)
		var dock_found: bool = _show(panel)
		await _shot("debugger-tab")
		_check(
			"the tab is on screen",
			panel.is_visible_in_tree(),
			"dock found=%s, hidden: %s" % [dock_found, _hidden_ancestors(panel)]
		)
	_stop_playing()
	_finished.append(DEBUGGER_CASE)


## The first GAS_Engine tab something has reported to, or whatever tab exists
## when the wait runs out - null when there is none at all.
func _reporting_panel() -> GasRuntimeDebuggerPanel:
	var waited: float = 0.0
	var found: GasRuntimeDebuggerPanel = null
	while waited < REPORT_TIMEOUT_SECONDS:
		found = _debugger_panel()
		if found != null and not found.reported.watched_ids().is_empty():
			return found
		await _wait(POLL_SECONDS)
		waited += POLL_SECONDS
	return found


func _debugger_panel() -> GasRuntimeDebuggerPanel:
	for node: Node in _descendants(EditorInterface.get_base_control()):
		var panel: GasRuntimeDebuggerPanel = node as GasRuntimeDebuggerPanel
		if panel != null:
			return panel
	return null


## How many snapshots of one entity arrived while watching, for the entity that
## got the most. The log keeps a new snapshot object for every message, so
## counting objects counts messages without reaching into the plugin.
func _most_snapshots_of_one_entity(panel: GasRuntimeDebuggerPanel) -> int:
	var last_seen: Dictionary[int, int] = {}
	var counted: Dictionary[int, int] = {}
	var waited: float = 0.0
	while waited < WATCH_SECONDS:
		for asc_id: int in panel.reported.watched_ids():
			var snapshot: GasRuntimeSnapshot = panel.reported.snapshot(asc_id)
			if snapshot == null:
				continue
			var previous: int = last_seen.get(asc_id, 0)
			if previous != snapshot.get_instance_id():
				last_seen[asc_id] = snapshot.get_instance_id()
				var so_far: int = counted.get(asc_id, 0)
				counted[asc_id] = so_far + 1
		await _wait(POLL_SECONDS)
		waited += POLL_SECONDS
	var most: int = 0
	for asc_id: int in counted:
		most = maxi(most, counted[asc_id])
	return most


func _rows_drawn(panel: GasRuntimeDebuggerPanel) -> int:
	var root: TreeItem = panel.table().get_root()
	return root.get_child_count() if root != null else 0


## Bring the Debugger dock up with this tab chosen, the way somebody would look.
## False when no Debugger dock was found above the tab to bring up.
func _show(panel: GasRuntimeDebuggerPanel) -> bool:
	var tabs: TabContainer = panel.get_parent() as TabContainer
	if tabs != null:
		tabs.current_tab = tabs.get_tab_idx_from_control(panel)
	var dock: Node = panel.get_parent()
	while dock != null and dock.get_class() != DEBUGGER_DOCK_CLASS:
		dock = dock.get_parent()
	var dock_control: Control = dock as Control
	if dock_control == null:
		return false
	# The editor's own Debugger is a dock of the editor's rather than a control a
	# plugin added: in 4.7 `make_bottom_panel_item_visible()` answers it with
	# `Parameter "dock" is null` and leaves it hidden. So its tab is chosen in
	# whatever holds it, which is what a click on "Debugger" does.
	var held: Node = dock_control
	while held.get_parent() != null and not held.get_parent() is TabContainer:
		held = held.get_parent()
	var holder: TabContainer = held.get_parent() as TabContainer
	var held_control: Control = held as Control
	if holder != null and held_control != null:
		holder.current_tab = holder.get_tab_idx_from_control(held_control)
	return true


## Every ancestor of the tab that is hidden, by class and name, so a tab that is
## not on screen says where it is hidden rather than only that it is.
func _hidden_ancestors(panel: Control) -> String:
	var hidden: PackedStringArray = PackedStringArray()
	var node: Node = panel
	while node != null:
		var control: Control = node as Control
		if control != null and not control.visible:
			hidden.append("%s:%s" % [node.get_class(), node.name])
		node = node.get_parent()
	return ", ".join(hidden)


func _stop_playing() -> void:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
#endregion


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-48s %s" % ["  ok " if held else "FAIL", what, detail])


func _say_and_close() -> void:
	for case_name: String in CASES:
		_check("the %s case ran to its last line" % case_name, _finished.has(case_name))
	var failed: int = _report.size() - _passed
	print("\n===== GAS_ENGINE IN THE EDITOR =====")
	for line: String in _report:
		print(line)
	print("%d checks, %d passed, %d to look at" % [_report.size(), _passed, failed])
	print("shots: %s" % ProjectSettings.globalize_path(SHOTS))
	# Said so a slow run shows whether the time went before the checks or after.
	print("editor up for %.1f s when this was written" % (Time.get_ticks_msec() / 1000.0))
	print("GAS_EDITOR_PROBE_RESULT: %s passed=%d failed=%d" % [
		"PASS" if failed == 0 else "FAIL", _passed, failed
	])
	get_tree().quit(0 if failed == 0 else 1)


func _settle() -> void:
	var files: EditorFileSystem = EditorInterface.get_resource_filesystem()
	while files.is_scanning():
		await _wait(POLL_SECONDS)
	await _wait(SETTLE_SECONDS)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	var image: Image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [SHOTS, label])


func _descendants(of: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in of.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
#endregion
