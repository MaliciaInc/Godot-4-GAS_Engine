## A buff, and the reason buffs are effects rather than arithmetic.
##
## Its payload registers contributions to the target's standing for as long as
## it lasts. Nothing writes a bigger number into `attack`; the engine folds the
## contribution in while the effect lives and withdraws it when the effect ends.
## That is what lets two of these stack, expire out of order, and still leave
## the target on the number it should be on.
##
## Infinite by design - this fight's buffs last the fight. Giving it a duration
## is one exported number away, and nothing else has to change.
##
## @meta_license: MIT
class_name EmpowerAbility extends BattlerAbility

@export var added_value: float = 10.0
@export var hop_height: float = 250.0
@export var hop_time: float = 0.22


func _perform() -> void:
	await _lunge(Vector2(0.0, -hop_height), hop_time, hop_time)


func _payload() -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INFINITE
	effect.modifiers = [
		_boost(BattlerAttributes.ATTACK), _boost(BattlerAttributes.HIT_CHANCE)
	] as Array[GameplayEffectModifier]
	return effect


func _boost(attribute_name: StringName) -> GameplayEffectModifier:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = added_value

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = attribute_name
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude
	return modifier
