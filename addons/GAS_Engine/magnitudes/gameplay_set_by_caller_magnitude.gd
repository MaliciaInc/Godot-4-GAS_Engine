## A magnitude the caster supplies at cast time rather than authors ahead of
## it - a boss's telegraphed damage, a charge-up ability's held duration.
##
## `data_tag` identifies which value this reads off the spec. Prefer a
## registered gameplay tag over a free-typed string: two magnitudes that
## meant to share one value but spelled it differently would silently read
## two different ones.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplaySetByCallerMagnitude extends GameplayMagnitude

@export var data_tag: StringName = &""
@export var default_value: float = 0.0

## When true, a caller that never set this tag refuses the whole evaluation.
## When false, `default_value` stands in instead.
@export var require_value: bool = true


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if data_tag == &"" or context == null or context.spec == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)

	var result: GameplayMagnitudeResult = context.spec.get_set_by_caller(data_tag)
	if result.is_ok():
		return result
	if not require_value:
		return GameplayMagnitudeResult.ok(default_value)
	return result
