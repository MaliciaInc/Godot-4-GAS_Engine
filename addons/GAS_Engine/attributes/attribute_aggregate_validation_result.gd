## What a preflight of candidate contributions answered.
##
## Asked before an application publishes anything: the aggregate is composed
## against a copy that includes what is about to be added, and if that
## composition cannot be finished the application is refused whole. The
## attribute is carried because a refusal that does not say which one leaves a
## caller reading every modifier to find out.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AttributeAggregateValidationResult extends RefCounted

var status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK
var attribute_name: StringName = &""

func is_ok() -> bool:
	return status == AttributeEvaluationResult.Status.OK
