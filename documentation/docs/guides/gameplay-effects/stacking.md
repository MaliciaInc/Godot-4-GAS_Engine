---
title: Stacking
sidebar_position: 4
description: How repeated applications of one effect combine into a stack, and what happens on refresh, overflow and expiration.
---

# Stacking

By default every application of an effect is its own independent active effect. Ten poison darts create ten poisons. **Stacking** makes repeated applications join one active effect with a stack count instead.

## Turning stacking on

`stacking_type` decides which applications count as "the same" and join one stack:

| `StackingType` | Applications join one stack when… |
|---|---|
| `NONE` | Never. Every application is independent. The default. |
| `AGGREGATE_BY_SOURCE` | They use the same effect **and** come from the same source component. |
| `AGGREGATE_BY_TARGET` | They use the same effect on this target, from any source. |

Two archers each stacking their own bleed on a boss is `AGGREGATE_BY_SOURCE`. A single "Sundered Armor" debuff that any attacker adds to is `AGGREGATE_BY_TARGET`.

## Stack settings

| Field | Default | Meaning |
|---|---|---|
| `stack_limit_count` | `0` | The most stacks allowed. `0` or less is unlimited. |
| `factor_in_stack_count` | `false` | `false`: each modifier contributes its single-stack value. `true`: its value is multiplied by the stack count, recomputed from the authored magnitude whenever the count changes. |
| `deny_overflow_application` | `false` | Refuse an application that would exceed the limit (`STACK_OVERFLOW_DENIED`) instead of accepting it as a non-growing refresh. |
| `clear_stack_on_overflow` | `false` | Remove the whole stack once an overflow happens. |
| `overflow_effects` | `[]` | Effects applied to the same target whenever an application overflows the limit. |
| `stack_duration_refresh_policy` | `NEVER` | `ON_SUCCESSFUL_APPLICATION` restarts the duration when a stack joins. |
| `stack_period_reset_policy` | `NEVER` | `ON_SUCCESSFUL_APPLICATION` restarts the periodic clock when a stack joins. |
| `stack_expiration_policy` | `CLEAR_ENTIRE_STACK` | What happens when the clock runs out. |

### Expiration

| `StackExpirationPolicy` | When the duration runs out |
|---|---|
| `CLEAR_ENTIRE_STACK` | The whole stack is removed. |
| `REMOVE_SINGLE_STACK_AND_REFRESH_DURATION` | One stack is removed; if any remain, the duration restarts. |
| `REFRESH_DURATION` | The count is kept and the duration restarts. |

## Example: a bleed that stacks to five

```gdscript
static func bleed() -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Bleed"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = 5.0
	effect.period = 1.0
	effect.modifiers = [_health_change(-2.0)] as Array[GameplayEffectModifier]

	effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_SOURCE
	effect.stack_limit_count = 5
	effect.factor_in_stack_count = true
	effect.stack_duration_refresh_policy = GameplayEffect.StackDurationRefreshPolicy.ON_SUCCESSFUL_APPLICATION
	effect.stack_expiration_policy = GameplayEffect.StackExpirationPolicy.REMOVE_SINGLE_STACK_AND_REFRESH_DURATION
	return effect
```

Each hit from the same attacker adds a stack (up to five) and restarts the five seconds. Every tick deals 2 damage per stack. When the attacker stops hitting, the bleed decays one stack at a time.

## Example: a charge meter that bursts

A stack that triggers something when it is full uses the overflow settings:

```gdscript
effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
effect.stack_limit_count = 3
effect.clear_stack_on_overflow = true
effect.overflow_effects = [static_discharge] as Array[GameplayEffect]
```

The fourth application overflows: `static_discharge` is applied to the target and the stack is cleared.

## Stacks and cues

Every joined application is still an application, so `EXECUTED_ON_APPLICATION` cues play each time. Set `suppress_stacking_cues` on the effect to play them only for the first application of a stack. `PERSISTENT` cues always run once per active effect, never once per stack.

## Watching and changing stacks

| Signal / method | Purpose |
|---|---|
| `active_effect_stack_changed(handle, old_count, new_count)` | The count actually changed. |
| `active_effect_stack_overflowed(handle)` | An application arrived while the stack was full. |
| `active_effect_refreshed(active_effect)` | A reapplication renewed an existing effect. |
| `ActiveGameplayEffect.stack_count` | The current count. |
| `asc.set_active_effect_stack_count(handle, count)` | Set the count directly. |
| `asc.remove_active_effect_stacks(handle, count)` | Take some stacks off. |
| `AbilityTaskFactory.wait_gameplay_effect_stack_change(self, handle)` | Wait for a count change inside an ability. |
