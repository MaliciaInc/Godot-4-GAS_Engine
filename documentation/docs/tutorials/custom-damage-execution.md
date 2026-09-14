---
title: A Custom Damage Execution
sidebar_position: 4
description: Build a damage pipeline with an execution calculation, a meta attribute, shields, armor piercing, critical hits against exposed targets, and a death event.
---

# A Custom Damage Execution

Modifiers cover "add 20". Real damage is a formula: the attacker's attack, the defender's armor, a shield that absorbs first, a critical against an exposed target, and a death event when health runs out. This tutorial builds that pipeline with an [execution calculation](../guides/gameplay-effects/executions-and-context.md) and a [meta attribute](../guides/attributes.md#meta-attributes).

```text
ability ──► Strike effect ──► StrikeDamageExecution ──► incoming_damage (meta)
                                                              │
                                   CombatAttributes.post_gameplay_effect_execute
                                                              │
                                              shield ──► health ──► Event.Death
```

## Step 1: The attribute set

```gdscript
class_name CombatAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const SHIELD: StringName = &"shield"
const ATTACK: StringName = &"attack"
const ARMOR: StringName = &"armor"
const INCOMING_DAMAGE: StringName = &"incoming_damage"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)
@export var shield: AttributeData = AttributeData.new(0.0)
@export var attack: AttributeData = AttributeData.new(10.0)
@export var armor: AttributeData = AttributeData.new(0.0)
@export var incoming_damage: AttributeData = AttributeData.new(0.0)


func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	shield = AttributeData.new(0.0)
	attack = AttributeData.new(10.0)
	armor = AttributeData.new(0.0)
	incoming_damage = AttributeData.new(0.0)
	incoming_damage.is_meta = true


func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func _bounded(attribute_name: StringName, value: float) -> float:
	if attribute_name == HEALTH:
		return clampf(value, 0.0, max_health.current_value)
	return maxf(value, 0.0)
```

`incoming_damage` holds nothing between hits: the engine returns it to zero after the set has read it, and refuses any lasting effect on it.

## Step 2: The execution

The execution reads three things and decides one number:

| Reads | From | When |
|---|---|---|
| `attack` | The attacker | `SNAPSHOT` - as strong as the attacker was when the effect was made. |
| `armor` | The defender | `LIVE` - the armor the defender has at the moment of the hit. |
| `Status.Exposed` | The defender's tags | At the moment of the hit. |

```gdscript
class_name StrikeDamageExecution extends GameplayExecutionCalculation

## Multiplies the attacker's attack.
@export var power: float = 1.0
## The fraction of armor ignored, from 0 to 1.
@export_range(0.0, 1.0) var armor_pierce: float = 0.0
## Multiplies damage against an exposed defender.
@export var critical_multiplier: float = 2.0

const EXPOSED: StringName = &"Status.Exposed"
const CRITICAL: StringName = &"Hit.Critical"

var _attack: GameplayAttributeCaptureDefinition = null
var _armor: GameplayAttributeCaptureDefinition = null


func _init() -> void:
	_attack = GameplayAttributeCaptureDefinition.new()
	_attack.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
	_attack.attribute_name = CombatAttributes.ATTACK
	_attack.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

	_armor = GameplayAttributeCaptureDefinition.new()
	_armor.actor = GameplayAttributeCaptureDefinition.Actor.TARGET
	_armor.attribute_name = CombatAttributes.ARMOR
	_armor.policy = GameplayAttributeCaptureDefinition.Policy.LIVE


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return [_attack, _armor] as Array[GameplayAttributeCaptureDefinition]


func declared_output_attributes() -> Array[StringName]:
	return [CombatAttributes.INCOMING_DAMAGE] as Array[StringName]


func execute_typed(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayExecutionOutput:
	var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
	var attack: AttributeCaptureResult = spec.resolve_capture(_attack, spec.source_asc, target_asc)
	var armor: AttributeCaptureResult = spec.resolve_capture(_armor, spec.source_asc, target_asc)
	if not attack.is_ok() or not armor.is_ok():
		return output

	var effective_armor: float = armor.value * (1.0 - armor_pierce)
	var damage: float = maxf(attack.value * power - effective_armor, 1.0)

	if target_asc.has_tag(EXPOSED):
		damage *= critical_multiplier
		spec.inject_tag(CRITICAL)

	output.modifiers.append(GameplayExecutionOutput.adding(CombatAttributes.INCOMING_DAMAGE, damage))
	return output
```

The execution **reads** and **returns**; it never writes an attribute, adds a tag to a component or applies an effect. Marking the hit with `spec.inject_tag()` describes this application only.

## Step 3: Turn damage into shield and health loss

The attribute set decides what incoming damage means, after the whole application has committed:

```gdscript
func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
	if data.attribute_name != INCOMING_DAMAGE:
		return
	var target: AbilitySystemComponent = data.target_asc
	var damage: float = data.committed_base

	var absorbed: float = minf(damage, target.get_attribute_base(SHIELD))
	if absorbed > 0.0:
		target.apply_attribute_base_delta(SHIELD, -absorbed, data.spec)

	var health_before: float = target.get_attribute_base(HEALTH)
	target.apply_attribute_base_delta(HEALTH, -(damage - absorbed), data.spec)

	if health_before > 0.0 and target.get_attribute_base(HEALTH) <= 0.0:
		var died: GameplayEventData = GameplayEventData.new()
		died.event_tag = &"Event.Death"
		died.target = target.get_effect_target()
		target.send_gameplay_event(died)
```

`committed_base` is the amount this hit wrote into the meta attribute. The event fires only on the hit that crosses zero.

## Step 4: The effect

```gdscript
class_name CombatEffects extends RefCounted


static func strike(power: float, armor_pierce: float) -> GameplayEffect:
	var execution: StrikeDamageExecution = StrikeDamageExecution.new()
	execution.power = power
	execution.armor_pierce = armor_pierce

	var impact: GameplayCueBinding = GameplayCueBinding.new()
	impact.cue_tag = &"Cue.Hit"

	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "Strike"
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.executions = [execution] as Array[GameplayExecutionCalculation]
	effect.cues = [impact] as Array[GameplayCueBinding]
	return effect
```

## Step 5: The ability

```gdscript
extends GameplayAbility

@export var power: float = 1.5
@export_range(0.0, 1.0) var armor_pierce: float = 0.25


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false
	var aim: GameplayAbilityTargetData = get_activation_target_data()
	if aim == null or not aim.has_targets():
		return false
	apply_effect_to_targets(CombatEffects.strike(power, armor_pierce), aim)
	return true
```

## Step 6: Check the numbers

With an attacker at `attack = 20` and a defender at `armor = 8`, `shield = 10`, `health = 100`:

| | Normal | Defender has `Status.Exposed` |
|---|---|---|
| Attack × power | 20 × 1.5 = 30 | 30 |
| Armor after 25% pierce | 8 × 0.75 = 6 | 6 |
| Damage | 30 − 6 = 24 | 24 × 2 = 48 |
| Absorbed by shield | 10 | 10 |
| Health afterwards | 100 − 14 = **86** | 100 − 38 = **62** |

Write these as tests - see [Testing your gameplay](testing-your-gameplay.md).

## Step 7: React to criticals and deaths

Tags injected into a spec are sent as gameplay events to the component that received the effect, so a floating-text UI can listen for criticals:

```gdscript
target_asc.gameplay_event_received.connect(_on_gameplay_event)


func _on_gameplay_event(event: GameplayEventData) -> void:
	match event.event_tag:
		&"Hit.Critical":
			show_floating_text("CRITICAL!")
		&"Event.Death":
			play_death()
```

An ability can react instead, with a trigger on `Event.Death`. See [Gameplay events](../guides/gameplay-events.md).

## Going further

- **Scoped modifiers** adjust what one execution reads without buffing anyone: "against armor as if 20% stronger". See [Scoped modifiers](../guides/gameplay-effects/executions-and-context.md#scoped-modifiers).
- **Conditional effects** let the execution decide to apply more: append a burning effect to `output.conditional_effects` on a critical.
- **Invulnerability** belongs in `pre_gameplay_effect_execute`, which can change or refuse a write before anything commits. See [Execute hooks on the attribute set](../guides/gameplay-effects/executions-and-context.md#execute-hooks-on-the-attribute-set).
