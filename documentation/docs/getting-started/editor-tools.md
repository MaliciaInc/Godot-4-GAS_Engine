---
title: Editor Tools
sidebar_position: 4
description: Everything the GAS_Engine plugin adds to the Godot editor, and where each tool is documented in depth.
---

# Editor Tools

Enabling the GAS_Engine plugin adds a small, focused set of tools to the Godot editor. None of them is required at runtime, and nothing under `addons/GAS_Engine/editor/` can be reached by a running game.

## The Ability Composer

A visual editor for abilities that is a view of the `.gd` file itself.

| How to open it | What happens |
|---|---|
| **Project → Tools → Ability Composer** | Draws the ability open in the Script editor, or offers the project's abilities. |
| The **GAS_Engine** tab at the top of the editor | Shows the Composer main screen. |

When several abilities exist, a menu lists them, followed by **Re-scan abilities** (for a file created a moment ago) and **Browse…** (to pick a file by hand). When the project has no ability yet, the Composer says so and points at `addons/GAS_Engine/reference/`.

The Composer is covered in its own section, starting at [Ability Composer](../guides/ability-composer/index.md).

## Create Gameplay Effect

**Project → Tools → Create Gameplay Effect** asks where to save a new effect and writes a blank `GameplayEffect` resource (an `INSTANT` effect with nothing in it) as a `.tres`. The new resource opens in the Inspector and in the Gameplay Effect panel.

Use effect assets when several abilities must apply the same effect. When the numbers belong to one ability, building the effect in code is equally valid - see [Authoring effects](../guides/gameplay-effects/index.md#authoring-an-effect).

## The Gameplay Effect panel

Whenever the Inspector opens a `GameplayEffect` - an asset selected in the FileSystem dock, or one just created - the **Gameplay Effect** bottom panel shows it too. The panel edits the same resource the Inspector does, so a change in one appears in the other.

| Part | What it does |
|---|---|
| Duration policy, **Duration**, **Period** | The effect's timing. |
| Stacking type, **Stack limit** | How reapplications stack. |
| Modifier rows, **Add modifier** | One row per modifier: attribute, operation, evaluation channel and a flat amount, each with a remove button. |
| Component rows, **Add component** | One row per component, added from a menu of component types and removed whole. |
| Cue rows | One row per cue binding, removed whole. |
| Findings | What the asset validator says about the effect as it stands. |
| **Save effect** | Saves the resource. |

A component's own fields, a magnitude other than a flat amount, and anything else the panel does not show are edited in the Inspector.

## Inspector pickers

Three inspector plugins replace the default property editors for GAS_Engine data.

### Tag picker

Any exported property whose **name** matches the configured rule gets an **Edit Tags…** button (it reads **Tags (N selected)** once tags are chosen). By default a property matches when its name ends with `gas_tag` or `gas_tags`, and the property can be a `StringName`, a `String`, an `Array` or a `PackedStringArray`:

```gdscript
@export var immunity_gas_tags: Array[StringName] = []
@export var stance_gas_tag: StringName = &""
```

The button opens the **Gameplay Tag Editor**:

- a **Search tags…** box that filters the tree;
- one checkbox per tag, grouped by hierarchy;
- a **New.Tag.Hierarchy** field with **Add Tag**, which adds the tag to the project registry;
- a per-tag **Delete from Registry** button.

The property keeps the container type it was authored with. The rule that decides which properties get the picker lives in Project Settings under `gas_engine/editor/tag_property_editor` - see [Configuration and export](../guides/configuration-and-export.md).

### Tag query editor

Every `GameplayTagQuery` property - an ability's `activation_required_query`, a filter step, a tag relationship row - is edited as a tree of `ALL` / `ANY` / `NONE` expressions over tags. This applies by property **type**, so it works on your own resources too. See [Tag queries](../guides/gameplay-tags.md#tag-queries).

### Attribute picker

Every `GameplayAttributeRef` property - on a modifier, a capture, a cost, a cue binding - offers the attributes declared by the project's attribute sets, and flags a name nothing declares. On a modifier, a capture or a cost, the reference the picker writes is what the runtime reads; the bare name field beside it is only read while the reference is empty. See [Referring to an attribute](../guides/attributes.md#referring-to-an-attribute).

## Project files the plugin maintains

On start-up the plugin makes sure the project has the two files its tags and cues live in, under `res://gas_engine/`. It creates them when they are missing and never rewrites a file that exists. Both are ordinary GDScript and safe to edit by hand. See [Project layout](project-layout.md#the-gas_engine-folder).

## Runtime debugging

While a game runs from the editor, the **Debugger** dock gains a **GAS_Engine** tab, one per running instance of the game:

- down the side, every ability system the game reports;
- the chosen one's **Attributes**, **Active effects**, **Abilities** and **Tags** pages, kept current while the game runs;
- beside them, what happened to it, newest first - grants, commits (refused ones included), activations, effects applied, ticked and removed, tag counts and attribute changes.

Every component reports on its own; nothing has to be attached, and an exported release build sends nothing. The game can also draw and answer the same information itself:

- **`GasDebugOverlay`** draws the same four pages for one entity inside the running game, away from the editor.
- **`GasDebugCommands`** answers console lines such as `gas.list`.
- **`GasDebugOptions`** switches costs and cooldowns off in debug builds.

See [Debugging](../guides/debugging.md).
