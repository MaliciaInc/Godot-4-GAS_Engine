## What actually happened when an ability fired an effect at a set of targets.
##
## Applying to several targets has more than two outcomes, and a bare count
## hides the ones that matter. A target can have no ability system at all, which
## is a scene wiring problem; it can have one that refused the effect, which is
## gameplay working as intended; and two colliders can turn out to be one actor,
## which is neither. Each is reported separately so a caller can tell them apart
## instead of inferring from a number that came back lower than expected.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayTargetApplicationResult extends RefCounted

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


func applied_count() -> int:
	return applied_effects.size()
