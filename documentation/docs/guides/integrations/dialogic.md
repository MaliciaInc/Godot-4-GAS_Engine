---
title: Dialogic
sidebar_position: 1
description: Sending gameplay events and adding or removing tags from Dialogic timelines through DialogicGasBridge.
---

# Dialogic

`DialogicGasBridge` lets a Dialogic timeline talk to an ability system: send a gameplay event, add a tag, remove a tag. A dialogue cannot activate an ability directly - an event wakes whatever ability is triggered on it, through the ordinary gates.

| | |
|---|---|
| Certified Dialogic version | `2.0-alpha-20` |
| Uses | Dialogic's `signal_event` signal, and nothing else |

## Binding the bridge

Add a bridge to the scene and bind it to the component a dialogue speaks for, on a **channel** you name:

```gdscript
func _ready() -> void:
	var bridge: DialogicGasBridge = DialogicGasBridge.new()
	add_child(bridge)
	if not bridge.bind_installed(get_tree(), player_asc, &"Player"):
		push_warning("Dialogic is not running; dialogue cannot reach the player's abilities.")
```

| Method | Purpose |
|---|---|
| `bind_installed(tree, asc, channel)` | Bind to the running Dialogic autoload. `false` when Dialogic is not installed or not enabled. |
| `bind(dialogic_node, asc, channel)` | Bind to a specific Dialogic-shaped node. |
| `unbind()` | Stop listening. Safe to call at any time. |

Several bridges can listen to the same dialogue, each on its own channel - one for the player, one for a companion.

## Writing the messages

In a timeline, add a **signal event** whose argument is a dictionary:

```text
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"send_event","tag":"Event.Dialogue.Accepted","magnitude":3}"]
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"add_tag","tag":"State.Sworn"}"]
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"remove_tag","tag":"State.Sworn"}"]
```

| Key | Meaning |
|---|---|
| `bridge` | Always `"GAS_Engine"`. |
| `channel` | Which bound bridge the message is for. |
| `command` | `send_event`, `add_tag` or `remove_tag`. |
| `tag` | A tag, spelled exactly. It is validated, never corrected. |
| `magnitude` | Optional number carried by `send_event`. |

| Command | Does |
|---|---|
| `send_event` | Sends a gameplay event with that tag and magnitude to the component. See [Gameplay events](../gameplay-events.md). |
| `add_tag` / `remove_tag` | Adds or removes one reference to a loose tag. |

A tag added by a dialogue stays until something removes it - usually a later `remove_tag`.

## Messages that are refused

Dialogic's signal is shared by the whole game. A message that is not a dictionary addressed to `GAS_Engine`, or is for another channel, is ignored silently. A message addressed to this bridge that is malformed is refused and reported through `command_rejected(error)`:

| `DialogicGasCommandParser.Error` | Cause |
|---|---|
| `MISSING_CHANNEL` | No `channel`. |
| `UNKNOWN_COMMAND` | A `command` other than the three. |
| `INVALID_TAG` | A `tag` that is not a legal tag. |
| `INVALID_MAGNITUDE` | A `magnitude` that is not a number. |

Every command carried out is reported through `command_applied(command)`.

:::warning Declare the tags your timelines use
The bridge checks that a tag is spelled like a tag, not that your project declares it. A typo such as `State.Sword` for `State.Sworn` is added as a new tag that nothing listens for.
:::

## Reacting in an ability

An ability that should react to the dialogue listens for the event:

```gdscript
extends GameplayAbility


func _init() -> void:
	activation_policy = ActivationPolicy.ON_GAMEPLAY_EVENT
	gameplay_event_triggers = [
		GameplayAbilityEventTrigger.for_tag(&"Event.Dialogue.Accepted")
	] as Array[GameplayAbilityEventTrigger]


func _activate_ability() -> bool:
	var accepted: GameplayEventData = get_activation_event()
	# accepted.magnitude is the number the timeline sent
	return true
```
