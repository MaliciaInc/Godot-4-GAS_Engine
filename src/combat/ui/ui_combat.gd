## The player's side of a turn: pick an ability, then pick who it lands on.
##
## The UI decides nothing about the fight. It asks the component what is legal,
## shows that, and reports back what the player chose. The arena is what turns a
## choice into a turn, which is why this emits a declaration rather than writing
## one anywhere.
##
## @meta_license: MIT
class_name UICombat extends Control

## The player finished choosing for `battler`.
signal declaration_made(battler: Battler, choice: CombatAI.Choice)

@export var action_menu_scene: PackedScene
@export var target_cursor_scene: PackedScene

var _roster: BattlerRoster = null

@onready var animation: AnimationPlayer = $AnimationPlayer as AnimationPlayer
@onready var _effect_label_builder: UIEffectLabelBuilder = $EffectLabelBuilder as UIEffectLabelBuilder
@onready var _action_description: UIActionDescription = $PlayerMenus/ActionDescription as UIActionDescription
@onready var _action_menu_anchor: Control = $PlayerMenus/ActionMenuAnchor as Control
@onready var _battler_list: UIPlayerBattlerList = $PlayerMenus/PlayerBattlerList as UIPlayerBattlerList


func _ready() -> void:
	CombatEvents.player_battler_selected.connect(
		func _on_player_battler_selected(battler: Battler) -> void:
			if battler != null:
				choose_ability(battler)
	)


func setup(roster: BattlerRoster) -> void:
	_roster = roster
	_effect_label_builder.setup(roster)
	_battler_list.battlers = roster.get_player_battlers()


#region Choosing
func choose_ability(battler: Battler) -> void:
	var menu: UIActionMenu = action_menu_scene.instantiate() as UIActionMenu
	_action_menu_anchor.add_child(menu)
	menu.setup(battler, _roster)
	menu.is_active = true

	menu.ability_focused.connect(
		func _on_focused(ability: BattlerAbility) -> void:
			_action_description.description = ability.description
	)
	menu.ability_selected.connect(
		func _on_selected(handle: GameplayAbilityHandle) -> void:
			menu.queue_free()
			if handle != null:
				choose_targets.call_deferred(battler, handle)
	)


func choose_targets(battler: Battler, handle: GameplayAbilityHandle) -> void:
	var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(handle)
	var ability: BattlerAbility = spec.per_actor_instance as BattlerAbility if spec != null else null
	if ability == null:
		choose_ability(battler)
		return

	var cursor: UIBattlerTargetingCursor = target_cursor_scene.instantiate() as UIBattlerTargetingCursor
	# Both asked of the ability, which is the same thing the opponent asks. The
	# cursor can therefore never offer a target the engine would refuse.
	cursor.targets_all = ability.takes_everyone()
	cursor.targets = ability.possible_targets(_roster)
	add_child(cursor)

	cursor.targets_selected.connect(
		func _on_targets_selected(targets: Array[Battler]) -> void:
			if targets.is_empty():
				# Backed out. Straight to the ability list, not to a half-made
				# declaration nobody would clear.
				choose_ability(battler)
				return
			_action_description.description = ""
			var choice: CombatAI.Choice = CombatAI.Choice.new()
			choice.handle = handle
			choice.targets = targets
			declaration_made.emit(battler, choice)
	)
#endregion
