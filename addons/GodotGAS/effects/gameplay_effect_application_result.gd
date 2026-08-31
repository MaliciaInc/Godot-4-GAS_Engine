## The single, extensible result of applying a GameplayEffectSpec.
##
## Replaces a bare ActiveGameplayEffect-or-null: a component can refuse an
## application for a reason AttributeEvaluationResult.Status cannot express,
## and callers need one typed answer, not a second parallel result type per
## new refusal source. Later tasks add new Status values here - IMMUNE (T10),
## stacking statuses (T12), CHAIN_DEPTH_EXCEEDED (T13) - never a competing
## result type.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectApplicationResult extends RefCounted

enum Status {
	SUCCESS,
	INVALID_SPEC,
	INVALID_DEFINITION,
	COMPONENT_REJECTED,
	EVALUATION_FAILED,
}

var status: Status = Status.SUCCESS
var spec: GameplayEffectSpec = null
var active_effect: ActiveGameplayEffect = null
var evaluation_status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK
var error_attribute_name: StringName = &""


func is_ok() -> bool:
	return status == Status.SUCCESS


static func ok(spec: GameplayEffectSpec, active_effect: ActiveGameplayEffect) -> GameplayEffectApplicationResult:
	var result: GameplayEffectApplicationResult = GameplayEffectApplicationResult.new()
	result.spec = spec
	result.active_effect = active_effect
	return result


static func failure(
	failure_status: Status,
	spec: GameplayEffectSpec = null,
	evaluation_status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK,
	error_attribute_name: StringName = &""
) -> GameplayEffectApplicationResult:
	var result: GameplayEffectApplicationResult = GameplayEffectApplicationResult.new()
	result.status = failure_status
	result.spec = spec
	result.evaluation_status = evaluation_status
	result.error_attribute_name = error_attribute_name
	return result
