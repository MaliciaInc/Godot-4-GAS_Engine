---
title: Gameplay Cues
sidebar_position: 7
description: Sounds, particles and screen feedback triggered by tag - binding cues, cues on effects and abilities, cue scenes, templates, handlers and pooling.
---

# Gameplay Cues

A **gameplay cue** is the feedback for something that happened: the spark of a hit, the flames on a burning character, a camera shake, a line in a combat log. Gameplay code asks for a cue **by tag** and never knows what plays it.

Cues are cosmetic by contract. A cue with nothing bound to it plays nothing and changes nothing, and a component with `suppress_cues` on - a dedicated server - plays none at all.

## How a cue tag is answered

| Answered by | Use it for |
|---|---|
| A **scene** whose root is a `GameplayCueNotify` | Anything with a position: particles, sounds, decals. |
| A **handler** script extending `GameplayCueHandler` | Feedback with nothing to instantiate: a combat log, a HUD counter, a controller rumble. |
| The **target** itself, through `handle_gameplay_cue()` | A character reacting in its own code: a red flash, a hurt animation. |

The target is told even when nothing is bound to the tag.

### Binding cues

Bindings live in `res://gas_engine/gameplay_cues.gd`, loaded when the game starts:

```gdscript
const BINDINGS: Dictionary[StringName, PackedScene] = {
	&"Cue.Hit": preload("res://game/cues/hit.tscn"),
	&"Cue.Hit.Fire": preload("res://game/cues/fire_hit.tscn"),
	&"Cue.Status.Burning": preload("res://game/cues/burning.tscn"),
}


const HANDLERS: Dictionary[StringName, Script] = {
	&"Cue.Log": preload("res://game/cues/combat_log_handler.gd"),
}


const OVERRIDE_PARENT: Array[StringName] = [
	&"Cue.Hit.Silent",
]
```

A game that builds cues at runtime binds them on the `GameplayCueManager` autoload:

```gdscript
const CueManager = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")


func _ready() -> void:
	var manager: CueManager = get_node_or_null(CueManager.AUTOLOAD_NODE_PATH) as CueManager
	if manager != null:
		manager.bind_cue(&"Cue.Hit.Ice", preload("res://game/cues/ice_hit.tscn"))
```

`unbind_cue(tag)` takes a binding back and frees what was pooled for it.

### Resolution

A request nothing answers falls back up its family: `Cue.Hit.Fire.Critical`, then `Cue.Hit.Fire`, then `Cue.Hit`. Scenes and handlers are consulted together at each level, and the first binding found plays. `params.matched_cue_tag` says which tag answered.

A tag in `OVERRIDE_PARENT` stops the walk: with a binding of its own that binding plays; without one nothing plays. `Cue.Hit.Silent` above silences its whole branch without binding every leaf to an empty scene.

`manager.resolve_cue_tag(tag)` returns the tag that would answer, or `&""`.

## Cues on effects

An effect declares its cues in `cues`, as `GameplayCueBinding` resources:

```gdscript
var burning_look: GameplayCueBinding = GameplayCueBinding.new()
burning_look.cue_tag = &"Cue.Status.Burning"
burning_look.type = GameplayCueBinding.Type.PERSISTENT

var ignite: GameplayCueBinding = GameplayCueBinding.new()
ignite.cue_tag = &"Cue.Hit.Fire"

burn.cues = [burning_look, ignite] as Array[GameplayCueBinding]
```

| `type` | Plays |
|---|---|
| `EXECUTED_ON_APPLICATION` | Once when the effect is applied, and when a stack joins it. The default. |
| `EXECUTED_ON_PERIODIC` | Once on every periodic tick. |
| `PERSISTENT` | For as long as the effect is active and not inhibited - one running cue per active effect, however many stacks. It stops when the effect is removed or inhibited, and starts again if the effect is uninhibited. |

| Binding field | Meaning |
|---|---|
| `cue_tag` | The cue. |
| `type` | When it plays. |
| `magnitude_attribute` | An attribute of the target to read the cue's number from, instead of the effect's level. |
| `min_level` / `max_level` | The range `normalized_magnitude` is computed against. |
| `replication` | `REPLICATED` or `LOCAL_ONLY`. See [Networking](networking.md). |

Three switches on the effect itself:

| Field | Effect |
|---|---|
| `require_modifier_success_to_trigger_cues` | Play nothing when the application changed no attribute. |
| `suppress_stacking_cues` | Only the first application of a stack plays its application cues. |
| An execution's `trigger_cues = false` | Silence this one application. See [Richer outputs](gameplay-effects/executions-and-context.md#richer-outputs). |

## Cues from abilities

| Method | Plays |
|---|---|
| `execute_cue(tag)` | A one-shot cue on the avatar. |
| `activate_persistent_cue(tag, params)` | A persistent cue on the avatar, returning a `GameplayCueHandle`. |
| `deactivate_persistent_cue(handle)` | Stops one persistent cue this activation started. |

Every persistent cue an ability started is stopped when the ability ends, however it ends. See [Abilities](abilities/index.md#what-an-ability-can-call).

## Cues from game code

```gdscript
var params: GameplayCueParams = GameplayCueParams.for_target(&"Cue.Pickup.Coin", player, chest, 25.0)
player_asc.execute_cue(params)
```

| Method on the component | Purpose |
|---|---|
| `execute_cue(params)` | Play a one-shot cue. The target defaults to the avatar. Emits `cue_executed(tag)`. |
| `activate_persistent_cue(params)` | Start a persistent cue and return its handle. |
| `deactivate_persistent_cue(handle, params)` | Stop it. |
| `remove_all_gameplay_cues()` | Stop every persistent cue on this entity - for a despawn or a reset. |

### From an animation

A footstep belongs to a frame of an animation. Add a method to the character and call it from a method track:

```gdscript
func play_cue(tag: StringName) -> void:
	GameplayCueAnimation.fire(self, tag)
```

`GameplayCueAnimation.fire()` finds the component the node belongs to and plays the cue there. It does nothing for a node without one.

## What a cue receives

Every cue receives a `GameplayCueParams`:

| Field | Meaning |
|---|---|
| `cue_tag` / `matched_cue_tag` | The tag requested, and the tag whose binding answered. |
| `instigator` / `target` | Who caused it, and who it plays on. |
| `raw_magnitude` (`magnitude`) | The cue's number: the effect's level, or the binding's attribute reading. |
| `normalized_magnitude` | That number between the binding's `min_level` and `max_level`, clamped to `0`-`1`. Scale visuals by this one. |
| `effect_level` / `ability_level` | The levels of the effect and ability behind it, or `0`. |
| `source_tags` / `target_tags` | Each side's tags when the cue was made. |
| `stack_count` | The effect's stacks when the cue was made. |
| `target_hit` | Where the application hit this target, when targeting recorded a hit. |
| `location` / `has_location` | A world position set with `with_location()`. |
| `causer` / `source_object` | What physically caused it, and the item behind it. |
| `context` / `effect_handle` | The effect context and the active effect's handle, when an effect played it. |

## Writing a cue scene

Make a scene whose root node's script extends `GameplayCueNotify`, and override the moments it needs:

```gdscript
extends GameplayCueNotify

@onready var sparks: GPUParticles3D = $Sparks
@onready var sound: AudioStreamPlayer3D = $Sound


func executed(params: GameplayCueParams) -> void:
	var hit: GameplayTargetHit = params.target_hit
	if hit != null and hit.has_position and hit.space_kind == GameplayTargetHit.SpaceKind.THREE_D:
		sparks.global_position = hit.position_3d
	sparks.amount_ratio = maxf(params.normalized_magnitude, 0.2)
	sparks.restart()
	sound.play()
```

| Override | Called |
|---|---|
| `executed(params)` | For a one-shot cue. |
| `on_active(params)` | When a persistent cue starts. |
| `while_active(params)` | Once, right after `on_active`. Use `_process()` for per-frame work. |
| `on_removed(params)` | When a persistent cue stops, before the node is pooled. |

The manager parents the cue under its target, and a cue is never played on a target outside the scene tree.

| Export | Meaning |
|---|---|
| `auto_destroy` | Return a one-shot cue to the pool after `destroy_delay` seconds. On by default. Call `finish_cue()` to return it earlier. |
| `destroy_delay` | Longer than the longest sound or particle in the scene. |
| `unique_per_instigator` | At most one persistent instance per instigator on a target: two archers set two fires, one archer's ticks set one. |
| `unique_per_source_object` | At most one per source object. |
| `allow_multiple_on_active` | Whether a second activation that resolves to a running instance calls `on_active` again. |
| `preallocate` | How many instances to create ahead of time. |

:::warning Cue scenes are pooled
The same node plays many times. Reset whatever a playback changes at the start of `executed()` or `on_active()`, not in `_ready()`.
:::

## Templates

Most cues need no script. Two templates play authored `GameplayCueEffectSet` resources:

| Template | Sets |
|---|---|
| `GameplayCueNotifyBurst` | `burst`, played when the cue executes. |
| `GameplayCueNotifyLooping` | `on_application`, `looping` (kept while the cue runs), `recurring` (every `recurring_interval` seconds), `on_removal`. |

| `GameplayCueEffectSet` field | Meaning |
|---|---|
| `sounds`, `particles`, `decals` | Audio streams and scenes to spawn. |
| `camera_shake`, `haptics` | Names emitted as `camera_shake_requested(shake, params)` and `haptics_requested(haptics, params)`. The engine never moves a camera; your game maps the names. |
| `placement` | A `GameplayCuePlacement`: `mode` (`ATTACH_TO_TARGET`, `AT_LOCATION`, `AT_TARGET_ORIGIN`), `offset`, `follow_rotation`, `scale_by_magnitude`. |

To use a template, give a scene's root node the template script and fill in the sets in the Inspector. To react to the shake and haptics requests, extend the template and connect the signals in `_ready()`.

## Handlers

A handler answers a tag without a scene. One handler instance serves every playback, so it must keep no state between calls:

```gdscript
extends GameplayCueHandler


func on_execute(params: GameplayCueParams) -> void:
	CombatLog.write("%s hit %s for %d" % [params.instigator.name, params.target.name, params.raw_magnitude])
```

| Override | Called |
|---|---|
| `on_execute(params)` | A one-shot cue. |
| `on_active(params)` | A persistent cue started. |
| `while_active(params)` | Every frame while it runs. |
| `on_removed(params)` | It stopped. |

`CombatLog` stands for your game's own autoload.

## The target's own reaction

A target that implements `handle_gameplay_cue` hears every cue played on it, bound or not:

```gdscript
func handle_gameplay_cue(tag: StringName, event: GameplayCueNotify.Event, _params: GameplayCueParams) -> void:
	if event == GameplayCueNotify.Event.EXECUTED and tag == &"Cue.Hit":
		hurt_flash.play(&"flash")
```

`event` is `EXECUTED`, `ON_ACTIVE`, `WHILE_ACTIVE` or `REMOVED`.

## Pooling and queries

| Manager method | Purpose |
|---|---|
| `preallocate_from_registry()` | Create each scene's `preallocate` instances now - on a loading screen. |
| `get_pooled_count(tag)` | How many dormant instances a tag has. |
| `is_cue_active(target, tag)` | Whether a persistent cue is running on a target. |
| `remove_all_cues(target)` | Stop every persistent cue on a target. |
