---
title: Gameplay Effects
sidebar_position: 1
description: What a GameplayEffect is, how to author one, and how to apply, query, change and remove effects.
---

# Gameplay Effects

A `GameplayEffect` is the only way gameplay changes attributes and grants tags. Damage, healing, a mana cost, a poison, a haste buff, a stun, a cooldown, the stats a sword gives while it is worn - every one of them is an effect.

An effect is a `Resource` that describes what should happen. Applying it creates a `GameplayEffectSpec` for one target, and effects that last become an `ActiveGameplayEffect` addressed by a `GameplayEffectHandle`.

## Duration policies

The `policy` decides what kind of effect it is.

| Policy | What its modifiers do | Grants tags | Leaves an active effect | Typical use |
|---|---|---|---|---|
| `INSTANT` | Write the **base** value once. | No | No | Damage, healing, a cost. |
| `DURATION` | Contribute to the **current** value for `duration` seconds. | Yes | Yes | A timed buff, a slow. |
| `INFINITE` | Contribute until something removes the effect. | Yes | Yes | Equipment, an aura, a stance. |
| `TURN_BASED` | Contribute for `duration_turns` turns, aged by `advance_turn()`. | Yes | Yes | Turn-based buffs, debuffs and cooldowns. |

A `DURATION`, `INFINITE` or `TURN_BASED` effect with a `period` above zero is **periodic**: instead of contributing, its modifiers write the base value on every tick, and those writes are permanent. See [Duration and periodic effects](duration-and-periodic-effects.md).

## Anatomy of an effect

The Inspector groups an effect's fields into categories.

| Category | Fields | Covered in |
|---|---|---|
| Effect Rules | `policy`, `duration`, `period`, `duration_magnitude`, `period_magnitude`, `execute_periodic_on_application`, `period_inhibition_policy` | [Duration and periodic effects](duration-and-periodic-effects.md) |
| Turn Based Settings | `duration_turns`, `tick_on_turn_start` | [Duration and periodic effects](duration-and-periodic-effects.md#turn-based-effects) |
| Stacking | `stacking_type`, `stack_limit_count`, `factor_in_stack_count`, overflow and refresh policies | [Stacking](stacking.md) |
| Cue Management | `cues`, `require_modifier_success_to_trigger_cues`, `suppress_stacking_cues` | [Gameplay cues](../gameplay-cues.md#cues-on-effects) |
| Attribute Modifiers | `modifiers`, `executions` | [Modifiers and magnitudes](modifiers-and-magnitudes.md), [Executions and context](executions-and-context.md) |
| Event Management | `event_tags` | [Gameplay events](../gameplay-events.md#events-sent-by-effects) |
| Components | `components` | [Components](components.md) |

## Authoring an effect

GAS_Engine supports two ways of authoring an effect. Both produce the same `GameplayEffect` object, and the runtime cannot tell them apart.

### In code

Build the effect in a function, from numbers the ability or system already owns:

```gdscript
static func haste(bonus_speed: float, seconds: float) -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = bonus_speed

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = &"speed"
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var granted: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	granted.granted_tags = [&"Status.Hasted"] as Array[StringName]

	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Haste"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = seconds
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	effect.components = [granted] as Array[GameplayEffectComponent]
	return effect
```

### As an asset

Choose **Project → Tools → Create Gameplay Effect**, save the `.tres`, and fill it in the Inspector or the **Gameplay Effect** bottom panel. Abilities reference it through an export:

```gdscript
@export var haste: GameplayEffect
```

### Which to choose

| Build in code when… | Author an asset when… |
|---|---|
| The numbers belong to one ability and are already exported on it. | Several abilities, items or systems apply the same effect. |
| The effect is derived from other values at runtime. | Designers tune the effect without touching scripts. |
| You want every number visible in code review. | The effect is data a level or an item points at. |

:::tip Name your effects
The runtime overlay shows an effect by its `resource_name`, and falls back to the file name for an asset. An effect built in code has neither unless you set `resource_name`.
:::

:::warning Never change a definition at runtime
A `GameplayEffect` is shared by every spec created from it. Per-application data - level, caller-supplied values, dynamic tags - belongs on the `GameplayEffectSpec`, never on the resource.
:::

## Applying an effect

### From an ability, to its targets

```gdscript
var result: GameplayTargetApplicationResult = apply_effect_to_targets(damage, aimed)
```

`apply_effect_to_targets()` resolves each target's component, collapses several colliders of one actor into one target, checks the ability's `target_required_query` and `target_blocked_query`, and gives every target its own copy of the spec. The result separates the outcomes:

| Field | Meaning |
|---|---|
| `attempted_targets` | How many nodes the target data offered. |
| `applied_targets` / `applied_effects` | Components that received the effect, and the active effects created. |
| `rejected_targets` | Components that refused it: a tag rule, an immunity, a failed requirement. |
| `missing_asc_targets` | Nodes no component could be found for - usually a scene wiring problem. |
| `applications` | One `GameplayEffectApplicationResult` per target reached. |
| `refusal` | `NO_ACTOR_TARGETS` when the target data held no actors at all. |

### From an ability, to its caster

```gdscript
owner_asc.apply_gameplay_effect(blessing, owner_asc, get_ability_level())
```

### From game code

```gdscript
var result: GameplayEffectApplicationResult = target_asc.apply_gameplay_effect_result(
	trap_damage, null, 1.0
)
```

The second argument is the source component. Pass `null` for an effect with no instigator, such as a trap or the weather.

### With a prepared spec

Build the spec yourself when the application needs data the effect cannot know in advance - a caller-supplied value, an effect context with payloads, captured attributes taken at a chosen moment:

```gdscript
var context: GameplayEffectContext = GameplayEffectContext.new(caster_node)
var spec: GameplayEffectSpec = GameplayEffectSpec.new(charged_blast, context, 2.0)
spec.source_asc = caster_asc
spec.set_set_by_caller(&"Data.ChargeSeconds", held_seconds)

var result: GameplayEffectApplicationResult = caster_asc.apply_effect_spec_to_target_result(
	spec, target_asc
)
```

See [Caller-supplied values](modifiers-and-magnitudes.md#caller-supplied-values) and [Executions and context](executions-and-context.md).

## Reading the result

Every `apply_*_result()` call returns a `GameplayEffectApplicationResult` and emits `gameplay_effect_application_finished` with it.

| Status | Meaning |
|---|---|
| `SUCCESS` | Applied. `active_effect` and `active_handle` are set for effects that persist, and `null` for `INSTANT`. |
| `INVALID_SPEC` | No spec, or a spec that cannot be applied (for example a non-finite duration). |
| `INVALID_DEFINITION` | No effect was given. |
| `COMPONENT_REJECTED` | A component refused: a tag requirement, a failed chance roll, a custom requirement. |
| `EVALUATION_FAILED` | The arithmetic could not be evaluated. `evaluation_status` and `error_attribute_name` say why and where. |
| `IMMUNE` | An active immunity on the target matched the incoming effect. |
| `STACK_OVERFLOW_DENIED` | The stack was full and the effect denies overflow applications. |
| `CHAIN_DEPTH_EXCEEDED` | Effects applying effects recursed past the limit of 32. |

A refused application leaves nothing behind: no modifier, tag, cue, event or registration.

## Querying running effects

A `GameplayEffectQuery` is a filter over active effects. Every field you set must match; an empty query matches everything.

| Field | Matches |
|---|---|
| `effect_definition` | A specific `GameplayEffect` resource. |
| `asset_tags` | A tag query over the effect's asset tags. |
| `granted_tags` | A tag query over the tags the effect grants. |
| `source_tags` | A tag query over what the source carried when it applied the effect. |
| `target_tags` | A tag query over the target's current tags. |
| `modified_attribute` | Effects whose modifiers write this attribute. |
| `inhibition` | `ANY`, `ACTIVE_ONLY` or `INHIBITED_ONLY`. |
| `source` | Set in code: effects applied by this node. |

| Method | Returns |
|---|---|
| `find_active_effects(query)` | `Array[ActiveGameplayEffect]` |
| `find_active_effect_handles(query)` | `Array[GameplayEffectHandle]` |
| `count_active_effects(query)` | `int` |
| `get_active_effect(handle)` | The active effect, or `null`. |
| `get_active_effects()` | Every active effect on the component. |
| `get_effect_duration_remaining(handle)` / `get_effect_turns_remaining(handle)` | Time left on one effect. |

## Changing a running effect

These methods change an active effect in place and return a `GameplayEffectMutationResult` (`SUCCESS`, `HANDLE_NOT_FOUND`, `INVALID_VALUE`, `INVALID_OPERATION` or `EVALUATION_FAILED`):

| Method | Changes |
|---|---|
| `set_active_effect_level(handle, level)` | The level its magnitudes resolve at. |
| `set_active_effect_stack_count(handle, count)` | The stack count. |
| `remove_active_effect_stacks(handle, count)` | Removes some stacks. |
| `update_active_effect_set_by_caller(handle, tag, value)` | A caller-supplied value. |
| `set_active_effect_duration(handle, seconds)` | The time left. |

## Removing effects

| Method | Removes |
|---|---|
| `remove_active_effect(active_effect)` | One active effect. |
| `remove_active_effect_by_handle(handle)` | One active effect, by handle. Returns `false` if nothing matched. |
| `remove_active_effects(query)` | Every match. Returns how many were removed. |
| `remove_effects_with_tag(tag)` | Effects that grant or carry the tag. |
| `remove_effects_from_source(node)` | Effects a given node applied. |

`gameplay_effect_removal_finished(active_effect, reason)` reports why each effect ended:

| `ActiveGameplayEffect.RemovalReason` | When |
|---|---|
| `NATURAL_EXPIRATION` | Its duration or turns ran out. |
| `EXPLICIT` | Game code removed it. |
| `CLEANSE` | Another effect's removal component purged it. |
| `SOURCE_REMOVED` | The source it depended on went away. |
| `STACK_OVERFLOW` | The stack was cleared on overflow. |
| `ASC_CLEANUP` | The component was reset or torn down. |
| `GRANT_FINALIZATION_FAILED` | An ability it granted could not be committed. |

## Guarantees

- **Atomic.** An application either commits everything - base writes, contributions, tags, registration, cues, events - or nothing.
- **One spec per target.** Area effects never let one target's evaluation change what another received.
- **Recomposition, not deltas.** Removing an effect drops its contributions and recomposes the attribute from scratch, so the removal order of effects never matters.
- **Bounded chains.** Effects that apply effects stop at a depth of 32.

## In this section

- [Modifiers and magnitudes](modifiers-and-magnitudes.md) - operations, channels and every way to say "how much".
- [Duration and periodic effects](duration-and-periodic-effects.md) - timed, infinite, periodic and turn-based effects, and inhibition.
- [Stacking](stacking.md) - how repeated applications combine.
- [Components](components.md) - tags, requirements, immunity, cleansing, chained effects and granted abilities.
- [Executions and context](executions-and-context.md) - custom calculations and the data an effect carries.
