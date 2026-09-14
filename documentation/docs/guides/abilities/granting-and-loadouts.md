---
title: Granting and Loadouts
sidebar_position: 5
description: Granting abilities, handles and specs, what is frozen at grant, grant sources, removal policies and all-or-nothing ability sets.
---

# Granting and Loadouts

## Granting an ability

```gdscript
var slash: GameplayAbilityHandle = asc.give_ability(preload("res://game/abilities/slash.tscn"))
```

| Parameter | Meaning |
|---|---|
| `ability_scene` | A scene whose root is a `GameplayAbility`. |
| `level` | The grant's level. Defaults to `1.0`. |
| `input_id` | The input slot it answers, or `-1`. |
| `source` | What caused the grant. See [Sources](#sources). |

For an input action, use `give_ability_with_options()`:

```gdscript
var options: GameplayAbilityGrantOptions = GameplayAbilityGrantOptions.new()
options.level = 2.0
options.input_action = &"dash"
var dash: GameplayAbilityHandle = asc.give_ability_with_options(dash_scene, options)
```

When the options name no action, the grant uses the ability's own `input_action` export.

A refused grant returns a handle whose `is_valid()` is `false`. A grant is refused when the scene is missing, cannot be instantiated, has a root that is not a `GameplayAbility`, or declares a `PASSIVE` ability with `PER_EXECUTION` instancing. A component with `suppress_ability_grants` on refuses every grant.

Every successful grant emits `ability_granted(handle)`.

## Handles and specs

A `GameplayAbilityHandle` is the identity of a grant. It outlives every activation, and it only resolves on the component that issued it. After the grant is removed the handle still answers `is_valid()`, but resolves to nothing. Compare handles with `same_as()`.

`asc.get_ability_spec(handle)` returns the `GameplayAbilitySpec`:

| Member | Meaning |
|---|---|
| `handle` | The grant's handle. |
| `definition` | The frozen definition. |
| `level` | The grant's level. |
| `input_id` / `input_action` | The input binding. |
| `source` | What caused the grant. |
| `dynamic_tags` | Extra identity tags for this grant. |
| `active_count` | How many activations are running. |
| `per_actor_instance` | The `PER_ACTOR` node, or `null`. |
| `active_instances` | The running `PER_EXECUTION` and `NON_INSTANCED` nodes. |
| `pending_remove` | Whether the grant is waiting to be removed. |
| `last_activation_result` | The result of the most recent activation attempt. |

| Finding grants | Returns |
|---|---|
| `get_ability_specs()` | Every grant, in grant order. |
| `find_ability_specs(query)` | Grants whose effective tags match. |
| `find_ability_spec_by_input(id)` | The first grant bound to a slot. |
| `find_ability_spec_by_script(script)` | The first grant of an ability script. |

## The frozen definition

The grant reads the ability scene once into a `GameplayAbilityDefinitionSnapshot`: its name, policies, tags and tag queries, triggers, costs, cost effect, custom costs, cooldowns and input action. Arrays are copied. Editing the scene or the instance afterwards changes nothing about the grant.

The snapshot is taken right after `instantiate()`, before `_ready()`. The engine reports, once, an ability whose fields no longer match its snapshot when it first commits - the sign that something was configured too late.

## Sources

A source records **why** a grant exists. It never affects gameplay; it lets a game find and remove what one thing granted.

| Source | Carries |
|---|---|
| `GameplayAbilityNodeSource` | `node` - a weapon, a trap, a caster. |
| `GameplayAbilityNamedSource` | `id` - a quest id, an item prototype, any identity the game tracks itself. |
| `GameplayAbilityEffectSource` | `effect_handle` - set by the engine for abilities granted by an effect. |

```gdscript
var reward: GameplayAbilityNamedSource = GameplayAbilityNamedSource.new()
reward.id = &"quest.the_lost_blade"
asc.give_ability(blade_dance_scene, 1.0, -1, reward)
```

`asc.find_effect_handle_that_granted(handle)` returns the effect behind a grant, when there is one.

Effects grant abilities for as long as they are active through `GameplayEffectGrantAbilitiesComponent`. See [Granted abilities](../gameplay-effects/components.md#granted-abilities).

## Removing an ability

```gdscript
asc.remove_ability_handle(handle)
asc.remove_ability_handle(handle, AbilityRuntime.AbilityRemovalPolicy.AFTER_ACTIVE_END)
```

| Policy | Behaviour |
|---|---|
| `CANCEL_IMMEDIATELY` | Running activations are cancelled and the grant is gone now. The default. |
| `AFTER_ACTIVE_END` | Running activations finish; new ones are refused with `PENDING_REMOVAL`; the grant goes when the last one ends. |

The `PER_ACTOR` instance is told through `on_removed()` before anything is severed.

| Also | Does |
|---|---|
| `set_remove_ability_on_end(handle)` | The same as `AFTER_ACTIVE_END`. |
| `clear_abilities_with_input(id)` | Removes every grant bound to a slot and returns how many. |
| `clear_all_abilities()` | Removes every grant. |
| `give_ability_and_activate_once(scene, level, source, context)` | Grants, activates, and removes the grant when that activation ends - or at once if it never started. |

## Ability sets

A loadout - a class kit, a weapon's moves, a transformation - is a `GameplayAbilitySet`:

| Field | Holds |
|---|---|
| `abilities` | `GameplayAbilitySetEntry` resources: `ability_scene`, `level`, `input_id`. |
| `effects` | Effects applied to the owner, typically `INFINITE` passives. |
| `attribute_sets` | Attribute sets registered on the owner. |

```gdscript
class_name WarriorLoadout extends RefCounted


static func built() -> GameplayAbilitySet:
	var slash: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	slash.ability_scene = preload("res://game/abilities/slash.tscn")
	slash.input_id = 0

	var shield_wall: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	shield_wall.ability_scene = preload("res://game/abilities/shield_wall.tscn")
	shield_wall.input_id = 1

	var kit: GameplayAbilitySet = GameplayAbilitySet.new()
	kit.abilities = [slash, shield_wall] as Array[GameplayAbilitySetEntry]
	kit.attribute_sets = [WarriorAttributes.new()] as Array[AttributeSet]
	return kit
```

```gdscript
var receipt: GameplayAbilitySetHandles = WarriorLoadout.built().grant(asc)
# … when the class changes
receipt.take_back()
```

`grant(asc, level_multiplier = 1.0)` publishes **everything or nothing**:

1. Attribute sets are registered first, because effects and abilities may read them. Attributes already on the owner keep their values - putting a kit on does not heal anybody.
2. Effects are applied, at `level_multiplier`.
3. Abilities are granted, at `entry.level × level_multiplier`.

If any step fails, everything already published is taken back and the receipt is empty.

The `GameplayAbilitySetHandles` receipt lists `ability_handles`, `effect_handles` and `attribute_set_handles`. `take_back()` retires everything in the exact reverse order it was published, continues past anything the game already removed, and does nothing the second time. A receipt only acts on the component it was granted to, so one set resource can be granted to every character in a game.

On a component attached to a network runtime, only the authority grants sets; a client call is refused with a warning.
