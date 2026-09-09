## What actually happened when an ability fired an effect at a set of targets.
##
## Applying to several targets has more than two outcomes, and a bare count
## hides the ones that matter. A target can have no ability system at all, which
## is a scene wiring problem; it can have one that refused the effect, which is
## gameplay working as intended; and two colliders can turn out to be one actor,
## which is neither. Each is reported separately so a caller can tell them apart
## instead of inferring from a number that came back lower than expected.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetApplicationResult extends RefCounted

## Why an application reached nobody, when it did.
enum Refusal {
	## It reached somebody, or it was never going to - a null effect, a
	## null aim. Nothing to explain.
	NONE,
	## The aim held no actors. A ground-targeted spell aimed at a place
	## with nobody standing on it is the ordinary case of this, and it is
	## not an error: the effect had nobody to apply to, and the engine
	## does not go looking for somebody nearby on its own.
	NO_ACTOR_TARGETS,
}

var refusal: GameplayTargetApplicationResult.Refusal = Refusal.NONE

## Every node the target data offered, before any of them were resolved or
## merged. The difference between this and `applied_count()` is the whole point.
var attempted_targets: int = 0

var applied_targets: Array[AbilitySystemComponent] = []

## Resolved, reached, and refused by the target's own rules - an immunity tag, a
## requirement it does not meet. Not an error.
var rejected_targets: Array[AbilitySystemComponent] = []

## Nodes no ability system could be found for, once each. Usually a scene that
## was wired differently than the ability expected.
var missing_asc_targets: Array[Node] = []

var applied_effects: Array[ActiveGameplayEffect] = []

## One typed result per target actually reached, in the same order as
## applied_targets/rejected_targets - Task 8's richer answer to why a target
## was rejected, alongside the legacy arrays this class already kept.
var applications: Array[GameplayEffectApplicationResult] = []


func applied_count() -> int:
	return applied_effects.size()
