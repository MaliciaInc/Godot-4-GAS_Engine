---
title: Executions and Context
sidebar_position: 6
description: Custom damage formulas with execution calculations, attribute captures, scoped modifiers, the pre/post execute hooks, and the context an effect carries.
---

# Executions and Context

Modifiers cover most arithmetic: add this, multiply that. When an effect needs a formula - damage equal to the attacker's attack minus the defender's armor, a heal that scales with missing health - it uses an **execution calculation**.

## Modifier or execution?

| Use a modifier when… | Use an execution when… |
|---|---|
| The change is one operation on one attribute. | The result depends on several attributes of both sides. |
| It should last as long as the effect (a buff). | It is a one-off change to a durable value (a hit). |
| A designer tunes it in the Inspector. | It is a formula you want in code. |

An execution is always an **instant mutation of the base value**, even inside a periodic effect, where it runs on every tick. A "+20% attack" buff is never an execution: it is a modifier, so it lives and dies with its effect.

## Writing an execution

Subclass `GameplayExecutionCalculation`, declare the attributes you read as **captures**, and return the base deltas.

```gdscript
class_name WeaponDamageExecution extends GameplayExecutionCalculation

## Added to the attacker's attack before the defender's armor is subtracted.
@export var weapon_power: float = 10.0

var _attack: GameplayAttributeCaptureDefinition = null
var _armor: GameplayAttributeCaptureDefinition = null


func _init() -> void:
	_attack = GameplayAttributeCaptureDefinition.new()
	_attack.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
	_attack.attribute_name = &"attack"
	_attack.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

	_armor = GameplayAttributeCaptureDefinition.new()
	_armor.actor = GameplayAttributeCaptureDefinition.Actor.TARGET
	_armor.attribute_name = &"armor"
	_armor.policy = GameplayAttributeCaptureDefinition.Policy.LIVE


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return [_attack, _armor] as Array[GameplayAttributeCaptureDefinition]


func declared_output_attributes() -> Array[StringName]:
	return [&"health"] as Array[StringName]


func execute(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> Dictionary[StringName, float]:
	var attack: AttributeCaptureResult = spec.resolve_capture(_attack, spec.source_asc, target_asc)
	var armor: AttributeCaptureResult = spec.resolve_capture(_armor, spec.source_asc, target_asc)
	if not attack.is_ok() or not armor.is_ok():
		return {}

	var damage: float = maxf(attack.value + weapon_power - armor.value, 1.0)
	return {&"health": -damage}
```

Put it in an `INSTANT` effect:

```gdscript
var effect: GameplayEffect = GameplayEffect.new()
effect.resource_name = "Weapon hit"
effect.policy = GameplayEffect.DurationPolicy.INSTANT
effect.executions = [WeaponDamageExecution.new()] as Array[GameplayExecutionCalculation]
```

| Method | Purpose |
|---|---|
| `required_captures()` | Every attribute the calculation reads. They are registered on the spec and snapshots are taken before `execute()` runs. |
| `declared_output_attributes()` | Which attributes it writes. Advisory: it lets `GameplayEffectQuery.modified_attribute` find the effect. |
| `execute(spec, target_asc)` | Return `{attribute: delta}`. Every entry is an addition to the base value. |
| `execute_typed(spec, target_asc)` | Return a `GameplayExecutionOutput` when a dictionary of additions is not enough. |
| `execute_in(context)` | The entry point the engine actually calls. Override it to use the execution context. |
| `scoped_modifiers()` | Adjustments that exist only while this calculation runs. |

:::warning An execution has no side effects
The engine evaluates executions while an application can still be refused. Read through the spec and the components, and **return** what should change. Never grant a tag, apply or remove an effect, or write an attribute from inside a calculation.
:::

When an effect has both, the execution decides the base and the effect's modifiers compose over what it decided.

## Captures

A `GameplayAttributeCaptureDefinition` says which attribute to read, from whom, which of its two values, and when:

| Field | Values |
|---|---|
| `actor` | `SOURCE` (the instigator's component) or `TARGET` (the component receiving the effect). |
| `attribute_name` or `attribute` | The attribute, by name or by `GameplayAttributeRef`. |
| `value` | `CURRENT` (default) or `BASE`. |
| `policy` | `SNAPSHOT` freezes the value; `LIVE` reads it fresh every time it is asked. |

- A `SOURCE` snapshot is taken once, when the spec is prepared, and shared by every target of an area effect - the swing is as strong as the attacker was when it swung.
- A `TARGET` snapshot is taken on each target's own copy, immediately before that target's evaluation.
- `spec.capture_source_now(asc)` and `spec.capture_target_now(asc)` take snapshots at a moment you choose, for a spec built now and applied later.

`resolve_capture()` returns an `AttributeCaptureResult` with a `value` and a `status`: `OK`, `INVALID_DEFINITION`, `SOURCE_MISSING`, `TARGET_MISSING`, `ATTRIBUTE_NOT_FOUND` or `NON_FINITE_VALUE`.

Captures are also what [attribute-based magnitudes](modifiers-and-magnitudes.md#attribute-based-magnitudes) read.

## Richer outputs

Override `execute_typed()` and return a `GameplayExecutionOutput` to say more than "add this":

| Field | Meaning |
|---|---|
| `modifiers` | `GameplayExecutionOutput.Modifier` entries, each with an `attribute` (`GameplayAttributeRef`), an `operation` and a `magnitude`. `GameplayExecutionOutput.adding(name, amount)` builds an addition. |
| `conditional_effects` | Effects to apply to the target once this calculation's writes land - a hit that also sets the target alight when it crits. |
| `trigger_cues` | `false` silences the containing effect's cues for this application. |
| `stack_count_handled_manually` | Under the channel-folded profile, execution results are multiplied by the stack count; set this when the calculation already accounted for stacks. |

```gdscript
func execute_typed(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayExecutionOutput:
	var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
	var damage: float = _damage(spec, target_asc)
	output.modifiers.append(GameplayExecutionOutput.adding(&"health", -damage))
	if spec.passed_in_tags.has(&"Hit.Critical"):
		output.conditional_effects.append(burning)
	return output
```

## The execution context

Override `execute_in(context)` to receive a `GameplayExecutionContext`:

| Member | Meaning |
|---|---|
| `spec`, `source_asc`, `target_asc` | The application being evaluated. |
| `passed_in_tags` | Tags the application was handed by whoever built it, such as `Hit.Critical`. |
| `transient` | A `Dictionary[StringName, float]` scratch space that lives for one run and is then dropped. |
| `scoped` | The scoped modifiers in force for this run. |
| `captured(definition)` | A capture with this run's scoped adjustments folded in. |
| `adjust(attribute_name, value)` | Any number with this run's adjustments for that attribute folded in. |

## Scoped modifiers

A scoped modifier adjusts what one execution **reads**, and disappears when the execution returns. "Damage against armor as if the attacker were 20% stronger" is a scoped modifier, not a temporary buff on the attacker:

```gdscript
func scoped_modifiers() -> Array[GameplayExecutionScopedModifier]:
	return [_empowered_attack] as Array[GameplayExecutionScopedModifier]
```

A `GameplayExecutionScopedModifier` has an `attribute`, an `operation`, a `magnitude`, an `evaluation_channel`, and optional `source_requirements` / `target_requirements` tag queries that make it count for nothing unless both sides match. Nothing is registered as a contribution, and no other effect ever sees it. Read through `context.captured()` to see the adjusted value.

## Execute hooks on the attribute set

Every base write an effect performs - an instant modifier, a periodic tick, an execution output - passes through two `AttributeSet` hooks around the commit. Each receives a `GameplayEffectExecuteData`:

| Field | Meaning |
|---|---|
| `spec`, `effect_handle`, `source_asc`, `target_asc` | Where the write came from. |
| `attribute_name` | Which attribute. |
| `old_base` | The value before the write. |
| `requested_base` / `proposed_base` | What the effect asked for, and what will be clamped and committed. |
| `committed_base` | What was stored (read it in the post hook). |

**`pre_gameplay_effect_execute(data) -> bool`** runs before anything commits. It must be pure. Return `false` to refuse the whole evaluation, or change the proposal with `data.set_proposed_base(value)`:

```gdscript
func pre_gameplay_effect_execute(data: GameplayEffectExecuteData) -> bool:
	var invulnerable: bool = data.target_asc != null and data.target_asc.has_tag(&"State.Invulnerable")
	if data.attribute_name == HEALTH and invulnerable and data.proposed_base < data.old_base:
		data.set_proposed_base(data.old_base)
	return true
```

**`post_gameplay_effect_execute(data)`** runs once per write, after the whole transaction committed. This is the place for ordinary gameplay reactions through normal APIs - a death event, lifesteal, a shield breaking:

```gdscript
func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
	if data.attribute_name != HEALTH or data.old_base <= 0.0 or data.committed_base > 0.0:
		return
	var died: GameplayEventData = GameplayEventData.new()
	died.event_tag = &"Event.Death"
	died.target = data.target_asc.get_effect_target()
	data.target_asc.send_gameplay_event(died)
```

Plain `DURATION` and `INFINITE` contributions never pass through these hooks: they do not write base values.

## What the spec carries

An execution reads everything about its application from the `GameplayEffectSpec`:

| Member | Meaning |
|---|---|
| `effect_def` | The effect being applied. |
| `context` | The `GameplayEffectContext` (see below). |
| `source_asc` | The component that caused the application. |
| `level` | The level magnitudes resolve at. |
| `stack_count` | How many stacks this application represents. |
| `passed_in_tags` | Tags handed in by the builder of the spec, for executions only. |
| `dynamic_tags`, `inject_tag(tag)` | Tags describing this application, such as `Hit.Dodged`, visible to queries. |
| `get_set_by_caller(tag)` | A caller-supplied value, as a `GameplayMagnitudeResult`. |
| `duration`, `period`, `remaining_turns` | Runtime timing, which may be changed before the application commits. |

## The effect context

A `GameplayEffectContext` records where an effect came from:

| Member | Meaning |
|---|---|
| `instigator` | Who is responsible - the character that cast the ability. |
| `causer` | What physically caused it - a projectile. Defaults to the instigator. |
| `source_object` | The item behind it - a weapon, a thrown bottle. |
| `ability_handle` | The ability that produced the application, when one did. |
| `target_data` | What this application was aimed at. Each target of an area effect receives only its own share. |
| `payloads` | Typed game-specific data. |

`GameplayEffectContext.new(instigator, causer)` builds one; `apply_effect_to_targets()` builds one for you.

References to nodes are read through validity checks, so an effect that outlives its caster reads `instigator` as `null` rather than as a freed object.

### Context payloads

GAS_Engine does not invent schemas for weapons, critical hits or surfaces. Attach your own typed data by subclassing `GameplayEffectContextPayload`:

```gdscript
class_name CriticalHitPayload extends GameplayEffectContextPayload

var multiplier: float = 1.0


func create_application_copy() -> GameplayEffectContextPayload:
	var copy: CriticalHitPayload = CriticalHitPayload.new()
	copy.multiplier = multiplier
	return copy
```

```gdscript
var payload: CriticalHitPayload = CriticalHitPayload.new()
payload.multiplier = 2.5
context.add_payload(payload)

# … inside an execution
var crit: CriticalHitPayload = spec.context.find_payload(CriticalHitPayload) as CriticalHitPayload
```

`create_application_copy()` is required: every target of an area effect receives its own copy of the context. Returning `null` refuses the copy, so a context is never handed out missing data. The engine ships one payload, `GameplayHitContextPayload`, which carries a single `GameplayTargetHit`.
