## One modifier's contribution to one attribute, as a value the aggregator owns.
##
## Replaces the `Array[Dictionary]` upstream used to carry the same four facts.
## A dictionary cannot say which of two contributions came first, and ordering
## is load-bearing here: OVERRIDE resolution depends on it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AttributeModifierContribution extends RefCounted

## The attribute this contribution writes to.
var attribute_name: StringName = &""

## Which arm of the canonical formula this joins.
var operation: GameplayEffectModifier.Operation = GameplayEffectModifier.Operation.ADD

## The runtime magnitude, already resolved from curve and level.
var magnitude: float = 0.0

## Position of the source modifier inside its effect's `modifiers` array.
## Two modifiers of one effect writing the same attribute are distinguished by
## this, never by their magnitude.
var modifier_index: int = -1

## Monotonic order in which the owning effect was applied to this ASC. Together
## with `modifier_index` it totally orders every contribution, which is what
## makes "last OVERRIDE wins" a definition rather than an accident.
var application_order: int = -1
