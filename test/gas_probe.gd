## Drives a real battle and writes down what the engine did.
##
## The addon's own suite cannot reach here. Every engine defect this sandbox has
## found was invisible to thirty thousand assertions and visible the moment a
## game used the engine for real, so the evidence that matters is a fight that
## actually happened - not a fixture shaped like one.
##
## Runs the real `main.tscn`, starts an arena the way a combat trigger would, and
## answers `player_battler_selected` the way the action menu does. Both are the
## seams a player goes through; reaching past them into `Combat.setup()` or
## straight at an ability would test a path nobody takes.
##
## Plays a fixed hand rather than a random one - same ability, same target, every
## run. Random play makes a failure unreproducible, and the point of this is a
## record that can be re-run and disagreed with.
##
## @meta_license: MIT
extends Node

const MAIN: String = "res://src/main.tscn"
const ARENA_ONE: String = "res://overworld/maps/town/battles/test_combat_arena.tscn"
const ARENA_TWO: String = "res://overworld/maps/town/battles/test_combat_arena2.tscn"
const SHOTS: String = "user://gas_probe"

const PUNCH: String = "Punch"
const HEAL: String = "Heal"
const FOCUS: String = "Focus"

## Enough rounds to reach the far side of a four-turn cooldown.
const MAX_ROUNDS: int = 9
const SETTLE: float = 2.5
## Wall-clock only. Turns are counted, so nothing about the fight changes.
const HASTE: float = 6.0
const TICK: float = 0.2
## A round that does not arrive in this many scaled seconds is not slow, it
## is stuck. Waiting it out reads as a hung machine rather than a finding.
const STALL: float = 12.0
const DEFAULT_SEED: int = 8

var _main: Node = null
var _combat: Combat = null
var _seen_round: int = 0
## Round number -> the roster state read at the top of it.
var _log: Dictionary[int, String] = {}
var _notes: PackedStringArray = PackedStringArray()
var _finished: bool = false
var _victory: bool = false
## Set once, the first time the punched enemy is seen below full health.
var _isolation_verdict: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	_seed_rng()
	_main = (load(MAIN) as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame

	_combat = _main.find_child("Combat", true, false) as Combat
	if _combat == null:
		push_error("[probe] no Combat node")
		get_tree().quit(1)
		return

	CombatEvents.player_battler_selected.connect(_on_asked)
	CombatEvents.combat_finished.connect(_on_finished)
	Dialogic.timeline_started.connect(_on_timeline_started)

	await _run(ARENA_ONE, "arena1")
	await _run(ARENA_TWO, "arena2")

	print("\n===== PROBE NOTES =====")
	for note: String in _notes:
		print("[probe] note: %s" % note)
	get_tree().quit(0)


## Fix the dice.
##
## Accuracy is rolled per target, so an attack that misses leaves exactly the
## trace an attack that never fired leaves - the cost is spent and the cooldown
## starts either way. Without a seed, "the enemy took no damage" is a coin
## landing, and a coin cannot be re-examined. Pass one with
## `-- --seed=N`; the default is a seed under which Punch connects.
func _seed_rng() -> void:
	var chosen: int = DEFAULT_SEED
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			chosen = int(argument.trim_prefix("--seed="))
	seed(chosen)
	_notes.append("seed=%d" % chosen)
	print("[probe] seed=%d" % chosen)


## Results are a Dialogic timeline that waits to be read. Nothing about the
## engine is in it, and a probe that cannot press a key would wait forever - so
## end it the moment it starts and let the fight finish.
func _on_timeline_started() -> void:
	Dialogic.end_timeline()


#region Running an arena
func _run(arena: String, label: String) -> void:
	_seen_round = 0
	_finished = false
	_log.clear()
	print("\n===== %s =====" % label)

	Engine.time_scale = 1.0
	FieldEvents.combat_triggered.emit(load(arena) as PackedScene)
	await get_tree().create_timer(SETTLE).timeout

	# The fade-in is over; the fight itself can run fast. Every await and
	# animation still happens, there are just fewer wall-clock seconds
	# between them - the engine's turn clock counts turns, not time.
	Engine.time_scale = HASTE

	var idle: float = 0.0
	while not _finished and _combat.round_count <= MAX_ROUNDS:
		if _combat.round_count > _seen_round:
			_seen_round = _combat.round_count
			idle = 0.0
			_record(label)
			await _shoot("%s_round%d" % [label, _seen_round])
		await get_tree().create_timer(TICK).timeout
		idle += TICK
		if idle >= STALL:
			_stalled(label)
			break

	_record(label)
	await _shoot("%s_end" % label)
	Engine.time_scale = 1.0
	_notes.append("%s: ended=%s victory=%s rounds=%d reason=%s" % [
		label, _finished, _victory, _combat.round_count,
		"combat_finished" if _finished else "hit the round cap"
	])


## Say exactly what the fight was waiting for when it stopped waiting.
##
## A stall is only useful as evidence if it names who held the turn. Whether a
## battler was mid-declaration, mid-resolution, or simply never asked is the
## difference between three different faults.
func _stalled(label: String) -> void:
	var waiting: PackedStringArray = PackedStringArray()
	for battler: Battler in _combat._roster.get_standing(
		_combat._roster.get_battlers()
	):
		waiting.append("%s:%s" % [
			battler.name, "declared" if _combat._intentions.has(battler) else "waiting"
		])
	_notes.append("%s: STALLED at round %d - %s" % [
		label, _combat.round_count, " ".join(waiting)
	])
	print("[probe] STALL round %d: %s" % [_combat.round_count, " ".join(waiting)])


func _on_finished(is_player_victory: bool) -> void:
	_finished = true
	_victory = is_player_victory
#endregion


#region Playing the party's turns
## The action menu's job, done by hand and always the same way.
##
## Baloo punches the first enemy still standing and falls back on Focus, so the
## only damage any enemy takes comes from one ability aimed at one of them -
## which is what makes the other two a control group. Nutsy heals, which reaches
## the clamp when everyone is full and never touches an enemy.
func _on_asked(battler: Battler) -> void:
	if battler == null or _finished:
		return
	var choice: CombatAI.Choice = _decide(battler)
	if choice.is_valid():
		_combat.declare(battler, choice)
		return
	# Nothing legal. Say so rather than hanging with the cursor on a battler
	# that can do nothing - a hang would read as an engine fault.
	_notes.append("round %d: %s had no legal action" % [_combat.round_count, battler.name])
	_finished = true


func _decide(battler: Battler) -> CombatAI.Choice:
	var choice: CombatAI.Choice = CombatAI.Choice.new()
	var wanted: Array[String] = [PUNCH, HEAL, FOCUS]
	for name: String in wanted:
		var handle: GameplayAbilityHandle = _legal_handle(battler, name)
		if handle == null:
			continue
		var ability: BattlerAbility = _ability(battler, handle)
		var candidates: Array[Battler] = ability.possible_targets(_combat._roster)
		if candidates.is_empty():
			continue
		choice.handle = handle
		choice.targets = candidates if ability.takes_everyone() else (
			[_pick(name, candidates)] as Array[Battler]
		)
		return choice
	return choice


## The first candidate, except for a heal, which always goes to Baloo.
##
## Not a fairness rule - a test requirement. Turn order is read from `speed`, so
## Baloo (40) acts after all three bugcats (50), and he is the only one holding a
## single-target attack. Every round he dies before acting is a round the one
## ability that can damage exactly one enemy never fires, and without that the
## other two enemies are not a control group.
func _pick(ability_name: String, candidates: Array[Battler]) -> Battler:
	if ability_name != HEAL:
		return candidates[0]
	for battler: Battler in candidates:
		if battler.name == "Baloo":
			return battler
	return candidates[0]


func _legal_handle(battler: Battler, ability_name: String) -> GameplayAbilityHandle:
	for handle: GameplayAbilityHandle in battler.granted:
		var ability: BattlerAbility = _ability(battler, handle)
		if ability == null or ability.ability_name != ability_name:
			continue
		var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(handle)
		return handle if battler.asc.ability_runtime.can_activate(spec) else null
	return null


func _ability(battler: Battler, handle: GameplayAbilityHandle) -> BattlerAbility:
	var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(handle)
	if spec == null:
		return null
	return spec.per_actor_instance as BattlerAbility
#endregion


#region Evidence
## Every battler's standing, plus why the engine would refuse Punch right now.
##
## The refusal reason is the interesting column: an ability can be unusable for
## being unaffordable or for being on cooldown, and only one of those proves the
## turn clock is running.
func _record(label: String) -> void:
	if _combat._roster == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	for battler: Battler in _combat._roster.get_battlers():
		parts.append("%s %.0f/%.0f hp %.0f en %de%s" % [
			battler.name,
			battler.attribute(BattlerAttributes.HEALTH),
			battler.attribute(BattlerAttributes.MAX_HEALTH),
			battler.attribute(BattlerAttributes.ENERGY),
			battler.asc.get_active_effects().size(),
			" DOWN" if battler.is_downed() else "",
		])
	_check_isolation()
	var line: String = "  r%d  %s   punch=%s" % [
		_combat.round_count, " | ".join(parts), _punch_state()
	]
	_log[_combat.round_count] = line
	print("[probe]%s" % line)


## The whole reason three identical enemies stand in arena 1.
##
## All three are built from one authored resource. Punch is aimed at the first
## of them and at nothing else, so the moment one of them is hurt the other two
## are a control group: if they move together, they are one pool of health
## wearing three sprites, and the game looks fine right up until the party dies
## at once.
func _check_isolation() -> void:
	var enemies: Array[Battler] = _combat._roster.get_enemy_battlers()
	if enemies.size() < 3 or _isolation_verdict != "":
		return
	var hurt: float = enemies[0].attribute(BattlerAttributes.HEALTH)
	var full: float = enemies[0].attribute(BattlerAttributes.MAX_HEALTH)
	if is_equal_approx(hurt, full):
		return
	var others_untouched: bool = true
	for index: int in range(1, enemies.size()):
		if not is_equal_approx(
			enemies[index].attribute(BattlerAttributes.HEALTH),
			enemies[index].attribute(BattlerAttributes.MAX_HEALTH)
		):
			others_untouched = false
	_isolation_verdict = "ISOLATED" if others_untouched else "SHARED POOL"
	_notes.append("P1 isolation: %s (target %.0f/%.0f, others %.0f and %.0f)" % [
		_isolation_verdict, hurt, full,
		enemies[1].attribute(BattlerAttributes.HEALTH),
		enemies[2].attribute(BattlerAttributes.HEALTH),
	])


func _punch_state() -> String:
	for battler: Battler in _combat._roster.get_battlers():
		for handle: GameplayAbilityHandle in battler.granted:
			var ability: BattlerAbility = _ability(battler, handle)
			if ability == null or ability.ability_name != PUNCH:
				continue
			var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(handle)
			var error: AbilityRuntime.ActivationError = (
				battler.asc.ability_runtime.activation_error(spec)
			)
			return AbilityRuntime.ActivationError.keys()[error]
	return "-"


## Clear the action menus this probe leaks, so a frame shows the fight.
##
## `UICombat` builds a fresh menu per battler and frees it inside the handler for
## `ability_selected`. This probe declares through `Combat.declare()` instead -
## the seam the menu itself reports into - so that handler never runs and the
## menus stack up on screen. Confirmed against real play: a person choosing an
## action sees one menu. The stacking is this harness, not the game, and it is
## swept here rather than left to be mistaken for a defect in a screenshot.
##
## What that costs is real and worth naming: the button press, the target cursor
## and the menu's own teardown are NOT exercised by this probe. It tests the
## engine underneath them, not the UI on top.
func _sweep_menus() -> void:
	var menus: Array[Node] = []
	_collect(_main, menus)
	for index: int in range(0, maxi(0, menus.size() - 1)):
		menus[index].queue_free()
	if not menus.is_empty():
		await get_tree().process_frame


func _collect(node: Node, found: Array[Node]) -> void:
	if node is UIActionMenu:
		found.append(node)
	for child: Node in node.get_children():
		_collect(child, found)


func _shoot(label: String) -> void:
	await _sweep_menus()
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, label])
#endregion
