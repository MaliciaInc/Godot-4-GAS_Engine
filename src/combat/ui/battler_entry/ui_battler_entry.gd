## One party member's bars.
##
## Reads the component and follows its attribute signal. It keeps no copy of a
## number it displays, so a bar can never show a value the fight has already
## moved past.
##
## @meta_license: MIT
class_name UIBattlerEntry extends TextureRect

var battler: Battler = null:
	set(value):
		battler = value
		if not is_inside_tree():
			await ready
		if battler == null or battler.asc == null:
			return

		_energy.setup(
			battler.attribute(BattlerAttributes.MAX_ENERGY),
			battler.attribute(BattlerAttributes.ENERGY)
		)
		_life.setup(
			battler.name,
			battler.attribute(BattlerAttributes.MAX_HEALTH),
			battler.attribute(BattlerAttributes.HEALTH)
		)
		battler.asc.attribute_changed.connect(_on_attribute_changed)

@onready var _energy: UIBattlerEnergyBar = $VBoxContainer/CenterContainer/EnergyBar as UIBattlerEnergyBar
@onready var _life: UIBattlerLifeBar = $VBoxContainer/LifeBar as UIBattlerLifeBar


func _ready() -> void:
	CombatEvents.player_battler_selected.connect(
		func _on_player_battler_selected(selected: Battler) -> void:
			_life.is_highlighted = battler == selected
	)


## One handler for every attribute rather than one connection per bar: the
## component reports them all through the same signal, and splitting that into
## per-attribute listeners would only add places to forget one.
func _on_attribute_changed(
	attribute_name: StringName, _old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	match attribute_name:
		BattlerAttributes.HEALTH:
			_life.target_value = new_value
		BattlerAttributes.ENERGY:
			_energy.value = new_value
		BattlerAttributes.MAX_HEALTH:
			_life.max_value = new_value
		BattlerAttributes.MAX_ENERGY:
			_energy.max_value = new_value
