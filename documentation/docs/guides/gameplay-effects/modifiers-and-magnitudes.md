---
title: Modifiers and Magnitudes
sidebar_position: 2
description: Modifier operations under both aggregation profiles, evaluation channels, and every kind of magnitude - scalable, attribute-based, caller-supplied and custom.
---

# Modifiers and Magnitudes

A `GameplayEffectModifier` says **which** attribute changes, **how** (the operation) and **by how much** (the magnitude).

```gdscript
var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
modifier.attribute_name = &"attack"
modifier.operation = GameplayEffectModifier.Operation.MULTIPLY
modifier.magnitude = magnitude
```

| Field | Meaning |
|---|---|
| `attribute` | The attribute this modifier changes, as a `GameplayAttributeRef` - what the Inspector's attribute picker writes. |
| `attribute_name` | The same, by name. Read only while `attribute` is empty. |
| `operation` | What the magnitude does to the value. |
| `magnitude` | A `GameplayMagnitude` resource. |
| `evaluation_channel` | `0`-`9`. Which pass of the aggregate this modifier joins, under the channel-folded profile. |
| `source_requirements` / `target_requirements` | Tag queries. When either side does not match, this one modifier counts for nothing; the effect still applies. |

A modifier writes by name, even when its reference names a set, so an attribute that two sets on one component both declare is refused with `AMBIGUOUS_ATTRIBUTE_WRITE`. See [Referring to an attribute](../attributes.md#referring-to-an-attribute).

In an `INSTANT` or periodic effect the modifier writes the base value. In any other effect it registers a contribution that the attribute's aggregation folds into the current value for as long as the effect is active.

## Operations

Which operations exist depends on the component's [aggregation profile](../attributes.md#aggregation-profiles).

### Under `GODOT_NATIVE` (the default)

```text
current = ((base + ΣADD) × ΠMULTIPLY) / ΠDIVIDE      then the winning OVERRIDE, then the clamp
```

| Operation | Effect |
|---|---|
| `ADD` | Adds the magnitude. `-30` subtracts. |
| `MULTIPLY` | Multiplies. Several multipliers multiply together: two `×1.5` are `×2.25`. |
| `DIVIDE` | Divides. A zero divisor fails the evaluation with `DIVISION_BY_ZERO`. |
| `OVERRIDE` | Replaces the value. The most recently applied override wins. |

`MULTIPLY_ADDITIVE`, `DIVIDE_ADDITIVE`, `MULTIPLY_COMPOUND` and `ADD_FINAL` have no meaning in this arithmetic and fail the evaluation with `INVALID_OPERATION`.

### Under `CHANNEL_FOLDED`

Each channel, from `0` to `9`, folds over the value the previous channel produced:

```text
value = ((value + ΣADD) × (1 + Σ(MULTIPLY_ADDITIVE − 1)) / (1 + Σ(DIVIDE_ADDITIVE − 1)))
        × ΠMULTIPLY_COMPOUND + ΣADD_FINAL
```

| Operation | Effect |
|---|---|
| `ADD` | Adds to the value at the start of the channel. |
| `MULTIPLY_ADDITIVE` | Bonuses add, then multiply once: two `×1.5` are `×2.0`. |
| `DIVIDE_ADDITIVE` | Divisor bonuses add, then divide once. |
| `MULTIPLY_COMPOUND` | Multiplies the channel's result. Two `×1.5` are `×2.25`. |
| `ADD_FINAL` | Adds after every multiplication in the channel. |
| `OVERRIDE` | Replaces the channel's result. The first applied override claims the value. |
| `MULTIPLY` / `DIVIDE` | Accepted and folded as `MULTIPLY_ADDITIVE` / `DIVIDE_ADDITIVE`. The asset validator warns about them under this profile. |

Channels are what let a game say "this multiplies the buffed value, not the base": put base-stat bonuses on channel 0 and a late multiplier on channel 1.

## Magnitudes

A magnitude is a `Resource` that resolves to one number for one application.

| Magnitude | The number comes from |
|---|---|
| `GameplayScalableMagnitude` | A fixed value, optionally scaled by level. |
| `GameplayAttributeBasedMagnitude` | An attribute of the source or the target. |
| `GameplaySetByCallerMagnitude` | A value supplied by the caller when the spec is built. |
| `GameplayCustomMagnitude` | Your own `GameplayMagnitudeCalculation`. |

Every magnitude resolves against a `GameplayMagnitudeContext` (`spec`, `source_asc`, `target_asc`, `level`) and returns a `GameplayMagnitudeResult`. A magnitude that cannot resolve - a missing capture, a caller value nobody supplied, a non-finite number - fails the whole application rather than applying a zero.

### Scalable magnitudes

```gdscript
var damage: GameplayScalableFloat = GameplayScalableFloat.new()
damage.value = -25.0
damage.scaling_curve = preload("res://game/curves/damage_by_level.tres")

var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
magnitude.value = damage
```

`GameplayScalableFloat` evaluates to `scaling_curve.sample(level) × value`, or just `value` when there is no curve. The level is the spec's level - normally the ability's level.

:::warning Widen the curve's range
A new Godot `Curve` clamps both axes to `[0, 1]`. A curve sampled at level 5, or one that multiplies past `1.0`, needs its `min_domain`/`max_domain` and `min_value`/`max_value` widened first.
:::

### Attribute-based magnitudes

Read an attribute through a [capture](executions-and-context.md#captures) and shape it:

```text
((reading + pre_add) × coefficient) + post_add      then attribute_curve
```

This damage is "the caster's attack, plus the ability's own bite, taken away from health":

```gdscript
var from_attack: GameplayAttributeCaptureDefinition = GameplayAttributeCaptureDefinition.new()
from_attack.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
from_attack.attribute_name = &"attack"
from_attack.value = GameplayAttributeCaptureDefinition.Value.CURRENT
from_attack.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

var bite: GameplayScalableFloat = GameplayScalableFloat.new()
bite.value = 50.0
var negate: GameplayScalableFloat = GameplayScalableFloat.new()
negate.value = -1.0

var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
magnitude.capture = from_attack
magnitude.pre_add = bite        # attack + 50
magnitude.coefficient = negate  # … taken away
```

| Field | Meaning |
|---|---|
| `capture` | Which attribute, from whom, `BASE` or `CURRENT`, `SNAPSHOT` or `LIVE`. |
| `calculation` | Which reading: `MAGNITUDE` (what the capture says), `BASE_VALUE`, `BONUS_MAGNITUDE` (current minus base), or `MAGNITUDE_UP_TO_CHANNEL` with `final_channel`. |
| `coefficient`, `pre_add`, `post_add` | `GameplayScalableFloat`s, evaluated at the spec's level. |
| `attribute_curve` | Applied last, to the finished number. |
| `source_requirements` / `target_requirements` | When a side does not match, the magnitude is worth `0` - "double damage against burning targets" is one modifier that is worth nothing the rest of the time. The source is read from its tags when the spec was made; the target is read live. |

`SNAPSHOT` fixes the value when the spec is prepared. `LIVE` is read when it is needed, and a lasting effect whose attribute-based magnitude reads a `LIVE` capture is re-resolved whenever that attribute changes. A modifier that reads, `LIVE`, the very attribute it writes is refused with `LIVE_MAGNITUDE_CYCLE`.

### Caller-supplied values

Some numbers only exist when the ability runs: how long a charge was held, how many enemies a chain hit. Author a `GameplaySetByCallerMagnitude` with a `data_tag`, and supply the value on the spec:

```gdscript
var charge: GameplaySetByCallerMagnitude = GameplaySetByCallerMagnitude.new()
charge.data_tag = &"Data.ChargeDamage"
```

```gdscript
var spec: GameplayEffectSpec = GameplayEffectSpec.new(charged_hit, context, get_ability_level())
spec.source_asc = owner_asc
spec.set_set_by_caller(&"Data.ChargeDamage", -held_seconds * 40.0)
```

| Field | Meaning |
|---|---|
| `data_tag` | The key the value is supplied under. Use a declared tag so two magnitudes cannot spell it differently. |
| `require_value` | `true` (the default) fails the application when nobody supplied the value. |
| `default_value` | Used instead when `require_value` is `false`. |

`set_set_by_caller()` returns `false` for an empty tag, a non-finite value, or a spec whose evaluation has already started. Change the value on an effect that is already running with `asc.update_active_effect_set_by_caller(handle, tag, value)`.

### Custom magnitudes

For arithmetic the other kinds cannot express, subclass `GameplayMagnitudeCalculation`:

```gdscript
class_name MissingHealthCalculation extends GameplayMagnitudeCalculation


func calculate(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if context.target_asc == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)
	var target: AbilitySystemComponent = context.target_asc
	var missing: float = target.get_attribute_current(&"max_health") - target.get_attribute_current(&"health")
	return GameplayMagnitudeResult.ok(maxf(missing, 0.0))
```

and wrap it in a `GameplayCustomMagnitude`, which shapes the raw result in a fixed order:

```text
raw  →  + pre_add  →  × coefficient  →  final_curve  →  + post_add
```

A heal of half the target's missing health is this calculation with a `coefficient` of `0.5`. The same calculation at three strengths is three resources, not three scripts.

Override `required_captures()` on the calculation when it reads captures, so they are registered and snapshotted before `calculate()` runs.

### Following something outside the attributes

A lasting effect re-resolves a `LIVE` capture whenever its attribute changes. A magnitude that reads something else - the weather, the time of day, an inventory - says so by returning signals from `external_dependencies()`:

```gdscript
class_name StormDamageCalculation extends GameplayMagnitudeCalculation

@export var weather: WeatherState


func calculate(_context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	return GameplayMagnitudeResult.ok(-weather.intensity * 5.0)


func external_dependencies() -> Array[Signal]:
	var read: Array[Signal] = [weather.changed]
	return read
```

`WeatherState` stands for a resource of your own; its `changed` signal fires when it calls `emit_changed()`.

- While a lasting effect carries the modifier, every emission re-resolves that modifier's contribution. The signal may carry any arguments; they are ignored.
- Removing the effect ends the subscriptions.
- An `INSTANT` effect resolves once and follows nothing.
- `GameplayCustomMagnitude` answers with its calculation's `external_dependencies()`.

### Your own magnitude type

For a magnitude kind of your own, subclass `GameplayMagnitude`, override `resolve(context)`, and override `required_captures()` for any attribute it reads through a capture and `external_dependencies()` for anything else it follows.

## Stacks and magnitudes

When a stacking effect sets `factor_in_stack_count`, each modifier's magnitude is rescaled from the authored value whenever the stack count changes:

| Operation | At `n` stacks |
|---|---|
| `OVERRIDE` | Unchanged - an override is a value, not an amount. |
| `MULTIPLY_ADDITIVE`, `DIVIDE_ADDITIVE` (and, under `CHANNEL_FOLDED`, `MULTIPLY`, `DIVIDE`) | The bonus scales: `1 + (magnitude − 1) × n`. Two stacks of `×1.5` are `×2.0`. |
| `MULTIPLY_COMPOUND` | Applied once per stack: `magnitude^n`. |
| Everything else | `magnitude × n`. |

See [Stacking](stacking.md).
