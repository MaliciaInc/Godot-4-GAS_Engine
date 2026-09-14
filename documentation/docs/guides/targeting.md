---
title: Targeting
sidebar_position: 8
description: Target data and hits, physics queries and filters, targeting presets, interactive providers and reticles.
---

# Targeting

An ability applies effects to **target data**: the nodes and places it is aimed at. GAS_Engine offers four ways to produce target data, from the simplest to the most interactive:

| Way | When |
|---|---|
| The caller passes it | The target is already decided - an AI's choice, a click on a unit, a turn-based menu. See [Passing context](abilities/activation-and-input.md#passing-context). |
| A **physics query** | The ability finds targets itself, now: a sweep around the caster, a ray forward. |
| A **preset** | The same query authored as steps: select, filter, sort. |
| A **provider** | A person aims over time, sees a preview and confirms. |

GAS_Engine never reads the mouse, the camera or the input map. Your game turns input into positions and rays; the engine turns positions and rays into targets.

## Target data

`GameplayAbilityTargetData` holds **hits**. A hit is either on a node (an actor) or at a place (a location with nothing standing at it).

| Method | Purpose |
|---|---|
| `append_node(node)` | Aim at a node. Its position is read from the node. |
| `append_overlap(nodes)` | Aim at several nodes. Returns how many were added. |
| `append_physics_hit(hit)` | Add a raw physics result dictionary, with its position and normal. |
| `append_location(position, normal)` | Aim at a place: a `Vector2` or `Vector3`, and an optional normal of the same kind. |
| `get_target_nodes()` | The unique nodes aimed at, skipping freed ones. |
| `has_targets()` / `has_locations()` | Whether anything aimed at is still there, and whether any hit is a place. |
| `get_all_hits()` / `get_hits_for_node(node)` / `first_hit_for(node)` | The hits themselves. |
| `copied(only)` | A new copy, optionally keeping only one node's hits. |
| `force_remove_target(node)` / `clear()` | Remove targets - for an aura whose target walked out. |

A `GameplayTargetHit` has `collider`, `space_kind` (`TWO_D` or `THREE_D`), `has_position`, and `position_2d`/`normal_2d` or `position_3d`/`normal_3d`.

`apply_effect_to_targets(effect, target_data)` resolves each node to its component, applies the effect once per component - two colliders on one character are one target - and gives each target only its own hits. See [Applying to targets](gameplay-effects/index.md#applying-an-effect).

## Physics queries

`GameplayTargetingService` runs one query and returns target data:

| Method | Query |
|---|---|
| `raycast_2d(source_asc, world, request)` | A `GameplayRaycastRequest2D`: `from`, `to`. |
| `raycast_3d(source_asc, world, request)` | A `GameplayRaycastRequest3D`. |
| `overlap_2d(source_asc, world, request)` | A `GameplayOverlapRequest2D`: a circle at `center` with `radius`. |
| `overlap_3d(source_asc, world, request)` | A `GameplayOverlapRequest3D`: a sphere. |

Every request also has `collision_mask`, `collide_with_bodies` (on), `collide_with_areas` (off) and an optional `filter`; overlaps have `max_results` (256).

```gdscript
extends GameplayAbility

@export var volley: GameplayEffect


func _activate_ability() -> bool:
	var avatar: Node2D = owner_asc.get_effect_target() as Node2D
	if avatar == null or not commit_ability().is_ok():
		return false

	var nearest_three: GameplayTargetFilter = GameplayTargetFilter.new()
	nearest_three.max_targets = 3

	var around: GameplayOverlapRequest2D = GameplayOverlapRequest2D.new()
	around.center = avatar.global_position
	around.radius = 180.0
	around.filter = nearest_three

	var found: GameplayAbilityTargetData = GameplayTargetingService.overlap_2d(
		owner_asc, avatar.get_world_2d(), around
	)
	apply_effect_to_targets(volley, found)
	return true
```

- A ray keeps its hit position and normal. A sweep keeps nodes only: physics reports no impact point for an overlap.
- A sweep adds each component once, in the order physics reported, and stops at the filter's `max_targets`. It does not sort by distance.

### Filters

A `GameplayTargetFilter` decides which candidates count:

| Field | Meaning |
|---|---|
| `exclude_source` | Skip the caster. On by default. |
| `required_tags` | The candidate must hold every one of these, exactly. |
| `blocked_tags` | The candidate must hold none of these, exactly. |
| `max_targets` | Keep at most this many. `0` keeps all. |

A candidate is only a target when it has a component or [answers for its own tags](gameplay-tags.md#tags-on-things-that-are-not-characters); a wall with neither is skipped.

## Presets

A `GameplayTargetingPreset` is a list of `GameplayTargetingTask` steps, run in order. Each step receives what the previous one produced.

```gdscript
static func slam_preset() -> GameplayTargetingPreset:
	var area: TargetingSelectAoe = TargetingSelectAoe.new()
	area.radius = 4.0
	var nearest: TargetingSortByDistance = TargetingSortByDistance.new()
	nearest.keep = 3

	var preset: GameplayTargetingPreset = GameplayTargetingPreset.new()
	preset.tasks = [area, nearest] as Array[GameplayTargetingTask]
	return preset
```

```gdscript
var victims: GameplayAbilityTargetData = slam_preset().execute(owner_asc)
```

| Step | Does |
|---|---|
| `TargetingSelectSource` | Adds the caster's avatar. |
| `TargetingSelectAoe` | Adds everything in a sphere around the caster: `radius`, `offset`, `collision_mask`, `collide_with_areas`. |
| `TargetingSelectTrace` | Adds what a ray along the caster's forward (-Z) strikes: `length`, `offset`, `collision_mask`, and the impact point when `keep_impact_point` is on. |
| `TargetingFilterByClass` | Keeps nodes carrying `required_script` or a script extending it; `invert` keeps the rest. |
| `TargetingFilterByTagQuery` | Keeps nodes whose component matches `query`; nodes without a component are dropped unless `invert` is on. |
| `TargetingSortByDistance` | Orders nodes nearest first (or `descending`) and keeps the first `keep`. Places are carried through unsorted. |

The select, trace and sort steps work in 3D. Steps are deterministic - no clocks, no random numbers - so the same world always produces the same targets.

For a step of your own, subclass `GameplayTargetingTask` and override `execute(input, source_asc)`, returning the target data to pass on.

## Providers: interactive aiming

A `GameplayTargetProvider` is an aim with a beginning, a middle and an end. It previews as often as it is asked, then finishes exactly once: **confirmed** with target data, or **cancelled**.

```text
aim_with(provider) ─► PREVIEWING ─┬─► confirm() ─► CONFIRMED ─► submitted to the ability
                        ▲         │
            update_preview()      └─► cancel()  ─► CANCELLED
```

1. The ability starts it with `aim_with(provider)` and waits with `wait_target_data()`.
2. Game code writes the aim - a ray from the camera, a marker position - and calls `update_preview()`, typically every frame. Each call emits `preview_changed(data)`.
3. A confirm - `asc.input_confirm()`, or `provider.confirm()` - emits `confirmed(data)`, and the data is submitted to the ability.
4. A cancel - `asc.input_cancel()`, or `provider.cancel()` - emits `cancelled`. Ending the ability cancels every provider it started.

### A ground-targeted ability

**The ability:**

```gdscript
class_name MeteorAbility extends GameplayAbility

@export var meteor: GameplayEffect
@export var reach: float = 20.0

var provider: GameplayGroundTraceProvider3D = null


func _activate_ability() -> bool:
	provider = GameplayGroundTraceProvider3D.new()
	provider.max_range = reach
	provider.cancelled.connect(abort_ability)
	aim_with(provider)

	var aim: AbilityTaskWaitTargetData = wait_target_data()
	await aim.completed()
	if aim.target_data == null or not aim.target_data.has_locations():
		return false

	# Paid only after the player confirmed a spot.
	if not commit_ability().is_ok():
		return false
	execute_cue(&"Cue.Meteor.Impact")
	# … select and damage whoever stands at the spot
	return true
```

**The player's controller:**

```gdscript
func _physics_process(_delta: float) -> void:
	var ability: MeteorAbility = meteor_spec.per_actor_instance as MeteorAbility
	if ability == null or not ability.is_active or ability.provider == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	ability.provider.request.from = camera.project_ray_origin(mouse)
	ability.provider.request.to = ability.provider.request.from + camera.project_ray_normal(mouse) * 100.0
	ability.provider.update_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"confirm_target"):
		asc.input_confirm()
	elif event.is_action_pressed(&"cancel_target"):
		asc.input_cancel()
```

### Confirmation modes

| `confirmation` | The aim is confirmed… |
|---|---|
| `USER_CONFIRMED` | …when somebody says yes. The default. |
| `INSTANT` | …by the first preview that has a target or a place - snap-to-nearest, auto-aim. |
| `CUSTOM` | …when the provider decides, once. |
| `CUSTOM_MULTI` | …each time the provider decides; it keeps previewing and confirming until cancelled or the ability ends - a chain picking one target after another. |

`state` is `IDLE`, `PREVIEWING`, `CONFIRMED` or `CANCELLED`; `is_choosing()` answers whether it is previewing; `previewed` is the last preview.

### Built-in providers

| Provider | Aims | Game code writes |
|---|---|---|
| `GameplayRaycastTargetProvider2D` / `3D` | Whatever a ray strikes. | `request.from`, `request.to` |
| `GameplayOverlapTargetProvider2D` / `3D` | Everything in a circle or sphere. | `request.center` |
| `GameplayRadiusProvider2D` / `3D` | Everything in a circle or sphere placed within `max_range` of the caster. | `request.center` |
| `GameplayGroundTraceProvider3D` | The **place** a ray meets the world, within `max_range`. Also exposes `landed` and `landed_at`. | `request.from`, `request.to` |
| `GameplayPlacementProvider3D` | A **place** set directly, within `max_range`. `placeable` says whether the last position was allowed. | `position`, `normal` |

Ground-trace and placement providers answer with a location and no nodes; select who stands there with a radius provider, a sweep or a preset.

### Writing a provider

Subclass `GameplayTargetProvider` and override `_aim()`, which returns the target data for the current aim. `source_asc()`, `avatar()`, `world_2d()` and `world_3d()` describe where the ability is aiming from. Override `validate_authoritative(data, source_asc)` to let a server check what a client claims it aimed at. See [Networking](networking.md).

## Reticles

A reticle is what a person sees while aiming. Subclass `GameplayTargetReticle2D` or `GameplayTargetReticle3D` and override `_redraw()`:

```gdscript
class_name MeteorReticle extends GameplayTargetReticle3D

@onready var ring: MeshInstance3D = $Ring


func _redraw() -> void:
	if ring == null:
		return
	ring.visible = valid
	ring.scale = Vector3.ONE * maxf(radius, 0.1)
```

| Method | Effect |
|---|---|
| `follow(data)` | Moves to the first located hit of the aim. |
| `set_valid(value)` | Whether the aim is legal - read `valid` to draw it red. |
| `set_radius(value)` | The area's size - read `radius`. |
| `face_source(value)` | Whether it turns toward the caster - read `faces_source`. |

Each calls `_redraw()`. `aimed` holds the last data passed to `follow()`.

To show a reticle for exactly as long as a provider previews, run the targeting visualization task:

```gdscript
owner_asc.register_ability_task(
	AbilityTaskVisualizeTargeting.create(self, provider, preload("res://game/targeting/meteor_reticle.tscn"))
)
```

It instantiates the scene under the avatar's parent (or the `into` node you pass), moves it with every preview, and frees it when the provider finishes or the ability ends.
