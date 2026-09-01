## Shared by everything that hurts.
##
## Damage is the caster's `attack` plus the ability's own bite, applied as a
## negative contribution to the target's health. Reading `attack` through a
## capture rather than baking it in at author time is what makes an attack buff
## matter: the number is resolved when the blow lands, not when the ability was
## written.
##
## @meta_license: MIT
@abstract
class_name DamageAbility extends BattlerAbility

## What this ability adds on top of the caster's attack.
@export var base_damage: float = 50.0


func _payload() -> GameplayEffect:
	var from_attack: GameplayAttributeCaptureDefinition = GameplayAttributeCaptureDefinition.new()
	from_attack.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
	from_attack.attribute_name = BattlerAttributes.ATTACK
	from_attack.value = GameplayAttributeCaptureDefinition.Value.CURRENT
	# Snapshot: the blow is as hard as the caster was when it swung, so a buff
	# expiring mid-animation cannot weaken a hit already in the air.
	from_attack.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

	var bite: GameplayScalableFloat = GameplayScalableFloat.new()
	bite.value = base_damage
	var negate: GameplayScalableFloat = GameplayScalableFloat.new()
	negate.value = -1.0

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = from_attack
	magnitude.pre_add = bite      # attack + base_damage
	magnitude.coefficient = negate # ...taken away, not given

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = BattlerAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
