---
title: Attributes
sidebar_position: 2
description: Declaring attribute sets, base and current values, clamping hooks, meta attributes, aggregator policies and the two aggregation profiles.
---

# Attributes

An **attribute** is a number an entity has: health, mana, attack, move speed. Attributes are declared in an `AttributeSet`, owned by an `AbilitySystemComponent`, and changed by [gameplay effects](gameplay-effects/index.md).

## Declaring an attribute set

Subclass `AttributeSet` and export one `AttributeData` per attribute:

```gdscript
class_name CharacterAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const MANA: StringName = &"mana"
const MAX_MANA: StringName = &"max_mana"
const MOVE_SPEED: StringName = &"move_speed"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)
@export var mana: AttributeData = AttributeData.new(50.0)
@export var max_mana: AttributeData = AttributeData.new(50.0)
@export var move_speed: AttributeData = AttributeData.new(300.0)


func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	mana = AttributeData.new(50.0)
	max_mana = AttributeData.new(50.0)
	move_speed = AttributeData.new(300.0)
```

Every exported `AttributeData` property is an attribute, named after the property. There is nothing to register.

:::warning Create fresh instances in `_init()`
An exported default is evaluated once for the script. Without the `_init()` block, every set built in code shares the same `AttributeData` objects.
:::

The constants are optional but recommended: effects, costs, captures and UI code all refer to attributes by name, and a constant cannot be misspelled.

A set can also be saved as a `.tres` and edited in the Inspector, one resource per kind of character.

## Base and current

Every attribute holds two values:

| Value | Meaning | Written by |
|---|---|---|
| `base_value` | The durable value: what the entity is worth with no active effects. | Instant effects, periodic ticks, executions, `set_attribute_base()`. |
| `current_value` | The base with every active contribution folded in, then clamped. | The engine, and only the engine. |

A "+20 attack for 10 seconds" effect never touches `base_value`. It registers a **contribution** that is folded into `current_value` while the effect lives and withdrawn when it ends, so buffs that expire in any order always land on the right number.

:::danger Never write `current_value`
It is derived. Anything written there is overwritten at the next recomposition.
:::

## Giving attributes to a component

Assign sets to the component's `attribute_sets`, in the Inspector or in code before the component is ready:

```gdscript
var asc: AbilitySystemComponent = AbilitySystemComponent.new()
asc.attribute_sets = [preload("res://game/characters/wolf_attributes.tres")] as Array[AttributeSet]
add_child(asc)
```

By default the component works on **deep copies** (`share_attributes = false`). Ten wolves built from one `wolf_attributes.tres` have ten health pools, and the resource on disk is never modified. Set `share_attributes` to `true` only when several components must genuinely read and write one set.

When the component adopts its sets, each current value is seeded from its base. No `attribute_changed` is emitted for this.

### Adding and removing sets at runtime

```gdscript
var mount: RegisteredAttributeSetHandle = asc.register_attribute_set(MountAttributes.new())
# … later
asc.unregister_attribute_set(mount)
```

`register_attribute_set()` seeds only the attributes of the new set; the attributes already on the component keep their values and contributions. Loadouts use it for exactly that reason. See [Granting and loadouts](abilities/granting-and-loadouts.md#ability-sets).

## Reading attributes

| Method | Returns |
|---|---|
| `get_attribute_current(name)` | The current value, or `0.0` when no set declares it. |
| `get_attribute_base(name)` | The base value, or `0.0`. |
| `has_attribute(name)` | Whether any set declares it. |
| `get_attribute(name)` | The `AttributeData` itself, for read-only use. |
| `get_attribute_up_to_channel(name, channel)` | The value with only channels `0..channel` applied (channel-folded profile). |

To follow changes, connect to `attribute_changed`:

```gdscript
asc.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(
	attribute_name: StringName, _old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	if attribute_name == CharacterAttributes.HEALTH:
		health_bar.value = new_value
```

It fires whenever a **current** value actually changes, with the spec that caused it, or `null` for a direct write.

## Writing attributes

Gameplay changes should go through effects, so they can be predicted, stacked, blocked and inspected. For the cases that are not gameplay - loading a save, a level-up screen, an editor tool - write the base directly:

| Method | Purpose |
|---|---|
| `set_attribute_base(name, value, source_spec = null)` | Replace the base. |
| `apply_attribute_base_delta(name, amount, source_spec = null)` | Add to the base. |
| `initialize_attribute_overrides({name: value})` | Replace several bases, keeping active contributions. A ×2 buff over base 10 shows 20; initializing the base to 50 shows 100. |

Both single writes return an `AttributeMutationResult`:

| Field | Meaning |
|---|---|
| `status` | `OK`, or why nothing was written (`ATTRIBUTE_NOT_FOUND`, `NON_FINITE_VALUE`, …). |
| `old_base_value`, `requested_base_value`, `new_base_value` | The base before, asked for, and stored. |
| `old_current_value`, `new_current_value` | The current value before and after. |
| `base_changed`, `current_changed` | Whether each actually moved. |
| `was_clamped` | Whether the base clamp changed what was requested. |

## Clamping

Three hooks on the set keep values legal:

| Hook | Called | Use it to |
|---|---|---|
| `pre_attribute_base_change(name, proposed) -> float` | Before a base value is stored. | Clamp the durable value. |
| `pre_attribute_change(name, proposed) -> float` | Before a current value is stored, after contributions are folded in. | Clamp the derived value. |
| `post_attribute_change(asc, name, old_value, new_value)` | After a current value changed. | React to dependent attributes. |

Clamp at **both** boundaries. With only the current clamp, 500 damage against 100 health leaves the base at -400 while the current value shows 0, and a later heal of 30 still shows 0.

```gdscript
func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func _bounded(attribute_name: StringName, value: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(value, 0.0, max_health.current_value)
		MANA:
			return clampf(value, 0.0, max_mana.current_value)
		_:
			return maxf(value, 0.0)
```

When a maximum drops - a "+50 max health" buff expiring - the current clamp hides the overflow, but the pool's base still holds it. Pull the base down in `post_attribute_change`:

```gdscript
func post_attribute_change(asc: Node, attribute_name: StringName, _old_value: float, new_value: float) -> void:
	var pool: StringName = _pool_under(attribute_name)
	var component: AbilitySystemComponent = asc as AbilitySystemComponent
	if pool == &"" or component == null:
		return
	if component.get_attribute_base(pool) > new_value:
		component.set_attribute_base(pool, new_value)


func _pool_under(ceiling: StringName) -> StringName:
	match ceiling:
		MAX_HEALTH:
			return HEALTH
		MAX_MANA:
			return MANA
		_:
			return &""
```

Two more hooks, `pre_gameplay_effect_execute` and `post_gameplay_effect_execute`, wrap every base write an effect performs. See [Execute hooks on the attribute set](gameplay-effects/executions-and-context.md#execute-hooks-on-the-attribute-set).

## Meta attributes

A **meta attribute** is a message rather than a store. Damage is the classic case: an effect writes 40 into `incoming_damage`, the set decides what that means - armor, shields, a death event - and the number is gone.

```gdscript
const INCOMING_DAMAGE: StringName = &"incoming_damage"

@export var incoming_damage: AttributeData = AttributeData.new(0.0)


func _init() -> void:
	# … the other attributes
	incoming_damage = AttributeData.new(0.0)
	incoming_damage.is_meta = true


func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
	if data.attribute_name != INCOMING_DAMAGE:
		return
	var taken: float = maxf(data.committed_base - armor.current_value, 0.0)
	data.target_asc.apply_attribute_base_delta(HEALTH, -taken, data.spec)
```

The engine enforces both rules of a meta attribute:

- It is returned to zero right after `post_gameplay_effect_execute` has read it.
- A `DURATION` or `INFINITE` effect may not contribute to it; such an application is refused with `META_ATTRIBUTE_CANNOT_PERSIST`.

## Aggregator policies

By default every contribution counts. Override `aggregator_policy()` to change that per attribute:

```gdscript
func aggregator_policy(attribute_name: StringName) -> AttributeSet.AggregatorPolicy:
	if attribute_name == MOVE_SPEED:
		return AttributeSet.AggregatorPolicy.MOST_NEGATIVE
	return AttributeSet.AggregatorPolicy.ALL
```

| Policy | Which contributions count |
|---|---|
| `ALL` | Every one. The default. |
| `MOST_NEGATIVE` | For each operation, only the contribution that leaves the value lowest. |
| `MOST_POSITIVE` | For each operation, only the contribution that leaves the value highest. |

With `MOST_NEGATIVE` on move speed, a character standing in four slowing puddles is slowed by the strongest one, not by all four. The selection is made separately for each operation (all `ADD`s compete with each other, all `MULTIPLY`s with each other) and, under the channel-folded profile, separately for each channel. Overrides are never filtered.

:::info Buffs compete too
Under `MOST_NEGATIVE`, a +20 `ADD` haste and a -50 `ADD` slow are the same operation, so only the slow counts while both are active.
:::

## Referring to an attribute

Attributes are referred to by name, as a `StringName`, or by a `GameplayAttributeRef`, which names an attribute together with its set:

| Field | Meaning |
|---|---|
| `set_name` | The set's `class_name`, or its `resource_name` when one is given. Optional. |
| `attribute_name` | The attribute. |

References are what the attribute picker in the Inspector writes. These fields take only a reference:

- `GameplayCueBinding.magnitude_attribute`
- `GameplayExecutionOutput.Modifier.attribute`
- `GameplayExecutionScopedModifier.attribute`

These take either, side by side - fill in one of them:

| Resource | Reference | Name |
|---|---|---|
| `GameplayEffectModifier` | `attribute` | `attribute_name` |
| `GameplayAttributeCaptureDefinition` | `attribute` | `attribute_name` |
| `GameplayAbilityCost` | `target`, `reference` | `target_attribute`, `reference_attribute` |

When both are filled in, the reference wins; the name is read only while the reference is empty.

**Give every attribute on one entity a unique name.** When two sets on the same component both declare `health`:

- an effect that writes `health` is refused with `AMBIGUOUS_ATTRIBUTE_WRITE` rather than guessing which set was meant. Writes are addressed by name, even when a reference names the set;
- a capture, or a cost's percentage `reference`, reads the set its reference names; one that names no set is refused as not found;
- a bare read such as `get_attribute_current(&"health")` answers from the first set that declares it.

## Aggregation profiles

How contributions are folded into a current value is decided by the component's `compatibility_profile`, a `GameplayCompatibilityProfile` resource:

```gdscript
var profile: GameplayCompatibilityProfile = GameplayCompatibilityProfile.new()
profile.mode = GameplayCompatibilityProfile.Mode.CHANNEL_FOLDED
asc.compatibility_profile = profile
```

| | `GODOT_NATIVE` (default) | `CHANNEL_FOLDED` |
|---|---|---|
| Arithmetic | One pass: `((base + ΣADD) × ΠMULTIPLY) / ΠDIVIDE`. | Ten channels, each folding over the previous one. |
| Operations | `ADD`, `MULTIPLY`, `DIVIDE`, `OVERRIDE`. | All eight; `MULTIPLY` and `DIVIDE` behave as their additive forms. |
| Winning override | The most recently applied. | The first applied. |
| Two `×1.5` multipliers | `×2.25` | `×2.0` with `MULTIPLY_ADDITIVE`, `×2.25` with `MULTIPLY_COMPOUND`. |
| Execution outputs on a stacked effect | Not scaled by the stack count. | Multiplied by the stack count unless the execution handles stacks itself. |
| Cost affordability | The charge must not take the base below zero or be altered by the clamp. | The charge must fit in the current value. |

The full formulas and every operation are on [Modifiers and magnitudes](gameplay-effects/modifiers-and-magnitudes.md#operations).

Choose one profile per project and keep it: the same effect composes to different numbers under the two. The asset validator warns when an effect uses `MULTIPLY` or `DIVIDE`, or stacks without setting `factor_in_stack_count`, under `CHANNEL_FOLDED`.
