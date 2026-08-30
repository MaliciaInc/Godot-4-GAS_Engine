## The outcome of a durable base-value mutation, with both axes reported.
##
## A single `float` return would have to mean "the new value", "the amount that
## changed" and "nothing happened" at once. It cannot, so callers guess. This
## reports base and current separately, says whether each actually moved, and
## says whether the clamp intervened.
##
## A failed mutation leaves no partial state: on any status other than OK the
## value fields describe the untouched attribute.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AttributeMutationResult extends RefCounted

var status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK

var old_base_value: float = 0.0
var requested_base_value: float = 0.0
var new_base_value: float = 0.0

var old_current_value: float = 0.0
var new_current_value: float = 0.0

## Whether the write actually moved the value. A caller emitting a signal must
## consult these rather than comparing floats itself, so "no change" means the
## same thing everywhere.
var base_changed: bool = false
var current_changed: bool = false

## True when the base clamp changed what was requested.
var was_clamped: bool = false


func is_ok() -> bool:
	return status == AttributeEvaluationResult.Status.OK
