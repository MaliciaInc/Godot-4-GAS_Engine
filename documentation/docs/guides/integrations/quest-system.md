---
title: QuestSystem
sidebar_position: 3
description: Turning quest announcements into gameplay events, and gameplay events into quest progress, with QuestSystemGasBridge.
---

# QuestSystem

`QuestSystemGasBridge` connects QuestSystem and an ability system in both directions:

- **Outward** - a quest becoming available, accepted or completed sends a gameplay event.
- **Inward** - a gameplay event can count as progress on a quest, and can complete it.

| | |
|---|---|
| Certified QuestSystem version | `2.0.2.4_4` |
| Uses | QuestSystem's `new_available_quest`, `quest_accepted` and `quest_completed` signals, and its `update_quest` / `complete_quest` methods |

## Bindings

Each `QuestGasBinding` describes one quest:

| Field | Meaning |
|---|---|
| `quest_id` | The quest's id. Ids start at `1`. |
| `available_event_tag` | Event sent when the quest becomes available. |
| `accepted_event_tag` | Event sent when it is accepted. |
| `completed_event_tag` | Event sent when it is completed. |
| `objective_event_tag` | An event under this tag counts as progress on the quest. |
| `auto_complete_on_objective_event` | Whether that progress completes the quest. |

Every tag is optional; an empty one means nothing is sent, or nothing counts, at that moment.

## Binding the bridge

```gdscript
func _ready() -> void:
	var wolves: QuestGasBinding = QuestGasBinding.new()
	wolves.quest_id = 3
	wolves.completed_event_tag = &"Event.Quest.WolvesCleared"
	wolves.objective_event_tag = &"Event.Kill.Wolf"
	wolves.auto_complete_on_objective_event = true

	var bridge: QuestSystemGasBridge = QuestSystemGasBridge.new()
	bridge.bindings = [wolves] as Array[QuestGasBinding]
	add_child(bridge)
	bridge.binding_rejected.connect(func(quest_id: int) -> void: push_warning("Quest binding %d refused" % quest_id))
	bridge.bind_installed(get_tree(), player_asc)
```

| Method | Purpose |
|---|---|
| `bind_installed(tree, asc)` | Bind to the running QuestSystem autoload. |
| `bind(quest_system_node, asc)` | Bind to a specific QuestSystem-shaped node. |
| `unbind()` | Let go of both directions. |

Binding fails, and `binding_rejected(quest_id)` is emitted, when a binding is invalid or two bindings name the same quest. The `update_quest` and `complete_quest` methods are only required when some binding auto-completes.

## Outward: quests to events

When QuestSystem announces a quest the bridge has a binding for, it sends that moment's event to the bound component:

| Event field | Value |
|---|---|
| `event_tag` | The binding's tag for that moment. |
| `instigator`, `target` | The component's avatar. |
| `magnitude` | The quest id, so a listener can tell which quest. |

`quest_event_forwarded(quest_id, event_tag)` is emitted after each one.

## Inward: events to progress

Every gameplay event the component receives is matched, hierarchically, against each binding's `objective_event_tag`. On a match the bridge calls `update_quest` for that quest and, with `auto_complete_on_objective_event`, marks its objective completed and calls `complete_quest`.

The bridge only acts on quests QuestSystem has announced to it - it never looks quests up by id on its own. An event the bridge is itself sending outward is never counted as progress, so a quest whose completion event matches its own objective does not complete itself again.

Progress events come from anywhere: an effect's `event_tags`, a death event sent by an attribute set, a Dialogic timeline. See [Gameplay events](../gameplay-events.md).
