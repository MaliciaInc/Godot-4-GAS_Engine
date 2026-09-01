## Close the distance, hit, come back.
##
## @meta_license: MIT
class_name MeleeAttackAbility extends BattlerAbility

## How far in front of the target the caster stops. Far enough to read as a
## charge, near enough that the hit looks like contact.
@export var reach: float = 350.0
@export var travel_time: float = 0.25


func _perform() -> void:
	# Stop on the near side of the target, whichever side that is.
	var target_x: float = targets[0].position.x
	var caster: Battler = owner_asc.get_parent() as Battler
	var offset: Vector2 = Vector2(target_x - caster.position.x - reach * _facing(), 0.0)
	await _lunge(offset, travel_time, travel_time)
