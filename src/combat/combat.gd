## One battle, from the transition in to the results dialogue.
##
## A round has two halves: everyone declares what they intend, then the
## intentions resolve in speed order. The arena holds those intentions, and it
## is the only thing that does - a battler asked to act is told what to use and
## on whom, and does not remember having chosen.
##
## That single ownership is why the turn loop is short. There is no "has this
## one chosen yet" to keep in sync across a cached action on the battler, a
## queue here and a filter on the roster; there is one dictionary, and it
## empties as the round resolves.
##
## @meta_license: MIT
class_name Combat extends CanvasLayer

## What every standing battler gains at the top of a round.
const ENERGY_PER_ROUND: float = 1.0

var round_count: int = 0

var _previous_music_track: AudioStream = null
var _roster: BattlerRoster = null

## What each battler intends this round. Emptied as each intention resolves, so
## an empty dictionary is exactly "this round is over".
var _intentions: Dictionary[Battler, CombatAI.Choice] = {}

@onready var _combat_container: CenterContainer = $CenterContainer as CenterContainer
@onready var _transition_delay_timer: Timer = $UI/TransitionDelay as Timer
@onready var _ui: UICombat = $UI as UICombat


func _ready() -> void:
	hide()
	FieldEvents.combat_triggered.connect(setup)


#region Setup
func setup(arena: PackedScene) -> void:
	await Transition.cover(0.2)
	show()

	var combat_arena: CombatArena = arena.instantiate() as CombatArena
	assert(combat_arena != null, "Failed to start combat: that scene is not a CombatArena.")
	_combat_container.add_child(combat_arena)
	_roster = combat_arena.get_battler_roster()

	# One frame, so every battler's `_ready` has built its component before
	# anything asks it for an attribute.
	await get_tree().process_frame
	_ui.setup(_roster)
	# The UI reports what the player chose; turning a choice into a turn is
	# this arena's job, so it listens rather than the UI reaching in.
	if not _ui.declaration_made.is_connected(declare):
		_ui.declaration_made.connect(declare)

	_previous_music_track = Music.get_playing_track()
	Music.play(combat_arena.music)
	CombatEvents.combat_initiated.emit()

	Transition.clear.call_deferred(0.2)
	await Transition.finished
	_ui.animation.play("fade_in")
	await _ui.animation.animation_finished

	round_count = 0
	next_round.call_deferred()
#endregion


#region Declaring
func next_round() -> void:
	round_count += 1
	_intentions.clear()

	for battler: Battler in _roster.get_standing(_roster.get_battlers()):
		battler.asc.apply_gameplay_effect(_energy_tick())

	_report_round()

	for battler: Battler in _roster.get_standing(_roster.get_enemy_battlers()):
		if battler.ai == null:
			continue
		var choice: CombatAI.Choice = battler.ai.choose(battler, _roster)
		if choice.is_valid():
			_intentions[battler] = choice

	_ask_next_player()


## What every battler is standing on, printed once at the top of each round.
##
## A playthrough is the only way to put the engine in front of real content, and
## an impression of a fight is not evidence. This turns one into a record.
##
## Health per battler is what tells an isolated attribute set apart from a shared
## one: three of the enemies here are built from the same authored resource, so
## if hitting one moves the others, they are sharing a pool. Reading it round by
## round also carries across battles - a resource the engine wrote through would
## show up as an enemy starting the second fight already wounded.
func _report_round() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for battler: Battler in _roster.get_battlers():
		lines.append("%s %d/%d hp %d/%d en %de%s" % [
			battler.name,
			roundi(battler.attribute(BattlerAttributes.HEALTH)),
			roundi(battler.attribute(BattlerAttributes.MAX_HEALTH)),
			roundi(battler.attribute(BattlerAttributes.ENERGY)),
			roundi(battler.attribute(BattlerAttributes.MAX_ENERGY)),
			battler.asc.get_active_effects().size(),
			" DOWN" if battler.is_downed() else "",
		])
	print("[GAS round %d] %s" % [round_count, " | ".join(lines)])


## The energy every standing battler gains at the top of a round.
##
## Applied as an effect rather than written onto the attribute, for the same
## reason damage is: the pool's own ceiling clamps it, so a full battler stays
## full instead of banking energy it could never spend.
##
## Without this, energy never leaves zero and any ability that costs anything is
## permanently unusable - a cost with no income is not a cost, it is a disabled
## button.
func _energy_tick() -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = ENERGY_PER_ROUND

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = BattlerAttributes.ENERGY
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect


## Hand the cursor to the next player battler that has not declared yet.
func _ask_next_player() -> void:
	var waiting: Array[Battler] = _roster.get_standing(_roster.get_player_battlers()).filter(
		func _undeclared(battler: Battler) -> bool:
			return not _intentions.has(battler)
	)
	if waiting.is_empty():
		CombatEvents.player_battler_selected.emit(null)
		_resolve_next.call_deferred()
		return

	var next_battler: Battler = waiting.front()
	await next_battler.anim.move_forward(0.15)
	CombatEvents.player_battler_selected.emit(next_battler)


## Called by the UI once a player battler has picked.
##
## Declaring is all this does. Nothing resolves until everyone has declared,
## which is what makes speed decide the order rather than who chose first.
func declare(battler: Battler, choice: CombatAI.Choice) -> void:
	if not choice.is_valid():
		return
	_intentions[battler] = choice
	await battler.anim.move_to_rest(0.15)
	_ask_next_player()
#endregion


#region Resolving
func _resolve_next() -> void:
	if _roster.is_side_defeated(_roster.get_player_battlers()):
		_finish.call_deferred(false)
		return
	if _roster.is_side_defeated(_roster.get_enemy_battlers()):
		_finish.call_deferred(true)
		return

	var actor: Battler = _next_actor()
	if actor == null:
		next_round()
		return

	var choice: CombatAI.Choice = _intentions[actor]
	# Withdrawn before the ability runs, not after. A battler killed earlier
	# this round still has an intention on file, and resolving one after the
	# fact would let a corpse swing.
	_intentions.erase(actor)

	actor.turn_finished.connect(_resolve_next, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	actor.act(choice.handle, choice.targets)


## The fastest battler still holding an intention.
##
## Read live from `speed`, so a haste landed earlier in this same round changes
## who moves next inside it.
func _next_actor() -> Battler:
	var pending: Array[Battler] = []
	for battler: Battler in _intentions:
		if not battler.is_downed():
			pending.append(battler)
	if pending.is_empty():
		return null
	pending.sort_custom(Battler.sort_by_speed)
	return pending.front()
#endregion


#region Ending
func _finish(is_player_victory: bool) -> void:
	_ui.animation.play("fade_out")
	await _ui.animation.animation_finished
	await _show_results(is_player_victory)

	_intentions.clear()
	_roster = null

	_transition_delay_timer.start()
	await _transition_delay_timer.timeout
	await Transition.cover(0.2)
	hide()
	for child: Node in _combat_container.get_children():
		child.free()

	Music.play(_previous_music_track)
	_previous_music_track = null
	CombatEvents.combat_finished.emit(is_player_victory)


func _show_results(is_player_victory: bool) -> void:
	var leader_name: String = _roster.get_player_battlers()[0].name
	var timeline: DialogicTimeline = DialogicTimeline.new()
	timeline.events = (
		_victory_events(leader_name) if is_player_victory else _loss_events(leader_name)
	)
	Dialogic.start_timeline(timeline)
	await Dialogic.timeline_ended


func _victory_events(leader_name: String) -> Array[String]:
	return [
		"%s's party won the battle!" % leader_name,
		"You wanted to find some coins, but animals have no pockets to carry them.",
	] as Array[String]


func _loss_events(leader_name: String) -> Array[String]:
	return ["%s's party lost the battle!" % leader_name] as Array[String]
#endregion
