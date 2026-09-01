## Everything a component's on_effect_removed() needs, as one typed value.
##
## The removal counterpart of GameplayEffectComponentRuntimeContext, kept
## separate because removal has no fresh evaluation result to carry and a
## caller should not have to leave application-only fields blank to build one.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectComponentRemovalContext extends RefCounted

var spec: GameplayEffectSpec = null
var active_effect: ActiveGameplayEffect = null
var target_asc: AbilitySystemComponent = null
var component_index: int = -1
var component_state: GameplayEffectComponentState = null
