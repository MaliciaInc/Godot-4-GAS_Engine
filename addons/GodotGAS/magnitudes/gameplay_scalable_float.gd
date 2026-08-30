## A single number that may optionally scale with level via a curve.
##
## Shared by ability costs now and gameplay magnitudes in a later task. It
## knows nothing about attributes, an ASC, or what the number pays for - only
## how to turn a level into a value.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayScalableFloat extends Resource

@export var value: float = 0.0

## The X axis is level; the Y axis multiplies `value`. Null means no scaling:
## the result is `value` at every level.
##
## A fresh `Curve` clamps both axes to [0, 1]: a point added beyond either
## bound is silently pulled back to it. A curve meant to be sampled past
## level 1, or to multiply past 1.0, needs its `max_domain`/`max_value`
## widened first - Godot's default, not a rule of this class.
@export var scaling_curve: Curve = null


## `value` at `level`, or `value` unscaled when there is no curve. Never
## mutates `scaling_curve`.
func evaluate(level: float) -> float:
	if scaling_curve != null:
		return scaling_curve.sample(level) * value
	return value
