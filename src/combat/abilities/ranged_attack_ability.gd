## Throw from where you stand, or nearly.
##
## The caster steps toward the target rather than onto it: the payload lands at
## the apex, so the hit reads as the thing arriving, not as the caster touching.
##
## @meta_license: MIT
class_name RangedAttackAbility extends BattlerAbility

@export var travel_distance: float = 350.0
@export var travel_time: float = 0.25
@export var return_time: float = 0.25


func _perform() -> void:
	await _lunge(Vector2(travel_distance * _facing(), 0.0), travel_time, return_time)
