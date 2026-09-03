## The AttributeSet the README's quick start prints, kept runnable.
##
## The quick start claims a newcomer can go from an empty scene to a fireball
## that lands. A claim in a README is a claim nobody checks, so it is written
## here as code the suite executes and printed there verbatim.
##
## The only difference from the printed version is the name: the README calls
## it `HeroAttributes`, which is what a reader would call it in their own
## project, while this repository already spends several class names on test
## doubles and cannot spend that one twice.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name QuickStartAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)


## Fresh instances per set. Without this the `@export` defaults are evaluated
## once and every character built from this script shares one health pool -
## the whole party dies the moment anyone does.
func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)


## Asked before a durable write lands, so an overkill hit is clamped at the
## source instead of after several systems have already seen a negative pool.
func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


## Asked again after modifiers compose, so a `max_health` buff that expires
## cannot leave `health` standing above the ceiling it just lost.
func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func _bounded(attribute_name: StringName, value: float) -> float:
	if attribute_name == HEALTH:
		return clampf(value, 0.0, max_health.current_value)
	return maxf(value, 0.0)
