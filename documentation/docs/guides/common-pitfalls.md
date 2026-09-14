---
title: Common Pitfalls
sidebar_position: 14
description: The mistakes that most often make an ability free, an effect silent, a wait endless or a cooldown permanent - each with its cause and fix.
---

# Common Pitfalls

Each entry is a symptom, why it happens, and what to do instead.

## Abilities

### An ability costs nothing, or ignores its tag rules

**Cause:** costs, cooldowns, tag queries, policies or triggers were set in `_ready()`. The definition is frozen when the ability is granted, before `_ready()` runs.

**Fix:** set them in the scene, in `_init()`, or in a property setter. See [Configure rules before `_ready()`](abilities/index.md#1-granting).

### Granting does nothing

**Cause:** `give_ability()` was called before the component entered the scene tree; its runtimes are wired in its `_ready()`.

**Fix:** `add_child(asc)` first, then grant.

### An `ON_GRANTED` ability never ran

**Cause:** it was refused at grant - on cooldown, blocked, unaffordable - and `ON_GRANTED` tries only once.

**Fix:** use `PASSIVE` for an ability that should start whenever it can, or activate it yourself later.

### A passive ability keeps restarting

**Cause:** `auto_end_on_activate_return` is on, so it ends when `_activate_ability()` returns and is started again.

**Fix:** set it to `false` for a passive that should stay on.

### The ability node is treated as the character

**Cause:** the ability is a child of the component, not of the character.

**Fix:** use `owner_asc.get_effect_target()` for the avatar.

## Waiting

### An ability stops at an `await` and never continues

**Cause:** `await task.finished` on a task that ended while it started - a threshold already crossed, an animation that does not exist.

**Fix:** `await task.completed()`. See [Ability tasks](abilities/ability-tasks.md#using-a-task).

### A wait does not wait

**Cause:** `await wait_delay(1.0)` awaits the task object, not its completion.

**Fix:** `await wait_delay(1.0).completed()`.

### Waiting for an ability to end hangs

**Cause:** `await instance.ability_ended` after an activation that was refused or had already finished.

**Fix:** `await instance.completed()`.

### A cancelled ability still lands its hit

**Cause:** the ability waited on a `SceneTreeTimer` or a tween, which knows nothing about the ability ending.

**Fix:** wait with `wait_delay()` or another task, and check `is_active` after any other `await`.

## Attributes

### Every character shares one health pool

**Cause:** the attribute set's `AttributeData` objects were created only in `@export` defaults, which are evaluated once per script.

**Fix:** create them again in `_init()`. See [Declaring an attribute set](attributes.md#declaring-an-attribute-set).

### A full heal after an overkill hit still shows zero health

**Cause:** only the current value is clamped, so the base went negative.

**Fix:** clamp in `pre_attribute_base_change` as well as `pre_attribute_change`. See [Clamping](attributes.md#clamping).

### A value written to `current_value` disappears

**Cause:** the current value is recomposed from the base and contributions.

**Fix:** apply an effect, or use `set_attribute_base()`.

### A capture or a percentage cost is refused as not found

**Cause:** two attribute sets on the component declare that attribute, and the reference does not say which set it means.

**Fix:** set `set_name` on the reference, or give every attribute on one entity a unique name. See [Referring to an attribute](attributes.md#referring-to-an-attribute).

### An effect is refused with `AMBIGUOUS_ATTRIBUTE_WRITE`

**Cause:** two attribute sets on the component declare an attribute with the same name.

**Fix:** give every attribute on one entity a unique name.

### A buff has no effect while a debuff is active

**Cause:** the attribute's aggregator policy is `MOST_NEGATIVE`, which keeps one contribution per operation.

**Fix:** use a different operation for the buff, or `ALL`. See [Aggregator policies](attributes.md#aggregator-policies).

## Effects and cooldowns

### A turn-based effect or cooldown never ends

**Cause:** turns only pass when the game calls `advance_turn()`.

**Fix:** call it on every component at the end of each turn or round.

### Commit fails with `INVALID_COOLDOWN_DEFINITION`

**Cause:** the cooldown effect has modifiers, grants no tag, has other components, is `INFINITE`, or has no duration.

**Fix:** a `DURATION` or `TURN_BASED` effect with only a target-tags component. See [Cooldowns](abilities/costs-and-cooldowns.md#cooldowns).

### A scaled magnitude is stuck at a small value

**Cause:** a new Godot `Curve` clamps both axes to `0`-`1`.

**Fix:** widen its domain and value range.

### A `DURATION` effect on a damage attribute is refused

**Cause:** the attribute is a meta attribute, which cannot hold a lasting contribution.

**Fix:** use an `INSTANT` or periodic effect. See [Meta attributes](attributes.md#meta-attributes).

### The same effect gives different numbers in two projects

**Cause:** the components use different aggregation profiles.

**Fix:** pick one profile for the project. See [Aggregation profiles](attributes.md#aggregation-profiles).

## Tags and events

### A tag added by game code never goes away

**Cause:** nothing removes a loose tag except the code that added it.

**Fix:** remove it yourself, or grant it with an effect that has a duration.

### A tag or event is ignored

**Cause:** a misspelled tag is simply a different tag. The runtime accepts any tag.

**Fix:** use the `GameplayTags` constants, and declare every tag.

### An event does not start an ability that has a matching trigger

**Cause:** `GAMEPLAY_EVENT` triggers are only heard by abilities whose policy is `ON_GAMEPLAY_EVENT`.

**Fix:** set the activation policy.

## Input

### Pressing a key does nothing

**Cause:** GAS_Engine does not read Godot's input.

**Fix:** forward presses and releases with `ability_local_input_pressed()` or `ability_local_input_action_pressed()`. See [Input](abilities/activation-and-input.md#input).

## Cues

### No cue ever plays

**Cause:** the `GameplayCueManager` autoload is missing, cues are suppressed, or nothing is bound to the tag or its parents.

**Fix:** check the autoload, `suppress_cues` and `resolve_cue_tag()`. See [Gameplay cues](gameplay-cues.md).

### A cue shows the previous playback's state

**Cause:** cue scenes are pooled and reused.

**Fix:** reset state at the start of `executed()` or `on_active()`.

## Project

### Cues or tags are missing in an exported build

**Cause:** the export uses **Selected scenes and dependencies**.

**Fix:** add the include filter. See [Exporting](configuration-and-export.md#exporting).

### A feature silently does nothing after updating the engine

**Cause:** the project registries were written by the older engine and lack a newer declaration.

**Fix:** re-render them. See [Updating GAS_Engine](../getting-started/installation.md#updating-gas_engine).

## Ability Composer

### An ability opens read-only

**Cause:** its script has no `_activate_ability()` of its own.

**Fix:** open the script that declares it. See [Abilities with no body of their own](ability-composer/what-the-composer-can-draw.md#abilities-with-no-body-of-their-own).

### Part of an ability cannot be edited in the Composer

**Cause:** it is a kept region - a loop, an inline function, a local without a written type.

**Fix:** write the type, or move the region into a helper method. See [Kept regions](ability-composer/what-the-composer-can-draw.md#kept-regions).
