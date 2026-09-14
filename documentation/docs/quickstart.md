---
title: Quickstart
sidebar_position: 1
description: Build a damaging ability, give it to a character, cast it, and watch the result - in about ten minutes.
---

# GAS_Engine in 10 minutes

This walkthrough takes an empty Godot 4.7.2 project to a working ability. You will:

- ✅ Install and enable GAS_Engine
- ✅ Declare the numbers a character is made of
- ✅ Write a fireball that pays for itself, reads its target and deals damage
- ✅ Give it to a character and cast it
- ✅ Watch the result in the runtime overlay

Every file below lives in `res://quickstart/`.

---

## Step 1: Install the addon

1. Copy the `addons/GAS_Engine/` folder into your project's `addons/` folder.
2. Open **Project → Project Settings → Plugins** and enable **GAS_Engine**.

There is no build step. See [Installation](getting-started/installation.md) for what enabling the plugin changes.

---

## Step 2: Declare the attributes

An `AttributeSet` holds every number an entity has. Each attribute is an exported `AttributeData`; the engine finds them by reflection, so there is nothing to register.

**`res://quickstart/hero_attributes.gd`**

```gdscript
class_name HeroAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)


func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)


## Asked before a durable value is stored, so an overkill hit cannot leave
## health at -400.
func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


## Asked again after active modifiers are folded in.
func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func _bounded(attribute_name: StringName, value: float) -> float:
	if attribute_name == HEALTH:
		return clampf(value, 0.0, max_health.current_value)
	return maxf(value, 0.0)
```

:::warning Do not skip `_init()`
An exported default is evaluated once for the script. Without the `_init()` block, every character built from `HeroAttributes` shares one `AttributeData`, and damaging one damages them all.
:::

---

## Step 3: Write the ability

A `GameplayAbility` is a `Node`. It pays for itself with `commit_ability()`, reads whatever it was aimed at, and applies an effect.

**`res://quickstart/fireball.gd`**

```gdscript
class_name Fireball extends GameplayAbility

## Health taken from each target.
@export var damage: float = 30.0


func _activate_ability() -> bool:
	# Pay first. This fireball is free, so the commit succeeds - but the call is
	# what makes a cost or a cooldown work the moment you add one.
	if not commit_ability().is_ok():
		return false

	# Whoever cast the ability handed it its targets.
	var aimed: GameplayAbilityTargetData = get_activation_target_data()
	if aimed == null or not aimed.has_targets():
		return false

	apply_effect_to_targets(_damage_effect(), aimed)
	return true


func _damage_effect() -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = -damage

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = HeroAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Fireball damage"
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

Now make it a scene:

1. Create a new scene whose root is a plain **Node**.
2. Attach `fireball.gd` to the root.
3. Set **Damage** in the Inspector if you want something other than 30.
4. Save it as `res://quickstart/fireball.tscn`.

An ability is always granted from its scene: **the scene carries the numbers, the script carries the behaviour.**

---

## Step 4: Give it to a character

A character is any node with an `AbilitySystemComponent` child.

**`res://quickstart/quickstart_character.gd`**

```gdscript
class_name QuickstartCharacter extends Node2D

const FIREBALL: PackedScene = preload("res://quickstart/fireball.tscn")

var asc: AbilitySystemComponent = null
var fireball: GameplayAbilityHandle = null


func _ready() -> void:
	asc = AbilitySystemComponent.new()
	asc.name = "AbilitySystemComponent"
	asc.attribute_sets = [HeroAttributes.new()] as Array[AttributeSet]
	add_child(asc)

	fireball = asc.give_ability(FIREBALL)


## Cast the fireball at one target, and say what happened.
func cast_fireball_at(target: Node2D) -> GameplayAbilityActivationResult:
	var aim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aim.append_node(target)

	var context: GameplayAbilityActivationContext = GameplayAbilityActivationContext.new()
	context.effect_context = GameplayEffectContext.new(self)
	context.effect_context.target_data = aim
	return asc.try_activate_ability_handle(fireball, context)
```

`give_ability()` returns a `GameplayAbilityHandle`. The handle, not the ability node, is how you refer to a grant from then on.

---

## Step 5: Cast it

Create a scene with a **Node2D** root, attach the script below, and run it.

**`res://quickstart/arena.gd`**

```gdscript
extends Node2D

var hero: QuickstartCharacter = null
var dummy: QuickstartCharacter = null


func _ready() -> void:
	hero = _spawn("Hero", Vector2(200.0, 300.0))
	dummy = _spawn("Dummy", Vector2(600.0, 300.0))
	dummy.asc.attribute_changed.connect(_on_dummy_attribute_changed)

	# The engine's own debugger, drawn by the game.
	var overlay_scene: PackedScene = load(GasDebugOverlay.SCENE) as PackedScene
	var overlay: GasDebugOverlay = overlay_scene.instantiate() as GasDebugOverlay
	add_child(overlay)
	overlay.watch(dummy.asc)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var result: GameplayAbilityActivationResult = hero.cast_fireball_at(dummy)
		print("Fireball: ", GameplayAbilityActivationResult.Status.keys()[result.status])


func _spawn(named: String, at: Vector2) -> QuickstartCharacter:
	var character: QuickstartCharacter = QuickstartCharacter.new()
	character.name = named
	character.position = at
	add_child(character)
	return character


func _on_dummy_attribute_changed(
	attribute_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	print("Dummy %s: %s -> %s" % [attribute_name, old_value, new_value])
```

Press **Enter** (or **Space**). The output shows:

```text
Dummy health: 100.0 -> 70.0
Fireball: SUCCESS
```

---

## Step 6: Watch it in the overlay

The overlay in the top-left corner shows the dummy's **Attributes** page: `health` has dropped by 30 on both its base and current values. Press **Enter** three more times and the clamp in `HeroAttributes` stops health at 0.

The other tabs - **Active effects**, **Abilities**, **Tags** - stay empty for now, because an `INSTANT` effect changes a base value and leaves nothing running.

---

## What just happened

| Step | Engine call | What it guaranteed |
|---|---|---|
| Grant | `give_ability(FIREBALL)` | The scene was instantiated once and its definition frozen into a spec. |
| Activate | `try_activate_ability_handle()` | Tag rules, cooldowns and costs were checked before `_activate_ability()` ran. |
| Pay | `commit_ability()` | Every cost and cooldown is taken as one transaction, or none is. |
| Aim | `get_activation_target_data()` | The ability read the targets its caller chose instead of searching the world. |
| Hit | `apply_effect_to_targets()` | Each target got its own copy of the effect, found through its own ASC. |
| React | `attribute_changed` | The signal fired once, because the value actually moved. |

## Next steps

- Understand the model behind these calls in [Core concepts](getting-started/core-concepts.md).
- Give the fireball a mana cost and a cooldown with [Costs and cooldowns](guides/abilities/costs-and-cooldowns.md).
- Turn the damage into a burn that ticks with [Duration and periodic effects](guides/gameplay-effects/duration-and-periodic-effects.md).
- Open `fireball.gd` in the [Ability Composer](guides/ability-composer/index.md) and see it drawn as a graph.
