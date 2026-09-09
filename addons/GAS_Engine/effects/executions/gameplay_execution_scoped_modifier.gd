## A modifier that exists only while one execution is running.
##
## An execution that wants to compute "damage against armour, if the attacker
## were 20% stronger" has two bad options without this: change the attacker,
## which is a mutation nobody asked for and which outlives the calculation, or
## do the arithmetic inline, which hides the adjustment inside a script instead
## of declaring it where a designer can see it.
##
## A scoped modifier is the third option. It adjusts what this execution reads
## for one attribute and it is gone the moment the execution returns: nothing
## is registered as a contribution, nothing is recomposed, and no other effect
## on the target ever sees it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayExecutionScopedModifier extends Resource

## Which attribute this adjusts, said so it cannot mean two of them.
@export var attribute: GameplayAttributeRef = null

@export var operation: GameplayEffectModifier.Operation = GameplayEffectModifier.Operation.ADD

@export var magnitude: GameplayMagnitude = null

## Where in the composition it lands, for the profile that has channels.
@export_range(0, 9, 1) var evaluation_channel: int = 0

## The adjustment counts for nothing unless both sides match, the same way an
## attribute-based magnitude's requirements work: a scoped modifier that is
## about burning targets is worth nothing against everybody else, rather than
## refusing the execution it belongs to.
@export var source_requirements: GameplayTagQuery = null
@export var target_requirements: GameplayTagQuery = null
