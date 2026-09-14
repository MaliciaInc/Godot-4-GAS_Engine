---
title: Gameplay Tags
sidebar_position: 5
description: Declaring hierarchical tags, holding them on a component, listening to tag changes, tag queries, tagged scenery, renames and restricted branches.
---

# Gameplay Tags

A **gameplay tag** is a hierarchical name: `State.Debuff.Stunned`, `Ability.Attack.Melee`, `Cue.Hit.Fire`. Tags are how GAS_Engine says what something **is** and what state it is **in**. Abilities, effects, cooldowns, events, cues and targeting all speak in tags.

## Declaring tags

A tag is one or more segments separated by dots. Each segment starts with an uppercase letter and contains only letters and digits.

| Legal | Not legal |
|---|---|
| `State.Stunned` | `state.stunned` (lowercase start) |
| `Ability.Fireball2` | `Ability..Fireball` (empty segment) |
| `Cue.Hit.CriticalFire` | `Cue.Hit-Fire` (hyphen) |

Declare tags with the tag editor in the Inspector (see [Tag picker](../getting-started/editor-tools.md#tag-picker)) or by hand in `res://gas_engine/gameplay_tags.gd`. Adding a tag through the editor capitalises the first letter of each segment, refuses a tag that already exists, and refuses a tag under a restricted branch.

Each declared tag becomes a constant of the `GameplayTags` class, with dots replaced by underscores:

```gdscript
if asc.has_tag(GameplayTags.State_Debuff_Stunned):
	return
```

:::tip Declare every tag you use
Tags are `StringName`s, and the runtime accepts any of them. Declaring a tag is what gives you the constant, the picker and one list of every tag in the project; a misspelled literal is simply a different tag that nothing holds.
:::

## Hierarchy

A tag is held **under** each of its ancestors. The separator is part of the rule.

| The component holds | `has_tag(&"State.Debuff")` | `has_tag_exact(&"State.Debuff")` |
|---|---|---|
| `State.Debuff.Stunned` | `true` | `false` |
| `State.Debuff` | `true` | `true` |
| `State.DebuffImmune` | `false` | `false` |

Queries, event triggers, event listeners and cue resolution all use this same rule.

## Tags on a component

A component's tags are **reference counted**. `State.Stunned` granted by two effects is held twice; removing one effect leaves it held once.

Tags reach a component from:

- effects with a `GameplayEffectTargetTagsComponent`, for as long as the effect is active - see [Components](gameplay-effects/components.md#target-tags);
- running abilities' `activation_owned_tags` - see [Tag rules](abilities/tag-rules.md#tags-held-while-running-activation_owned_tags);
- game code.

| Method | Purpose |
|---|---|
| `add_tag(tag)` / `remove_tag(tag)` | Add or remove one reference. |
| `set_tag_count(tag, count)` | Add or remove references until the exact count is `count`. |
| `clear_tag(tag)` | Drop the tag whatever its count. |
| `has_tag(tag)` / `has_tag_exact(tag)` | Hierarchical or exact presence. |
| `has_any_tags(tags)` / `has_all_tags(tags)` | Hierarchical; an empty array is `false` for any and `true` for all. |
| `get_tag_duration_remaining(tag)` | Seconds left on the effects granting it, or `INF` when one has no end. |
| `get_tag_turns_remaining(tag)` | The same in turns. |
| `tags.count_exact(tag)` / `tags.count(tag)` | How many references to the tag, or to the tag and everything under it. |
| `tags.active_tags()` | Every tag held. |

:::warning Tags added by game code are yours to remove
Nothing else removes a tag that `add_tag()` put on a component. Prefer an effect with a target-tags component when the tag has a duration or a cause.
:::

### Listening to tag changes

| Signal | Fires when |
|---|---|
| `tag_added(tag)` | A tag goes from not held to held. |
| `tag_removed(tag)` | A tag goes from held to not held. |
| `tag_count_changed(tag, new_count)` | A tag's exact count changes. |
| `tag_or_child_count_changed(tag, new_count)` | The count of a tag **or anything under it** changes. Emitted for the tag and every ancestor. |
| `tag_or_child_presence_changed(tag, present)` | A tag and everything under it goes from none held to some held, or back. Emitted for the tag and every ancestor, only when that crossing happens. |

A status bar that shows a debuff icon while *any* debuff is present listens to the hierarchy:

```gdscript
asc.tag_or_child_presence_changed.connect(_on_tag_presence_changed)


func _on_tag_presence_changed(tag: StringName, present: bool) -> void:
	if tag == GameplayTags.State_Debuff:
		debuff_icon.visible = present
```

Adding `State.Debuff.Rooted` beside an existing `State.Debuff.Stunned` does not fire the presence signal for `State.Debuff` again.

## Tag queries

A `GameplayTagQuery` is a boolean sentence about tags - "burning or poisoned, and not immune". Abilities, effects, relationship rows, triggers and targeting steps all take queries.

A query has one `root` expression. A `GameplayTagQueryExpression` has an `operator` and a list of **conditions**: each tag in `tags` (held, hierarchically) and each nested expression in `expressions`.

| Operator | True when |
|---|---|
| `ALL` | Every condition holds. With no conditions: `true`. |
| `ANY` | At least one condition holds. With no conditions: `false`. |
| `NONE` | No condition holds. With no conditions: `true`. |

A query with no root is **empty** and matches everything; every gate on the engine treats an empty query as "no requirement".

```gdscript
var afflicted: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
afflicted.operator = GameplayTagQueryExpression.Operator.ANY
afflicted.tags = [&"Status.Burning", &"Status.Poisoned"] as Array[StringName]

var not_immune: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
not_immune.operator = GameplayTagQueryExpression.Operator.NONE
not_immune.tags = [&"Status.Immune"] as Array[StringName]

var root: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
root.operator = GameplayTagQueryExpression.Operator.ALL
root.expressions = [afflicted, not_immune] as Array[GameplayTagQueryExpression]

var vulnerable: GameplayTagQuery = GameplayTagQuery.new()
vulnerable.root = root
```

For a flat query, `GameplayTagQueryEdits` is shorter:

```gdscript
var stunned: GameplayTagQuery = GameplayTagQuery.new()
var any_of: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(stunned)
GameplayTagQueryEdits.set_operator(any_of, GameplayTagQueryExpression.Operator.ANY)
GameplayTagQueryEdits.add_tag(any_of, &"State.Stunned")
```

| Method | Evaluates against |
|---|---|
| `matches_runtime(asc.tags)` | A component's live tags. |
| `matches_tags(tags)` | Any array of tags. |
| `matches_node(node)` | A node's component tags and its own [owned tags](#tags-on-things-that-are-not-characters), together. |
| `validate()` | Nothing - checks the definition: `OK`, `EMPTY_TAG`, `INVALID_TAG` or `CYCLIC_EXPRESSION`. |

In the Inspector every `GameplayTagQuery` property is edited as a tree. See [Tag query editor](../getting-started/editor-tools.md#tag-query-editor).

## Tags on things that are not characters

A door that is `Locked` or cover that is `Cover.Low` needs tags but not an ability system. Any node can answer for itself by implementing `get_owned_gameplay_tags()`:

```gdscript
extends StaticBody3D

@export var locked: bool = true


func get_owned_gameplay_tags() -> Array[StringName]:
	return [&"Door.Locked"] as Array[StringName] if locked else [] as Array[StringName]
```

`GameplayTagQuery.matches_node()` and targeting filters read these tags together with the node's component tags, when it has one.

## Renaming tags

Renaming a tag that shipped would break every asset naming the old one. Add a redirect instead:

```gdscript
const REDIRECTS: Dictionary[StringName, StringName] = {
	&"Status.OnFire": &"Status.Burning",
}
```

Every tag entering or leaving a component is resolved through the redirects, so an asset that still says `Status.OnFire` grants `Status.Burning` and a query for the old name finds the new one. Assets are never rewritten on load. The engine prints the rename once per run per old tag. Chains of renames are followed up to 64 steps; a cycle is reported and the tag is used as written.

## Restricted branches

A plugin or another team can own a branch of the hierarchy:

```gdscript
const RESTRICTED: Dictionary[StringName, StringName] = {
	&"Vendor": &"Vendor Plugin Team",
}
```

Adding `Vendor.Ability.Sprint` through the editor is refused with the owner named. The longest matching prefix decides the owner, and the boundary is a whole segment: `Vendor` owns `Vendor.Ability` but not `Vendors.Ability`.

`COMMENTS` holds a note per tag, for people reading the file.
