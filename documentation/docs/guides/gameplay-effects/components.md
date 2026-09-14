---
title: Components
sidebar_position: 5
description: The built-in effect components - tags, requirements, chance, immunity, cleansing, blocking, chained effects, granted abilities, UI data - and how to write your own.
---

# Components

Everything an effect does beyond changing numbers is a **component**: a small `Resource` in the effect's `components` array. A stun is an effect with a target-tags component; an antidote is an effect with a remove-other-effects component; a cursed ring is an infinite effect with a grant-abilities component.

Components are authoring data only. They never store per-application state, so one component resource can safely appear in many effects.

## Built-in components

| Component | What it does | One per effect? |
|---|---|---|
| `GameplayEffectTargetTagsComponent` | Grants tags to the target while the effect is active. | No |
| `GameplayEffectAssetTagsComponent` | Describes the effect with tags that queries match. Never granted. | No |
| `GameplayEffectTargetTagRequirementsComponent` | Tag requirements to apply, to stay active, and to be removed. | Yes |
| `GameplayEffectChanceToApplyComponent` | A random chance that the application proceeds. | No |
| `GameplayEffectCustomCanApplyComponent` | Delegates the can-apply decision to your own requirement resource. | No |
| `GameplayEffectImmunityComponent` | While active, refuses incoming effects that match a query. | Yes |
| `GameplayEffectRemoveOtherEffectsComponent` | On application, removes active effects that match a query. | Yes |
| `GameplayEffectBlockAbilityTagsComponent` | While active, blocks abilities whose tags match a query. | Yes |
| `GameplayEffectCancelAbilityTagsComponent` | On application, cancels running abilities whose tags match a query. | No |
| `GameplayEffectAdditionalEffectsComponent` | Applies other effects at lifecycle points. | Yes |
| `GameplayEffectGrantAbilitiesComponent` | Grants abilities while the effect is active. | No |
| `GameplayEffectUIDataComponent` | A display name, description and icon for your UI. | No |

"One per effect" components are read by the runtime as "the first one found". A second one would never be read, and the asset validator reports it.

### Target tags

```gdscript
var stunned: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
stunned.granted_tags = [&"State.Stunned"] as Array[StringName]
```

Tags are granted through the target's reference count, so a stun and a freeze that both grant `State.Incapacitated` hold it twice. `INSTANT` effects grant no tags - nothing remains to hold them.

### Asset tags

`asset_tags` say what an effect **is** - `Effect.Debuff.Poison`, `Effect.Magic` - so a query can find it: a cleanse removes everything tagged `Effect.Debuff`, an immunity refuses anything tagged `Effect.Magic`.

### Tag requirements

`GameplayEffectTargetTagRequirementsComponent` holds three tag queries, all evaluated against the target:

| Query | Effect |
|---|---|
| `application_query` | The target must match for the application to proceed. |
| `ongoing_query` | The active effect is inhibited whenever the target stops matching. See [Inhibition](duration-and-periodic-effects.md#inhibition). |
| `removal_query` | The active effect is removed as soon as the target matches. An application to a target that already matches is refused. |

A `null` or empty query imposes nothing.

### Chance to apply

```gdscript
var chance: GameplayEffectChanceToApplyComponent = GameplayEffectChanceToApplyComponent.new()
chance.chance = 0.25
```

`0.0` always refuses, `1.0` always allows. Each target of an area effect rolls independently.

### Custom can-apply

For a rule no other component expresses, subclass `GameplayEffectApplicationRequirement` and put it in a `GameplayEffectCustomCanApplyComponent`:

```gdscript
class_name BelowHalfHealthRequirement extends GameplayEffectApplicationRequirement


func can_apply(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	var target: AbilitySystemComponent = request.target_asc
	if target == null:
		return GameplayEffectComponentDecision.deny("no target")
	var ceiling: float = maxf(target.get_attribute_current(&"max_health"), 1.0)
	if target.get_attribute_current(&"health") / ceiling < 0.5:
		return GameplayEffectComponentDecision.allow()
	return GameplayEffectComponentDecision.deny("target is above half health")
```

The request carries `spec`, `target_asc`, `source_asc`, a shared `rng`, and `existing_active_effect` when the application is joining a stack. A requirement is a resource, so designers can reuse it across effects.

### Immunity

```gdscript
var poison_tags: GameplayTagQuery = GameplayTagQuery.new()
var expression: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(poison_tags)
GameplayTagQueryEdits.set_operator(expression, GameplayTagQueryExpression.Operator.ANY)
GameplayTagQueryEdits.add_tag(expression, &"Effect.Debuff.Poison")

var no_poison: GameplayEffectQuery = GameplayEffectQuery.new()
no_poison.asset_tags = poison_tags

var immunity: GameplayEffectImmunityComponent = GameplayEffectImmunityComponent.new()
immunity.incoming_effect_query = no_poison
```

While the effect carrying this component is active and uninhibited, any incoming application the query matches is refused with `IMMUNE` before anything happens. `AbilityTaskFactory.wait_effect_blocked_by_immunity()` lets an ability react when that occurs.

### Remove other effects

```gdscript
var cleanse: GameplayEffectRemoveOtherEffectsComponent = GameplayEffectRemoveOtherEffectsComponent.new()
cleanse.query = debuffs_query
```

On a successful application, every active effect matching the query is removed with the reason `CLEANSE`. The purge is part of the application's transaction: if the application is refused, nothing is removed.

### Block and cancel abilities

- `GameplayEffectBlockAbilityTagsComponent.query` - while the effect is active and uninhibited, abilities whose tags match cannot activate. They are refused with `BLOCKED_BY_ACTIVE_ABILITY`.
- `GameplayEffectCancelAbilityTagsComponent.query` - when the effect is applied, running abilities whose tags match are cancelled.

A silence is an effect that blocks `Ability.Spell`; an interrupt is an effect that cancels it.

### Additional effects

`GameplayEffectAdditionalEffectsComponent` applies more effects to the same target at four lifecycle points:

| List | When |
|---|---|
| `on_application` | After this effect's own application has committed. |
| `on_natural_expiration` | After it expires on its own. |
| `on_premature_removal` | After it is removed for any other gameplay reason. |
| `on_any_removal` | After either of the two above. |

Each entry is a `GameplayEffectConditionalEffect` with the `effect` to apply and two optional queries: `target_query` (checked on the target receiving the chained effect) and `source_query` (checked on the original application's source). A reset through `cleanup()` fires none of them.

Chains are bounded: an application more than 32 levels deep is refused with `CHAIN_DEPTH_EXCEEDED`.

### Granted abilities

```gdscript
var grant: GameplayEffectAbilityGrant = GameplayEffectAbilityGrant.new()
grant.ability_scene = preload("res://game/abilities/fire_slash.tscn")
grant.removal_policy = GameplayEffectAbilityGrant.RemovalPolicy.REMOVE_ON_ACTIVE_END

var grants: GameplayEffectGrantAbilitiesComponent = GameplayEffectGrantAbilitiesComponent.new()
grants.grants = [grant] as Array[GameplayEffectAbilityGrant]
```

Abilities are granted when the effect applies and retired according to each grant's `removal_policy`:

| `RemovalPolicy` | When the effect ends |
|---|---|
| `CANCEL_AND_REMOVE_ON_EFFECT_END` | A running activation is cancelled and the grant retired immediately. The default. |
| `REMOVE_ON_ACTIVE_END` | No new activations; the grant is retired once nothing is running. |
| `KEEP_AFTER_EFFECT_END` | The grant stays. |

A grant can also set its own `level` (a `GameplayScalableFloat` resolved against the effect's level) and `input_id`. A stack grants once per active effect, never once per stack.

### UI data

`GameplayEffectUIDataComponent` carries `display_name`, `description` and `icon` for a buff bar or tooltip. The runtime never reads it. Subclass it to add fields your UI needs.

## Writing your own component

Subclass `GameplayEffectComponent` and override only the hooks you need:

| Hook | Called | May change gameplay? |
|---|---|---|
| `allows_duplicates()` | By the editor and runtime. Return `false` if a second copy would never be read. | - |
| `validate_definition(owner_effect)` | Once per effect asset. | No |
| `can_apply(request)` | Before anything happens. Return `GameplayEffectComponentDecision.deny(reason)` to refuse. | No |
| `prepare_application(request)` | After every `can_apply()` passed, before commit. Return state to keep for this application. | No |
| `discard_prepared(state)` | When the application was refused after preparation. | No |
| `on_spec_created(request)` | When a spec is created from the effect. | No |
| `on_effect_applied(context)` | After the application committed. | Yes |
| `on_effect_executed(context)` | After each periodic tick committed. | Yes |
| `on_effect_removed(context)` | When the active effect is removed. | Yes |

Two rules keep effects atomic:

1. **No side effects before commit.** `can_apply()` and `prepare_application()` run while the application can still be refused. They must not add tags, apply or remove effects, write attributes, send events, play cues or grant abilities.
2. **No state on the component.** Per-application state is returned from `prepare_application()` as a `GameplayEffectComponentState` subclass (through `GameplayEffectComponentPreparationResult.ok(state)`) and handed back to the later hooks as `context.component_state`.

A component that writes a line to your game's combat log whenever its effect lands:

```gdscript
class_name CombatLogComponent extends GameplayEffectComponent

@export var line: String = ""


func on_effect_applied(context: GameplayEffectComponentRuntimeContext) -> void:
	var victim: Node = context.target_asc.get_effect_target()
	CombatLog.write("%s: %s" % [victim.name, line])
```

`CombatLog` stands for whatever logging your game already has.
