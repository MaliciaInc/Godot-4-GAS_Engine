## Close the distance, hit, come back.
##
## @meta_license: MIT
class_name MeleeAttackAbility extends DamageAbility

## How far in front of the target the caster stops. Far enough to read as a
## charge, near enough that the hit looks like contact.
@export var reach: float = 350.0
@export var travel_time: float = 0.35


func _perform() -> void:
	# Stop on the near side of the target, whichever side that is.
	var caster: Battler = owner_asc.get_parent() as Battler
	if caster == null or targets.is_empty():
		return
	var target_x: float = targets[0].position.x
	var offset: Vector2 = Vector2(target_x - caster.position.x - reach * _facing(), 0.0)
	await _lunge(offset, travel_time, travel_time)
