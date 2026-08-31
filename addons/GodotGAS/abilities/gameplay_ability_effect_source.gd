## A grant caused by a GameplayEffect being active on the target - a buff, a
## piece of equipment, a transformation.
##
## `effect_handle` is set after the granting effect's own handle exists
## (GameplayEffectRuntime._commit assigns it after the purge/evaluate stage
## that GameplayEffectGrantAbilitiesComponent.prepare_application runs
## before) - never a mutable ActiveGameplayEffect reference, which a stack
## reapplication would leave pointing at swapped-out state.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAbilityEffectSource extends GameplayAbilitySource

var effect_handle: GameplayEffectHandle = null


func source_id() -> StringName:
	if effect_handle == null or not effect_handle.is_valid():
		return &""
	return StringName("Effect#" + str(effect_handle.id))
