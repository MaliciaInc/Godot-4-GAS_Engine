## An ability made in the Composer, given to a battler of this game, and run.
##
## The Composer harness and smoke prove what the Composer does to a file. Neither
## asks the question a designer's afternoon ends on: does what I just drew run?
## This makes an ability through the same model the Composer screen drives -
## the template, the document, the statement operations, the save - hands the
## scene to a battler's component and activates it.
##
## Headless, because nothing here is a gesture. And the Composer reading every
## ability this project holds - this game's and the addon's reference set - so a
## construction it cannot print back byte for byte is found by reading, not by a
## designer losing a comment on save.
##
## @meta_license: MIT
extends Node

const MADE: String = "res://test/_composer_game_probe_ability.gd"
const BEAR_ATTRIBUTES: String = "res://combat/battlers/bear/bear_attributes.tres"
const REFERENCE_DIR: String = "res://addons/GAS_Engine/reference"

const GAME_ABILITIES: Array[String] = [
	"res://src/combat/abilities/battler_ability.gd",
	"res://src/combat/abilities/damage_ability.gd",
	"res://src/combat/abilities/empower_ability.gd",
	"res://src/combat/abilities/heal_ability.gd",
	"res://src/combat/abilities/melee_attack_ability.gd",
	"res://src/combat/abilities/ranged_attack_ability.gd",
]

const COMMIT_CALL: StringName = &"commit_ability"
const WAIT_CALL: StringName = &"wait_delay"

## Frames an activation gets to end on its own before it is called stuck.
const RUN_FRAMES: int = 120

const CASES: Array[String] = ["read", "author", "run", "turn"]

var _passed: int = 0
var _report: Array[String] = []
var _finished: Array[String] = []

var _scene: PackedScene = null
var _baloo: Battler = null
var _handle: GameplayAbilityHandle = null


func _ready() -> void:
	_clear_made()
	await get_tree().process_frame

	await _case_read()
	await _case_author()
	await _case_run()
	await _case_turn()

	if _baloo != null:
		_baloo.free()
	_clear_made()
	_check("nothing this run made is left behind", _left_behind().is_empty(), ", ".join(_left_behind()))

	var missing: Array[String] = []
	for name: String in CASES:
		if not _finished.has(name):
			missing.append(name)
	_check("every case ran to its last line", missing.is_empty(), "stopped part way: %s" % ", ".join(missing))

	print("\n===== COMPOSER -> THIS GAME =====")
	for line: String in _report:
		print(line)
	var failed: int = _report.size() - _passed
	print("%d checks, %d passed, %d to look at" % [_report.size(), _passed, failed])
	print("COMPOSER_GAME_RESULT: %s passed=%d failed=%d" % ["PASS" if failed == 0 else "FAIL", _passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


#region Saying what happened
func _check(what: String, held: bool, detail: String = "") -> void:
	_passed += 1 if held else 0
	_report.append("%s %-60s %s" % ["  ok " if held else "FAIL", what, detail])


func _finish(case_name: String) -> void:
	_finished.append(case_name)
#endregion


#region What this run makes
func _made_files() -> PackedStringArray:
	return PackedStringArray([
		MADE, MADE + ".uid",
		ComposerAbilityTemplate.scene_path_for(MADE),
	])


func _left_behind() -> Array[String]:
	var left: Array[String] = []
	for path: String in _made_files():
		if FileAccess.file_exists(path):
			left.append(path)
	return left


func _clear_made() -> void:
	for path: String in _made_files():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
#endregion


#region Cases
## Every ability in the project, read and printed back.
##
## A file the Composer cannot draw is reported with its reason and is not a
## failure. A file it can draw and does not print back byte for byte is.
func _case_read() -> void:
	var paths: Array[String] = GAME_ABILITIES.duplicate()
	for file: String in DirAccess.get_files_at(REFERENCE_DIR):
		if file.ends_with(".gd"):
			paths.append("%s/%s" % [REFERENCE_DIR, file])

	var drawable: int = 0
	var faithful: int = 0
	var noted: Array[String] = []
	for path: String in paths:
		var source: String = FileAccess.get_file_as_string(path)
		var graph: ComposerGraph = ComposerReader.read(source, path)
		if not graph.is_editable():
			print("[composer] %-34s READ-ONLY  %s" % [path.get_file(), graph.blocked_reason()])
			continue
		drawable += 1
		var printed: ComposerWriter.Result = ComposerWriter.apply(graph, source)
		var same: bool = printed.is_ok() and printed.text == source
		faithful += 1 if same else 0
		if not graph.diagnostics.is_empty():
			noted.append("%s (%d)" % [path.get_file(), graph.diagnostics.size()])
		print("[composer] %-34s %d nodes, %d wires, %d notes, %s" % [
			path.get_file(), graph.nodes.size(), graph.connections.size(),
			graph.diagnostics.size(), "byte for byte" if same else "CHANGED THE FILE",
		])
	_check("the Composer read %d abilities" % paths.size(), paths.size() > GAME_ABILITIES.size())
	_check("every one it can draw prints back byte for byte", faithful == drawable, "%d of %d" % [faithful, drawable])
	_check("and none of those carries a note", noted.is_empty(), ", ".join(noted))
	_finish("read")


## New Ability, then two calls from the catalog, then save - the path the screen
## drives, without the screen.
func _case_author() -> void:
	var refusal: String = ComposerAbilityTemplate.create(MADE)
	_check("New Ability writes the script and its scene", refusal.is_empty() and _left_behind().size() >= 2, refusal)

	var document: ComposerDocument = ComposerDocument.new()
	document.open(FileAccess.get_file_as_string(MADE), MADE)
	_check("the Composer opens what it just made", document.graph() != null and document.graph().is_editable())

	var ops: ComposerStatementOps = ComposerStatementOps.new()
	ops.bind(document)

	# What a palette row goes stale into: a key the catalog no longer has.
	var untouched: String = document.printed()
	var nothing: ComposerGraph.Diagnostic = ops.insert_call([] as Array[StringName], &"no_such_call")
	_check("a call the catalog does not have is refused, not reported done", nothing != null,
		"answered %s, body %s" % [
			"null (the screen's word for done)" if nothing == null else nothing.message,
			"unchanged" if document.printed() == untouched else "CHANGED",
		])

	var commit_key: StringName = _key(COMMIT_CALL)
	var wait_key: StringName = _key(WAIT_CALL)
	_check("the catalog files both calls under one script each", commit_key != &"" and wait_key != &"",
		"%s / %s" % [ComposerCatalog.sources_offering(COMMIT_CALL), ComposerCatalog.sources_offering(WAIT_CALL)])
	var committed: ComposerGraph.Diagnostic = ops.insert_call([] as Array[StringName], commit_key)
	var waited: ComposerGraph.Diagnostic = ops.insert_call([] as Array[StringName], wait_key)
	var body: String = document.printed()
	_check("the catalog writes commit_ability into the body", committed == null and body.contains("commit_ability("), _refusal_of(committed))
	_check("and a wait after it", waited == null and body.contains("wait_delay("), _refusal_of(waited))
	_check("both above the return", _above_return(body, "commit_ability(") and _above_return(body, "wait_delay("))

	# The catalog writes a wait of nothing. A designer gives it a length in the
	# Inspector, and that goes through the same commit every edit does.
	var timed: ComposerGraph.Diagnostic = document.commit(body.replace("wait_delay(0.0)", "wait_delay(0.5)"))
	body = document.printed()
	_check("the wait is given half a second", timed == null and body.contains("wait_delay(0.5)"), _refusal_of(timed))

	_read_only_says_why(wait_key)

	var saved: ComposerGraph.Diagnostic = document.save()
	_check("saving writes it", saved == null and FileAccess.get_file_as_string(MADE) == body, _refusal_of(saved))
	print("[composer] the body it wrote:\n%s" % body)
	_finish("author")


## The scene handed to a battler of this game, activated through its component.
func _case_run() -> void:
	# One process made the file and now runs it. Packing the scene loaded the
	# template, and the scene holds that script object - so the object itself is
	# reloaded from what was saved, which is what the editor does when a file it
	# has loaded changes on disk. A game started fresh reads the disk anyway.
	var script: GDScript = load(MADE) as GDScript
	script.source_code = FileAccess.get_file_as_string(MADE)
	var reloaded: Error = script.reload()
	_check("Godot compiles what the Composer wrote", reloaded == OK and script.can_instantiate(), error_string(reloaded))
	_scene = load(ComposerAbilityTemplate.scene_path_for(MADE)) as PackedScene
	_check("and the scene beside it loads", _scene != null)

	_baloo = Battler.new()
	_baloo.name = "Baloo"
	_baloo.attributes = load(BEAR_ATTRIBUTES) as BattlerAttributes
	add_child(_baloo)

	_handle = _baloo.asc.give_ability(_scene)
	_check("a battler of this game is given it", _handle != null and _handle.is_valid())
	var spec: GameplayAbilitySpec = _baloo.asc.ability_runtime.get_spec(_handle)
	var instance: GameplayAbility = spec.per_actor_instance if spec != null else null
	if instance == null:
		_check("the grant has an instance to run", false)
		_finish("run")
		return

	# Asked of what it does, not of what its text says: the body that was saved
	# commits and then waits, and the template it was made from did neither.
	var commits: Array[int] = [0]
	_baloo.asc.ability_committed.connect(
		func _paid(_h: GameplayAbilityHandle, _r: AbilityCommitResult) -> void: commits[0] += 1
	)
	var endings: Array[bool] = []
	instance.ability_ended.connect(func _ended(was_cancelled: bool) -> void: endings.append(was_cancelled))
	# Started at the top of an ordinary frame, not straight after the work above.
	# Reloading the script, packing the scene and granting it make one long frame,
	# and the ASC counts a wait in the deltas it is handed - the delta of the frame
	# the wait begins in included, as Godot's own timers do. Begun inside that
	# work, the wait was charged for time spent before it existed: measured, 248 ms
	# of wall time, while the frame it began in carried 0.150 s and the frames
	# after it 0.357 s - the half second, on the clock the engine promises. Two
	# frames, because the first one after the work is the one handed its length.
	await get_tree().process_frame
	await get_tree().process_frame
	var result: GameplayAbilityActivationResult = _baloo.asc.ability_runtime.try_activate(_handle)
	_check("it activates", result.is_ok(), GameplayAbilityActivationResult.Status.keys()[result.status])
	_check("and is still waiting when the call returns", instance.is_active, "active=%s" % instance.is_active)
	var started: int = Time.get_ticks_msec()
	var deadline: int = started + 3000
	while instance.is_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var waited: int = Time.get_ticks_msec() - started
	_check("and it waits the half second it was given before ending", waited >= 450, "%d ms" % waited)
	_check("the instance runs the body that was saved: it committed", commits[0] == 1, "%d commits" % commits[0])
	_check("and ends on its own, once, not cancelled", endings == ([false] as Array[bool]), "%s" % [endings])
	_finish("run")


## This game's own turn, handed an ability the Composer made.
##
## `Battler.act()` only runs a BattlerAbility, which is the game's rule and not
## the engine's. Asked so the answer is on record: a turn given anything else
## must end rather than hang the fight.
func _case_turn() -> void:
	if _baloo == null or _handle == null:
		_finish("turn")
		return
	var turns: Array[int] = [0]
	_baloo.turn_finished.connect(func _turned() -> void: turns[0] += 1)
	var activated: Array[int] = [0]
	_baloo.asc.ability_activated.connect(
		func _activated(_h: GameplayAbilityHandle, _i: GameplayAbility) -> void: activated[0] += 1
	)
	_baloo.act(_handle, [] as Array[Battler])
	for _frame: int in RUN_FRAMES:
		if turns[0] > 0:
			break
		await get_tree().process_frame
	_check("a turn handed a Composer-made ability ends", turns[0] == 1, "%d turn endings" % turns[0])
	_check("without running it", activated[0] == 0, "%d activations" % activated[0])
	_finish("turn")
#endregion


## Five of this game's six abilities open read-only, so a palette click or a paste
## on one of them is an afternoon's ordinary mistake rather than an edge case.
## The Composer must leave the file alone and say it did - an answer shaped like
## "done" is what the screen redraws as success.
func _read_only_says_why(wait_key: StringName) -> void:
	var path: String = GAME_ABILITIES[1]
	var source: String = FileAccess.get_file_as_string(path)
	var document: ComposerDocument = ComposerDocument.new()
	document.open(source, path)
	_check("this game's damage ability opens read-only", document.graph() != null and not document.graph().is_editable(),
		document.graph().blocked_reason() if document.graph() != null else "")
	var ops: ComposerStatementOps = ComposerStatementOps.new()
	ops.bind(document)

	var inserted: ComposerGraph.Diagnostic = ops.insert_call([] as Array[StringName], wait_key)
	_check("a palette call on it is refused, not reported done", inserted != null,
		"answered %s" % ["null" if inserted == null else inserted.message])
	var pasted: ComposerGraph.Diagnostic = ops.paste([] as Array[StringName], "\tend_ability()")
	_check("a paste on it is refused, not reported done", pasted != null,
		"answered %s" % ["null" if pasted == null else pasted.message])
	_check("and the file is what it was", document.printed() == source and FileAccess.get_file_as_string(path) == source)


## The key a palette row carries: the script that declares the call, joined to
## its name. Empty when no script, or more than one, offers it.
func _key(method: StringName) -> StringName:
	var offering: Array[String] = ComposerCatalog.sources_offering(method)
	return ComposerCatalog.key_for(offering[0], method) if offering.size() == 1 else &""


func _refusal_of(diagnostic: ComposerGraph.Diagnostic) -> String:
	return diagnostic.message if diagnostic != null else ""


func _above_return(body: String, call: String) -> bool:
	var at: int = body.find(call)
	var returned: int = body.find("return true")
	return at >= 0 and returned >= 0 and at < returned
