## What this battler can do, offered as a list.
##
## The menu asks the component what is legal and shows the rest greyed out. It
## never decides affordability itself - an ability the engine would refuse is
## disabled here for exactly the engine's reason, so the two can never disagree
## about what a player is allowed to press.
##
## @meta_license: MIT
class_name UIActionMenu extends VBoxContainer

## Null means the player backed out without choosing.
signal ability_selected(handle: GameplayAbilityHandle)
signal ability_focused(ability: BattlerAbility)

@export var entry_scene: PackedScene

var is_active: bool = false:
	set(value):
		is_active = value
		visible = is_active
		set_process_unhandled_input(is_active)

var _roster: BattlerRoster = null

@onready var _menu_cursor: UIMenuCursor = $MenuCursor as UIMenuCursor


func _ready() -> void:
	is_active = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("select") or event.is_action_released("back"):
		ability_selected.emit(null)


func setup(battler: Battler, roster: BattlerRoster) -> void:
	_roster = roster
	var first_button: UIActionButton = null
	var last_button: UIActionButton = null

	for handle: GameplayAbilityHandle in battler.granted:
		var spec: GameplayAbilitySpec = battler.asc.ability_runtime.get_spec(handle)
		if spec == null:
			continue
		var ability: BattlerAbility = spec.per_actor_instance as BattlerAbility
		if ability == null:
			continue

		var entry: UIActionButton = entry_scene.instantiate() as UIActionButton
		assert(entry != null, "UIActionMenu entries must be UIActionButtons.")
		add_child(entry)
		entry.handle = handle
		entry.ability = ability
		# Two reasons a button is dead, both asked of something that knows:
		# the engine refuses the activation, or there is no one to aim at.
		entry.available = (
			battler.asc.ability_runtime.can_activate(spec)
			and not ability.possible_targets(roster).is_empty()
		)
		entry.focus_entered.connect(_on_entry_focused.bind(entry))
		entry.mouse_entered.connect(_on_entry_focused.bind(entry))
		entry.pressed.connect(_on_entry_pressed.bind(entry))
		last_button = entry
		if first_button == null:
			first_button = entry

	if last_button != null and last_button != first_button:
		first_button.focus_neighbor_top = first_button.get_path_to(last_button)
		last_button.focus_neighbor_bottom = last_button.get_path_to(first_button)

	await get_tree().process_frame
	if first_button != null:
		first_button.grab_focus()
		_menu_cursor.position = first_button.global_position + Vector2(0.0, first_button.size.y / 2.0)
		_menu_cursor.show()
	show()
	set_process_unhandled_input(true)


func _on_entry_focused(entry: UIActionButton) -> void:
	_menu_cursor.move_to(entry.global_position + Vector2(0.0, entry.size.y / 2.0))
	ability_focused.emit(entry.ability)


func _on_entry_pressed(entry: UIActionButton) -> void:
	ability_selected.emit(entry.handle)
