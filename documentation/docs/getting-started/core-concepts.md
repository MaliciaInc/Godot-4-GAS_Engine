---
title: Core Concepts
sidebar_position: 2
description: The mental model behind GAS_Engine - components, attributes, effects, abilities, tags, events, cues and tasks.
---

# Core Concepts

GAS_Engine is built from a small number of ideas that every subsystem shares. Learn these once and the rest of the documentation reads as detail.

## The pieces at a glance

```text
                 ┌──────────────────────────── AbilitySystemComponent ───────────────────────────┐
                 │                                                                              │
  AttributeSet ──►  attributes     (base value + current value per attribute)                   │
                 │                                                                              │
  GameplayEffect ►  active effects (contributions, tags, cues, periodic ticks)                  │
                 │                                                                              │
  ability scene ─►  granted abilities (specs, addressed by GameplayAbilityHandle)               │
                 │                                                                              │
                 │  tags (reference-counted)   ·   events   ·   tasks   ·   cooldowns            │
                 └──────────────────────────────────────────────────────────────────────────────┘
                          │                               │
                  signals the game listens to      cues the GameplayCueManager plays
```

| Concept | Class | One sentence |
|---|---|---|
| Ability system | `AbilitySystemComponent` (ASC) | The node that owns everything gameplay knows about one entity. |
| Attributes | `AttributeSet`, `AttributeData` | Every number about an entity, each with a durable base and a derived current value. |
| Effect | `GameplayEffect` | A definition of what happens to attributes and tags: instant, timed, infinite or turn-based. |
| Ability | `GameplayAbility` | A `Node` script, saved as a scene, that pays for itself and applies effects. |
| Tag | `StringName` such as `State.Stunned` | A hierarchical label used for rules, queries, routing and state. |
| Event | `GameplayEventData` | A typed message sent to an ASC that can wake abilities and tasks. |
| Cue | `GameplayCueNotify`, `GameplayCueHandler` | Cosmetic feedback - particles, sounds, UI - addressed by tag. |
| Task | `GameplayAbilityTask` | An asynchronous step inside an ability: wait, aim, animate, listen. |
| Target data | `GameplayAbilityTargetData` | Who and where an ability was aimed at. |

## The AbilitySystemComponent

Every entity that takes part in gameplay has one `AbilitySystemComponent`, normally as a child node named `AbilitySystemComponent`. It is a facade: the state lives in focused runtimes (`attributes`, `tags`, `effects`, `scheduler`, `ability_runtime`, `events`), and the component exposes the public API and the signals.

The ASC distinguishes two roles that are usually the same node:

- the **owner** - whoever the abilities belong to;
- the **avatar** - the body effects and cues act on (`get_effect_target()`).

By default both are the ASC's parent. A game with possession, mounts or vehicles calls `init_ability_actor_info(owner, avatar)` to separate them. See [The AbilitySystemComponent](../guides/ability-system-component.md).

## Attributes: base and current

An attribute has two values, and they answer different questions:

- **base value** - what the entity durably is. Instant effects, periodic ticks and execution calculations write here.
- **current value** - the base plus every active contribution, clamped. Buffs and debuffs live here.

```text
base 10  ──►  + active "+10 attack" buff  ──►  × active "×2" buff  ──►  current 40
```

Gameplay code never writes `current_value`. It changes the base through `set_attribute_base()` or, more usually, applies an effect. See [Attributes](../guides/attributes.md).

## A modifier is a contribution, not a write

This is the most important idea in the engine. A `+5 attack` buff does not set attack to 15. It registers a **contribution** the aggregator folds in while the effect is active and withdraws when the effect ends. Nothing has to remember to undo anything, so any number of buffs and debuffs, expiring in any order, always land on the right value.

## Effects: definition, spec, active effect

An effect exists at three levels:

| Level | Class | Lifetime |
|---|---|---|
| Definition | `GameplayEffect` (a `Resource`) | Authored once, never changed at runtime. |
| Application | `GameplayEffectSpec` | One application to one target, with its level, context and caller-supplied values. |
| Running effect | `ActiveGameplayEffect` + `GameplayEffectHandle` | Exists only for `DURATION`, `INFINITE` and `TURN_BASED` effects, until it is removed. |

`INSTANT` effects change base values and leave nothing behind. The other three policies register contributions, grant tags, play persistent cues and can be inhibited, stacked, queried and removed. See [Gameplay effects](../guides/gameplay-effects/index.md).

## Abilities: scene, grant, activation

An ability is authored as a **script** (behaviour) plus a **scene** (the numbers, set in the Inspector). Granting it gives the ASC a **spec** addressed by a `GameplayAbilityHandle`:

```text
give_ability(scene) ──► GameplayAbilitySpec (frozen definition, level, input) ──► handle
try_activate(handle) ─► _activate_ability() ─► commit_ability() ─► effects ─► end_ability()
```

Three rules shape every ability:

1. **The definition is frozen at grant time.** Costs, cooldowns, tag rules and policies are read from a snapshot taken immediately after the scene is instantiated. Configure them in the scene, in `_init()` or in a property setter - never in `_ready()`.
2. **An ability never deducts its own cost.** It calls `commit_ability()`, which pays every cost and starts every cooldown as one transaction, or refuses and changes nothing.
3. **Activation answers with a result, not a boolean.** `GameplayAbilityActivationResult` says exactly why an activation did not start.

See [Abilities](../guides/abilities/index.md).

## Tags

Tags are hierarchical `StringName`s such as `Status.Burning.Strong`. Matching is by segment: a check for `Status.Burning` matches `Status.Burning.Strong`, but `Damage.Fire` never matches `Damage.Firestorm`.

Tags on an ASC are **reference-counted**. Two effects that both grant `State.Slowed` hold it twice; removing one leaves it held once. Tags drive activation requirements, blocking, cancellation, immunity, effect requirements, event routing and target filtering, through one shared definition of what a match means. See [Gameplay tags](../guides/gameplay-tags.md).

## Events, cues and tasks

- **Events** (`send_gameplay_event`) are how the world talks to abilities: an event tag can wake an ability authored to trigger on it, or resume a task waiting for it. See [Gameplay events](../guides/gameplay-events.md).
- **Cues** are how gameplay talks to presentation. An ability or effect names a cue tag; the `GameplayCueManager` autoload plays whatever the project bound to that tag. A missing cue never breaks gameplay. See [Gameplay cues](../guides/gameplay-cues.md).
- **Tasks** let an ability wait without blocking or leaking: wait for a delay, a target, an input, an event, an attribute threshold, an animation. Tasks are owned by the ASC and cancelled with their ability. See [Ability tasks](../guides/abilities/ability-tasks.md).

## Handles, results and atomic failure

GAS_Engine is designed so that a mistake is refused loudly rather than half-applied:

- **Handles, not objects.** Grants are addressed by `GameplayAbilityHandle`, running effects by `GameplayEffectHandle`. A handle whose target is gone resolves to nothing instead of to whatever reused its slot.
- **Results, not booleans.** Applications return `GameplayEffectApplicationResult`, commits return `AbilityCommitResult`, activations return `GameplayAbilityActivationResult`, target applications return `GameplayTargetApplicationResult`.
- **Atomic failure.** An application that cannot be evaluated - division by zero, a non-finite value, an unknown attribute, a refused requirement - leaves no modifier, tag, cue or event behind.

## Code and the Ability Composer

The `.gd` file is always the ability. The [Ability Composer](../guides/ability-composer/index.md) is a visual editor that draws that file as a graph and writes your edits back into it; there is no second representation to keep in sync. You can move between the script editor and the Composer freely.

## Where to go next

- Put these ideas to work in the [Quickstart](../quickstart.md).
- See how the files are organised in [Project layout](project-layout.md).
