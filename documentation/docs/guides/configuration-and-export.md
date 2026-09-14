---
title: Configuration and Export
sidebar_position: 13
description: GAS_Engine's project settings, failure tag overrides, the cue manager autoload, and what to do when exporting a game.
---

# Configuration and Export

GAS_Engine needs no configuration to run. Everything on this page is optional.

## Project settings

The plugin registers its settings under `gas_engine/` in **Project → Project Settings**.

| Setting | Default | Meaning |
|---|---|---|
| `gas_engine/editor/tag_property_editor/enable` | `true` | Whether exported properties get the tag picker. |
| `gas_engine/editor/tag_property_editor/match/on` | `gas_tag,gas_tags` | Comma-separated name fragments that give a property the picker. |
| `gas_engine/editor/tag_property_editor/match/type` | `Suffix` | Where the fragment must appear in the property name: `Prefix`, `Suffix` or `Anywhere`. |
| `gas_engine/resources/tags/generated_script` | `res://gas_engine/gameplay_tags.gd` | The project's tag registry. |
| `gas_engine/resources/cues/generated_script` | `res://gas_engine/gameplay_cues.gd` | The project's cue bindings. |
| `gas_engine/failure_tags/<n>` | *(not set)* | Replaces the tag reported for one activation refusal reason. |

To move a registry, move its file and point the setting at the new path, then restart the editor.

A project that used the addon's earlier setting names or registry resources has them read and folded in once; nothing needs to be done by hand.

### Failure tag overrides

Each activation refusal is reported with a tag - see [When an activation is refused](abilities/activation-and-input.md#when-an-activation-is-refused). To change one, add a setting whose last segment is the reason's number and whose value is the tag:

| `<n>` | Reason | Default tag |
|---|---|---|
| `1` | `ALREADY_ACTIVE` | `Ability.Failed.AlreadyActive` |
| `2` | `ON_COOLDOWN` | `Ability.Failed.Cooldown` |
| `3` | `BLOCKED_TAG` | `Ability.Failed.BlockedTags` |
| `4` | `MISSING_TAG` | `Ability.Failed.MissingTags` |
| `5` | `INSUFFICIENT_RESOURCES` | `Ability.Failed.Cost` |
| `6` | `INTERNAL_ERROR` | `Ability.Failed.Internal` |
| `7` | `PENDING_REMOVAL` | `Ability.Failed.PendingRemoval` |
| `8` | `BLOCKED_BY_ACTIVE_ABILITY` | `Ability.Failed.BlockedByAbility` |
| `9` | `BLOCKED_EXTERNALLY` | `Ability.Failed.BlockedExternally` |

For example, `gas_engine/failure_tags/5` set to `UI.Refusal.NotEnoughMana`.

## The cue manager autoload

Enabling the plugin registers the `GameplayCueManager` autoload, which loads the cue bindings and plays and pools every cue. Without it, gameplay works and no cue plays.

If your project already declares an autoload with that name, the plugin leaves yours in place and warns. Disabling the plugin removes the autoload only if the plugin added it.

## After updating the engine

Re-render the project registries so declarations a newer engine expects are present. See [Updating GAS_Engine](../getting-started/installation.md#updating-gas_engine).

## Exporting

With Godot's default export mode, **Export all resources in the project**, there is nothing to do.

With **Selected scenes and dependencies**, add this to the export preset's include filter:

```text
addons/GAS_Engine/*, gas_engine/*
```

and select every scene a cue plays, the same way you select any other scene your game loads at runtime.

The reason is Godot's exporter: it keeps files by following resource dependencies, and a `preload()` in a GDScript file is not reported as one. Under the selective mode nothing reached only through GDScript is exported - including the registries and the scripts the cue manager preloads. A build missing them logs `No cue registry found at …` at startup.

## Debug builds and release builds

| Feature | Debug build | Exported release build |
|---|---|---|
| `GasDebugOverlay`, `GasDebugCommands` | Available | Available - your game decides whether to include them. |
| `gas.ignore_costs`, `gas.ignore_cooldowns` | Work | Refused, and inert even if set. |
| `SUPPRESS_CUES`, `SUPPRESS_ABILITY_GRANTS` | Work | Work |
| Snapshots and trace events for the editor's Debugger tab | Sent while running from the editor | Never attached |
| Ability Composer, asset validator, inspector pickers | Editor only | Never loaded |
