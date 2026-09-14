---
title: Custom Nodes
sidebar_position: 4
description: Which engine calls the Composer's palette offers, how they are grouped, and registering your game's own calls as nodes.
---

# Custom Nodes

A node on the palette is a call - nothing more. There are no special node types: every card prints as its own call and reads back the same way, so a call's signature is everything the Composer needs to know about it.

## What the palette offers

The palette is read from five engine classes:

- `GameplayAbility`
- `AbilitySystemComponent`
- `GameplayTargetingService`
- `AbilityTaskFactory`
- `GameplayAbilityTargetData`

A method of these classes is offered when its doc comment says so with an `@composer` annotation. Methods the runtime uses internally, such as `dispose()`, are public but not offered.

What each node takes and returns is read from the method by reflection, so a method added to the engine appears on the palette the next time the editor starts, and a renamed method takes its node with it.

A node's title is the method's name capitalized - `apply_effect_to_targets` is **Apply Effect To Targets** - and its argument labels are the parameter names capitalized.

:::info Calls that are not on the palette are still drawn
Any call written in `_activate_ability()` is drawn as a card, with its arguments numbered. Offering it on the palette - registering it - names and types its arguments, and lets the Composer report a missing one.
:::

## Groups

| Group | Holds |
|---|---|
| **Ability** | Committing, ending, cooldowns, input, the ability's own state. |
| **Tasks** | `wait_*` calls, `repeat`, animation. |
| **Effects** | Applying and querying effects. |
| **Tags** | Adding, removing and asking about tags. |
| **Targeting** | Target data, traces and sweeps. |
| **Events** | Sending and waiting for gameplay events. |
| **Cues** | Playing cues. |
| **Context** | What the activation carries. |
| **Values** | Attributes and costs. |

An engine method can name its group in its annotation. Otherwise the group is chosen from the method's name, by the first rule that matches:

| The name contains | Group |
|---|---|
| `wait_`, `repeat`, `play_animation` | Tasks |
| `cue` | Cues |
| `effect` | Effects |
| `tag` | Tags |
| `target`, `raycast`, `overlap`, `hit` | Targeting |
| `event` | Events |
| `attribute`, `cost` | Values |
| `abilit`, `cooldown`, `input` | Ability |

## Registering your own calls

Register a call from editor code - an `EditorPlugin` of your game - with `ComposerCatalog.register()`:

```gdscript
@tool
extends EditorPlugin

const COMBAT_CALLS: String = "res://game/composer/combat_calls.gd"


func _enter_tree() -> void:
	ComposerCatalog.register("roll_critical", ComposerCatalog.EFFECTS, COMBAT_CALLS, false)
	ComposerCatalog.register("wait_until_landed", ComposerCatalog.TASKS, COMBAT_CALLS, true)


func _exit_tree() -> void:
	ComposerCatalog.forget(ComposerCatalog.key_for(COMBAT_CALLS, &"roll_critical"))
	ComposerCatalog.forget(ComposerCatalog.key_for(COMBAT_CALLS, &"wait_until_landed"))
```

| Parameter | Meaning |
|---|---|
| `method` | The method's name. |
| `group` | One of `ComposerCatalog.ABILITY`, `TASKS`, `EFFECTS`, `TAGS`, `TARGETING`, `EVENTS`, `CUES`, `CONTEXT`, `VALUES` - or a name of your own, which becomes a new group after the engine's. |
| `path` | The script that declares the method. |
| `suspends` | `true` when the method is a coroutine the ability should `await`. |

`register()` returns an empty string on success, or the reason it refused - the script is missing, is not a script, or has no such method - and also reports the refusal as an error. Registering the same call twice is harmless. A call is keyed by script and method, `ComposerCatalog.key_for(path, method)`, so two scripts may offer calls with the same name.

Call `forget()` when your plugin is disabled, so the palette stops offering calls into scripts that may no longer be loaded.

### Writing callable helpers

The Composer writes a registered call on whatever reaches it from the ability: bare for a method of the ability's own class, on the class name for a static method. A helper class with a `class_name` and static methods is the simplest shape:

```gdscript
class_name CombatCalls extends RefCounted


## Whether this hit is a critical, from the caster's crit chance.
static func roll_critical(caster: AbilitySystemComponent) -> bool:
	return randf() * 100.0 < caster.get_attribute_current(&"crit_chance")


## Waits until the body is standing on the floor again.
static func wait_until_landed(ability: GameplayAbility, body: CharacterBody3D) -> void:
	var landed: AbilityTaskWaitLanded = ability.owner_asc.register_ability_task(
		AbilityTaskWaitLanded.create(ability, body)
	) as AbilityTaskWaitLanded
	if landed != null:
		await landed.completed()
```

`wait_until_landed` wraps a custom task in a coroutine and is registered with `suspends` set to `true`, so the Composer writes it as `await CombatCalls.wait_until_landed(…)`. `AbilityTaskWaitLanded` is the task from [Writing your own task](../abilities/ability-tasks.md#writing-your-own-task).

Methods of your own ability base class can be registered the same way, with the base class's script as `path`; abilities that extend it call them bare.

## Annotating engine methods

When contributing to GAS_Engine itself, a method is offered by annotating its doc comment:

```gdscript
## Find the component a node belongs to.
## @composer
## @composer_name: Find The Ability System On
static func find_asc_on(node: Node) -> AbilitySystemComponent:
```

| Annotation | Meaning |
|---|---|
| `## @composer` | Offer this method; choose its group from its name. |
| `## @composer: Tasks` | Offer it in a named group. |
| `## @composer_name: …` | The title to show instead of the capitalized method name. |
| `## @composer_deprecated: …` | Still offered, so existing abilities open, but marked with what to use instead. |

The first sentence of the doc comment becomes the node's description.
