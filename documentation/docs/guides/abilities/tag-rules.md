---
title: Tag Rules
sidebar_position: 4
description: Ability identity tags, activation requirements, blocking, cancellation, target and source rules, external blocks and the tag relationship table.
---

# Tag Rules

Most "can this ability run right now?" questions in a game are about tags: stunned characters cannot attack, a silenced mage cannot cast, starting a dash cancels a reload. GAS_Engine expresses all of them as declarations on the ability, so the engine - and every UI that asks it - gives the same answer.

All the queries on this page are `GameplayTagQuery` resources, edited in the Inspector with the tag query editor. See [Tag queries](../gameplay-tags.md#tag-queries).

## Identity: `ability_tags`

`ability_tags` say what an ability **is**: `Ability.Attack.Melee`, `Ability.Spell.Fire`, `Ability.Movement`. They grant nothing and gate nothing on their own. Other rules - block queries, cancel queries, relationship rows, blocking effects - match against them.

An ability's **effective tags** are its `ability_tags` plus the grant's `dynamic_tags` (on `GameplayAbilitySpec`), so one grant can carry extra identity at runtime.

## Requirements on the owner

| Field | The ability cannot start while… | Refusal |
|---|---|---|
| `activation_blocked_query` | the owner's tags match the query. | `BLOCKED_BY_TAGS` |
| `activation_required_query` | the owner's tags do **not** match the query. | `MISSING_REQUIRED_TAGS` |

A null or empty query imposes nothing.

## Tags held while running: `activation_owned_tags`

`activation_owned_tags` are added to the owner when the grant starts running and removed when it stops - once for the grant, however many `PER_EXECUTION` instances run. A charge that should make the character `State.Charging` for its duration declares it here instead of adding and removing a tag by hand.

## Cancelling other abilities: `cancel_abilities_query`

When this ability activates, every running ability whose effective tags match `cancel_abilities_query` is cancelled. Its own grant is excluded unless `allow_self_cancel` is on.

## Blocking other abilities: `block_abilities_query`

While this ability runs, a new activation of any ability whose effective tags match `block_abilities_query` is refused with `BLOCKED_BY_ACTIVE_ABILITY`.

## Target rules

| Field | Effect |
|---|---|
| `target_required_query` | A target whose tags do not match is skipped. |
| `target_blocked_query` | A target whose tags match is skipped. |

They are enforced by `apply_effect_to_targets()` through `accepts_target()`, which reads the frozen definition. A skipped target is reported in the result's `rejected_targets`. This is the right way to stop an ability from hitting a corpse:

```gdscript
func _init() -> void:
	var downed: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	downed.operator = GameplayTagQueryExpression.Operator.ANY
	downed.tags = [&"State.Downed"] as Array[StringName]
	target_blocked_query = GameplayTagQuery.new()
	target_blocked_query.root = downed
```

It is built in `_init()` because the definition is frozen when the ability is granted, before `_ready()`.

## Source rules

| Field | Effect |
|---|---|
| `source_required_query` | An event-triggered activation whose instigator's tags do not match is refused with `MISSING_REQUIRED_TAGS`. |
| `source_blocked_query` | An event-triggered activation whose instigator's tags match is refused with `BLOCKED_BY_TAGS`. |

They only apply to activations that arrive with a gameplay event, after every other gate has passed. They read the tags the instigator carried when the event was sent; an event with no instigator tags never passes a non-empty required query. See [Gameplay events](../gameplay-events.md).

## Effects that block and cancel

Effects apply the same rules from the outside:

- An active effect with `GameplayEffectBlockAbilityTagsComponent` blocks abilities whose tags match its query - a **silence**.
- An effect with `GameplayEffectCancelAbilityTagsComponent` cancels matching running abilities when it applies - an **interrupt**.

See [Components](../gameplay-effects/components.md#block-and-cancel-abilities).

## Blocks from game code

Cutscenes, menus and tutorials block abilities without an effect:

```gdscript
asc.block_abilities_with_query(everything_but_movement)
# … later
asc.unblock_abilities_with_query(everything_but_movement)
```

- Blocks are **counted**: two blocks and one unblock leave one block in place, so a cutscene ending does not lift a stun's block.
- Two queries that say the same thing are the same block, so the unblock does not need the resource the block was made with.
- A blocked activation is refused with `BLOCKED_EXTERNALLY`, and `is_ability_blocked(spec)` answers whether an outside block covers a grant.

## Cancelling from game code

| Method | Cancels | Asks `can_be_cancelled()` |
|---|---|---|
| `cancel_abilities_matching(query, excluding)` | Running abilities whose effective tags match, except the `excluding` spec. | Yes |
| `cancel_abilities_with_tags(tags)` | Running abilities carrying any of these tags. | Yes |
| `cancel_all_abilities(reason)` | Every running ability. | No |

Cancel queries on abilities and cancelling effects go through the same path as `cancel_abilities_matching()`, so an uninterruptible finisher can refuse them too.

## The tag relationship table

Rules that apply to **kinds** of abilities belong in one place rather than on every ability. `AbilitySystemComponent.ability_tag_relationships` takes a `GameplayAbilityTagRelationships` resource whose `relationships` rows each say:

| Row field | Meaning | Refusal |
|---|---|---|
| `ability_query` | Which abilities the row is about, matched against their effective tags. | - |
| `blocks_query` | While one of them runs, abilities matching this are refused. | `BLOCKED_BY_ACTIVE_ABILITY` |
| `cancels_query` | Starting one of them cancels abilities matching this. | - |
| `requires_query` | They cannot start unless the owner's tags match this. | `MISSING_REQUIRED_TAGS` |
| `blocked_by_query` | They cannot start while the owner's tags match this. | `BLOCKED_BY_TAGS` |

One row - `ability_query: Ability.Attack.Melee`, `blocked_by_query: State.Stunned` - covers every melee attack in the game, including the ones written next year.

The table only ever **adds** restrictions. It runs after an ability's own declarations and cannot make an ability activatable that its own rules refuse, and the order of the rows never changes the result.

## Order of evaluation

When several rules apply, the first failing gate decides the refusal. See [the gate order](index.md#2-activating).
