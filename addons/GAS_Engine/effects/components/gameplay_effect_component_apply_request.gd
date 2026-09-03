## Everything a component's can_apply()/prepare_application()/on_spec_created()
## needs to answer, as one typed value.
##
## Also the parameter GameplayEffectApplicationRequirement.can_apply() takes:
## a custom requirement asks exactly what a component asks, so it gets exactly
## the same request rather than a second, narrower one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectComponentApplyRequest extends RefCounted

var spec: GameplayEffectSpec = null
var target_asc: AbilitySystemComponent = null
var source_asc: AbilitySystemComponent = null

## The one RNG every ChanceToApply/random-dependent component reads from.
## Owned by GameplayEffectComponentRuntime, so a test can seed one instance
## and every component asked through the same runtime draws from it - never
## from the engine's global random state, which no test can pin down.
var rng: RandomNumberGenerator = null

## Null for a fresh application; the stack this one is about to join, for a
## reapplication onto an existing stack (see GameplayEffectStackingRuntime).
## A component whose state belongs to the stack as a whole, not to each
## individual reapplication - GameplayEffectGrantAbilitiesComponent grants
## once per active effect, never once per stack join - reads this to skip
## preparing again.
var existing_active_effect: ActiveGameplayEffect = null
