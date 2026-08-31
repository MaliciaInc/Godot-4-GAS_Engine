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
	## A modifier's GameplayMagnitude is null, or otherwise malformed on its
	## own terms - distinct from INVALID_MODIFIER_INDEX, which means the
	## index itself was out of range.
	INVALID_MAGNITUDE_DEFINITION,
	## A GameplayAttributeBasedMagnitude's capture never resolved.
	MISSING_CAPTURE,
	## A GameplaySetByCallerMagnitude's tag was never set and requires one.
	MISSING_SET_BY_CALLER,
	## A GameplayCustomMagnitude's calculation refused or returned nothing.
	MAGNITUDE_CALCULATION_FAILED,
	## A modifier's magnitude reads, LIVE, the very attribute it writes -
	## direct self-reference, refused outright rather than evaluated once and
	## left to loop the moment anything reacts to it.
	LIVE_MAGNITUDE_CYCLE,
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
