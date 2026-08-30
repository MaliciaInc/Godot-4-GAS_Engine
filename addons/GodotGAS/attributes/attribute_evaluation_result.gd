## The outcome of evaluating one attribute, as a closed status plus values.
##
## The machine-readable error is the enum. Human log text is built only at the
## logging boundary from `Status`; this domain object never stores a free-form
## message or a numeric code as its authority, because two representations of
## the same failure drift apart the moment one of them is easier to write.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AttributeEvaluationResult extends RefCounted

## Every way an evaluation can end. Closed on purpose: a caller that switches
## over this cannot silently miss a case that was added later.
enum Status {
	OK,
	INVALID_SPEC,
	ATTRIBUTE_NOT_FOUND,
	INVALID_OPERATION,
	INVALID_MODIFIER_INDEX,
	AMBIGUOUS_ATTRIBUTE_WRITE,
	DIVISION_BY_ZERO,
	NON_FINITE_VALUE,
}

var status: Status = Status.OK

## The aggregated value before the effective clamp is applied.
var raw_value: float = 0.0

## The value after the effective clamp. This is what current_value becomes.
var final_value: float = 0.0

## Which OVERRIDE won, identified by both axes so ties are never resolved by
## chance. -1 means no OVERRIDE participated.
var winning_override_application_order: int = -1
var winning_override_modifier_index: int = -1


func is_ok() -> bool:
	return status == Status.OK
