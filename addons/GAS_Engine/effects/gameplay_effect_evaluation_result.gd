## Everything evaluating one spec produced, before anything was committed.
##
## Preview and commit consume this same object. That is the point: a cost
## preview that runs different code from the commit will eventually disagree
## with it, and the disagreement will surface as a player paying for something
## they did not get.
##
## `gameplay_effect_runtime.gd` commits `base_mutations` and registers
## `contributions` only when `is_ok()` holds for the whole transaction.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectEvaluationResult extends RefCounted

var status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK

## Instant writes, staged. Empty for a purely modifier-based effect.
var base_mutations: Array[AttributeBaseMutation] = []

## Durable contributions this spec adds to the aggregator while it is active.
var contributions: Array[AttributeModifierContribution] = []

## Which attribute the failure was about, when the status names one. Empty on OK.
var error_attribute_name: StringName = &""

## What this spec's executions decided beyond their numbers.
##
## Carried rather than re-derived: the calculations have already run, and asking
## them again what else they wanted would be a second run with a second answer.
## Null only when the evaluation failed before they ran.
var execution_output: GameplayExecutionOutput = null


## Whether the effect's cues play for this application.
##
## An execution can decide they should not - a hundred hits landing in one frame
## should be a hundred numbers and one sound - and an effect that ran none keeps
## what every effect has always done.
func plays_cues() -> bool:
	return execution_output == null or execution_output.trigger_cues


func is_ok() -> bool:
	return status == AttributeEvaluationResult.Status.OK


## Build a failed result that carries no staged work, so a caller cannot commit
## half of a transaction by reading the arrays without checking the status.
static func failure(
	failed_status: AttributeEvaluationResult.Status, attribute_name: StringName
) -> GameplayEffectEvaluationResult:
	var result: GameplayEffectEvaluationResult = GameplayEffectEvaluationResult.new()
	result.status = failed_status
	result.error_attribute_name = attribute_name
	return result
