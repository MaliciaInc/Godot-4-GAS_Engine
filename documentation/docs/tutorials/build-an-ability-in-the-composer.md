---
title: Build an Ability in the Composer
sidebar_position: 1
description: Create an ignite ability from scratch in the Ability Composer - effect asset, ability files, calls, values, a data cable, a branch written in code - and cast it in game.
---

# Build an Ability in the Composer

In this tutorial you build **Ignite**: an ability that pays for itself, then sets whatever it is aimed at on fire for a few seconds. You build it almost entirely in the Ability Composer, switch to code once for a guard, and cast it on a character.

**You need:** GAS_Engine installed and enabled, and a character with an `AbilitySystemComponent` whose attribute set declares `health` - the [Quickstart](../quickstart.md) character works.

## Step 1: Create the burn effect

The ability applies an effect, so create the effect first.

1. Choose **Project → Tools → Create Gameplay Effect** and save it as `res://game/effects/ignite_burn.tres`. The effect opens in the Inspector, and in the **Gameplay Effect** bottom panel.
2. In the Inspector, set:

| Property | Value |
|---|---|
| Resource Name | `Ignite burn` |
| Policy | `DURATION` |
| Duration | `4` |
| Period | `1` |

3. Add one element to **Modifiers**, a new `GameplayEffectModifier`:

| Property | Value |
|---|---|
| Attribute | `health`, chosen with the attribute picker |
| Operation | `ADD` |
| Magnitude | a new `GameplayScalableMagnitude` whose **Value** is a new `GameplayScalableFloat` with **Value** `-5` |

Typing `health` into **Attribute Name** instead works just as well; when both are filled in, the picker's choice wins. See [Referring to an attribute](../guides/attributes.md#referring-to-an-attribute). The **Gameplay Effect** panel now shows the modifier on a row of its own.

A periodic effect writes its modifier to the base value on every tick, so this takes 5 health every second while it lasts. See [Periodic effects](../guides/gameplay-effects/duration-and-periodic-effects.md#periodic-effects).

## Step 2: Create the ability

1. Choose **Project → Tools → Ability Composer**.
2. Click **New ability** in the top bar and save as `res://game/abilities/ignite.gd`.

The Composer writes `ignite.gd` and `ignite.tscn`, and draws the new ability: an **Entry** card connected to an **End** card - the `return true` of the template.

## Step 3: Commit the ability

1. In the palette, open the **Ability** group.
2. Click **Commit Ability**.

With nothing selected, the call is written at the end of the body, before the `return`. The canvas now reads **Entry → Commit Ability → End**.

## Step 4: Apply the effect

1. Click the **Commit Ability** card to select it.
2. In the palette, open **Effects** and click **Apply Effect To Targets**.

The call is written after the selected card. Its two arguments, **Effect Res** and **Target Data**, are written as `null`.

## Step 5: Choose the effect

1. Select the **Apply Effect To Targets** card.
2. In the Inspector, use **Effect Res**'s resource picker to choose `ignite_burn.tres`.

The argument becomes `preload("res://game/effects/ignite_burn.tres")`.

## Step 6: Aim at the activation's target

Ignite hits whatever the caller aimed it at, which the ability reads with `get_activation_target_data()`.

1. Drag a cable **out of** the **Target Data** input pin of **Apply Effect To Targets**, and let go over empty canvas.
2. The action menu opens, showing only calls that return what that pin takes. Pick **Get Activation Target Data**.

The Composer writes the call **before** the card that needs it, stores the result in a typed local, and draws the cable from that local into **Target Data** - one change, one undo.

## Step 7: Save and read the code

Press **Ctrl+S**. The Output panel should report nothing to fix.

Click **Code** in the top bar. The Script editor shows the same file:

```gdscript
@tool
extends GameplayAbility


func _activate_ability() -> bool:
	commit_ability()
	var get_activation_target_data_result: GameplayAbilityTargetData = get_activation_target_data()
	apply_effect_to_targets(preload("res://game/effects/ignite_burn.tres"), get_activation_target_data_result)
	return true
```

If you moved cards around, you will also see `# @composer-position` comments above the statements. They only record where each card is drawn.

## Step 8: Guard the commit in code

A commit can be refused - not enough mana, still on cooldown - and the ability should stop when it is. Branches are written in code.

In the Script editor, replace `commit_ability()` with:

```gdscript
	if not commit_ability().is_ok():
		return false
```

While you are there, rename the local to something readable - `aim`, in both places. Save, then choose **Project → Tools → Ability Composer** again.

The canvas now shows a branch: its **True** path leads to an **End** for `return false`, and its **False** path continues to **Get Activation Target Data**. The cable from `aim` into **Target Data** followed the rename, because a data cable is the local's name.

## Step 9: Set the ability's rules on its scene

Rules belong to the scene, so they are part of the definition frozen at grant.

1. Create a second effect with **Create Gameplay Effect**, `res://game/effects/ignite_cooldown.tres`: policy `DURATION`, duration `3`, and one **Components** element, a `GameplayEffectTargetTagsComponent` whose **Granted Tags** holds `Cooldown.Ignite`.
2. Open `ignite.tscn`, select its root node, and set:

| Property | Value |
|---|---|
| Ability Name | `Ignite` |
| Ability Tags | `Ability.Spell.Fire` |
| Cooldown Effect | `ignite_cooldown.tres` |

3. Save the scene.

See [Cooldowns](../guides/abilities/costs-and-cooldowns.md#cooldowns) for what makes a cooldown effect legal.

## Step 10: Cast it

Grant the scene to your character and activate it aimed at a target:

```gdscript
const IGNITE: PackedScene = preload("res://game/abilities/ignite.tscn")

var ignite: GameplayAbilityHandle = null


func _ready() -> void:
	# … after the component has been added
	ignite = asc.give_ability(IGNITE)


func ignite_target(target: Node) -> GameplayAbilityActivationResult:
	var aim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aim.append_node(target)
	var context: GameplayEffectContext = GameplayEffectContext.new(self)
	context.target_data = aim
	return asc.try_activate_ability_handle(
		ignite, GameplayAbilityActivationContext.from_effect_context(context)
	)
```

Cast it on the dummy and watch the [debug overlay](../guides/debugging.md#the-debug-overlay): **Ignite burn** appears under **Active effects** on the target, its health drops every second, and a second cast within three seconds is refused with `ON_COOLDOWN`.

## Where to go next

- Add a wind-up: select the **Get Activation Target Data** card and click **Tasks → Wait Delay**. The Composer writes `await wait_delay(0.0).completed()` right after it; set **Seconds** in the Inspector.
- Play a cue on impact by adding a `GameplayCueBinding` to the burn effect. See [Gameplay cues](../guides/gameplay-cues.md#cues-on-effects).
- Learn every gesture in [Editing abilities](../guides/ability-composer/editing-abilities.md).
