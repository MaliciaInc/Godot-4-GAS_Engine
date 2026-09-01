## Everything a GameplayMagnitude needs to resolve itself: which spec it
## belongs to, the source and target it may capture from, and the level its
## own scaling runs at.
##
## Bundled the same way GameplayEffectEvaluator.Request is, and for the same
## reason: one typed value instead of four loose parameters every resolve()
## override would otherwise repeat.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayMagnitudeContext extends RefCounted

var spec: GameplayEffectSpec = null
var source_asc: AbilitySystemComponent = null
var target_asc: AbilitySystemComponent = null
var level: float = 1.0
