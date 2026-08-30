## Builds GameplayEffect definitions for tests.
##
## This is a factory, not a second engine. It assembles Resources and computes
## nothing: a factory that did its own arithmetic would let a test pass against
## the factory's idea of the maths rather than the engine's.
##
## @meta_license: MIT
class_name TestEffectFactory extends RefCounted


#region Modifiers
## One modifier. Several may target the same attribute; the engine tells them
## apart by index, which is exactly what the suite has to prove.
static func modifier(
	attribute_name: StringName, operation: GameplayEffectModifier.Operation, magnitude: float
) -> GameplayEffectModifier:
	var mod: GameplayEffectModifier = GameplayEffectModifier.new()
	mod.attribute_name = String(attribute_name)
	mod.operation = operation
	mod.magnitude = magnitude
	return mod


static func add(attribute_name: StringName, magnitude: float) -> GameplayEffectModifier:
	return modifier(attribute_name, GameplayEffectModifier.Operation.ADD, magnitude)


static func multiply(attribute_name: StringName, magnitude: float) -> GameplayEffectModifier:
	return modifier(attribute_name, GameplayEffectModifier.Operation.MULTIPLY, magnitude)


static func divide(attribute_name: StringName, magnitude: float) -> GameplayEffectModifier:
	return modifier(attribute_name, GameplayEffectModifier.Operation.DIVIDE, magnitude)


static func override(attribute_name: StringName, magnitude: float) -> GameplayEffectModifier:
	return modifier(attribute_name, GameplayEffectModifier.Operation.OVERRIDE, magnitude)
#endregion


#region Effects
static func instant(modifiers: Array[GameplayEffectModifier]) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = modifiers
	return effect


static func duration(
	modifiers: Array[GameplayEffectModifier], seconds: float
) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = seconds
	effect.modifiers = modifiers
	return effect


static func infinite(modifiers: Array[GameplayEffectModifier]) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INFINITE
	effect.modifiers = modifiers
	return effect


## A periodic effect. One effect cannot be both periodic and a
## persistent contributor, so these modifiers mutate the base on each tick.
static func periodic(
	modifiers: Array[GameplayEffectModifier], seconds: float, period: float
) -> GameplayEffect:
	var effect: GameplayEffect = duration(modifiers, seconds)
	effect.period = period
	return effect


static func infinite_periodic(
	modifiers: Array[GameplayEffectModifier], period: float
) -> GameplayEffect:
	var effect: GameplayEffect = infinite(modifiers)
	effect.period = period
	return effect


static func turn_based(
	modifiers: Array[GameplayEffectModifier], turns: int, period: float = 0.0
) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.TURN_BASED
	effect.duration_turns = turns
	effect.period = period
	effect.modifiers = modifiers
	return effect
#endregion


#region Decorators
static func granting(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.granted_tags = tags
	return effect


static func refreshing(effect: GameplayEffect) -> GameplayEffect:
	effect.stacking_policy = GameplayEffect.StackingPolicy.REFRESH_DURATION
	return effect


static func requiring(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.application_required_tags = tags
	return effect


static func blocked_by(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.application_ignore_tags = tags
	return effect


static func with_events(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.event_tags = tags
	return effect


static func with_application_cues(
	effect: GameplayEffect, tags: Array[StringName]
) -> GameplayEffect:
	effect.application_cue_tags = tags
	return effect
#endregion


#region Application helpers
## Apply an effect to an ASC as if it came from a source entity.
static func apply(
	target: AbilitySystemComponent,
	effect: GameplayEffect,
	source: Node = null,
	level: float = 1.0
) -> ActiveGameplayEffect:
	var instigator: Node = source if source != null else target.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(instigator)
	return target.apply_effect_spec(GameplayEffectSpec.new(effect, context, level))
#endregion
