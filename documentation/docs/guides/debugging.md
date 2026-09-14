---
title: Debugging
sidebar_position: 10
description: The in-game debug overlay, console commands, debug switches, attribute history, the editor's Debugger tab, and asset validation.
---

# Debugging

Most of GAS_Engine's debugging tools run **inside your game**, so they work in the editor, in a build on another machine, and while the game is paused. While the game runs from the editor, the same pages also appear in the editor's **Debugger** dock.

## The debug overlay

`GasDebugOverlay` draws one entity's ability system as tabbed tables over your game.

```gdscript
var overlay: GasDebugOverlay = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_gas_overlay"):
		if overlay == null:
			overlay = (load(GasDebugOverlay.SCENE) as PackedScene).instantiate() as GasDebugOverlay
			add_child(overlay)
			overlay.watch(player.asc)
		else:
			overlay.queue_free()
			overlay = null
```

| Page | Columns |
|---|---|
| **Attributes** | Attribute, Base, Current, Last change |
| **Active effects** | Effect, Stacks, Seconds, Turns, State |
| **Abilities** | Granted ability, Level, Running, Cooldown, Last result |
| **Tags** | Tag, Count, Family, How |

The **Tags** page shows both counts: how many references hold the exact tag, and how many hold it or anything under it. The **Active effects** page names each effect by its `resource_name`, or by its file when it has none - name effects built in code so they can be told apart here.

| Member | Purpose |
|---|---|
| `watch(asc)` | Start showing an entity and recording its attribute changes. Returns whether it attached. |
| `stop()` | Stop watching and forget the history. |
| `show_page(index)` | Switch tabs from code. |
| `refresh()` | Rebuild the table now. |
| `snapshot()` | A `GasRuntimeSnapshot` of the watched entity. |
| `history()` | The `GasAttributeHistory` being recorded. |
| `seconds_between_refreshes` | How often the table is rebuilt. `0.25` by default. |
| `font_size` | The overlay's own text size, independent of your game's theme. |
| `notable_color` / `ordinary_color` | How rows worth looking at, and the rest, are drawn. |
| `history_limit` | How many attribute changes are kept. |

The overlay keeps updating while the scene tree is paused, and a watched entity that is freed simply stops being shown.

## Console commands

`GasDebugCommands.run(line, within)` runs one command and **returns** the answer as text, for your own console, chat window or remote channel. `within` is any node in the tree; entities are found by the name of the node that holds each component.

```gdscript
func _on_console_submitted(line: String) -> void:
	if line.begins_with(GasDebugCommands.PREFIX):
		console_output.append_text(GasDebugCommands.run(line, self) + "\n")
```

| Command | Answers |
|---|---|
| `gas.list` | Every entity with an ability system. |
| `gas.list Hero` | Hero's grants, with their handle numbers and whether each is running. |
| `gas.activate Hero Fireball` | Activates an ability by name - or by the handle number `gas.list` printed - and reports the result, with its failure tag when refused. |
| `gas.attributes Hero` | The Attributes page, as text. |
| `gas.effects Hero` | The Active effects page. |
| `gas.abilities Hero` | The Abilities page. |
| `gas.tags Hero` | The Tags page. |
| `gas.ignore_costs on` / `off` | Every ability is free. Debug builds only. |
| `gas.ignore_cooldowns on` / `off` | No cooldown gates. Debug builds only. |

`GasDebugCommands.names()` lists every command, for completion. `GasDebugCommands.pages()` is the one list of pages: the overlay, the console and the editor's Debugger tab all offer the same four.

## Debug switches

`GasDebugOptions` holds four process-wide switches:

| Switch | Effect | Builds |
|---|---|---|
| `IGNORE_COSTS` | Costs resolve as free and nothing is charged. | Debug only |
| `IGNORE_COOLDOWNS` | Cooldowns neither gate nor start. | Debug only |
| `SUPPRESS_CUES` | No cue plays anywhere. | All |
| `SUPPRESS_ABILITY_GRANTS` | Every ability grant is refused. | All |

```gdscript
print(GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COSTS, true))
```

`set_switch()` returns a sentence describing what happened, including a refusal in a release build. `GasDebugOptions.forget()` turns every switch off.

The cost and cooldown switches touch no attribute and no tag. Turning them off puts every entity back exactly where it would have been, so a save made while testing is not affected.

## Attribute history

`GasAttributeHistory` keeps the last changes to one entity's attributes - 128 by default - so you can see what took health to zero after it happened.

| Member | Purpose |
|---|---|
| `watch(asc)` / `stop()` | Start and stop recording. |
| `recent(count)` | The newest changes first; `0` for all. |
| `recent_for(attribute_name)` | One attribute's changes, newest first. |
| `record(attribute_name, from, to)` | Add a change your own code made. |
| `size()` / `recorded()` | How many are kept, and how many were ever recorded. |

The overlay keeps one for the entity it watches.

## The Debugger tab in the editor

While a debug build runs from the editor, every component reports itself over Godot's debugger connection - nothing has to be attached - and the **Debugger** dock gains a **GAS_Engine** tab, one per running instance of the game:

| Part | Shows |
|---|---|
| The list down the side | Every entity that reports, by the name of the node that holds its component. |
| The page buttons and the table | The chosen entity's **Attributes**, **Active effects**, **Abilities** or **Tags** - the overlay's own pages. |
| **What happened, newest first** | That entity's trace events. |

Each component sends a snapshot of itself when it is ready and then four times a second while the game runs, so the pages stay current, and a trace event for each thing that happens to it. A new run of the game starts its tab from nothing. In an exported release build nothing is attached and nothing is sent.

Report your own steps through the same channel; they appear in the tab beside the engine's:

```gdscript
asc.debug_channel.trace(GasDebugMessage.Kind.EFFECT_APPLIED, "Shield", "absorbed 40")
```

The kinds are `ABILITY_GRANTED`, `ABILITY_ACTIVATED`, `ABILITY_COMMITTED`, `ABILITY_ENDED`, `ABILITY_REFUSED`, `EFFECT_APPLIED`, `EFFECT_REFUSED`, `EFFECT_TICKED`, `EFFECT_REMOVED`, `TAG_COUNT_CHANGED`, `ATTRIBUTE_CHANGED` and `CUE_EXECUTED`. `ABILITY_COMMITTED` is sent for every commit attempt with its `AbilityCommitResult` status, so a commit that was refused shows up with its reason.

## Snapshots

`GasRuntimeSnapshot.of(asc)` captures one entity at one moment - attributes at both values, tags at both counts, grants and active effects - without changing anything. It is what the overlay, the console and the editor's Debugger tab draw from, and it is useful in tests.

## Finding out why nothing happened

| Symptom | Where to look |
|---|---|
| An ability does not start | The `GameplayAbilityActivationResult` status, or `ability_activation_failed_with_tag`. `gas.activate` reports both. |
| An ability starts but pays nothing | Costs set in `_ready()`. See [Common pitfalls](common-pitfalls.md). |
| An ability does not pay | The `ABILITY_COMMITTED` events in the Debugger tab, which carry the refusal. |
| An effect is not applied | The `GameplayEffectApplicationResult` status, and the component's `effect_application_refused` signal. |
| An attribute does not move | The Attributes page's Base and Current columns, and the history. |
| A cue does not play | `resolve_cue_tag()` on the manager, and whether cues are suppressed. |

## Validating assets

`GameplayAssetValidator` checks authored resources in editor code - an `EditorScript`, a test, a build step:

```gdscript
@tool
extends EditorScript


func _run() -> void:
	var effect: GameplayEffect = load("res://game/effects/burn.tres") as GameplayEffect
	for finding: GameplayAssetValidationResult in GameplayAssetValidator.validate_effect(effect, null):
		print(finding.code, " ", finding.field)
```

| Method | Checks |
|---|---|
| `validate_effect(effect, profile)` | Components, magnitudes, undeclared attributes, and - with a channel-folded profile - legacy operations and stacking without `factor_in_stack_count`. |
| `validate_ability_scene(scene)` | That the scene exists and its root is a `GameplayAbility`. |
| `validate_tag_query(query)` / `validate_effect_query(query)` | Empty or malformed tags and cycles. |
| `validate_costs(costs)` | Missing amounts and attributes, named either by reference or by name. |
| `validate_components(components, effect)` / `validate_magnitude(…)` | One part at a time. |

Each finding has a `severity` (`ERROR` or `WARNING`) and a `code` such as `MISSING_MAGNITUDE`, `UNDECLARED_ATTRIBUTE` or `STACKING_WITHOUT_STACK_COUNT_ANSWER`. The validator lives under `editor/` and is not available to a running game. The **Gameplay Effect** bottom panel shows the same findings for the effect it has open.
