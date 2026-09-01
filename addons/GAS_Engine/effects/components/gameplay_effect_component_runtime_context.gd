## Everything a component's on_effect_applied()/on_effect_executed() needs, as
## one typed value.
##
## component_index and component_state let a callback find the exact prepared
## state that belongs to it - never by Resource identity, because the same
## component Resource can appear twice on one effect, and two applications of
## one effect share the same definition but never the same state.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectComponentRuntimeContext extends RefCounted

var spec: GameplayEffectSpec = null
var active_effect: ActiveGameplayEffect = null
var target_asc: AbilitySystemComponent = null
var component_index: int = -1
var component_state: GameplayEffectComponentState = null
