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


## The F2 REFRESH_DURATION shape: one logical instance per target, never a
## second stack, reapplication restarts duration/period. Expressed now as a
## stack limited to 1 - overflow (any reapplication past the first) is
## accepted by default and settles as a pure refresh, never denied.
static func refreshing(effect: GameplayEffect) -> GameplayEffect:
	effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
	effect.stack_limit_count = 1
	effect.stack_duration_refresh_policy = GameplayEffect.StackDurationRefreshPolicy.ON_SUCCESSFUL_APPLICATION
	effect.stack_period_reset_policy = GameplayEffect.StackPeriodResetPolicy.ON_SUCCESSFUL_APPLICATION
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
	var component: GameplayEffectTargetTagRequirementsComponent = _target_tag_requirements(effect)
	if component.application_query == null:
		component.application_query = GameplayTagQuery.new()
		component.application_query.root = GameplayTagQueryExpression.new()
		component.application_query.root.operator = GameplayTagQueryExpression.Operator.ALL
	return component.application_query.root


## While active, `effect` stays uninhibited only while `tags` are held -
## losing them detaches its contributions/tags without removing it.
static func with_ongoing_requirement(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	_target_tag_requirements(effect).ongoing_query = _all_tag_query(tags)
	return effect


## `effect` removes itself outright once `tags` are held - and, checked at
## application time too, refuses to apply if they already are.
static func with_removal_requirement(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	_target_tag_requirements(effect).removal_query = _all_tag_query(tags)
	return effect


## `requiring()`/`blocked_by()`/`with_ongoing_requirement()`/
## `with_removal_requirement()` all share one component per effect.
static func _target_tag_requirements(effect: GameplayEffect) -> GameplayEffectTargetTagRequirementsComponent:
	for component: GameplayEffectComponent in effect.components:
		var existing: GameplayEffectTargetTagRequirementsComponent = (
			component as GameplayEffectTargetTagRequirementsComponent
		)
		if existing != null:
			return existing
	var created: GameplayEffectTargetTagRequirementsComponent = GameplayEffectTargetTagRequirementsComponent.new()
	effect.components.append(created)
	return created


static func _all_tag_query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


static func with_events(effect: GameplayEffect, tags: Array[StringName]) -> GameplayEffect:
	effect.event_tags = tags
	return effect


static func with_application_cues(
	effect: GameplayEffect, tags: Array[StringName]
) -> GameplayEffect:
	return _with_cue_bindings(effect, tags, GameplayCueBinding.Type.EXECUTED_ON_APPLICATION)


static func with_periodic_cues(
	effect: GameplayEffect, tags: Array[StringName]
) -> GameplayEffect:
	return _with_cue_bindings(effect, tags, GameplayCueBinding.Type.EXECUTED_ON_PERIODIC)


static func with_persistent_cues(
	effect: GameplayEffect, tags: Array[StringName]
) -> GameplayEffect:
	return _with_cue_bindings(effect, tags, GameplayCueBinding.Type.PERSISTENT)


static func _with_cue_bindings(
	effect: GameplayEffect, tags: Array[StringName], type: GameplayCueBinding.Type
) -> GameplayEffect:
	for tag: StringName in tags:
		var binding: GameplayCueBinding = GameplayCueBinding.new()
		binding.cue_tag = tag
		binding.type = type
		effect.cues.append(binding)
	return effect


## Attaches a GameplayEffectImmunityComponent: while `effect` is active on a
## target, any incoming application `query` matches is refused.
static func immune_to(effect: GameplayEffect, query: GameplayEffectQuery) -> GameplayEffect:
	var immunity: GameplayEffectImmunityComponent = GameplayEffectImmunityComponent.new()
	immunity.incoming_effect_query = query
	effect.components.append(immunity)
	return effect


## Turns `effect` into a stacked effect under `type`. `limit` <= 0 is
## unlimited.
static func stacked(
	effect: GameplayEffect,
	stacking_type: GameplayEffect.StackingType,
	limit: int = 0,
	factor_in_count: bool = false
) -> GameplayEffect:
	effect.stacking_type = stacking_type
	effect.stack_limit_count = limit
	effect.factor_in_stack_count = factor_in_count
	return effect


static func with_overflow_effects(
	effect: GameplayEffect,
	on_overflow: Array[GameplayEffect],
	deny_application: bool = false,
	clear_on_overflow: bool = false
) -> GameplayEffect:
	effect.overflow_effects = on_overflow
	effect.deny_overflow_application = deny_application
	effect.clear_stack_on_overflow = clear_on_overflow
	return effect


static func with_stack_expiration_policy(
	effect: GameplayEffect, expiration_policy: GameplayEffect.StackExpirationPolicy
) -> GameplayEffect:
	effect.stack_expiration_policy = expiration_policy
	return effect


static func with_stack_clock_policies(
	effect: GameplayEffect,
	duration_policy: GameplayEffect.StackDurationRefreshPolicy = GameplayEffect.StackDurationRefreshPolicy.NEVER,
	period_policy: GameplayEffect.StackPeriodResetPolicy = GameplayEffect.StackPeriodResetPolicy.NEVER
) -> GameplayEffect:
	effect.stack_duration_refresh_policy = duration_policy
	effect.stack_period_reset_policy = period_policy
	return effect


static func conditional_effect(
	child_effect: GameplayEffect, target_query: GameplayTagQuery = null, source_query: GameplayTagQuery = null
) -> GameplayEffectConditionalEffect:
	var conditional: GameplayEffectConditionalEffect = GameplayEffectConditionalEffect.new()
	conditional.effect = child_effect
	conditional.target_query = target_query
	conditional.source_query = source_query
	return conditional


static func with_additional_effects(
	effect: GameplayEffect,
	on_application: Array[GameplayEffectConditionalEffect] = [],
	on_natural_expiration: Array[GameplayEffectConditionalEffect] = [],
	on_premature_removal: Array[GameplayEffectConditionalEffect] = [],
	on_any_removal: Array[GameplayEffectConditionalEffect] = []
) -> GameplayEffect:
	var component: GameplayEffectAdditionalEffectsComponent = GameplayEffectAdditionalEffectsComponent.new()
	component.on_application = on_application
	component.on_natural_expiration = on_natural_expiration
	component.on_premature_removal = on_premature_removal
	component.on_any_removal = on_any_removal
	effect.components.append(component)
	return effect


## Packs a fresh ability instance into a scene, for a GameplayEffectAbilityGrant.
## Same pack-then-free rule as TestAbilityFactory.give(): packing captures
## state without consuming the Node, so the template is freed immediately -
## it was never added to a tree, and nothing else would free it.
static func ability_scene(ability: GameplayAbility) -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	var pack_error: Error = scene.pack(ability)
	assert(pack_error == OK, "TestEffectFactory: packing a fixture ability failed")
	ability.free()
	return scene


## Attaches one more grant to `effect`'s GameplayEffectGrantAbilitiesComponent,
## creating it on first use.
static func granting_ability(
	effect: GameplayEffect,
	scene: PackedScene,
	removal_policy: GameplayEffectAbilityGrant.RemovalPolicy = GameplayEffectAbilityGrant.RemovalPolicy.CANCEL_AND_REMOVE_ON_EFFECT_END,
	input_id: int = -1
) -> GameplayEffect:
	var grant: GameplayEffectAbilityGrant = GameplayEffectAbilityGrant.new()
	grant.ability_scene = scene
	grant.removal_policy = removal_policy
	grant.input_id = input_id

	var component: GameplayEffectGrantAbilitiesComponent = null
	for existing: GameplayEffectComponent in effect.components:
		var found: GameplayEffectGrantAbilitiesComponent = existing as GameplayEffectGrantAbilitiesComponent
		if found != null:
			component = found
	if component == null:
		component = GameplayEffectGrantAbilitiesComponent.new()
		effect.components.append(component)
	component.grants.append(grant)
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
