## A base-value change that has been staged but not yet applied to the ASC.
##
## The evaluator produces these; only `gameplay_effect_runtime.gd` commits them,
## and only when the whole transaction is OK. Staging is what makes atomicity
## expressible: a failure halfway through leaves nothing written, because
## nothing was written yet.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AttributeBaseMutation extends RefCounted

var attribute_name: StringName = &""

## The base value read when the mutation was staged.
var old_base_value: float = 0.0

## What the caller asked for, before any base clamp.
var requested_base_value: float = 0.0

## What the base clamp allows. This is the value that will actually be written.
var committed_base_value: float = 0.0

## Set only by stage_gameplay_effect_base_write - null for a plain
## stage_base_write. Carries the pre/post execute-hook context through commit,
## so the committing caller knows which mutations to fire post hooks for
## without re-deriving "was this effect-driven" from anything else.
var execute_data: GameplayEffectExecuteData = null
