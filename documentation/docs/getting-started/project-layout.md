---
title: Project Layout
sidebar_position: 3
description: What lives in addons/GAS_Engine, what lives in res://gas_engine, and how to lay out a game built on GAS_Engine.
---

# Project Layout

A project using GAS_Engine has three kinds of files: the engine, the project registries the engine maintains, and your game.

```text
res://
├── addons/
│   └── GAS_Engine/          The engine. Replaced as a whole on update, never edited.
├── gas_engine/              Your project's tag and cue registries. Yours: commit them.
│   ├── gameplay_tags.gd
│   └── gameplay_cues.gd
└── game/                    Your attribute sets, abilities, effects, cues and characters.
```

## The engine folder

| Folder | What is in it |
|---|---|
| `abilities/` | `GameplayAbility`, specs and handles, ability sets, costs (`costs/`) and every ability task (`tasks/`). |
| `animation/` | The surface and ownership helpers behind the animation task. |
| `attributes/` | `AttributeSet`, `AttributeData`, `GameplayAttributeRef` and the aggregation math. |
| `compatibility/` | `GameplayCompatibilityProfile`, which selects the attribute aggregation profile. |
| `components/` | `AbilitySystemComponent` and the runtimes behind it. |
| `cooldowns/` | `AbilityCooldownState`, the snapshot a UI draws a cooldown from. |
| `cues/` | Cue notifies, handlers, parameters, bindings, and the ready-made templates in `notifies/`. |
| `debug/` | `GasDebugOverlay`, `GasDebugCommands`, `GasDebugOptions`, `GasDebugChannel`, attribute history. |
| `editor/` | Editor-only: the Ability Composer, effect asset creation and the Gameplay Effect panel, inspector pickers, the Debugger tab, diagnostics. |
| `effects/` | `GameplayEffect`, specs, active effects, queries, `components/` and `executions/`. |
| `events/` | `GameplayEventData` and event dispatch. |
| `gameplay_tag/` | Tag queries, the registry, the generator, redirects and restrictions. |
| `icons/` | The icons the editor shows for the engine's classes and tools. |
| `integrations/` | Optional bridges for Dialogic, GLoot and QuestSystem. |
| `magnitudes/` | Every way a modifier can say how much. |
| `managers/` | The `GameplayCueManager` autoload. |
| `networking/` | The network runtime, replication, prediction, the transport (`transport/`) and the bit stream messages cross as (`wire/`). |
| `reference/` | Six complete, commented abilities to read and copy. |
| `target_data/` | `GameplayAbilityTargetData`, hits, the effect context and context payloads. |
| `targeting/` | The physics service, filters, providers (`providers/`), presets (`presets/`) and reticles. |
| `utilities/` | Project settings and source-file helpers. |

:::info The editor boundary
Nothing outside `addons/GAS_Engine/editor/` references anything inside it, so no part of the Composer or the other editor tools can be loaded by a running game. The engine's test suite enforces this.
:::

## The `gas_engine` folder

`res://gas_engine/` holds two GDScript files that **are** the project's registries - not caches, not copies. The plugin creates them if they are missing and otherwise only writes to them when you change tags or cues through the editor. Both are safe to edit by hand.

### `gameplay_tags.gd`

Declares `class_name GameplayTags`: one constant per tag, so code can reach a tag without spelling the string, plus three dictionaries.

```gdscript
@tool
class_name GameplayTags

const State_Stunned: StringName = &"State.Stunned"
const Status_Burning: StringName = &"Status.Burning"


const REDIRECTS: Dictionary[StringName, StringName] = {
	&"Status.OnFire": &"Status.Burning",
}


const RESTRICTED: Dictionary[StringName, StringName] = {
	&"Vendor": &"Vendor Plugin Team",
}


const COMMENTS: Dictionary[StringName, String] = {
	&"State.Stunned": "Cannot act; set by stun effects only.",
}
```

| Declaration | Meaning |
|---|---|
| Constants | The tags the project declares. |
| `REDIRECTS` | An old tag name and the name it now resolves to. |
| `RESTRICTED` | A tag branch another team or plugin owns; adding tags under it is refused with the owner named. |
| `COMMENTS` | A note about a tag. |

See [Gameplay tags](../guides/gameplay-tags.md).

### `gameplay_cues.gd`

Declares `class_name GameplayCues`: which scene or script answers which cue tag.

```gdscript
@tool
class_name GameplayCues

const BINDINGS: Dictionary[StringName, PackedScene] = {
	&"Cue.Hit.Fire": preload("res://game/cues/fire_hit.tscn"),
}


const HANDLERS: Dictionary[StringName, Script] = {
	&"Cue.Screen.Shake": preload("res://game/cues/screen_shake_handler.gd"),
}


const OVERRIDE_PARENT: Array[StringName] = [
]
```

See [Gameplay cues](../guides/gameplay-cues.md).

Both paths can be changed in Project Settings; see [Configuration and export](../guides/configuration-and-export.md).

## Laying out your game

GAS_Engine imposes no layout on your own files. This one keeps each kind of gameplay data easy to find:

```text
res://game/
├── attributes/     hero_attributes.gd, enemy_attributes.gd
├── abilities/      fireball.gd + fireball.tscn, one pair per ability
├── effects/        shared effect assets (.tres) or effect builder scripts
├── executions/     GameplayExecutionCalculation and GameplayMagnitudeCalculation scripts
├── cues/           cue scenes (GameplayCueNotify roots) and GameplayCueHandler scripts
└── characters/     scenes that own an AbilitySystemComponent
```

## Reference abilities

`addons/GAS_Engine/reference/` contains six complete abilities, each written by hand and commented, and each one idea larger than the last. They all open in the Ability Composer.

| File | Idea |
|---|---|
| `instant_damage.gd` | Pay, wait for targets, apply, finish. |
| `costly_strike.gd` | Costs and cooldowns authored on the ability, paid by one commit. |
| `timed_buff.gd` | A `DURATION` effect applied to the caster. |
| `confirmed_blast.gd` | Aim, then confirm, then pay - nothing is spent if the player backs out. |
| `sweeping_volley.gd` | Finding targets with a 2D overlap instead of asking the player. |
| `cued_dash.gd` | Cues fired at the start and the end of an ability. |

## The action sample

The engine repository also ships `examples/action_sample/`: a 3D character with three abilities, three targets and the runtime overlay, plus the same sample running across two processes. It is not part of the addon. See the [Action sample walkthrough](../tutorials/action-sample-walkthrough.md).
