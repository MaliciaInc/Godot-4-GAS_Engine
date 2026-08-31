## Builds GameplayEffect definitions for tests.
##
## This is a factory, not a second engine. It assembles Resources and computes
## nothing: a factory that did its own arithmetic would let a test pass against
## the factory's idea of the maths rather than the engine's.
##
## @meta_license: MIT
class_name TestEffectFactory extends RefCounted


#region Modifiers
## One modifier, its magnitude a flat GameplayScalableMagnitude. Several
## modifiers may target the same attribute; the engine tells them apart by
## index, which is exactly what the suite has to prove.
static func modifier(
	attribute_name: StringName, operation: GameplayEffectModifier.Operation, magnitude: float
) -> GameplayEffectModifier:
	var mod: GameplayEffectModifier = GameplayEffectModifier.new()
	mod.attribute_name = attribute_name
	mod.operation = operation
	mod.magnitude = scalable_magnitude(magnitude)
	return mod


## A flat GameplayScalableMagnitude, for a modifier or any other authoring
## surface that takes one directly.
static func scalable_magnitude(value: float, curve: Curve = null) -> GameplayScalableMagnitude:
	var scalable_float: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable_float.value = value
	scalable_float.scaling_curve = curve
	var scalable: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	scalable.value = scalable_float
	return scalable


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
	var component: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	component.granted_tags = tags
	effect.components.append(component)
	return effect


static func refreshing(effect: GameplayEffect) -> GameplayEffect:
	effect.stacking_policy = GameplayEffect.StackingPolicy.REFRESH_DURATION
	return effect


## On a successful application, purge every active effect granting ANY of
## `tags` - the exact F2 semantics of the removed remove_effects_with_tags
## field, now expressed as a GameplayEffectRemoveOtherEffectsComponent query.
static func removing_effects_with_tags(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	var any_of: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	any_of.operator = GameplayTagQueryExpression.Operator.ANY
	any_of.tags = tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = any_of

	var remover: GameplayEffectRemoveOtherEffectsComponent = GameplayEffectRemoveOtherEffectsComponent.new()
	remover.query = GameplayEffectQuery.new()
	remover.query.granted_tags = query
	effect.components.append(remover)
	return effect


## `requiring()`/`blocked_by()` share one GameplayEffectTargetTagRequirementsComponent
## per effect: an ALL root with one ALL child per requiring() call and one
## NONE child per blocked_by() call, so calling both on the same effect - in
## either order - reconstructs F2's exact "must have all of these, must have
## none of those" semantics as one query.
static func requiring(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	var required: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	required.operator = GameplayTagQueryExpression.Operator.ALL
	required.tags = tags
	_requirements_root(effect).expressions.append(required)
	return effect


static func blocked_by(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	var blocked: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	blocked.operator = GameplayTagQueryExpression.Operator.NONE
	blocked.tags = tags
	_requirements_root(effect).expressions.append(blocked)
	return effect


static func _requirements_root(effect: GameplayEffect) -> GameplayTagQueryExpression:
	for component: GameplayEffectComponent in effect.components:
		var existing: GameplayEffectTargetTagRequirementsComponent = (
			component as GameplayEffectTargetTagRequirementsComponent
		)
		if existing != null:
			return existing.application_query.root
	var created: GameplayEffectTargetTagRequirementsComponent = GameplayEffectTargetTagRequirementsComponent.new()
	created.application_query = GameplayTagQuery.new()
	created.application_query.root = GameplayTagQueryExpression.new()
	created.application_query.root.operator = GameplayTagQueryExpression.Operator.ALL
	effect.components.append(created)
	return created.application_query.root


static func with_events(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.event_tags = tags
	return effect


static func with_application_cues(
	effect: GameplayEffect, tags: Array[StringName]
) -> GameplayEffect:
	effect.application_cue_tags = tags
	return effect


## Attaches a GameplayEffectImmunityComponent: while `effect` is active on a
## target, any incoming application `query` matches is refused.
static func immune_to(effect: GameplayEffect, query: GameplayEffectQuery) -> GameplayEffect:
	var immunity: GameplayEffectImmunityComponent = GameplayEffectImmunityComponent.new()
	immunity.incoming_effect_query = query
	effect.components.append(immunity)
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


## Same as apply(), but returns the full typed result - for asserting on a
## refusal's status rather than only "was there an active effect back".
static func apply_result(
	target: AbilitySystemComponent,
	effect: GameplayEffect,
	source: Node = null,
	level: float = 1.0
) -> GameplayEffectApplicationResult:
	var instigator: Node = source if source != null else target.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(instigator)
	return target.apply_effect_spec_result(GameplayEffectSpec.new(effect, context, level))
#endregion


#region Captures
## One attribute capture declaration, for a GameplayAttributeBasedMagnitude or
## an execution calculation to register.
static func capture_definition(
	actor: GameplayAttributeCaptureDefinition.Actor,
	attribute_name: StringName,
	value: GameplayAttributeCaptureDefinition.Value = GameplayAttributeCaptureDefinition.Value.CURRENT,
	policy: GameplayAttributeCaptureDefinition.Policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT
) -> GameplayAttributeCaptureDefinition:
	var definition: GameplayAttributeCaptureDefinition = GameplayAttributeCaptureDefinition.new()
	definition.actor = actor
	definition.attribute_name = attribute_name
	definition.value = value
	definition.policy = policy
	return definition
#endregion
