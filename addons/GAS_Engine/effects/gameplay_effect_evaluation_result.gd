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


## Whether this effect's cues play for this application.
##
## Two rules, asked in one place because a caller consulting only one of them
## would be a second opinion about the same question. An execution can decide
## the cues should not play - a hundred hits landing in one frame should be a
## hundred numbers and one sound - and an effect can say it wants no cue for an
## application that changed no number.
func plays_cues_for(effect: GameplayEffect) -> bool:
	if execution_output != null and not execution_output.trigger_cues:
		return false
	if effect != null and effect.require_modifier_success_to_trigger_cues:
		return changed_a_number()
	return true


## Whether this evaluation actually moved anything.
##
## Staged writes or contributions: an INSTANT effect stages base mutations and
## a lasting one registers contributions, so asking about only one of them
## would answer no for half the effects that did something.
func changed_a_number() -> bool:
	return not base_mutations.is_empty() or not contributions.is_empty()


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
