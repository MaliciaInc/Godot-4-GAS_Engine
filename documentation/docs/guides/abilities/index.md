---
title: Abilities
sidebar_position: 1
description: How a GameplayAbility is authored, granted, activated, committed and ended, and what it can read and call while it runs.
---

# Abilities

A `GameplayAbility` is anything an entity can **do**: an attack, a spell, a dodge, a passive regeneration, an interaction. It is a `Node` script saved as a scene, granted to an `AbilitySystemComponent`, and activated through the component.

## Anatomy of an ability

```gdscript
extends GameplayAbility

@export var damage: GameplayEffect


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	var pick: AbilityTaskWaitTargetData = wait_target_data()
	await pick.completed()
	if pick.target_data == null:
		return false

	apply_effect_to_targets(damage, pick.target_data)
	return true
```

| Part | Role |
|---|---|
| The **script** | The behaviour, in `_activate_ability()`. |
| The **scene** | A `Node` root with the script attached; the Inspector holds the numbers and the rules. |
| `_activate_ability()` | Runs when the activation is accepted. Return `true` for success. It may `await`. |
| `commit_ability()` | Pays every cost and starts every cooldown as one transaction. |
| The return value | With `auto_end_on_activate_return` (the default), returning ends the ability. |

The **Ability Composer** creates the script and the scene together from **New ability**, and draws the body as a graph. See [Ability Composer](../ability-composer/index.md).

## The lifecycle

```text
give_ability(scene) ─► spec + handle ─► try_activate ─► gates ─► _activate_ability()
                                                                     │
                                            commit_ability() ◄───────┤
                                            tasks, effects, cues ◄───┤
                                                                     ▼
                                                               end_ability()
```

### 1. Granting

`give_ability(scene)` instantiates the scene once, validates it, freezes its definition into a `GameplayAbilityDefinitionSnapshot`, and returns a `GameplayAbilityHandle`. See [Granting and loadouts](granting-and-loadouts.md).

:::danger Configure rules before `_ready()`
The snapshot is taken **immediately after the scene is instantiated**, before `_ready()` runs. Costs, cooldowns, tag queries, policies and triggers set in `_ready()` never reach the engine: a cost set there makes the ability silently free. Set them in the scene, in `_init()`, or in a property setter. The engine reports an ability whose fields drift from its snapshot at its first commit.
:::

### 2. Activating

```gdscript
var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)
```

The component checks the grant's gates in this order and refuses at the first that fails:

| Gate | Refusal |
|---|---|
| The grant is being removed. | `PENDING_REMOVAL` |
| An outside block covers it. | `BLOCKED_EXTERNALLY` |
| It is already running and `retrigger_while_active` is off. | `ALREADY_ACTIVE` |
| The owner matches `activation_blocked_query`. | `BLOCKED_BY_TAGS` |
| One of its cooldown tags is present. | `ON_COOLDOWN` |
| The owner does not match `activation_required_query`. | `MISSING_REQUIRED_TAGS` |
| A running ability, a relationship row or an active effect blocks it. | `BLOCKED_BY_ACTIVE_ABILITY` |
| The component's tag relationship table refuses it. | `BLOCKED_BY_TAGS` / `MISSING_REQUIRED_TAGS` |
| Its `costs` cannot be paid right now. | `INSUFFICIENT_RESOURCES` |
| An event-triggered activation's instigator fails the source rules. | `BLOCKED_BY_TAGS` / `MISSING_REQUIRED_TAGS` |

A handle that names nothing on this component answers `SPEC_NOT_FOUND`, and a cost list that cannot be resolved answers `INVALID_DEFINITION`.

`SUCCESS` means the activation **started**. What the body does afterwards is reported by the ability's `ability_ended(was_cancelled)` signal and the component's `ability_runtime_ended` signal. See [Activation and input](activation-and-input.md) and [Tag rules](tag-rules.md).

### 3. Committing

```gdscript
var paid: AbilityCommitResult = commit_ability()
if not paid.is_ok():
	return false
```

Commit before anything visible happens, or after a confirmation when the player may still back out. A commit that fails changes nothing. See [Costs and cooldowns](costs-and-cooldowns.md).

### 4. Ending

| How | What happens |
|---|---|
| Return from `_activate_ability()` | Ends the ability when `auto_end_on_activate_return` is on. Returning anything but `true` ends it as cancelled. |
| `end_ability()` | Ends it now. |
| `end_ability(true)` or `abort_ability()` | Ends it as cancelled. |
| `cancel_all_abilities()`, a cancel query, a cancelling effect | Cancelled from outside. |

Ending an ability cancels every task it owns, stops every aiming provider it started, ends every persistent cue it activated, and removes its `activation_owned_tags`. Ending is not un-granting: the grant stays and can activate again.

Set `auto_end_on_activate_return` to `false` for an ability that must outlive its activation function - a stance, a toggle, a channel waiting on something outside it - and call `end_ability()` when it is done.

### Waiting for an ability to finish

`completed()` returns immediately for an ability that is not running and otherwise waits for it to end. Use it instead of awaiting `ability_ended` directly: an activation that was refused, or had nothing to do, has already ended by the time the caller looks.

```gdscript
var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)
if result.is_ok():
	await result.instance.completed()
```

## Instancing

`instancing_policy` decides which node runs an activation:

| Policy | Behaviour |
|---|---|
| `PER_ACTOR` | One node, created at grant and kept as a child of the component. Fields persist between activations. The default. |
| `PER_EXECUTION` | A new node for every activation, freed when it ends, so several can run at once. |
| `NON_INSTANCED` | Also a new node per activation, never kept. Nothing may read state back from it afterwards. |

`PASSIVE` abilities must be `PER_ACTOR`; a passive `PER_EXECUTION` ability is refused at grant.

## What an ability can read

| Member | Meaning |
|---|---|
| `owner_asc` | The component this ability is granted to. |
| `owner_asc.get_effect_target()` | The avatar - the body this ability acts through. The ability node is not the character. |
| `get_activation_target_data()` | Target data the caller passed in the activation context, or `null`. |
| `get_activation_event()` | The gameplay event that triggered this activation, or `null`. |
| `current_context` | The effect context the activation was started with, or `null`. |
| `get_ability_level()` / `get_input_id()` | The grant's level and input slot. |
| `get_ability_handle()` | This grant's handle. |
| `is_active` / `activation_id` | Whether it is running, and which activation this is. |
| `current_spec` | The grant: frozen definition, level, input binding, dynamic tags. |

## What an ability can call

| Method | Purpose |
|---|---|
| `commit_ability()` | Pay costs and start cooldowns. |
| `check_cost()` / `check_cooldown()` | Ask without paying. |
| `apply_effect_to_targets(effect, target_data)` | Apply an effect to everything aimed at, one spec per target. See [Gameplay effects](../gameplay-effects/index.md#applying-an-effect). |
| `accepts_target(target_asc)` | Whether a component passes this ability's target tag rules. |
| `execute_cue(tag)` | Play a one-shot cue on the avatar. |
| `activate_persistent_cue(tag, params)` / `deactivate_persistent_cue(handle)` | A cue that runs until stopped or until the ability ends. |
| `wait_delay`, `wait_target_data`, `wait_input_pressed`, `wait_gameplay_event`, … | Tasks. See [Ability tasks](ability-tasks.md). |
| `aim_with(provider)` | Start interactive targeting. See [Targeting](../targeting.md#providers-interactive-aiming). |
| `get_cooldown_state()` / `get_cooldown_tags()` | Cooldown information for a UI. |
| `find_asc_on(node)` | The component a node belongs to. |

## Hooks you can override

| Hook | Called when |
|---|---|
| `_activate_ability()` | The activation is accepted. |
| `on_granted()` | A `PER_ACTOR` instance has been granted and can find itself by handle. |
| `on_removed()` | A `PER_ACTOR` instance's grant is being taken away. |
| `on_avatar_changed(old_avatar, new_avatar)` | The component's avatar changed. |
| `should_respond_to_event(event)` | An event matched a trigger; return `false` to ignore it. Asked of the `PER_ACTOR` instance. |
| `can_be_cancelled()` | Something asks to cancel the ability; return `false` for an uninterruptible stretch. `set_can_be_cancelled()` overrides the answer at runtime. |
| `_active_input_pressed(asc)` / `_active_input_released(asc)` | The bound input changes while the ability runs. |

## Reference abilities

The six abilities in `addons/GAS_Engine/reference/` each add one idea to the example at the top of this page. See [Project layout](../../getting-started/project-layout.md#reference-abilities).

## In this section

- [Activation and input](activation-and-input.md) - policies, triggers, input binding, confirm and cancel.
- [Costs and cooldowns](costs-and-cooldowns.md) - paying for an ability and waiting to use it again.
- [Tag rules](tag-rules.md) - requirements, blocking, cancellation and the relationship table.
- [Granting and loadouts](granting-and-loadouts.md) - grants, sources, removal and ability sets.
- [Ability tasks](ability-tasks.md) - waiting, aiming, animating and listening inside an ability.
