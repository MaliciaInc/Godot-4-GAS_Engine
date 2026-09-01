## A hop, and something good lands on whoever it was aimed at.
##
## Identical in shape to an attack; the difference is entirely in the payload,
## which is the point of putting the numbers in the effect rather than here.
##
## @meta_license: MIT
class_name HealAbility extends BattlerAbility

@export var hop_height: float = 250.0
@export var hop_time: float = 0.15


func _perform() -> void:
	await _lunge(Vector2(0.0, -hop_height), hop_time, hop_time)
