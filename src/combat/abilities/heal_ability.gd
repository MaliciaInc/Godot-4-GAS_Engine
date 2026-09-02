## A hop, and something good lands on whoever it was aimed at.
##
## Identical in shape to an attack; the difference is entirely in the payload,
## which is the point of putting the numbers in the effect rather than in the
## choreography.
##
## @meta_license: MIT
class_name HealAbility extends BattlerAbility

@export var heal_amount: float = 50.0
@export var hop_height: float = 250.0
@export var hop_time: float = 0.22


func _perform() -> void:
	await _lunge(Vector2(0.0, -hop_height), hop_time, hop_time)


func _payload() -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = heal_amount

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = BattlerAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
