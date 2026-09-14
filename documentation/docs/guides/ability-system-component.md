---
title: The AbilitySystemComponent
sidebar_position: 1
description: Adding, finding and configuring the component every gameplay entity owns, and how time and turns reach it.
---

# The AbilitySystemComponent

The `AbilitySystemComponent` (ASC) is the node that owns everything gameplay knows about one entity: its attributes, active effects, tags, granted abilities and running tasks. Characters, turrets, destructible props and even a level's weather controller can each have one.

## Adding a component

### In code

```gdscript
func _ready() -> void:
	var asc: AbilitySystemComponent = AbilitySystemComponent.new()
	asc.name = "AbilitySystemComponent"
	asc.attribute_sets = [HeroAttributes.new()] as Array[AttributeSet]
	add_child(asc)
```

### In a scene

Add a child node of type **AbilitySystemComponent** to the character scene, name it `AbilitySystemComponent`, and fill **Attribute Sets** in the Inspector with your `AttributeSet` resources.

Either way, the component's parent becomes both its owner and its avatar when it enters the tree.

:::tip Name it `AbilitySystemComponent`
The name is not required - lookups resolve components by type - but it is checked first, so it is the fastest path and what every example uses.
:::

## Finding a component

`AbilitySystemLocator.find_for_node(node)` returns the component a node belongs to, or `null`. Inside an ability, `GameplayAbility.find_asc_on(node)` is the same search.

The search walks **outward** from the node:

1. If the node has a method `get_ability_system_component()` that returns a component, that answer wins.
2. The node itself, if it is a component.
3. A direct child named `AbilitySystemComponent`, then any direct child that is a component.
4. The same checks on the parent, then its parent, and so on.

It never searches descendants recursively. Hitting a character's sword must not reach the sword's own component, and a passenger inside a vehicle must not be found through the vehicle.

Implement `get_ability_system_component()` when the component lives somewhere else - on a player state node, or on the wearer of a piece of equipment:

```gdscript
func get_ability_system_component() -> AbilitySystemComponent:
	return owning_player.asc
```

## Owner, avatar and controller

| Role | Meaning | Default |
|---|---|---|
| Owner | Whoever the abilities belong to. | The component's parent. |
| Avatar | The body effects and cues act on; returned by `get_effect_target()`. | The owner. |
| Controller | Whoever issues the orders, if the game wants to record it. | `null` |

Separate them when a player's abilities act through something else - a possessed body, a mount, a vehicle:

```gdscript
player_asc.init_ability_actor_info(player, current_mount)
```

When the avatar changes, the component emits `ability_actor_info_changed(old_avatar, new_avatar)`, and every granted ability's `on_avatar_changed()` is called.

## Configuration

| Property | Default | Purpose |
|---|---|---|
| `attribute_sets` | `[]` | The attribute sets this entity starts with. See [Attributes](attributes.md). |
| `share_attributes` | `false` | `false` gives this component deep copies of the authored sets, so two characters built from one resource never share a pool. |
| `ability_tag_relationships` | `null` | A central table of which kinds of ability block, cancel or require which. See [Tag rules](abilities/tag-rules.md#the-tag-relationship-table). |
| `suppress_cues` | `false` | Play no cues on this component locally. |
| `suppress_ability_grants` | `false` | Refuse every ability grant, for a spectator or an entity being torn down. |
| `generic_confirm_input_id` | `-1` | The input slot that means "confirm" when nothing more specific is bound. |
| `generic_cancel_input_id` | `-1` | The input slot that means "cancel". |
| `compatibility_profile` | `GODOT_NATIVE` | Which attribute aggregation arithmetic this component uses. See [Aggregation profiles](attributes.md#aggregation-profiles). |

## Time and turns

The component advances every active effect and every running task from its own `_process(delta)`. Timed effects therefore pause when the component stops processing - for example when the scene tree is paused and the component's `process_mode` inherits that pause.

Turn-based games drive turn time explicitly. Nothing in the frame loop consumes turns:

```gdscript
func start_round() -> void:
	for character: Character in characters:
		character.asc.advance_turn()
```

`advance_turn(turns)` ages every `TURN_BASED` effect, which is what makes turn-counted buffs, debuffs and cooldowns expire. See [Duration and periodic effects](gameplay-effects/duration-and-periodic-effects.md#turn-based-effects).

## The API at a glance

The component's methods are grouped below. Each group is documented in its own guide.

### Attributes

| Method | Purpose |
|---|---|
| `get_attribute_base(name)` / `get_attribute_current(name)` | Read an attribute. |
| `get_attribute(name)` / `has_attribute(name)` | The `AttributeData`, or whether it exists. |
| `get_attribute_up_to_channel(name, channel)` | The value with only channels `0..channel` applied. |
| `set_attribute_base(name, value)` / `apply_attribute_base_delta(name, amount)` | Change a durable value directly. |
| `initialize_attribute_overrides(overrides)` | Replace several base values, keeping active contributions. |
| `register_attribute_set(set)` / `unregister_attribute_set(handle)` | Add or remove a set at runtime. |

### Effects

| Method | Purpose |
|---|---|
| `apply_gameplay_effect(effect, source_asc, level)` | Apply an effect to this component; returns the `ActiveGameplayEffect` or `null`. |
| `apply_gameplay_effect_result(...)` | The same, returning a `GameplayEffectApplicationResult`. |
| `apply_effect_spec_result(spec)` / `apply_effect_spec_to_target_result(spec, target)` | Apply a prepared spec here, or to another component. |
| `find_active_effects(query)` / `count_active_effects(query)` / `get_active_effects()` | Query what is running. |
| `remove_active_effect_by_handle(handle)` / `remove_active_effects(query)` | Remove running effects. |
| `set_active_effect_level` / `set_active_effect_stack_count` / `set_active_effect_duration` / `update_active_effect_set_by_caller` | Change a running effect. |
| `can_afford_cost(effect, level)` | Whether an effect used as a cost could be paid now. |

See [Gameplay effects](gameplay-effects/index.md).

### Tags

| Method | Purpose |
|---|---|
| `add_tag(tag)` / `remove_tag(tag)` / `set_tag_count(tag, count)` / `clear_tag(tag)` | Change loose tags. |
| `has_tag(tag)` / `has_tag_exact(tag)` / `has_any_tags(tags)` / `has_all_tags(tags)` | Check tags. |
| `get_tag_duration_remaining(tag)` / `get_tag_turns_remaining(tag)` | How long the effects granting a tag have left. |

See [Gameplay tags](gameplay-tags.md).

### Abilities and input

| Method | Purpose |
|---|---|
| `give_ability(scene, level, input_id, source)` / `give_ability_with_options(scene, options)` | Grant an ability. |
| `try_activate_ability_handle(handle, context)` | Activate a grant; returns a `GameplayAbilityActivationResult`. |
| `can_activate_ability_handle(handle)` | Whether it could activate now. |
| `remove_ability_handle(handle, policy)` / `clear_all_abilities()` | Take grants back. |
| `get_ability_spec(handle)` / `get_ability_specs()` / `find_ability_specs(query)` | Inspect grants. |
| `get_ability_cooldown_state(handle)` | What a UI needs to draw a cooldown. |
| `cancel_all_abilities()` / `cancel_abilities_matching(query)` | Cancel running abilities. |
| `block_abilities_with_query(query)` / `unblock_abilities_with_query(query)` | Block abilities from outside the ability system. |
| `ability_local_input_pressed(id)` / `ability_local_input_released(id)` | Route input by slot. |
| `ability_local_input_action_pressed(action)` / `..._released(action)` | Route input by InputMap action. |
| `input_confirm()` / `input_cancel()` | The generic confirm and cancel. |

See [Abilities](abilities/index.md) and [Activation and input](abilities/activation-and-input.md).

### Events and cues

| Method | Purpose |
|---|---|
| `send_gameplay_event(event)` | Deliver an event to tasks and triggered abilities. See [Gameplay events](gameplay-events.md). |
| `execute_cue(params)` / `activate_persistent_cue(params)` / `remove_all_gameplay_cues()` | Play cues on this entity. See [Gameplay cues](gameplay-cues.md). |

## Signals

| Group | Signals |
|---|---|
| Attributes | `attribute_changed(attribute_name, old_value, new_value, effect_spec)` |
| Tags | `tag_added`, `tag_removed`, `tag_count_changed`, `tag_or_child_count_changed`, `tag_or_child_presence_changed` |
| Effects | `active_effect_added`, `active_effect_removed`, `active_effect_refreshed`, `gameplay_effect_application_finished`, `effect_application_refused`, `gameplay_effect_executed`, `gameplay_effect_removal_finished`, `active_effect_time_changed`, `active_effect_stack_changed`, `active_effect_stack_overflowed`, `active_effect_inhibition_changed`, `effect_applied_to_target`, `effect_received` |
| Abilities | `ability_granted`, `ability_activated`, `ability_committed`, `ability_runtime_ended`, `ability_activation_failed`, `ability_activation_failed_with_tag`, `ability_spec_changed`, `ability_actor_info_changed` |
| Input, events, cues | `generic_confirmed`, `generic_cancelled`, `gameplay_event_received`, `cue_executed` |
| Safety | `live_magnitude_cycle_aborted`, `effect_requirement_cycle_aborted` |

Every signal fires only for a real change: `attribute_changed` never fires for a write that resolved to the same value, and `active_effect_stack_changed` never fires for an application that did not change the count.

## Resetting and tearing down

- `cleanup()` cancels every ability, removes every effect, retires every grant, clears tags and drops attribute contributions. The component stays usable - use it to reset an entity for reuse.
- `dispose()` is the terminal teardown. It runs automatically when the component is freed, and calling it twice is safe.
