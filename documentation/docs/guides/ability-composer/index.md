---
title: Ability Composer
sidebar_position: 1
description: The visual editor for abilities - a view of the ability's GDScript, how to open and create abilities, the screen, cards and pins, and diagnostics.
---

# Ability Composer

The Ability Composer draws an ability's `_activate_ability()` as a graph of cards and cables, and lets you edit it there.

It is a **view of the code**, not a second format. There is no graph file, no `.tres` and no interpreter: the `.gd` file is the ability, and the canvas is read out of it every time it is opened. Saving writes the same file back. Lines you did not touch are written back exactly as they were, comments and formatting included, and a save is refused unless the new file reads back as the graph you edited.

:::info Code and Composer are two windows onto one file
Everything the Composer writes is ordinary GDScript you can read, diff and edit by hand. Switch between the two whenever it is convenient.
:::

## Opening the Composer

| From | Does |
|---|---|
| **Project → Tools → Ability Composer** | Draws the script open in the Script editor when it is an ability. Otherwise it offers the project's abilities: one is opened directly; several are listed, followed by **Re-scan abilities** and **Browse…**. |
| The **GAS_Engine** tab at the top of the editor | Shows the Composer screen. |
| **Open an ability…** in the Composer's top bar | Picks a file. |

An ability is any script whose base-class chain reaches `GameplayAbility`, however many classes deep.

## Creating an ability

**New ability** in the top bar asks where to save and writes **two** files: the script, and a scene beside it whose root is the ability - the scene is what `give_ability()` takes. If either file already exists, nothing is written.

The new script is the smallest valid ability:

```gdscript
@tool
extends GameplayAbility


func _activate_ability() -> bool:
	return true
```

## The screen

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ Code │ Ability Composer     fireball  res://game/abilities/fireball.gd   │  top bar
├────────────┬───────────────────────────────────────────────┬─────────────┤
│  PALETTE   │                                               │  INSPECTOR  │
│            │                   canvas                      │             │
│ Search…    │     Entry ──► Commit Ability ──► End          │  selected   │
│ › Ability  │                                               │  card's     │
│ › Tasks    │                                               │  values     │
│ …          │                                               │             │
├────────────┴───────────────────────────────────────────────┴─────────────┤
│ Output                                                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

| Region | Holds |
|---|---|
| **Top bar** | `Code │ Ability Composer`, the open ability, **Open an ability…** and **New ability**. **Code** opens the same file in the Script editor. |
| **Palette** | The calls you can put down, in groups, with a search box. |
| **Canvas** | The cards and cables. |
| **Inspector** | The values of the selected card. Collapse it to give the canvas the width. |
| **Output** | Everything wrong with the ability, each row placed at a line. Click a row to go to it. |

## Cards and pins

Each statement of `_activate_ability()` is a card.

| Card | Stands for |
|---|---|
| **Entry** | Where the method starts. It has no line in the file. |
| A call, such as **Commit Ability** | A statement: a call, a typed local, an assignment or an `await`. |
| A **branch** | `if` / `elif` / `else`, with **True** and **False** execution outputs and a condition input. |
| A **match** | `match`, with one output per arm and **No Match** for values no arm takes. |
| **End** | A `return`. It has no execution output: nothing runs after it. |
| A **kept region** | Code the Composer does not draw, such as a loop. It runs where it is and is kept exactly as written. See [What the Composer can draw](what-the-composer-can-draw.md). |

Pins come in two families, told apart by their shape:

- **Execution** pins say what runs after what. An execution cable is the order of statements in the file.
- **Data** pins carry values. A data cable is a local passed as an argument.

A card that waits says `await`. A card with a problem carries a dot - amber for a warning, red for an error - matching its row in the Output panel. Pulled far back, cards draw as blocks so the shape of the flow stays readable.

## Unsaved changes

Opening another ability with unsaved changes asks **Save**, **Discard** or **Cancel**. If the editor closes or the plugin is disabled while changes are unsaved, the Composer writes a recovery copy under `user://gas_engine/composer_recovery/` and says where in the log.

## When an ability opens read-only

The Composer draws the `_activate_ability()` written in the file itself. A script with no `_activate_ability()` of its own - typically an ability that extends a base class of yours and only overrides hooks - opens read-only, with `no _activate_ability() to draw` on the Output panel.

Everything else opens editable, including abilities with code the Composer cannot draw.

## Diagnostics

Every finding has a severity and a stable code:

| Code | Severity | Meaning |
|---|---|---|
| `gas.missing_argument` | Error | A required argument has nothing in it. |
| `gas.wrong_type` | Error | A cable connects values GDScript would not assign. |
| `gas.unread_value` | Warning | A local is never used afterwards. |
| `gas.await_without_waiting` | Warning | An `await` on a call that returns a task, which does not wait. |
| `gas.kept_region` | Warning | Code the Composer keeps as written and does not edit. |
| `gas.not_drawable` | Read-only | The file has nothing the Composer can draw. |
| `gas.unclassified` | - | A finding with no more specific code. |

An ability with warnings runs normally. One with errors will not compile until they are fixed, but it still saves, so a half-finished ability can be put down and picked up later.

## It never reaches a running game

The Composer lives entirely under `addons/GAS_Engine/editor/`, and nothing outside that folder references it. No part of it is loaded by a running or exported game.

## In this section

- [Editing abilities](editing-abilities.md) - putting calls down, values, cables, branches, menus and keys.
- [What the Composer can draw](what-the-composer-can-draw.md) - the GDScript it draws, kept regions and reserved comments.
- [Custom nodes](custom-nodes.md) - which calls are offered, and adding your game's own.
- [Tutorial: build an ability in the Composer](../../tutorials/build-an-ability-in-the-composer.md).
