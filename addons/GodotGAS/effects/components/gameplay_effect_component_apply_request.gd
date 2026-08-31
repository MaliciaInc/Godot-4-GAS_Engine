## Everything a component's can_apply()/prepare_application()/on_spec_created()
## needs to answer, as one typed value.
##
## Also the parameter GameplayEffectApplicationRequirement.can_apply() takes:
## a custom requirement asks exactly what a component asks, so it gets exactly
## the same request rather than a second, narrower one.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectComponentApplyRequest extends RefCounted

var spec: GameplayEffectSpec = null
var target_asc: AbilitySystemComponent = null
var source_asc: AbilitySystemComponent = null

## The one RNG every ChanceToApply/random-dependent component reads from.
## Owned by GameplayEffectComponentRuntime, so a test can seed one instance
## and every component asked through the same runtime draws from it - never
## from the engine's global random state, which no test can pin down.
var rng: RandomNumberGenerator = null
