---
title: Installation
sidebar_position: 1
description: Requirements, installing and enabling the plugin, verifying it works, updating, and disabling.
---

# Install GAS_Engine

## Requirements

| | |
|---|---|
| Godot | **4.7.2** |
| Language | GDScript |
| Dependencies | None |

The exact patch version matters. GAS_Engine is strictly typed and treats GDScript warnings as errors, and the set of warnings can change between patch releases.

---

## Step 1: Copy the addon

Copy the `addons/GAS_Engine/` folder into your project so that the plugin lives at:

```text
res://addons/GAS_Engine/plugin.cfg
```

Copy the folder whole. Do not cherry-pick subfolders: the runtime, the cue manager autoload and the editor tools reference each other.

---

## Step 2: Enable the plugin

Open **Project → Project Settings → Plugins** and tick **GAS_Engine**.

Enabling the plugin does four things:

1. **Registers the `GameplayCueManager` autoload** (`res://addons/GAS_Engine/managers/gameplay_cue_manager.gd`). If your project already declares an autoload with that name pointing somewhere else, GAS_Engine leaves it alone and prints a warning.
2. **Creates the project registries** in `res://gas_engine/` when they do not exist yet: `gameplay_tags.gd`, seeded with a handful of `Example.*` tags, and `gameplay_cues.gd`, with no bindings. Existing files are never rewritten.
3. **Registers the project settings** under `gas_engine/`.
4. **Adds the editor tools**: the Ability Composer, **Project → Tools → Create Gameplay Effect** with the **Gameplay Effect** bottom panel, the tag, tag query and attribute pickers in the Inspector, and a **GAS_Engine** tab in the Debugger dock.

Nothing else needs configuring before you write your first ability.

---

## Step 3: Verify the installation

1. Choose **Project → Tools → Ability Composer**. A new project has no abilities, so the Composer says so and points you at `addons/GAS_Engine/reference/`.
2. Open **Project → Project Settings → Globals → Autoload** and check that `GameplayCueManager` is listed.
3. Check that `res://gas_engine/gameplay_tags.gd` and `res://gas_engine/gameplay_cues.gd` exist.

:::tip
The fastest end-to-end check is the [Quickstart](../quickstart.md): if the fireball takes 30 health off the dummy, the runtime is working.
:::

---

## Updating GAS_Engine

1. Commit your project first.
2. Delete `res://addons/GAS_Engine/` and copy the new version in its place. Never merge an old and a new addon folder.
3. **Do not** delete `res://gas_engine/`. Those files belong to your project.
4. Re-render the project registries with the new generators, so any declaration a newer engine expects is present.

Step 4 matters because the engine reads its registries as text. A declaration a newer version added - `REDIRECTS` in the tags file, `HANDLERS` in the cues file - is simply absent from a file written by an older one, and an absent declaration reads as an empty one. Nothing errors, and the feature silently does nothing.

Run this once from the Script editor with **File → Run**:

```gdscript
@tool
extends EditorScript


func _run() -> void:
	GameplayTagGenerator.generate_tags_file(GameplayTagGenerator.tags_in_file())
	GDScriptSource.write(
		GASEngineProjectSettings.get_generated_cue_script_path(),
		GameplayCueGenerator.render_source(
			GameplayCueGenerator.bindings_in_file(),
			GameplayCueGenerator.overrides_in_file(),
			GameplayCueGenerator.handlers_in_file()
		)
	)
```

Review the diff of `res://gas_engine/` before committing it.

---

## Disabling the plugin

Disabling GAS_Engine removes the `GameplayCueManager` autoload **only if the plugin added it**. An autoload your project declared itself is left in place. The `res://gas_engine/` files are never deleted.

---

## Exporting

With Godot's default export mode, **Export all resources in the project**, there is nothing to do. The **Selected scenes and dependencies** mode needs an include filter; see [Configuration and export](../guides/configuration-and-export.md#exporting).

---

## License

GAS_Engine is **source-available**. The Community Use License lets you use the **unmodified** engine free of charge in any game, including commercial games, with no royalties. Modifying the engine itself, distributing a modified version or building a derivative framework requires a separate Commercial Modification License. The full terms are in `LICENSE` and `COMMERCIAL-LICENSE.md` at the root of the engine repository.

In practice: extend GAS_Engine from your own code - subclasses, attribute sets, magnitude calculations, execution calculations, effect components, context payloads, cue notifies - and leave `addons/GAS_Engine/` untouched.
