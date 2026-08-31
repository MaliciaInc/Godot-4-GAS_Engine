## Fires GameplayEffectAdditionalEffectsComponent's declared chains: other
## effects applied to the same target after a parent's own application
## commits, or after its removal, gated by whichever target/source queries
## are configured.
##
## Composed into GameplayEffectRuntime, same pattern as
## GameplayEffectStackingRuntime/GameplayEffectInhibitionRuntime. A child's
## own chain_depth (Task 12) is what actually stops a cycle - this runtime
## never counts or tracks depth itself.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectChainRuntime extends RefCounted

var effects: GameplayEffectRuntime = null


## Called once a fresh application, or a stack reapplication, has committed.
func fire_on_application(spec: GameplayEffectSpec) -> void:
	var component: GameplayEffectAdditionalEffectsComponent = spec.effect_def.get_additional_effects_component()
	if component == null:
		return
	_apply_matching(component.on_application, spec)


## Called after `active` has been detached and dropped from the registry,
## before the final removal signal - `reason` decides which arrays fire.
## ASC_CLEANUP and GRANT_FINALIZATION_FAILED fire nothing: neither is a
## gameplay-caused removal.
func fire_on_removal(active: ActiveGameplayEffect, reason: ActiveGameplayEffect.RemovalReason) -> void:
	if (
		reason == ActiveGameplayEffect.RemovalReason.ASC_CLEANUP
		or reason == ActiveGameplayEffect.RemovalReason.GRANT_FINALIZATION_FAILED
	):
		return
	var component: GameplayEffectAdditionalEffectsComponent = active.get_effect_def().get_additional_effects_component()
	if component == null:
		return
	if reason == ActiveGameplayEffect.RemovalReason.NATURAL_EXPIRATION:
		_apply_matching(component.on_natural_expiration, active.spec)
	else:
		_apply_matching(component.on_premature_removal, active.spec)
	_apply_matching(component.on_any_removal, active.spec)


func _apply_matching(conditionals: Array[GameplayEffectConditionalEffect], parent_spec: GameplayEffectSpec) -> void:
	if effects.owner_asc == null:
		return
	for conditional: GameplayEffectConditionalEffect in conditionals:
		if conditional == null or conditional.effect == null:
			continue
		if not _matches(conditional, parent_spec):
			continue
		effects.owner_asc.apply_effect_spec_result(_build_child(conditional.effect, parent_spec))


## Every query configured on `conditional` must match: target_query against
## this runtime's own target tags, source_query against the parent
## application's own source ASC.
func _matches(conditional: GameplayEffectConditionalEffect, parent_spec: GameplayEffectSpec) -> bool:
	if conditional.target_query != null and not conditional.target_query.is_empty():
		if not conditional.target_query.matches_runtime(effects.tags):
			return false
	if conditional.source_query != null and not conditional.source_query.is_empty():
		var source_asc: AbilitySystemComponent = parent_spec.source_asc
		if source_asc == null or not conditional.source_query.matches_runtime(source_asc.tags):
			return false
	return true


## Carries instigator, causer, source ASC and source tags forward; the
## target is whatever this application copy resolves for itself when
## applied - never the parent's own target_data payload.
func _build_child(child_effect: GameplayEffect, parent_spec: GameplayEffectSpec) -> GameplayEffectSpec:
	var parent_context: GameplayEffectContext = parent_spec.context
	var context: GameplayEffectContext = GameplayEffectContext.new(
		parent_context.instigator if parent_context != null else null,
		parent_context.causer if parent_context != null else null
	)
	var child: GameplayEffectSpec = GameplayEffectSpec.new(child_effect, context, parent_spec.level)
	child.source_asc = parent_spec.source_asc
	child.source_tags_snapshot = parent_spec.source_tags_snapshot.duplicate()
	child.chain_depth = parent_spec.chain_depth + 1
	return child
