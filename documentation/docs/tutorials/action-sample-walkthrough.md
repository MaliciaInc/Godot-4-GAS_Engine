---
title: Action Sample Walkthrough
sidebar_position: 3
description: A tour of the engine repository's 3D action sample - a loadout, an instant strike, a channel with a persistent cue, and an aimed ground slam with a reticle and a preset.
---

# Action Sample Walkthrough

The engine repository ships `examples/action_sample/`: a 3D hero with three abilities, three dummies to hit, and the debug overlay. It is small enough to read in one sitting, and every ability in it adds one idea to the last.

## Running it

**Inside the engine repository:** open the project and play `examples/action_sample/main.tscn`.

**As a project of its own:**

1. Copy `examples/action_sample/` out of the repository.
2. Rename `project.godot.standalone` to `project.godot`.
3. Put `addons/GAS_Engine/` beside it.
4. Open the folder in Godot, enable the plugin, and play.

## What is where

| File | Shows |
|---|---|
| `attributes/sample_attributes.gd` | An attribute set with base and current clamps. |
| `effects/sample_effects.gd` | Every effect the sample applies, built in code. |
| `abilities/sample_basic_attack.gd` | An instant attack with a cooldown and a burst cue. |
| `abilities/sample_channel.gd` | An ability that stays up, with a drain and a looping cue. |
| `abilities/sample_ground_slam.gd` | An aimed area effect with a provider, a reticle and a preset. |
| `targeting/sample_targeting.gd` | The slam's preset, provider and reticle. |
| `cues/sample_cues.gd` | Cue templates bound at runtime. |
| `scripts/sample_loadout.gd` | The loadout, granted and taken back in one call each. |
| `scripts/sample_hero.gd` | A character: a node, a component and a loadout. |
| `scripts/sample_world.gd` | The scene: a hero, dummies, cues and the overlay. |
| `tests/sample_probe.gd` | An automated check of every ability. |
| `network/` | The same sample as an authority and a client. |

Everything is built in code rather than saved as `.tres`, so every number is visible in one place. Your own project can author the same objects as resources.

## The hero and the loadout

```gdscript
class_name SampleHero extends Node3D

var asc: AbilitySystemComponent = null
var loadout: GameplayAbilitySetHandles = null


func equip() -> void:
	if asc != null:
		return
	asc = AbilitySystemComponent.new()
	asc.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	asc.share_attributes = true
	add_child(asc)
	loadout = SampleLoadout.built().grant(asc)


func unequip() -> void:
	if loadout != null:
		loadout.take_back()
	loadout = null
```

- The component is named `AbilitySystemComponent`, which is how `AbilitySystemLocator` finds it from any node of the character.
- `share_attributes` is on, so the component uses the attribute set the loadout hands it rather than a copy. The loadout builds a fresh `SampleAttributes` for every character, so no two characters share one.
- The loadout is a `GameplayAbilitySet` holding the attribute set and three ability entries. `grant()` publishes all of it or none; `take_back()` retires it in reverse. See [Ability sets](../guides/abilities/granting-and-loadouts.md#ability-sets).

The abilities are built in code, so `SampleLoadout` packs each one into a `PackedScene` once and gives it a resource path with `take_over_path()`. A grant takes a scene, and a network definition is named by the scene's path.

## Strike: an instant attack

```gdscript
static func build() -> SampleBasicAttack:
	var ability: SampleBasicAttack = SampleBasicAttack.new()
	ability.name = String(NAME)
	ability.ability_name = "Strike"
	ability.ability_tags = [TAG]
	ability.cooldown_effect = SampleEffects.strike_cooldown(COOLDOWN_SECONDS)
	ability.net_execution_policy = NetExecutionPolicy.LOCAL_PREDICTED
	return ability


func _activate_ability() -> bool:
	struck.clear()
	if not commit_ability().is_ok():
		return false
	var data: GameplayAbilityTargetData = get_activation_target_data()
	if data == null or not data.has_targets():
		return false
	apply_effect_to_targets(SampleEffects.strike(), data)
	struck.assign(data.get_target_nodes())
	execute_cue(SampleCues.STRIKE_IMPACT)
	return not struck.is_empty()
```

- The rules are set in `build()`, on the node that is then packed - before any grant.
- The target arrives with the activation: `SampleHero.strike(victim)` builds target data and passes it in an activation context. See [Passing context](../guides/abilities/activation-and-input.md#passing-context).
- The cooldown is a `DURATION` effect with one target-tags component: a tag and a clock.

## Channel: an ability that stays up

```gdscript
static func build() -> SampleChannel:
	var ability: SampleChannel = SampleChannel.new()
	# …
	ability.auto_end_on_activate_return = false
	return ability


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false
	_drain = owner_asc.apply_gameplay_effect(
		SampleEffects.channel_drain(), owner_asc, get_ability_level()
	)
	if _drain == null:
		return false
	activate_persistent_cue(SampleCues.CHANNEL_LOOP)
	return true


func on_granted() -> void:
	if not ability_ended.is_connected(_on_ended):
		ability_ended.connect(_on_ended)


func _on_ended(_was_cancelled: bool) -> void:
	if _drain != null and owner_asc != null:
		owner_asc.remove_active_effect(_drain)
	_drain = null
```

- With `auto_end_on_activate_return` off, returning `true` leaves the ability running.
- The drain is an `INFINITE` effect with a `period`: it takes mana on every tick until removed.
- The looping cue is not tracked by hand. Every persistent cue an activation starts is stopped when the ability ends, however it ends.
- The drain is removed in one place - the ability's own `ability_ended` - so a normal end, a cancel and a removed grant all clean up the same way.

## Slam: aiming, a reticle and a preset

The slam lets the player choose a spot, shows a ring there, then damages and staggers whoever the preset selects.

```gdscript
func _activate_ability() -> bool:
	struck.clear()
	if not commit_ability().is_ok():
		return false
	_reticle = SampleTargeting.slam_reticle()
	var avatar: Node = owner_asc.get_effect_target()
	if avatar != null:
		avatar.add_child(_reticle)
	aim_with(SampleTargeting.slam_provider())
	var waiting: AbilityTaskWaitTargetData = wait_target_data()
	await waiting.completed()
	_land(waiting.target_data)
	return true
```

| Piece | Built as |
|---|---|
| Provider | A `GameplayPlacementProvider3D` with `max_range = 12`: the game writes its `position`. |
| Reticle | A `GameplayTargetReticle3D` with `set_radius(4.0)`. |
| Preset | `TargetingSelectAoe` with `radius = 4`, then `TargetingSortByDistance`. |

`aim_with()` connects the provider's confirmation to the ability's `submit_target_data()`, so `wait_target_data()` receives the confirmed spot without knowing a provider was involved. In a game, input moves the provider's `position`, calls `update_preview()`, and confirms with `asc.input_confirm()`. The sample's probe submits target data directly.

`_land()` reads where the aim landed, runs the preset to find who is standing in the circle, joins both lists, and applies two effects:

```gdscript
	if victims.has_targets():
		apply_effect_to_targets(SampleEffects.slam(), victims)
		apply_effect_to_targets(SampleEffects.stagger(), victims)
		struck.assign(victims.get_target_nodes())
	execute_cue(SampleCues.SLAM_IMPACT)
	end_ability()
```

The stagger is a `DURATION` effect that only grants `Status.Staggered`. The slam's own `activation_blocked_query` names that tag, so a staggered character cannot slam - and `can_activate_ability_handle()` says so to a UI before anyone presses a key. The query is built with `GameplayTagQueryEdits`:

```gdscript
static func _while_staggered() -> GameplayTagQuery:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	GameplayTagQueryEdits.set_operator(expression, GameplayTagQueryExpression.Operator.ANY)
	GameplayTagQueryEdits.add_tag(expression, SampleEffects.STAGGERED)
	return query
```

## Cues from templates

The sample's cues are not scripts. A strike and a slam play a `GameplayCueNotifyBurst`; the channel plays a `GameplayCueNotifyLooping` with a recurring set every second. `SampleCues` packs each template into a scene and binds it on the manager at runtime:

```gdscript
static func bind_into(manager: CueManagerScript) -> int:
	if manager == null:
		return 0
	var bound: int = 0
	bound += 1 if manager.bind_cue(STRIKE_IMPACT, burst()) else 0
	bound += 1 if manager.bind_cue(SLAM_IMPACT, burst()) else 0
	bound += 1 if manager.bind_cue(CHANNEL_LOOP, loop()) else 0
	return bound
```

The sample binds at runtime so it does not rewrite the repository's cue registry. A game lists its cues in `res://gas_engine/gameplay_cues.gd`. See [Binding cues](../guides/gameplay-cues.md#binding-cues).

## The world

`SampleWorld` binds the cues, builds the hero and three dummies, and watches the hero with the overlay:

```gdscript
func _overlay() -> GasDebugOverlay:
	var scene: PackedScene = load(GasDebugOverlay.SCENE)
	if scene == null:
		return null
	var made: GasDebugOverlay = scene.instantiate()
	add_child(made)
	return made


func console(line: String) -> String:
	return GasDebugCommands.run(line, self)
```

`console()` is the one call a game's console needs for every `gas.` command. See [Debugging](../guides/debugging.md).

## Over a network

The three abilities carry different network policies - predicted strike and slam, and a channel only the authority may start - and the same sample runs as two processes over ENet. Continue with [Multiplayer across two processes](multiplayer-across-two-processes.md).
