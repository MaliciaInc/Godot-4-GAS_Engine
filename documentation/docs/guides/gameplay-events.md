---
title: Gameplay Events
sidebar_position: 6
description: Sending tagged events to a component, what they carry, who receives them and in which order, and the events effects send by themselves.
---

# Gameplay Events

A **gameplay event** is a tagged message sent to one component: "this character parried", "this character was hit by a critical", "the quest objective was reached". Events wake abilities that are listening for them and tasks that are waiting on them, without the sender knowing who listens.

## Sending an event

```gdscript
var parried: GameplayEventData = GameplayEventData.new()
parried.event_tag = &"Event.Hit.Parried"
parried.instigator = attacker
parried.target = defender
defender_asc.send_gameplay_event(parried)
```

The event is delivered to the component it is sent to. To tell two characters, send it to both.

## What an event carries

| Field | Meaning |
|---|---|
| `event_tag` | The tag it is sent under. An event with an empty tag is ignored. |
| `instigator` | Who caused it. May be `null`. |
| `target` | Who it is about. |
| `magnitude` | One number, when the event has one. |
| `context` | The `GameplayEffectContext` behind it, when an effect sent it. |
| `optional_object`, `optional_object2` | Two slots for anything else - a weapon, a card, a definition. |
| `instigator_tags`, `target_tags` | The tags each side held when the event was sent. |
| `target_data` | What the event was aimed at, when it came from something aimed. |

`instigator_tags` and `target_tags` are filled in when the event is dispatched, from the instigator's and the target's components, unless the sender filled them in already. A listener that runs later still sees the moment the event happened.

## Who receives it, and in what order

1. **Tasks** waiting for a matching event hear it first, so an ability already waiting is not beaten to it by a second activation.
2. The component emits **`gameplay_event_received(event)`**, for game code.
3. **Abilities** with a matching `GAMEPLAY_EVENT` trigger and the `ON_GAMEPLAY_EVENT` policy are activated with the event.

Listeners are chosen before any of them runs: an ability granted or removed while the event is being handled affects the next event, not this one.

### Matching

Matching is hierarchical and one-directional. A listener on `Event.Hit` receives `Event.Hit`, `Event.Hit.Parried` and `Event.Hit.Parried.Perfect`. A listener on `Event.Hit.Parried` does not receive `Event.Hit`, and neither receives `Event.Hitch`.

`GameplayEventRuntime.matches(event_tag, listener_tag)` answers the same question for your own code.

## Receiving an event

| Where | How |
|---|---|
| In an ability that starts on the event | A `GAMEPLAY_EVENT` trigger, then `get_activation_event()`. See [Triggers](abilities/activation-and-input.md#triggers). |
| In a running ability | `wait_gameplay_event(tag)` for one event, or `wait_gameplay_events(tag, only_match_exact, from_asc)` for every event until the ability ends. See [Ability tasks](abilities/ability-tasks.md). |
| In game code | The component's `gameplay_event_received` signal. |

A running ability can listen on another character's component by passing `from_asc`:

```gdscript
var hits: AbilityTaskWaitGameplayEvent = wait_gameplay_events(&"Event.Hit", false, guarded_ally_asc)
hits.event_received.connect(_on_ally_hit)
```

An ability started by an event can be restricted by who sent it with `source_required_query` and `source_blocked_query`, which read `instigator_tags`. See [Source rules](abilities/tag-rules.md#source-rules).

## Events sent by effects

An effect sends an event for each tag in its `event_tags` to the component it is applied to:

- when it is applied,
- on every periodic tick,
- when a stack joins an existing application.

```gdscript
var poison: GameplayEffect = GameplayEffect.new()
poison.resource_name = "Spider venom"
poison.policy = GameplayEffect.DurationPolicy.DURATION
poison.duration = 6.0
poison.period = 1.0
poison.event_tags = [&"Event.Damage.Poison"] as Array[StringName]
```

The event's `target` is the receiving avatar, its `context` is the application's effect context, and its `instigator` is the context's instigator. `magnitude` is not filled in.

Tags injected into a spec with `spec.inject_tag()` - by an execution marking a hit as `Hit.Critical`, for example - are sent as events the same way.

For events that depend on the result, such as a death, send the event from `post_gameplay_effect_execute` on the attribute set. See [Execute hooks on the attribute set](gameplay-effects/executions-and-context.md#execute-hooks-on-the-attribute-set).

## Events from outside the ability system

Anything that can reach a component can send an event. The [Dialogic integration](integrations/dialogic.md) sends them from dialogue timelines, and the [QuestSystem integration](integrations/quest-system.md) forwards quest progress as events.

On a networked game, send events through the network runtime so the authority receives them. See [Networking](networking.md).
