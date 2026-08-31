## Grants abilities while this effect is active on the target, and retires
## them per grant when it is removed - a buff, equipment, or a transformation
## that comes with kit, without an ad hoc script watching signals.
##
## Reuses Task 4's grant pipeline exactly: `prepare_ability_grant` in
## `prepare_application()`, `commit_prepared_grant` in `on_effect_applied()`,
## `discard_prepared_grant`-equivalent cleanup in `discard_prepared()`. Never
## a second validator, never a second PreparedAbilityGrant-shaped type.
##
## A stack reapplication grants once per active effect, never once per join:
## `GameplayEffectComponentApplyRequest.existing_active_effect` set means
## this join already has a committed GameplayEffectGrantAbilitiesState -
## prepare_application() skips straight to ok() with no new state, and
## GameplayEffectStackingRuntime keeps the existing one in that slot rather
## than erasing it.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectGrantAbilitiesComponent extends GameplayEffectComponent

@export var grants: Array[GameplayEffectAbilityGrant] = []


func prepare_application(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentPreparationResult:
	if grants.is_empty() or request.existing_active_effect != null:
		return GameplayEffectComponentPreparationResult.ok()
	if request.target_asc == null or request.target_asc.ability_runtime == null:
		return GameplayEffectComponentPreparationResult.rejected("no ability runtime on the target")

	var state: GameplayEffectGrantAbilitiesState = GameplayEffectGrantAbilitiesState.new()
	for grant: GameplayEffectAbilityGrant in grants:
		if not _prepare_one(grant, request, state):
			_discard_all(state, request.target_asc)
			return GameplayEffectComponentPreparationResult.rejected("a granted ability failed preflight")
	return GameplayEffectComponentPreparationResult.ok(state)


func _prepare_one(
	grant: GameplayEffectAbilityGrant,
	request: GameplayEffectComponentApplyRequest,
	state: GameplayEffectGrantAbilitiesState
) -> bool:
	if grant == null or grant.ability_scene == null:
		return false
	var level: float = grant.level.evaluate(request.spec.level) if grant.level != null else request.spec.level
	if not is_finite(level) or level <= 0.0:
		return false

	var source: GameplayAbilityEffectSource = GameplayAbilityEffectSource.new()
	var prepared: PreparedAbilityGrant = request.target_asc.ability_runtime.prepare_ability_grant(
		grant.ability_scene, level, grant.input_id, source
	)
	if not prepared.validation.is_ok():
		request.target_asc.ability_runtime.discard_prepared_grant(prepared)
		return false

	state.prepared_grants.append(prepared)
	state.sources.append(source)
	state.policies.append(grant.removal_policy)
	return true


func _discard_all(state: GameplayEffectGrantAbilitiesState, target_asc: AbilitySystemComponent) -> void:
	for prepared: PreparedAbilityGrant in state.prepared_grants:
		target_asc.ability_runtime.discard_prepared_grant(prepared)


## Frees a still-unconsumed probe directly rather than through
## `discard_prepared_grant()` - this hook is not handed the ability runtime
## that call needs, and freeing a never-treed probe is exactly what it does.
func discard_prepared(state: GameplayEffectComponentState) -> void:
	var grant_state: GameplayEffectGrantAbilitiesState = state as GameplayEffectGrantAbilitiesState
	if grant_state == null:
		return
	for prepared: PreparedAbilityGrant in grant_state.prepared_grants:
		if prepared != null and not prepared.consumed:
			prepared.consumed = true
			if prepared.probe != null:
				prepared.probe.free()


func on_effect_applied(context: GameplayEffectComponentRuntimeContext) -> void:
	var state: GameplayEffectGrantAbilitiesState = context.component_state as GameplayEffectGrantAbilitiesState
	if state == null or state.committed:
		return
	if context.target_asc == null or context.target_asc.ability_runtime == null:
		return
	state.committed = true

	var runtime: AbilityRuntime = context.target_asc.ability_runtime
	var committed_handles: Array[GameplayAbilityHandle] = []
	for i: int in state.prepared_grants.size():
		state.sources[i].effect_handle = context.active_effect.handle
		var handle: GameplayAbilityHandle = runtime.commit_prepared_grant(state.prepared_grants[i])
		if not handle.is_valid():
			_unwind_finalization_failure(context, runtime, committed_handles, state, i)
			return
		committed_handles.append(handle)
		context.active_effect.granted_ability_handles.append(handle)


## Finalization failing after a validated prepare is an invariant violation,
## never a normal gameplay branch - retire everything already committed,
## free everything still prepared, and retire the granting effect itself
## with a reason that fires no Additional Effects chain. Deferred so this
## never removes the very active effect still mid-commit on the call stack
## above it.
func _unwind_finalization_failure(
	context: GameplayEffectComponentRuntimeContext,
	runtime: AbilityRuntime,
	already_committed: Array[GameplayAbilityHandle],
	state: GameplayEffectGrantAbilitiesState,
	failed_at: int
) -> void:
	push_error("GodotGAS: ability grant finalization failed after a validated prepare; retiring the granting effect.")
	for handle: GameplayAbilityHandle in already_committed:
		runtime.remove_ability(handle)
	for i: int in range(failed_at, state.prepared_grants.size()):
		var prepared: PreparedAbilityGrant = state.prepared_grants[i]
		if prepared != null and not prepared.consumed:
			prepared.consumed = true
			if prepared.probe != null:
				prepared.probe.free()
	if context.target_asc != null:
		context.target_asc.effects.call_deferred(
			"remove", context.active_effect, ActiveGameplayEffect.RemovalReason.GRANT_FINALIZATION_FAILED
		)


func on_effect_removed(context: GameplayEffectComponentRemovalContext) -> void:
	var state: GameplayEffectGrantAbilitiesState = context.component_state as GameplayEffectGrantAbilitiesState
	if state == null or context.target_asc == null or context.target_asc.ability_runtime == null:
		return
	var runtime: AbilityRuntime = context.target_asc.ability_runtime
	for i: int in context.active_effect.granted_ability_handles.size():
		var handle: GameplayAbilityHandle = context.active_effect.granted_ability_handles[i]
		var policy: GameplayEffectAbilityGrant.RemovalPolicy = (
			state.policies[i] if i < state.policies.size()
			else GameplayEffectAbilityGrant.RemovalPolicy.CANCEL_AND_REMOVE_ON_EFFECT_END
		)
		match policy:
			GameplayEffectAbilityGrant.RemovalPolicy.CANCEL_AND_REMOVE_ON_EFFECT_END:
				runtime.remove_ability(handle)
			GameplayEffectAbilityGrant.RemovalPolicy.REMOVE_ON_ACTIVE_END:
				runtime.mark_pending_removal(handle)
			GameplayEffectAbilityGrant.RemovalPolicy.KEEP_AFTER_EFFECT_END:
				pass
