## The Dialogic bridge, against the Dialogic this game actually ships.
##
## `main` proves the bridge against a stand-in that carries one signal and hands
## over whatever a test built. That proves the bridge's logic and nothing about
## the message a real timeline sends - which is built by Dialogic's own parser,
## from the text a writer typed, and is the only message that ever arrives in a
## game. So every message here starts as a line of timeline text, goes through
## `DialogicTimeline.from_text()` and Dialogic's own signal event, and reaches
## the bridge on the real autoload's bus, aimed at a battler of this game.
##
## Headless: a timeline made only of signal events never waits for a key, and
## `start_timeline()` starts no layout.
##
## @meta_license: MIT
extends Node

const BEAR_ATTRIBUTES: String = "res://combat/battlers/bear/bear_attributes.tres"
const LISTENER: String = "res://test/dialogic_probe_listener.gd"

const CHANNEL: String = "Player"
const OTHER_CHANNEL: String = "Companion"
const DOOMED_CHANNEL: String = "Doomed"
const SWORN: StringName = &"State.Sworn"
const WARY: StringName = &"State.Wary"
const ACCEPTED: StringName = &"Event.Dialogue.Accepted"

## A line this game's own timelines already put on the same bus - monk.dtl,
## thief.dtl, warrior.dtl, wizard.dtl. Traffic the bridge must leave alone.
const GAME_OWN_LINE: String = "[signal arg=\"coin_received\"]"

## Frames a timeline of signal events gets to reach its end.
const TIMELINE_FRAMES: int = 60

const CASES: Array[String] = [
	"finds", "add", "remove", "event", "traffic", "malformed",
	"channel", "legacy", "two", "freed_target", "unbind", "freed_bridge",
]

var _passed: int = 0
var _report: Array[String] = []
var _finished: Array[String] = []

var _baloo: Battler = null
var _bridge: DialogicGasBridge = null
var _applied: Array[DialogicGasCommand] = []
var _rejected: Array[DialogicGasCommandParser.Error] = []
var _events: Array[GameplayEventData] = []
var _listener_runs: int = 0
var _ended: bool = false
var _timelines_unfinished: int = 0


func _ready() -> void:
	Dialogic.timeline_ended.connect(_on_timeline_ended)
	await get_tree().process_frame

	await _case_finds()
	await _case_add()
	await _case_remove()
	await _case_event()
	await _case_traffic()
	await _case_malformed()
	await _case_channel()
	await _case_legacy()
	await _case_two()
	await _case_freed_target()
	await _case_unbind()
	await _case_freed_bridge()

	var missing: Array[String] = []
	for name: String in CASES:
		if not _finished.has(name):
			missing.append(name)
	_check("every case ran to its last line", missing.is_empty(), "stopped part way: %s" % ", ".join(missing))
	_check("every timeline reached its end", _timelines_unfinished == 0, "%d did not" % _timelines_unfinished)

	print("\n===== DIALOGIC BRIDGE vs REAL DIALOGIC =====")
	for line: String in _report:
		print(line)
	var failed: int = _report.size() - _passed
	print("%d checks, %d passed, %d to look at" % [_report.size(), _passed, failed])
	print("DIALOGIC_BRIDGE_RESULT: %s passed=%d failed=%d" % ["PASS" if failed == 0 else "FAIL", _passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-62s %s" % ["  ok " if held else "FAIL", what, detail])


func _finish(case_name: String) -> void:
	_finished.append(case_name)
#endregion


#region Timelines, the way a writer makes them
## One Dialogic signal line carrying a dictionary, spelled the way the timeline
## text stores it.
func _line(fields: Dictionary) -> String:
	return "[signal arg_type=\"dict\" arg=\"%s\"]" % JSON.stringify(fields)


func _for_bridge(channel: String, command: String, tag: String) -> Dictionary:
	return {
		"bridge": DialogicGasCommandParser.BRIDGE_NAME,
		"channel": channel,
		"command": command,
		"tag": tag,
	}


func _play(lines: Array[String]) -> void:
	var timeline: DialogicTimeline = DialogicTimeline.new()
	timeline.from_text("\n".join(lines))
	_ended = false
	Dialogic.start_timeline(timeline)
	for _frame: int in TIMELINE_FRAMES:
		if _ended:
			break
		await get_tree().process_frame
	if not _ended:
		_timelines_unfinished += 1
	# Dialogic clears after it announces the end; let that settle before the
	# next timeline starts.
	await get_tree().process_frame


func _on_timeline_ended() -> void:
	_ended = true


func _start_recording() -> void:
	_applied.clear()
	_rejected.clear()
	_events.clear()
	_listener_runs = 0
#endregion


#region The game's side
func _battler(named: String) -> Battler:
	var battler: Battler = Battler.new()
	battler.name = named
	battler.attributes = load(BEAR_ATTRIBUTES) as BattlerAttributes
	add_child(battler)
	return battler


func _listener_scene() -> PackedScene:
	var script: GDScript = load(LISTENER) as GDScript
	var made: Object = script.new()
	var root: Node = made as Node
	root.name = "DialogueListener"
	var scene: PackedScene = PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


func _watch(bridge: DialogicGasBridge, battler: Battler) -> void:
	bridge.command_applied.connect(_on_applied)
	bridge.command_rejected.connect(_on_rejected)
	battler.asc.gameplay_event_received.connect(_on_event)
	battler.asc.ability_activated.connect(_on_activated)


func _on_applied(command: DialogicGasCommand) -> void:
	_applied.append(command)


func _on_rejected(error: DialogicGasCommandParser.Error) -> void:
	_rejected.append(error)


func _on_event(event: GameplayEventData) -> void:
	_events.append(event)


func _on_activated(_handle: GameplayAbilityHandle, instance: GameplayAbility) -> void:
	if instance != null and instance.get_script() != null and (instance.get_script() as Script).resource_path == LISTENER:
		_listener_runs += 1


func _rejections() -> String:
	var named: PackedStringArray = PackedStringArray()
	for error: DialogicGasCommandParser.Error in _rejected:
		named.append(DialogicGasCommandParser.Error.keys()[error])
	return "[%s]" % ", ".join(named)


func _bus_listeners() -> int:
	return Dialogic.signal_event.get_connections().size()
#endregion


#region Cases
func _case_finds() -> void:
	_check("the addon's plugin.cfg is on disk", GameplayIntegrationAvailability.is_dialogic_installed())
	var runtime: Node = GameplayIntegrationAvailability.dialogic_runtime(get_tree())
	_check("the availability check finds the running autoload", runtime != null and runtime == Dialogic)
	_check("and it is Dialogic's own game handler", runtime is DialogicGameHandler)

	_baloo = _battler("Baloo")
	var handle: GameplayAbilityHandle = _baloo.asc.give_ability(_listener_scene())
	_check("a listener ability is granted to a battler of this game", handle.is_valid())

	_bridge = DialogicGasBridge.new()
	add_child(_bridge)
	_watch(_bridge, _baloo)
	_check(
		"the bridge binds to the installed Dialogic",
		_bridge.bind_installed(get_tree(), _baloo.asc, StringName(CHANNEL))
	)
	_finish("finds")


func _case_add() -> void:
	_start_recording()
	var line: String = _line(_for_bridge(CHANNEL, "add_tag", String(SWORN)))
	await _play([line] as Array[String])
	_check("a writer's add_tag line is applied", _applied.size() == 1, "applied %d, rejected %s - %s" % [_applied.size(), _rejections(), line])
	_check("and the battler carries the tag", _baloo.asc.has_tag_exact(SWORN))
	_check("nothing was refused", _rejected.is_empty(), _rejections())
	_finish("add")


func _case_remove() -> void:
	_start_recording()
	if not _baloo.asc.has_tag_exact(SWORN):
		_baloo.asc.add_tag(SWORN)
	await _play([_line(_for_bridge(CHANNEL, "remove_tag", String(SWORN)))] as Array[String])
	_check("a remove_tag line is applied", _applied.size() == 1, "applied %d, rejected %s" % [_applied.size(), _rejections()])
	_check("and the tag is gone", not _baloo.asc.has_tag_exact(SWORN))
	_finish("remove")


func _case_event() -> void:
	_start_recording()
	var fields: Dictionary = _for_bridge(CHANNEL, "send_event", String(ACCEPTED))
	fields["magnitude"] = 3
	await _play([_line(fields)] as Array[String])
	_check("a send_event line is applied", _applied.size() == 1, "applied %d, rejected %s" % [_applied.size(), _rejections()])
	var event: GameplayEventData = _events.back() if not _events.is_empty() else null
	_check("the battler's component heard the event", event != null and event.event_tag == ACCEPTED, "%d events" % _events.size())
	_check("with the magnitude the writer typed", event != null and is_equal_approx(event.magnitude, 3.0), "%s" % [event.magnitude if event != null else "no event"])
	_check("sent by the battler itself", event != null and event.instigator == _baloo, "%s" % [event.instigator if event != null else "no event"])
	_check("and it woke the ability listening on its family", _listener_runs == 1, "%d activations" % _listener_runs)
	_finish("event")


func _case_traffic() -> void:
	_start_recording()
	var theirs: Dictionary = {"bridge": "SomebodyElse", "quest": "coin"}
	await _play([GAME_OWN_LINE, _line(theirs)] as Array[String])
	_check("this game's own signal lines are left alone", _applied.is_empty(), "applied %d" % _applied.size())
	_check("and are not complained about", _rejected.is_empty(), _rejections())
	_finish("traffic")


func _case_malformed() -> void:
	_start_recording()
	var unknown: Dictionary = _for_bridge(CHANNEL, "detonate", String(SWORN))
	var lowercase: Dictionary = _for_bridge(CHANNEL, "add_tag", "state.sworn")
	var no_channel: Dictionary = _for_bridge(CHANNEL, "add_tag", String(SWORN))
	no_channel.erase("channel")
	var wordy: Dictionary = _for_bridge(CHANNEL, "send_event", String(ACCEPTED))
	wordy["magnitude"] = "a lot"
	await _play([_line(unknown), _line(lowercase), _line(no_channel), _line(wordy)] as Array[String])
	var expected: Array[DialogicGasCommandParser.Error] = [
		DialogicGasCommandParser.Error.UNKNOWN_COMMAND,
		DialogicGasCommandParser.Error.INVALID_TAG,
		DialogicGasCommandParser.Error.MISSING_CHANNEL,
		DialogicGasCommandParser.Error.INVALID_MAGNITUDE,
	]
	_check("four malformed lines addressed to the bridge are refused", _rejected == expected, _rejections())
	_check("and none of them was applied", _applied.is_empty(), "applied %d" % _applied.size())
	_check("and the misspelled tag was not granted anyway", not _baloo.asc.has_tag_exact(SWORN))
	_finish("malformed")


func _case_channel() -> void:
	_start_recording()
	await _play([_line(_for_bridge(OTHER_CHANNEL, "add_tag", String(WARY)))] as Array[String])
	_check("a line for another channel is not applied", _applied.is_empty(), "applied %d" % _applied.size())
	_check("and not refused either", _rejected.is_empty(), _rejections())
	_check("and the battler did not get the tag", not _baloo.asc.has_tag_exact(WARY))
	_finish("channel")


func _case_legacy() -> void:
	_start_recording()
	var legacy: Dictionary = _for_bridge(CHANNEL, "add_tag", String(SWORN))
	legacy["bridge"] = DialogicGasCommandParser.LEGACY_BRIDGE_NAME
	await _play([_line(legacy)] as Array[String])
	_check("a line written for the product's old name still applies", _applied.size() == 1, "applied %d, rejected %s" % [_applied.size(), _rejections()])
	_baloo.asc.remove_tag(SWORN)
	_finish("legacy")


func _case_two() -> void:
	_start_recording()
	var nutsy: Battler = _battler("Nutsy")
	var second: DialogicGasBridge = DialogicGasBridge.new()
	add_child(second)
	var bound: bool = second.bind_installed(get_tree(), nutsy.asc, StringName(OTHER_CHANNEL))
	_check("a second bridge binds to the same bus", bound)
	await _play([
		_line(_for_bridge(CHANNEL, "add_tag", String(SWORN))),
		_line(_for_bridge(OTHER_CHANNEL, "add_tag", String(WARY))),
	] as Array[String])
	_check("each battler got only its own channel's tag",
		_baloo.asc.has_tag_exact(SWORN) and not _baloo.asc.has_tag_exact(WARY)
		and nutsy.asc.has_tag_exact(WARY) and not nutsy.asc.has_tag_exact(SWORN),
		"Baloo sworn=%s wary=%s, Nutsy sworn=%s wary=%s" % [
			_baloo.asc.has_tag_exact(SWORN), _baloo.asc.has_tag_exact(WARY),
			nutsy.asc.has_tag_exact(SWORN), nutsy.asc.has_tag_exact(WARY),
		])
	second.free()
	nutsy.free()
	_baloo.asc.remove_tag(SWORN)
	_finish("two")


func _case_freed_target() -> void:
	_start_recording()
	var doomed: Battler = _battler("Doomed")
	var watcher: DialogicGasBridge = DialogicGasBridge.new()
	add_child(watcher)
	watcher.bind_installed(get_tree(), doomed.asc, StringName(DOOMED_CHANNEL))
	var applied_here: Array[int] = [0]
	watcher.command_applied.connect(func _count(_c: DialogicGasCommand) -> void: applied_here[0] += 1)
	doomed.free()
	await _play([_line(_for_bridge(DOOMED_CHANNEL, "add_tag", String(SWORN)))] as Array[String])
	_check("a line for a battler that was freed under its bridge does not crash", true)
	_check("and applies nothing", applied_here[0] == 0, "applied %d" % applied_here[0])
	watcher.free()
	_finish("freed_target")


func _case_unbind() -> void:
	_start_recording()
	var before: int = _bus_listeners()
	_bridge.unbind()
	_check("unbinding takes the bridge off the real bus", _bus_listeners() == before - 1, "%d -> %d" % [before, _bus_listeners()])
	await _play([_line(_for_bridge(CHANNEL, "add_tag", String(SWORN)))] as Array[String])
	_check("and nothing it said afterwards arrives", _applied.is_empty() and not _baloo.asc.has_tag_exact(SWORN))
	_finish("unbind")


func _case_freed_bridge() -> void:
	var before: int = _bus_listeners()
	var temporary: DialogicGasBridge = DialogicGasBridge.new()
	temporary.bind_installed(get_tree(), _baloo.asc, StringName(CHANNEL))
	_check("a bridge that binds adds one listener", _bus_listeners() == before + 1, "%d -> %d" % [before, _bus_listeners()])
	temporary.free()
	_check("and a freed one takes it away again", _bus_listeners() == before, "%d" % _bus_listeners())
	_finish("freed_bridge")
#endregion
