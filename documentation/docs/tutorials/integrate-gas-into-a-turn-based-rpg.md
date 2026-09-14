---
title: Integrate GAS_Engine into a Turn-Based RPG
sidebar_position: 2
description: How a complete turn-based RPG's combat was rebuilt on GAS_Engine - attributes, battlers, abilities with costs and turn cooldowns, the round loop, AI, UI and verification.
---

# Integrate GAS_Engine into a Turn-Based RPG

GAS_Engine's integration sandbox is a complete, playable turn-based RPG - the open-source *godot-open-rpg* - whose combat was **rebuilt** on GAS_Engine. This tutorial walks through that rebuild, so you can do the same in your own game.

## The approach: the game adapts to the engine

The old combat was not wrapped or migrated. Its stats class, action classes and turn logic were deleted, and combat was written as it would have been had GAS_Engine been there from the first commit. No adapter keeps both models alive.

One rule decided every design question: **a number is never written, it is contributed.** A +10 attack buff registers a contribution while its effect lives. Nothing keeps a private copy of a stat, and nothing has to remember to undo anything.

| Concern | Where it lives now |
|---|---|
| Stats | `BattlerAttributes`, an `AttributeSet` - one source of truth per battler. |
| A battler | A node with an `AbilitySystemComponent`, and no stats of its own. |
| An action | A `GameplayAbility` scene, granted to the component. |
| Energy cost | A `GameplayAbilityCost`, paid on commit, refused when unaffordable. |
| Damage and healing | `INSTANT` gameplay effects. |
| Buffs | Effects that register contributions. |
| "Can this act now?" | The activation gates, asked by the AI and the menu alike. |
| Targets | `GameplayAbilityTargetData`, filled by the arena's own selection. |
| Death | `health` reaching zero, observed through the component's attribute signal. |

## Step 1: Attributes

```gdscript
@tool
class_name BattlerAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const ENERGY: StringName = &"energy"
const MAX_ENERGY: StringName = &"max_energy"
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"
const SPEED: StringName = &"speed"
const HIT_CHANCE: StringName = &"hit_chance"
const EVASION: StringName = &"evasion"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)
@export var energy: AttributeData = AttributeData.new(0.0)
@export var max_energy: AttributeData = AttributeData.new(6.0)
@export var attack: AttributeData = AttributeData.new(10.0)
@export var defense: AttributeData = AttributeData.new(10.0)
@export var speed: AttributeData = AttributeData.new(70.0)
@export var hit_chance: AttributeData = AttributeData.new(100.0)
@export var evasion: AttributeData = AttributeData.new(0.0)


func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	energy = AttributeData.new(0.0)
	max_energy = AttributeData.new(6.0)
	attack = AttributeData.new(10.0)
	defense = AttributeData.new(10.0)
	speed = AttributeData.new(70.0)
	hit_chance = AttributeData.new(100.0)
	evasion = AttributeData.new(0.0)


func pre_attribute_base_change(attribute_name: StringName, proposed_base_value: float) -> float:
	return _bounded(attribute_name, proposed_base_value)


func pre_attribute_change(attribute_name: StringName, proposed_current_value: float) -> float:
	return _bounded(attribute_name, proposed_current_value)


## A maximum that drops pulls its pool's durable value down with it.
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
		MAX_ENERGY:
			return ENERGY
		_:
			return &""


func _bounded(attribute_name: StringName, value: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(value, 0.0, max_health.current_value)
		ENERGY:
			return clampf(value, 0.0, max_energy.current_value)
		HIT_CHANCE, EVASION:
			return clampf(value, 0.0, 100.0)
		_:
			return maxf(value, 0.0)
```

Each species has its numbers in a `.tres` of this set - `bear_attributes.tres`, `wolf_attributes.tres`. Three wolves built from one resource still have three health pools, because the component deep-copies what it is given.

## Step 2: The battler

A battler is a position, a look and a component. It owns no stats and no action list.

```gdscript
class_name Battler extends Node2D

signal turn_finished
signal downed
signal damaged(amount: float)
signal healed(amount: float)

const DOWNED: StringName = &"State.Downed"
const ACTING: StringName = &"State.Acting"

@export var attributes: BattlerAttributes = null
@export var ability_scenes: Array[PackedScene] = []

var asc: AbilitySystemComponent = null
## The grants, in the order of `ability_scenes`, for the action menu.
var granted: Array[GameplayAbilityHandle] = []


func _ready() -> void:
	asc = AbilitySystemComponent.new()
	asc.name = "AbilitySystemComponent"
	asc.attribute_sets = [attributes] as Array[AttributeSet]
	add_child(asc)
	asc.attribute_changed.connect(_on_attribute_changed)
	for scene: PackedScene in ability_scenes:
		var handle: GameplayAbilityHandle = asc.give_ability(scene)
		if handle.is_valid():
			granted.append(handle)


func attribute(attribute_name: StringName) -> float:
	return asc.get_attribute_current(attribute_name)


func is_downed() -> bool:
	return asc.has_tag_exact(DOWNED)


func _on_attribute_changed(
	attribute_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	if attribute_name != BattlerAttributes.HEALTH:
		return
	var delta: float = new_value - old_value
	if delta < 0.0:
		damaged.emit(absf(delta))
	elif delta > 0.0:
		healed.emit(delta)
	if new_value > 0.0 or is_downed():
		return
	# Tag first, signal second: a listener must never see a battler at zero
	# health that still reads as a legal target.
	asc.add_tag(DOWNED)
	downed.emit()
```

The component is added to the tree **before** abilities are granted: its runtimes are wired when it becomes ready.

## Step 3: Actions as abilities

Every combat action shares one shape - pay, move, land something on the targets, come home - so the game uses a base class, `BattlerAbility`, that subclasses fill in.

### Costs and cooldowns built in setters

Designers set `energy_cost`, `cooldown_tag` and `cooldown_turns` on each ability scene. The engine freezes an ability's definition right after the scene is instantiated, before `_ready()`, so the costs and cooldown are built **in the setters**, which run while the scene is being instantiated:

```gdscript
@abstract
class_name BattlerAbility extends GameplayAbility

@export_range(0.0, 10.0) var energy_cost: float = 0.0:
	set(value):
		energy_cost = value
		costs = _build_costs()

@export var cooldown_tag: StringName = &"":
	set(value):
		cooldown_tag = value
		cooldown_effect = _build_cooldown()

@export_range(0, 9) var cooldown_turns: int = 0:
	set(value):
		cooldown_turns = value
		cooldown_effect = _build_cooldown()

## Filled by the arena before activation.
var targets: Array[Battler] = []


func _init() -> void:
	# Never swing at a battler that went down earlier in the round.
	var downed: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	downed.operator = GameplayTagQueryExpression.Operator.ANY
	downed.tags = [Battler.DOWNED] as Array[StringName]
	target_blocked_query = GameplayTagQuery.new()
	target_blocked_query.root = downed


func _build_costs() -> Array[GameplayAbilityCost]:
	if energy_cost <= 0.0:
		return [] as Array[GameplayAbilityCost]
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = energy_cost
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = BattlerAttributes.ENERGY
	cost.amount = amount
	return [cost] as Array[GameplayAbilityCost]


func _build_cooldown() -> GameplayEffect:
	if cooldown_turns <= 0 or cooldown_tag == &"":
		return null
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.TURN_BASED
	effect.duration_turns = cooldown_turns
	var marker: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	marker.granted_tags = [cooldown_tag] as Array[StringName]
	effect.components.append(marker)
	return effect
```

Both cooldown setters rebuild the effect because a scene assigns properties in file order, and neither knows whether it runs last.

### The activation

```gdscript
func _activate_ability() -> bool:
	if targets.is_empty():
		return false
	# Paid first, before anything moves: a refusal costs nothing to undo.
	if not commit_ability().is_ok():
		return false
	await _perform()
	return true


## The choreography. Calls `_land()` at the moment the hit reads as landing.
@abstract
func _perform() -> void


## What this ability lands. Null for a pure movement.
func _payload() -> GameplayEffect:
	return null


func _land() -> void:
	var effect: GameplayEffect = _payload()
	if effect == null:
		return
	var aim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for battler: Battler in targets:
		aim.append_node(battler.asc)
	apply_effect_to_targets(effect, aim)


## A beat on the engine's clock, cancelled with the ability.
func _pause(seconds: float) -> bool:
	if seconds <= 0.0:
		return is_active
	var beat: AbilityTaskWaitDelay = wait_delay(seconds)
	if beat == null:
		return false
	await beat.completed()
	return beat.state == GameplayAbilityTask.State.SUCCEEDED
```

The choreography moves the battler with tweens and pauses with `_pause()`. After every `await` it checks `is_active`: a tween finishes on its own clock, and an ability cancelled mid-swing must not land its payload afterwards.

### Payloads

Each subclass only says what it moves and what it lands. Damage reads the caster's attack **through a capture**, so a buff to attack is felt on the next hit:

```gdscript
@abstract
class_name DamageAbility extends BattlerAbility

@export var base_damage: float = 50.0


func _payload() -> GameplayEffect:
	var from_attack: GameplayAttributeCaptureDefinition = GameplayAttributeCaptureDefinition.new()
	from_attack.actor = GameplayAttributeCaptureDefinition.Actor.SOURCE
	from_attack.attribute_name = BattlerAttributes.ATTACK
	from_attack.policy = GameplayAttributeCaptureDefinition.Policy.SNAPSHOT

	var bite: GameplayScalableFloat = GameplayScalableFloat.new()
	bite.value = base_damage
	var negate: GameplayScalableFloat = GameplayScalableFloat.new()
	negate.value = -1.0

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = from_attack
	magnitude.pre_add = bite
	magnitude.coefficient = negate

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = BattlerAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

A heal is the same with a positive `GameplayScalableMagnitude`; a buff is an `INFINITE` effect whose `ADD` modifiers on `attack` and `hit_chance` last the fight.

### The ability scenes

Each action is a scene of one node, with the numbers designers tune:

```text
[node name="Punch" type="Node"]
script = ExtResource("melee_attack_ability.gd")
ability_name = "Punch"
accuracy = 65.0
base_damage = 150.0
energy_cost = 3.0
cooldown_tag = &"Cooldown.Punch"
cooldown_turns = 4
```

:::info Hook-based abilities in the Composer
Subclasses such as `MeleeAttackAbility` override `_perform()` and `_payload()` and inherit `_activate_ability()`, so they open read-only in the Ability Composer. `BattlerAbility` itself, which declares the body, is the one to open. See [What the Composer can draw](../guides/ability-composer/what-the-composer-can-draw.md#abilities-with-no-body-of-their-own).
:::

## Step 4: The round

A round has two halves: everyone declares, then intentions resolve in speed order.

```gdscript
const ENERGY_PER_ROUND: float = 1.0


func next_round() -> void:
	# A turn passes for every battler. Without this, turn-based cooldowns
	# never lift.
	for battler: Battler in roster.get_battlers():
		battler.asc.advance_turn()

	for battler: Battler in roster.get_standing(roster.get_battlers()):
		battler.asc.apply_gameplay_effect(_energy_tick())

	# … enemies choose, then the player declares for each party member


## +1 energy, applied as an effect so the pool's own ceiling clamps it.
func _energy_tick() -> GameplayEffect:
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	amount.value = ENERGY_PER_ROUND
	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = BattlerAttributes.ENERGY
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude
	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

The next battler to act is the fastest one still holding an intention, read live from `speed`, so a haste landed earlier in the round changes the order within it.

## Step 5: Acting

The arena hands a battler the grant to use and its targets. The battler activates it and waits for it to finish:

```gdscript
func act(handle: GameplayAbilityHandle, at: Array[Battler]) -> void:
	if is_downed():
		turn_finished.emit()
		return
	var spec: GameplayAbilitySpec = asc.get_ability_spec(handle)
	var ability: BattlerAbility = spec.per_actor_instance as BattlerAbility if spec != null else null
	if ability == null:
		turn_finished.emit()
		return

	ability.targets = at
	asc.add_tag(ACTING)
	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)
	if result.is_ok():
		await ability.completed()
	asc.remove_tag(ACTING)
	turn_finished.emit()
```

`completed()` returns at once when the activation was refused, so a battler that cannot afford its action ends its turn instead of hanging.

## Step 6: The AI and the menu ask the engine

Neither the opponent AI nor the player's action menu decides what is legal. Both ask:

```gdscript
func choose(source: Battler, roster: BattlerRoster) -> Choice:
	var legal: Array[GameplayAbilityHandle] = []
	for handle: GameplayAbilityHandle in source.granted:
		if source.asc.can_activate_ability_handle(handle):
			legal.append(handle)
	# … pick one, then pick targets from the ability's own possible_targets()
```

```gdscript
entry.available = (
	battler.asc.can_activate_ability_handle(handle)
	and not ability.possible_targets(roster).is_empty()
)
```

An ability that costs too much, is on cooldown or is blocked by a tag is greyed out in the menu for exactly the reason the engine would refuse it.

## Step 7: The UI follows signals

Bars read the component once and then follow `attribute_changed`. They keep no copy of a number:

```gdscript
func _on_attribute_changed(
	attribute_name: StringName, _old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	match attribute_name:
		BattlerAttributes.HEALTH:
			life_bar.target_value = new_value
		BattlerAttributes.ENERGY:
			energy_bar.value = new_value
		BattlerAttributes.MAX_HEALTH:
			life_bar.max_value = new_value
		BattlerAttributes.MAX_ENERGY:
			energy_bar.max_value = new_value
```

## Step 8: Prove it in the game

The sandbox holds the engine to its word with headless probes that drive the same `Battler.act()` seam the arena uses: damage and overkill, a downed target refused, healing and its ceiling, a cost refused and a cost paid, a cooldown counted in turns, energy bounds, buffs stacking and withdrawn to exactly base, a maximum dropping under its pool, and a swing cancelled in its wind-up and in the air. [Testing your gameplay](testing-your-gameplay.md) shows how to write probes like these.

## Checklist for your own game

- One component per character, added to the tree before granting, with its attributes deep-copied from authored resources.
- Costs, cooldowns and tag queries built in the scene, in `_init()` or in setters - never in `_ready()`.
- Damage, healing, buffs and resource ticks as effects; no stat written directly.
- `advance_turn()` on every component once per turn.
- Tags set before the signals that announce the state they describe.
- Every "can this happen?" asked of the engine.
- Waits inside abilities done with tasks, and `is_active` checked after any other `await`.
