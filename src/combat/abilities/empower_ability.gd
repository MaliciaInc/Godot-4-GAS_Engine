## A buff, and the reason buffs are effects rather than arithmetic.
##
## Its payload registers contributions to the target's standing for as long as
## it lasts. Nothing writes a bigger number into `attack`; the engine folds the
## contribution in while the effect lives and withdraws it when the effect ends.
## That is what lets two of these stack, expire out of order, and still leave the
## target on the number it should be on.
##
## @meta_license: MIT
class_name EmpowerAbility extends BattlerAbility

@export var hop_height: float = 250.0
@export var hop_time: float = 0.15


func _perform() -> void:
	await _lunge(Vector2(0.0, -hop_height), hop_time, hop_time)
