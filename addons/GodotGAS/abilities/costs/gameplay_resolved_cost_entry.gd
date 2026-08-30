## A snapshot of why one cost entry resolved to the amount it did.
##
## Frozen at resolve time and never re-queried: a UI or log reading this after
## the fact sees exactly what was decided, not what the attributes hold now.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayResolvedCostEntry extends RefCounted

var target_attribute: StringName = &""
var mode: GameplayAbilityCost.Mode = GameplayAbilityCost.Mode.ABSOLUTE
var reference_attribute: StringName = &""

## The reference attribute's value at resolve time. Left at 0.0, and unused,
## for an ABSOLUTE entry.
var reference_value: float = 0.0

## What `amount.evaluate(level)` produced: the authored absolute quantity for
## ABSOLUTE, or the authored fraction for a percent mode.
var authored_value: float = 0.0

## The final, non-negative quantity this entry contributes to its target
## attribute's aggregated charge.
var resolved_amount: float = 0.0
