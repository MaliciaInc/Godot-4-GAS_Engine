## The attribute set the test suite is built on.
##
## Shaped like a production set, not like a stub: five real attributes and real
## dependency clamps, so the tests exercise the same code path a game would.
##
## Both clamp hooks are implemented, and they guard different things:
##
##   pre_attribute_base_change  keeps the durable value in range
##   pre_attribute_change       keeps the derived value in range
##
## Section 3.9's policy: Health may not exceed MaxHealth.current, in base as
## well as in current. When a MaxHealth buff expires and Health is above the new
## maximum, the excess is lost from the base and reapplying the buff does not
## bring it back. Health that was only ever borrowed does not become durable.
##
## @meta_license: MIT
@tool
class_name TestAttributeSet extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"
const MANA: StringName = &"mana"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)
@export var attack: AttributeData = AttributeData.new(10.0)
@export var defense: AttributeData = AttributeData.new(5.0)
@export var mana: AttributeData = AttributeData.new(50.0)


func _init() -> void:
	# Fresh instances per set. Without this, `@export` defaults evaluated once
	# would be shared by every set built from this script.
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	attack = AttributeData.new(10.0)
	defense = AttributeData.new(5.0)
	mana = AttributeData.new(50.0)


## Guard the durable value.
##
## Health floors at zero here, which is what stops 500 damage against 100 health
## leaving `base = -400` and making a later heal of 30 arrive at 0 instead of 30.
func pre_attribute_base_change(attribute_name: StringName, proposed_base_value: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(proposed_base_value, 0.0, max_health.current_value)
		MAX_HEALTH, MANA, ATTACK, DEFENSE:
			return maxf(proposed_base_value, 0.0)
	return proposed_base_value


## Guard the derived value.
func pre_attribute_change(attribute_name: StringName, proposed_current_value: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(proposed_current_value, 0.0, max_health.current_value)
		MAX_HEALTH, MANA, ATTACK, DEFENSE:
			return maxf(proposed_current_value, 0.0)
	return proposed_current_value


## React to a dependency: when MaxHealth moves, Health may now be out of range.
##
## The base is trimmed too, not just the current. Trimming only the current
## would leave the durable value holding health the character cannot have, and
## it would reappear the moment MaxHealth rose again.
func post_attribute_change(
	_asc: Node, attribute_name: StringName, _old_value: float, new_value: float
) -> void:
	if attribute_name != MAX_HEALTH:
		return
	if health.base_value > new_value:
		health.base_value = new_value
	if health.current_value > new_value:
		health.current_value = new_value
