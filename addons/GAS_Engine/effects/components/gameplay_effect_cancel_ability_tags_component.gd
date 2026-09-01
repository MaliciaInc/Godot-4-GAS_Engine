## When this effect applies, cancels every running ability whose effective
## tags match `query`.
##
## Delegates to AbilityRuntime.cancel_matching_query() - the one cancellation
## algorithm, shared with a successful activation's own
## GameplayAbility.cancel_abilities_query and the legacy cancel_with_tags().
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectCancelAbilityTagsComponent extends GameplayEffectComponent

@export var query: GameplayTagQuery = null


func on_effect_applied(context: GameplayEffectComponentRuntimeContext) -> void:
	if context.target_asc == null or context.target_asc.ability_runtime == null:
		return
	context.target_asc.ability_runtime.cancel_matching_query(query)
