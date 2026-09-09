## What a character in this sample is made of.
##
## Five attributes and the two clamps that keep them honest, which is the whole
## shape of a production set: health may not exceed max health, in the durable
## value as well as the derived one. Without the base clamp, 500 damage against
## 100 health leaves the base at -400 and a full heal brings the character back
## to nothing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name SampleAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const MANA: StringName = &"mana"
const MAX_MANA: StringName = &"max_mana"
const ATTACK: StringName = &"attack"

@export var health: AttributeData = null
@export var max_health: AttributeData = null
@export var mana: AttributeData = null
@export var max_mana: AttributeData = null
@export var attack: AttributeData = null


## Fresh instances per set. Exported defaults are evaluated once, so two
## characters built from this script would share one health value.
func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	mana = AttributeData.new(50.0)
	max_mana = AttributeData.new(50.0)
	attack = AttributeData.new(10.0)


func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _clamped(attribute_name, proposed)


func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _clamped(attribute_name, proposed)


## Health between nothing and the maximum, mana likewise. Nothing else is
## clamped: attack is a stat a buff is meant to raise.
func _clamped(attribute_name: StringName, proposed: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(proposed, 0.0, max_health.base_value)
		MANA:
			return clampf(proposed, 0.0, max_mana.base_value)
	return proposed
