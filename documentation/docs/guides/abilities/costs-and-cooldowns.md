---
title: Costs and Cooldowns
sidebar_position: 3
description: Pricing an ability with attribute costs, cost effects and custom costs, the transactional commit, and cooldowns in seconds or turns.
---

# Costs and Cooldowns

An ability pays and starts its cooldowns in one call:

```gdscript
func _activate_ability() -> bool:
	var paid: AbilityCommitResult = commit_ability()
	if not paid.is_ok():
		return false
	# … the ability
	return true
```

Everything an ability can charge and every cooldown it starts is declared on the ability, frozen at grant, and taken by `commit_ability()`.

| Field | Declares |
|---|---|
| `costs` | Attribute costs the engine prices. |
| `cost_effect` | A cost written as a gameplay effect. |
| `custom_costs` | Costs the engine cannot price: ammunition, items, charges. |
| `cooldown_effect` | The ability's own cooldown. |
| `shared_cooldown_effects` | Cooldowns shared with other abilities. |
| `shared_cooldown_tags` | Tags that also count as this ability's cooldown. |

:::danger Declare them before `_ready()`
The definition is frozen when the ability is granted, before `_ready()` runs. A cost built in `_ready()` never reaches the engine and the ability is free. Build costs and cooldowns in the scene, in `_init()`, or in a property setter.
:::

## The commit

`commit_ability()` is a transaction. It either takes the whole price or none of it:

1. Resolve the `costs`, check `cost_effect`, and ask every custom cost whether it can be paid.
2. Check that every cooldown is legal and none is already running.
3. Start the cooldowns.
4. Check the cost again - starting a cooldown raises signals, and a listener may have spent the resources.
5. Prepare every custom cost, charge the resolved cost, apply `cost_effect`, commit the custom costs.

Any failure undoes what was already done, in reverse. One activation commits at most once.

| `AbilityCommitResult.status` | Meaning |
|---|---|
| `SUCCESS` | Everything was paid and started. |
| `OWNER_MISSING` | The ability is not granted. |
| `ALREADY_COMMITTED` | This activation already paid. |
| `INVALID_COST_DEFINITION` | A cost cannot be resolved, or `cost_effect` breaks the cost contract. |
| `INVALID_COOLDOWN_DEFINITION` | A cooldown breaks the cooldown contract. |
| `INSUFFICIENT_RESOURCES` | Something cannot be paid. |
| `ON_COOLDOWN` | A cooldown tag is present. |
| `COOLDOWN_APPLICATION_FAILED` / `COST_APPLICATION_FAILED` | Applying failed; everything was rolled back. |
| `RESOURCES_CHANGED_DURING_COMMIT` | The resources moved while cooldowns were starting; everything was rolled back. |

The result also carries `resolved_cost` (what the costs resolved to, even on refusal), `applied_cost` and `applied_cooldowns`. Every commit attempt emits `ability_committed(handle, result)` on the component - a refused one too, with its status - except one with no owner to emit it on.

## Attribute costs

Each `GameplayAbilityCost` in `costs` charges one attribute:

| Field | Meaning |
|---|---|
| `mode` | `ABSOLUTE`, `PERCENT_OF_BASE` or `PERCENT_OF_CURRENT`. |
| `target` / `target_attribute` | The attribute spent, as a `GameplayAttributeRef` or by name. The reference wins when both are set. |
| `reference` / `reference_attribute` | For a percent mode, the attribute the percentage is taken of, the same two ways. Empty for `ABSOLUTE`. |
| `amount` | A `GameplayScalableFloat`. The amount itself for `ABSOLUTE`; the fraction (`0.10` for 10%) for a percent mode. Never negative, never above `1.0` for a percent. |

```gdscript
extends GameplayAbility

## Mana this costs. Built in the setter so it exists before the grant.
@export var mana_cost: float = 20.0:
	set(value):
		mana_cost = value
		costs = _priced()


func _priced() -> Array[GameplayAbilityCost]:
	var flat: GameplayScalableFloat = GameplayScalableFloat.new()
	flat.value = mana_cost
	var mana: GameplayAbilityCost = GameplayAbilityCost.new()
	mana.mode = GameplayAbilityCost.Mode.ABSOLUTE
	mana.target_attribute = &"mana"
	mana.amount = flat

	var tenth: GameplayScalableFloat = GameplayScalableFloat.new()
	tenth.value = 0.10
	var vigor: GameplayAbilityCost = GameplayAbilityCost.new()
	vigor.mode = GameplayAbilityCost.Mode.PERCENT_OF_BASE
	vigor.target_attribute = &"health"
	vigor.reference_attribute = &"max_health"
	vigor.amount = tenth

	return [mana, vigor] as Array[GameplayAbilityCost]
```

The list is resolved **once** per check: every entry is evaluated, entries on the same attribute are summed, and the result is one instant effect with one negative `ADD` per attribute. A percentage is never recomputed during the commit.

When the list cannot be resolved, the check reports why:

| `GameplayResolvedCost.status` | Meaning |
|---|---|
| `OK` | Resolved and affordable. |
| `INVALID_DEFINITION` | An entry is missing its attribute or amount, or names a reference in `ABSOLUTE` mode. |
| `TARGET_ATTRIBUTE_NOT_FOUND` / `REFERENCE_ATTRIBUTE_NOT_FOUND` | The owner has no such attribute. |
| `PERCENT_OUT_OF_RANGE` | A percent amount outside `0.0`-`1.0`. |
| `NON_FINITE_VALUE` | The price is not a number. |
| `INSUFFICIENT_RESOURCES` | Resolved, but not affordable. |

What "affordable" means depends on the [aggregation profile](../attributes.md#aggregation-profiles): under `GODOT_NATIVE` the charge must not take the base below zero or be altered by the set's clamp; under `CHANNEL_FOLDED` it must fit in the current value.

## Cost effects

A project that already prices things as effects can set `cost_effect`. The commit accepts it only when it is a charge that can be undone exactly:

- `INSTANT`, with no components, and silent (`GameplayEffect.is_silent()`).
- Only `ADD` modifiers, each with a `GameplayScalableMagnitude` that is zero or negative at the ability's level.

Anything else is refused with `INVALID_COST_DEFINITION`.

## Custom costs

Ammunition, an item, a charge on a weapon: subclass `GameplayAbilityCustomCost`. It answers two separate questions, so a UI can ask without anything being taken:

| Method | Returns |
|---|---|
| `check(asc, spec, level)` | `GameplayAbilityCustomCostCheck.allowed()`, or `refused(reason_tag)`. |
| `prepare(asc, spec, level)` | A `GameplayAbilityPreparedCustomCost` that can take the cost and put it back, or `null` to refuse. |

**`res://game/costs/ammo_cost.gd`**

```gdscript
class_name AmmoCost extends GameplayAbilityCustomCost

@export var rounds: int = 1


func check(asc: AbilitySystemComponent, _spec: GameplayAbilitySpec, _level: float) -> GameplayAbilityCustomCostCheck:
	var magazine: Magazine = _magazine_of(asc)
	if magazine == null or magazine.loaded < rounds:
		return GameplayAbilityCustomCostCheck.refused(&"Ability.Failed.NoAmmo")
	return GameplayAbilityCustomCostCheck.allowed()


func prepare(asc: AbilitySystemComponent, _spec: GameplayAbilitySpec, _level: float) -> GameplayAbilityPreparedCustomCost:
	var magazine: Magazine = _magazine_of(asc)
	return SpentRounds.new(magazine, rounds) if magazine != null else null


func _magazine_of(asc: AbilitySystemComponent) -> Magazine:
	return asc.get_effect_target().get_node_or_null("Magazine") as Magazine
```

**`res://game/costs/spent_rounds.gd`**

```gdscript
class_name SpentRounds extends GameplayAbilityPreparedCustomCost

var _magazine: Magazine = null
var _rounds: int = 0


func _init(magazine: Magazine, spent: int) -> void:
	_magazine = magazine
	_rounds = spent


func commit() -> bool:
	if _magazine.loaded < _rounds:
		return false
	_magazine.loaded -= _rounds
	return true


func rollback() -> void:
	_magazine.loaded += _rounds
```

`Magazine` stands for your game's own node. `commit()` must take everything or nothing, and `rollback()` must put back exactly what `commit()` took; the engine calls `rollback()` only on a cost whose `commit()` answered `true`.

## Checking affordability

| Question | Ask |
|---|---|
| Could it activate right now? | `asc.can_activate_ability_handle(handle)` - runs every gate, and prices the `costs` list. |
| Could the instance pay everything? | `check_cost()` on the ability - also checks `cost_effect` and every custom cost. |
| Is a cooldown in the way? | `check_cooldown()` on the ability. |

Both checks return an `AbilityCommitPreflight` with a `status` (`OK`, `ON_COOLDOWN`, `INSUFFICIENT_RESOURCES`, `INVALID_COST`, `INVALID_COOLDOWN`), the `resolved_cost`, and `refused_custom_cost` - the custom cost's refusal with its reason tag.

## Cooldowns

A cooldown is an effect that grants a tag for a while. **The tag is the cooldown**: an ability is on cooldown for exactly as long as its owner carries one of its cooldown tags.

```gdscript
func _cooldown(seconds: float) -> GameplayEffect:
	var marker: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	marker.granted_tags = [&"Cooldown.Fireball"] as Array[StringName]

	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Fireball cooldown"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = seconds
	effect.components.append(marker)
	return effect
```

A cooldown effect is legal when it:

- has no modifiers - a cooldown is not a debuff;
- grants at least one tag;
- has no components other than `GameplayEffectTargetTagsComponent` and `GameplayEffectUIDataComponent`;
- is silent;
- is `DURATION` with `duration` above zero, or `TURN_BASED` with `duration_turns` above zero.

Anything else is refused at commit with `INVALID_COOLDOWN_DEFINITION`.

### Cooldowns in turns

A `TURN_BASED` cooldown counts turns, and turns pass only when the game says so:

```gdscript
func next_round() -> void:
	for battler: Battler in roster.get_battlers():
		battler.asc.advance_turn()
```

Without `advance_turn()`, a turn-based cooldown never lifts. See [Duration and periodic effects](../gameplay-effects/duration-and-periodic-effects.md#turn-based-effects).

### Shared cooldowns

| To make… | Use |
|---|---|
| Several abilities wait on one cooldown | The same tag in each ability's cooldown, or the same effect in `shared_cooldown_effects`. |
| An ability wait on a cooldown it never starts | The tag in `shared_cooldown_tags` - a global cooldown started by other abilities. |

An effect listed both as `cooldown_effect` and in `shared_cooldown_effects` is started once.

### Showing a cooldown

`get_cooldown_state()` on the ability, or `asc.get_ability_cooldown_state(handle)`, returns an `AbilityCooldownState` snapshot:

| Field | Meaning |
|---|---|
| `active` | Whether any cooldown tag is present. |
| `infinite` | A cooldown tag with no end - nothing to draw a bar for. |
| `seconds_remaining` / `turns_remaining` | The longest wait left, in each unit. |
| `duration` / `turns` | What the running cooldown was started for - the denominator of a bar. |
| `tags` | The cooldown tags consulted. |

```gdscript
func _process(_delta: float) -> void:
	var cooldown: AbilityCooldownState = asc.get_ability_cooldown_state(handle)
	button.disabled = cooldown.active
	if cooldown.active and not cooldown.infinite and cooldown.duration > 0.0:
		sweep.value = cooldown.seconds_remaining / cooldown.duration
```

Ask again each frame rather than keeping the state: it is a snapshot.

## While testing

The debug commands `gas.ignore_costs` and `gas.ignore_cooldowns` make every ability free or cooldown-free in debug builds, without touching any attribute or tag. See [Debugging](../debugging.md).
