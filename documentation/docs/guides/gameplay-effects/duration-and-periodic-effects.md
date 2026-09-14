---
title: Duration and Periodic Effects
sidebar_position: 3
description: Timed, infinite, periodic and turn-based effects, inhibition, and reading or changing the time an effect has left.
---

# Duration and Periodic Effects

Every effect that is not `INSTANT` becomes an `ActiveGameplayEffect` that lives on the target until it expires or is removed. While it lives, its modifiers contribute to current values and its tags stay granted. This page covers how long that is, how periodic effects tick, and how turn-based games age effects.

## Duration effects

A `DURATION` effect lasts `duration` seconds, counted from the target component's own `_process` delta:

```gdscript
var effect: GameplayEffect = GameplayEffect.new()
effect.policy = GameplayEffect.DurationPolicy.DURATION
effect.duration = 8.0
```

When the clock runs out, the effect is removed with the reason `NATURAL_EXPIRATION`: its contributions are dropped, its tags are released, and its persistent cues stop.

### A duration that depends on something

`duration_magnitude` replaces the fixed `duration` with any [magnitude](modifiers-and-magnitudes.md#magnitudes). A burn that lasts as long as the caster's intellect, or a stun shortened by the target's tenacity, is an attribute-based magnitude resolved when the effect is applied. `period_magnitude` does the same for `period`. Leave both `null` to use the plain numbers.

An application whose resolved duration or period is not a finite number is refused with `INVALID_SPEC` rather than silently becoming permanent.

## Infinite effects

An `INFINITE` effect never expires on its own. Something has to remove it - the ability that applied it when it ends, an item bridge when the item comes off, a cleanse:

```gdscript
var aura: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(aura_effect, owner_asc)
# … later
owner_asc.remove_active_effect(aura)
```

Keep the `ActiveGameplayEffect` or its `handle` so you remove exactly the application you created, and not another source's copy of the same effect.

## Periodic effects

Give a `DURATION` or `INFINITE` effect a `period` above zero and it ticks. On each tick its modifiers and executions **write the base value**, its `EXECUTED_ON_PERIODIC` cues play, and its `event_tags` are sent.

```gdscript
static func poison(damage_per_tick: float) -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = -damage_per_tick

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = &"health"
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Poison"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = 6.0
	effect.period = 1.0
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

Periodic effects follow three rules:

- **Ticks are permanent.** A periodic effect does not contribute to the current value, so nothing is reversed when it ends. Six ticks of poison stay dealt.
- **The first tick comes one period after application.** Set `execute_periodic_on_application` to tick immediately as well.
- **No tick is dropped.** The clock counts elapsed time rather than a countdown, so a long frame that spans three periods pays three ticks. At most 64 catch-up ticks are paid in one frame; the rest carry over.

:::info Buff or damage-over-time?
The same effect cannot both contribute and tick. A "+10 armor for 10 seconds" buff has no period. A "5 damage every second for 10 seconds" poison has one.
:::

## Turn-based effects

A `TURN_BASED` effect lasts `duration_turns` turns. Turns do not pass on their own: whatever runs your turn order calls `advance_turn()` on each component.

```gdscript
func begin_round() -> void:
	for battler: Battler in roster.get_battlers():
		battler.asc.advance_turn()
```

Turn-based effects are how a turn-based game builds buffs, debuffs and cooldowns that last "three turns". A turn-based effect with a `period` is a damage-over-time that ticks as turns pass; `tick_on_turn_start` (on by default) makes it tick when the turn advances.

:::warning Forgetting `advance_turn()`
If nothing calls `advance_turn()`, a `TURN_BASED` effect never expires - and a turn-counted cooldown never lifts.
:::

## Inhibition

An active effect can be switched off without being removed. A `GameplayEffectTargetTagRequirementsComponent` with an `ongoing_query` keeps the effect **uninhibited** only while the target's tags satisfy the query:

```gdscript
var only_in_water: GameplayTagQuery = GameplayTagQuery.new()
var expression: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(only_in_water)
GameplayTagQueryEdits.add_tag(expression, &"Terrain.Water")

var requirements: GameplayEffectTargetTagRequirementsComponent = GameplayEffectTargetTagRequirementsComponent.new()
requirements.ongoing_query = only_in_water
swim_speed_effect.components.append(requirements)
```

While inhibited, the effect stays registered and keeps its handle, but its contributions and granted tags are detached and its persistent cues stop. When the query matches again, everything reattaches unchanged. `active_effect_inhibition_changed(handle, inhibited)` reports each change.

`period_inhibition_policy` decides what a periodic effect does with ticks it owed while inhibited:

| `PeriodInhibitionPolicy` | Behaviour |
|---|---|
| `SKIP_MISSED_TICKS` | Missed ticks are gone. The default. |
| `EXECUTE_IMMEDIATELY_ON_UNINHIBIT` | One tick fires the moment the effect is uninhibited, if any were missed. |
| `RESET_PERIOD_ON_UNINHIBIT` | No catch-up tick; the period restarts from the moment of uninhibition. |

The same component's `removal_query` removes the effect outright when it matches. See [Components](components.md#tag-requirements).

## Reading the time left

| Question | Call |
|---|---|
| Seconds left on one effect | `asc.get_effect_duration_remaining(handle)` |
| Turns left on one effect | `asc.get_effect_turns_remaining(handle)` |
| Seconds left on whatever grants a tag | `asc.get_tag_duration_remaining(tag)` - `INF` when an infinite effect grants it |
| Turns left on whatever grants a tag | `asc.get_tag_turns_remaining(tag)` |

Seconds and turns are separate questions with separate answers, so a UI never counts a turn-based debuff down in seconds.

To follow a timer without polling, connect `active_effect_time_changed(handle, remaining)`. It fires whenever the time left changes for a reason other than the clock - a refresh, a stack, or a call to `set_active_effect_duration()`.

## Changing the time left

```gdscript
asc.set_active_effect_duration(handle, 3.0)
```

The call returns a `GameplayEffectMutationResult`. Stacking policies can also restart a duration automatically; see [Stacking](stacking.md).
