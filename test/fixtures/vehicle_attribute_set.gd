## A second set that also declares `health`, because entities carry more than one.
##
## A character and the vehicle they are driving; a body and the shield around
## it; a creature and the armour bolted to it. Each is its own set with its own
## clamps, and both call the thing that runs out `health` - because that is what
## it is called.
##
## This exists to make `health` ambiguous on purpose, which is the case a bare
## attribute name cannot survive.
##
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name VehicleAttributeSet extends AttributeSet

const HEALTH: StringName = &"health"
const FUEL: StringName = &"fuel"

@export var health: AttributeData = AttributeData.new(500.0)
@export var fuel: AttributeData = AttributeData.new(80.0)


func _init() -> void:
	# Fresh instances per set, for the reason TestAttributeSet gives: `@export`
	# defaults are evaluated once and would otherwise be shared.
	health = AttributeData.new(500.0)
	fuel = AttributeData.new(80.0)


## Floored, and nothing else. The point of this set is the name it shares, not
## the rules it keeps.
func pre_attribute_base_change(
	_attribute_name: StringName, proposed_base_value: float
) -> float:
	return maxf(proposed_base_value, 0.0)
