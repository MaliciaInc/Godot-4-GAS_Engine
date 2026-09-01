## Orchestrates a GameplayEffect's components through one application:
## validate, can_apply, prepare/discard, and the applied/executed/removed
## notifications.
##
## Split out of GameplayEffectRuntime the same way AbilityInstancingRuntime is
## split out of AbilityRuntime: a focused collaborator, composed into the
## parent rather than folded inside it. This is not a second effect runtime -
## it owns no active-effect registry of its own.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectComponentRuntime extends RefCounted

## The one RNG every random-dependent component (ChanceToApply) draws from.
## A test seeds this instance, through the same composition chain that
## reaches it, for a deterministic roll - never the engine's global random
## state, which no test can pin down.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func build_request(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayEffectComponentApplyRequest:
	var request: GameplayEffectComponentApplyRequest = GameplayEffectComponentApplyRequest.new()
	request.spec = spec
	request.target_asc = target_asc
	request.source_asc = spec.source_asc if spec != null else null
	request.rng = rng
	return request


#region Preflight
## Whether every component of `effect` is a legal definition.
func validate_all(effect: GameplayEffect) -> GameplayEffectComponentValidationResult:
	if effect == null:
		return GameplayEffectComponentValidationResult.ok()
	for component: GameplayEffectComponent in effect.components:
		if component == null:
			continue
		var result: GameplayEffectComponentValidationResult = component.validate_definition(effect)
		if not result.is_ok():
			return result
	return GameplayEffectComponentValidationResult.ok()


## The first denial among every component's can_apply(), in declared order,
## or an allowing decision when none deny.
func can_apply_all(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	if request.spec == null or request.spec.effect_def == null:
		return GameplayEffectComponentDecision.allow()
	for component: GameplayEffectComponent in request.spec.effect_def.components:
		if component == null:
			continue
		var decision: GameplayEffectComponentDecision = component.can_apply(request)
		if not decision.is_allowed():
			return decision
	return GameplayEffectComponentDecision.allow()
#endregion


#region Preparation
## Prepare every component in declared order, appending one state per
## component to `states` (null for a component with nothing to prepare).
## Returns false on the first rejection, having already discarded everything
## prepared so far, in reverse order, and cleared `states` - the caller's
## cue to refuse the whole application before anything commits.
func prepare_all(
	request: GameplayEffectComponentApplyRequest, states: Array[GameplayEffectComponentState]
) -> bool:
	if request.spec == null or request.spec.effect_def == null:
		return true
	var components: Array[GameplayEffectComponent] = request.spec.effect_def.components
	for component: GameplayEffectComponent in components:
		if component == null:
			states.append(null)
			continue
		var prepared: GameplayEffectComponentPreparationResult = component.prepare_application(request)
		if not prepared.is_ok():
			_discard(components, states)
			states.clear()
			return false
		states.append(prepared.state)
	return true


func _discard(
	components: Array[GameplayEffectComponent], states: Array[GameplayEffectComponentState]
) -> void:
	for index: int in range(states.size() - 1, -1, -1):
		var component: GameplayEffectComponent = components[index]
		if component != null:
			component.discard_prepared(states[index])


## Discard every state prepare_all() built for `spec`, in reverse order -
## used when something after preparation (a failed capture, a failed
## evaluation) refuses the whole application. Clears the spec's prepared
## states afterward, so a stale reference cannot leak into a later apply().
func discard_for(spec: GameplayEffectSpec) -> void:
	if spec == null or spec.effect_def == null:
		return
	_discard(spec.effect_def.components, spec.prepared_component_states())
	spec.set_prepared_component_states([])
#endregion


#region Notifications
func notify_applied(
	spec: GameplayEffectSpec, active_effect: ActiveGameplayEffect, target_asc: AbilitySystemComponent
) -> void:
	_notify_runtime(spec, active_effect, target_asc, func(c: GameplayEffectComponent, ctx: GameplayEffectComponentRuntimeContext) -> void: c.on_effect_applied(ctx))


func notify_executed(
	spec: GameplayEffectSpec, active_effect: ActiveGameplayEffect, target_asc: AbilitySystemComponent
) -> void:
	_notify_runtime(spec, active_effect, target_asc, func(c: GameplayEffectComponent, ctx: GameplayEffectComponentRuntimeContext) -> void: c.on_effect_executed(ctx))


func _notify_runtime(
	spec: GameplayEffectSpec,
	active_effect: ActiveGameplayEffect,
	target_asc: AbilitySystemComponent,
	callback: Callable
) -> void:
	if spec == null or spec.effect_def == null:
		return
	var components: Array[GameplayEffectComponent] = spec.effect_def.components
	var states: Array[GameplayEffectComponentState] = (
		active_effect.component_states if active_effect != null else []
	)
	for index: int in components.size():
		var component: GameplayEffectComponent = components[index]
		if component == null:
			continue
		var context: GameplayEffectComponentRuntimeContext = GameplayEffectComponentRuntimeContext.new()
		context.spec = spec
		context.active_effect = active_effect
		context.target_asc = target_asc
		context.component_index = index
		context.component_state = states[index] if index < states.size() else null
		callback.call(component, context)


func notify_removed(
	spec: GameplayEffectSpec, active_effect: ActiveGameplayEffect, target_asc: AbilitySystemComponent
) -> void:
	if spec == null or spec.effect_def == null:
		return
	var components: Array[GameplayEffectComponent] = spec.effect_def.components
	var states: Array[GameplayEffectComponentState] = (
		active_effect.component_states if active_effect != null else []
	)
	for index: int in components.size():
		var component: GameplayEffectComponent = components[index]
		if component == null:
			continue
		var context: GameplayEffectComponentRemovalContext = GameplayEffectComponentRemovalContext.new()
		context.spec = spec
		context.active_effect = active_effect
		context.target_asc = target_asc
		context.component_index = index
		context.component_state = states[index] if index < states.size() else null
		component.on_effect_removed(context)
#endregion
