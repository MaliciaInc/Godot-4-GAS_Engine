---
title: Testing Your Gameplay
sidebar_position: 6
description: Test gameplay rules with GUT unit tests, and hold your real game to them with headless probe scenes.
---

# Testing Your Gameplay

GAS_Engine's rules are deterministic, which makes gameplay testable. Two kinds of test cover a game well:

| Kind | Proves | Runs |
|---|---|---|
| **Unit tests** | A rule: this effect deals this damage, this cost is refused, this cooldown lasts three turns. | GUT, in isolation, in seconds. |
| **Probes** | The game: real characters, real scenes, real content, through the same code paths the game uses. | A headless scene that prints a result line. |

## Unit tests with GUT

Install [GUT](https://github.com/bitwes/Gut) into your project. GAS_Engine's own suite uses GUT `v9.7.1` on Godot 4.7.

### A component to test against

```gdscript
extends GutTest

const HEALTH: StringName = &"health"
const MANA: StringName = &"mana"

var hero: Node2D = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	hero = Node2D.new()
	add_child_autofree(hero)
	asc = AbilitySystemComponent.new()
	asc.attribute_sets = [CharacterAttributes.new()] as Array[AttributeSet]
	hero.add_child(asc)


func _instant(attribute_name: StringName, amount: float) -> GameplayEffect:
	var value: GameplayScalableFloat = GameplayScalableFloat.new()
	value.value = amount
	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = value
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = attribute_name
	modifier.magnitude = magnitude
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

`CharacterAttributes` is the set from [Declaring an attribute set](../guides/attributes.md#declaring-an-attribute-set), with the clamps from [Clamping](../guides/attributes.md#clamping). `add_child_autofree()` frees the character after each test, so nothing leaks from one test into the next. The component is added to the tree before anything is granted or applied.

### Testing a rule

```gdscript
func test_overkill_leaves_health_at_zero_and_heals_from_zero() -> void:
	asc.apply_gameplay_effect(_instant(HEALTH, -500.0))
	assert_eq(asc.get_attribute_current(HEALTH), 0.0)
	assert_eq(asc.get_attribute_base(HEALTH), 0.0)

	asc.apply_gameplay_effect(_instant(HEALTH, 30.0))
	assert_eq(asc.get_attribute_current(HEALTH), 30.0)


func test_a_buff_is_withdrawn_to_exactly_base() -> void:
	var haste: GameplayEffect = _instant(CharacterAttributes.MOVE_SPEED, 50.0)
	haste.policy = GameplayEffect.DurationPolicy.INFINITE
	var active: ActiveGameplayEffect = asc.apply_gameplay_effect(haste)
	assert_almost_eq(asc.get_attribute_current(CharacterAttributes.MOVE_SPEED), 350.0, 0.0001)

	asc.remove_active_effect(active)
	assert_almost_eq(asc.get_attribute_current(CharacterAttributes.MOVE_SPEED), 300.0, 0.0001)
```

### Testing an ability

Grant abilities from scenes. A test can pack an ability built in code into a scene:

**`res://test/fixtures/expensive_probe.gd`**

```gdscript
class_name ExpensiveProbe extends GameplayAbility


func _init() -> void:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = 80.0
	var mana_cost: GameplayAbilityCost = GameplayAbilityCost.new()
	mana_cost.target_attribute = &"mana"
	mana_cost.amount = amount
	costs = [mana_cost] as Array[GameplayAbilityCost]


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false
	await wait_delay(0.5).completed()
	return true


static func scene() -> PackedScene:
	var ability: ExpensiveProbe = ExpensiveProbe.new()
	var packed: PackedScene = PackedScene.new()
	packed.pack(ability)
	ability.free()
	return packed
```

```gdscript
func test_an_unaffordable_ability_is_refused_and_charges_nothing() -> void:
	asc.set_attribute_base(MANA, 50.0)
	var handle: GameplayAbilityHandle = asc.give_ability(ExpensiveProbe.scene())

	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)

	assert_eq(result.status, GameplayAbilityActivationResult.Status.INSUFFICIENT_RESOURCES)
	assert_eq(asc.get_attribute_base(MANA), 50.0)


func test_an_affordable_ability_pays_and_ends_after_its_wait() -> void:
	asc.set_attribute_base(CharacterAttributes.MAX_MANA, 100.0)
	asc.set_attribute_base(MANA, 100.0)
	var handle: GameplayAbilityHandle = asc.give_ability(ExpensiveProbe.scene())

	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)

	assert_true(result.is_ok())
	assert_eq(asc.get_attribute_base(MANA), 20.0)
	assert_true(result.instance.is_active)
	await wait_seconds(0.75)
	assert_false(result.instance.is_active)
```

Tasks advance on the component's `_process`, so real frames must pass for a wait to finish - `wait_seconds()` and `wait_frames()` provide them.

### What is worth a unit test

- Every clamp, including the base clamp and a maximum dropping under its pool.
- Every cost and cooldown: refused, paid, and lifted on the right turn after `advance_turn()`.
- Every custom execution and magnitude calculation, with numbers worked out by hand.
- Stacking and expiry: buffs removed in any order land back on base.
- Refusals: assert the status, and that nothing changed.

## Probes in the real game

A probe is a scene that drives your real content through the same seam your game uses, and ends with one line a script can read. GAS_Engine's integration sandbox holds its turn-based RPG to the engine's contracts this way.

```gdscript
extends Node

const CASES: Array[String] = ["damage", "cost_refused", "cooldown"]

var _passed: int = 0
var _failures: Array[String] = []
var _finished: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	var wolf: Battler = _spawn("Wolf", [preload("res://combat/battlers/wolf/area_attack.tscn")])
	var target: Battler = _spawn("Target", [])
	await get_tree().process_frame

	await _case_damage(wolf, target)
	# … the other cases

	_report()


func _case_damage(attacker: Battler, target: Battler) -> void:
	var before: float = target.attribute(BattlerAttributes.HEALTH)
	await attacker.act(attacker.granted[0], [target] as Array[Battler])
	_check("damage", target.attribute(BattlerAttributes.HEALTH) < before, "health did not drop")
	_finished.append("damage")


func _check(case_name: String, holds: bool, detail: String) -> void:
	if holds:
		_passed += 1
	else:
		_failures.append("%s: %s" % [case_name, detail])


func _report() -> void:
	for case_name: String in CASES:
		if not _finished.has(case_name):
			_failures.append("%s did not reach its last line" % case_name)
	var verdict: String = "PASS" if _failures.is_empty() else "FAIL"
	print("COMBAT_PROBE_RESULT: %s passed=%d failed=%d" % [verdict, _passed, _failures.size()])
	for failure: String in _failures:
		print("  ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
```

`_spawn()` stands for your own helper that instantiates a character with abilities. Run the probe headless:

```bash
godot --headless --path . res://test/combat_probe.tscn
```

### Rules that keep probes honest

- **Every case must reach its last line.** A case that stops halfway - an `await` that never returns, an early `return` - must fail the run, not quietly shrink it. That is what `_finished` is for.
- **Choose content that cannot roll.** Use abilities without accuracy rolls and targets without evasion, so the same run gives the same numbers.
- **Let frames pass after heavy setup.** A wait counts the frame it starts in; starting a timed ability right after loading scenes can see one long frame and finish early. Await two `process_frame`s before timing-sensitive activations.
- **Speed up waits** with `Engine.time_scale` rather than shortening your game's timings.
- **Assert with the real tags and names** your content uses, not with copies typed into the test.
- **Read state through the engine** - `get_attribute_current()`, `has_tag_exact()`, `get_ability_cooldown_state()` - never through a copy your game keeps.

## Debug helpers in tests

- `GasDebugCommands.run("gas.attributes Hero", self)` returns the Attributes page as text, which makes a failing probe's output useful.
- `GasRuntimeSnapshot.of(asc)` captures an entity without changing it.
- `GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COOLDOWNS, true)` lets a probe run one ability repeatedly; call `GasDebugOptions.forget()` at the end.

See [Debugging](../guides/debugging.md).
