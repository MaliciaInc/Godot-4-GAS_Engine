---
title: Activation and Input
sidebar_position: 2
description: Every way an ability starts - calls, activation policies, event and tag triggers, input slots and actions - and how refusals are reported.
---

# Activation and Input

## Ways to start an ability

| From | How |
|---|---|
| Game code | `asc.try_activate_ability_handle(handle, activation_context)` |
| Several at once | `asc.try_activate_abilities_by_query(query)` returns the handles that started. |
| A one-off | `asc.give_ability_and_activate_once(scene, level, source, context)` grants, runs once and retires the grant. |
| Input | A press on the input slot or action the grant is bound to. |
| A gameplay event | A trigger on an `ON_GAMEPLAY_EVENT` ability. |
| A tag | A tag trigger on the ability. |
| Being granted | The `ON_GRANTED` policy. |
| Its own requirements | The `PASSIVE` policy. |

All of them go through the same gates and produce the same `GameplayAbilityActivationResult`: `status`, `handle` and, when it started, `instance`.

## Activation policies

`activation_policy` is frozen at grant:

| Policy | Behaviour |
|---|---|
| `MANUAL` | Starts only when asked: a call or an input. The default. |
| `ON_GRANTED` | Tries once, right after the grant. A refusal is not retried. |
| `ON_GAMEPLAY_EVENT` | Starts when a gameplay event matches one of its `GAMEPLAY_EVENT` triggers. |
| `PASSIVE` | Starts whenever its gates allow it, and is cancelled when its tag requirements stop allowing it. |
| `WHILE_INPUT_ACTIVE` | The press starts it and the release ends it. |

### Passive abilities

A passive ability is re-evaluated whenever something that could change its eligibility happens. An idle passive whose gates all pass is started. A running passive is cancelled - ignoring `can_be_cancelled()` - when `activation_blocked_query` starts matching, `activation_required_query` stops matching, or another ability blocks it. Costs and cooldowns never stop a passive that is already running.

A passive with `auto_end_on_activate_return` on ends as soon as `_activate_ability()` returns and is started again at the next re-evaluation. A passive that should stay on - an aura, a stance - sets it to `false`.

## Passing context

An activation can carry target data or an effect context from the caller - an AI that has already chosen its target, a replay, a console command:

```gdscript
var aim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
aim.append_node(enemy)
var context: GameplayEffectContext = GameplayEffectContext.new(self)
context.target_data = aim

var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(
	fireball, GameplayAbilityActivationContext.from_effect_context(context)
)
```

Inside the ability, `get_activation_target_data()` returns `aim`. An activation built with `GameplayAbilityActivationContext.from_gameplay_event(event)` carries the event instead, read with `get_activation_event()`.

## Retriggering

By default an ability that is already running refuses a second activation with `ALREADY_ACTIVE`. With `retrigger_while_active` on, the running activation is **ended** (not cancelled) and a new one starts - the second press replaces the first.

A `PER_EXECUTION` ability never answers `ALREADY_ACTIVE`: each activation runs on its own node.

## Triggers

`gameplay_event_triggers` holds `GameplayAbilityEventTrigger` resources, each with a `source` and an `event_query`:

| Source | Starts the ability when… | Notes |
|---|---|---|
| `GAMEPLAY_EVENT` | an event whose tag matches is sent to the owner. | Only heard by `ON_GAMEPLAY_EVENT` abilities. The ability receives the event. |
| `OWNED_TAG_ADDED` | the owner gains a matching tag. | Losing the tag does nothing. |
| `OWNED_TAG_PRESENT` | the owner has a matching tag, including at the moment of the grant. | Losing the tag cancels the ability. |

Tag triggers are honoured whatever the activation policy.

Matching is hierarchical: a trigger on `Event.Hit` hears `Event.Hit.Parried`. `GameplayAbilityEventTrigger.for_tag(tag)` builds a `GAMEPLAY_EVENT` trigger for one tag:

```gdscript
extends GameplayAbility


func _init() -> void:
	activation_policy = ActivationPolicy.ON_GAMEPLAY_EVENT
	gameplay_event_triggers = [
		GameplayAbilityEventTrigger.for_tag(&"Event.Hit.Parried")
	] as Array[GameplayAbilityEventTrigger]


func _activate_ability() -> bool:
	var parry: GameplayEventData = get_activation_event()
	var attacker: AbilitySystemComponent = find_asc_on(parry.instigator)
	# … riposte against the attacker
	return true
```

Override `should_respond_to_event(event)` to ignore a matching event based on the ability's own state. A tag trigger that keeps waking itself - an ability whose activation grants its own trigger tag - is stopped after 64 passes with a warning.

See [Gameplay events](../gameplay-events.md) for sending events.

## Input

GAS_Engine does not read Godot's input itself. The game forwards presses and releases to the component, by **slot** or by **action**:

```gdscript
const ABILITY_ACTIONS: Array[StringName] = [&"attack", &"dash", &"ultimate"]


func _unhandled_input(event: InputEvent) -> void:
	for action: StringName in ABILITY_ACTIONS:
		if event.is_action_pressed(action):
			asc.ability_local_input_action_pressed(action)
		elif event.is_action_released(action):
			asc.ability_local_input_action_released(action)
```

| Routing | Forward with | Bind with |
|---|---|---|
| By slot (an `int`) | `ability_local_input_pressed(id)` / `ability_local_input_released(id)` | `give_ability(scene, level, input_id)`, or `bind_ability_handle_to_input(handle, id)` |
| By action (a `StringName`) | `ability_local_input_action_pressed(action)` / `ability_local_input_action_released(action)` | The ability's own `input_action` export, or `GameplayAbilityGrantOptions.input_action` |

A grant can have both. `bind_ability_handle_to_input()` releases the slot from any other grant unless `unbind_others` is `false`.

### What a press does

| The ability is… | Press | Release |
|---|---|---|
| Idle | An activation attempt. | Nothing. |
| Running | `_active_input_pressed(asc)` | `_active_input_released(asc)`, or the end of the ability under `WHILE_INPUT_ACTIVE`. |

Tasks waiting on the input hear it before these hooks, whether it arrives by slot or by action. A press on a `PER_EXECUTION` grant, by slot or by action, starts one more activation even while earlier ones run.

A hold-and-release ability waits for the release as a task:

```gdscript
extends GameplayAbility

@export var javelin: GameplayEffect


func _activate_ability() -> bool:
	var release: AbilityTaskWaitInput = wait_input_released()
	await release.completed()
	if release.state != GameplayAbilityTask.State.SUCCEEDED:
		return false
	if not commit_ability().is_ok():
		return false
	var aimed: GameplayAbilityTargetData = get_activation_target_data()
	if aimed != null:
		apply_effect_to_targets(javelin, aimed)
	return true
```

### Confirm and cancel

Many abilities ask "confirm or cancel?" without caring which keys those are.

| Member | Purpose |
|---|---|
| `generic_confirm_input_id` / `generic_cancel_input_id` | Slots whose **release** means yes or no. `-1` by default. |
| `input_confirm()` / `input_cancel()` | Say yes or no directly - a touch button, a gamepad prompt. |
| `generic_confirmed` / `generic_cancelled` | Signals emitted when either is said. |

A yes or no reaches waiting tasks first and interactive targeting providers second. See [`wait_confirm_cancel`](ability-tasks.md#input-and-flow) and [Targeting](../targeting.md).

## Checking before offering

A UI should offer only what would start:

```gdscript
button.disabled = not asc.can_activate_ability_handle(handle)
```

`can_activate_ability_handle(handle, emit_failure)` runs every gate without starting anything; with `emit_failure` it also reports the refusal. It prices the `costs` list only - see [Costs and cooldowns](costs-and-cooldowns.md#checking-affordability).

## When an activation is refused

Every refusal by a gate emits, on the component:

- `ability_activation_failed(ability, reason)` with the `AbilityRuntime.ActivationError`.
- `ability_activation_failed_with_tag(handle, reason, tag)` with a tag naming the reason, for messages, icons and sounds.

| Reason | Default tag |
|---|---|
| `ALREADY_ACTIVE` | `Ability.Failed.AlreadyActive` |
| `ON_COOLDOWN` | `Ability.Failed.Cooldown` |
| `BLOCKED_TAG` | `Ability.Failed.BlockedTags` |
| `MISSING_TAG` | `Ability.Failed.MissingTags` |
| `INSUFFICIENT_RESOURCES` | `Ability.Failed.Cost` |
| `INTERNAL_ERROR` | `Ability.Failed.Internal` |
| `PENDING_REMOVAL` | `Ability.Failed.PendingRemoval` |
| `BLOCKED_BY_ACTIVE_ABILITY` | `Ability.Failed.BlockedByAbility` |
| `BLOCKED_EXTERNALLY` | `Ability.Failed.BlockedExternally` |

Override any of them with the project setting `gas_engine/failure_tags/<n>`, where `<n>` is the reason's integer value. See [Configuration and export](../configuration-and-export.md).
