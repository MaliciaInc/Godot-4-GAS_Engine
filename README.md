# GAS_Engine (v4.0.0)

> [!IMPORTANT]
> **"GAS Engine doesn’t adapt to any game... the game is the one that must adapt and be built around GAS as its backbone. I’d say it’s a very good trade-off, especially if you come from another Game Engine."**
>
> To report a bug or request a feature, open a [new issue](https://github.com/MaliciaInc/Godot-4-GAS_Engine/issues/new) in [Issues](https://github.com/MaliciaInc/Godot-4-GAS_Engine/issues).

### Proof of Concept & Real-World Integration
If you want to see the framework operating as the actual core of a production environment, switch over to the **`godot-open-rpg_GAS_Engine`** branch.

This branch contains the framework integrated into a real, fully realized game by **GDQuest** (Open RPG). To prove the architecture's power, I completely replaced their native `BattlerStats` system, re-mapped and re-wired the stats for all combat characters, and connected narrative dialogues seamlessly through the integration bridge.

---

**GAS_Engine** is a production-oriented Gameplay Ability System for **Godot 4.7.2**, built for games that need deterministic attributes, effects, abilities, gameplay tags, targeting, cues, and extensible combat rules without turning gameplay state into a pile of loosely typed dictionaries and side effects.

It is a standalone, reusable Godot addon - version **4.0.0** - with a visual ability editor, debugging tools inside the game and inside the editor, and multiplayer.

> **License model:** use GAS_Engine unmodified in personal or commercial games for free. Modifying GAS_Engine itself, distributing modified versions, or creating a derivative framework requires a separate paid Commercial Modification License.

See [License](#license) for the exact distinction.

## Requirements

| | |
|---|---|
| Godot | **4.7.2** |
| Language | GDScript, strictly typed |
| Runtime dependencies | none |

The exact patch version is named rather than "4.7" because GDScript warnings promoted to errors can change between patch releases, and this framework is strictly typed throughout.

The repository's own test suite runs on GUT `v9.7.1`, vendored under `addons/gut/`. A game does not need it.

## Documentation

The manual lives in [`documentation/`](documentation/README.md): getting started, one guide per subsystem, and end-to-end tutorials, covering the runtime API and the Ability Composer alike. This README is the overview; the manual is where each claim below is explained in full.

| Start with | For |
|---|---|
| [Quickstart](documentation/docs/quickstart.md) | A damaging ability cast on a character and watched in the runtime overlay, in about ten minutes. |
| [Core concepts](documentation/docs/getting-started/core-concepts.md) | The model: components, attributes, effects, abilities, tags, events, cues and tasks. |
| [Guides](documentation/docs/guides/) | One page per subsystem - what it guarantees, how to use it, and what to avoid. |
| [Integrate GAS_Engine into a turn-based RPG](documentation/docs/tutorials/integrate-gas-into-a-turn-based-rpg.md) | The engine wired into a complete game. |
| [Common pitfalls](documentation/docs/guides/common-pitfalls.md) | Symptoms, their causes, and the fix for each. |

## Installation

1. Copy the `addons/GAS_Engine/` folder, whole, into your project's `addons/` folder.
2. **Project → Project Settings → Plugins**, and tick **GAS_Engine**.

Enabling the plugin:

- adds one autoload, `GameplayCueManager`. If your project already declares an autoload by that name, GAS_Engine leaves your declaration alone and warns rather than overwriting it;
- creates the project's two registries in `res://gas_engine/` when they do not exist yet - `gameplay_tags.gd` and `gameplay_cues.gd`, ordinary GDScript it never rewrites;
- registers its project settings under `gas_engine/`;
- adds the tools described under [Editor tools](#editor-tools).

There is no build step, and nothing needs configuring before the next section works.

### Updating

Replace `addons/GAS_Engine/` whole - never merge an old folder and a new one - and keep `res://gas_engine/`, which belongs to your project. Then re-render the two registries with the new generators: the engine reads them as text, so a declaration a newer engine expects is simply absent from a file an older one wrote, and an absent declaration reads as an empty one. The [installation guide](documentation/docs/getting-started/installation.md#updating-gas_engine) has the script.

### Exporting

On Godot's default export mode, **Export all resources in the project**, there is nothing to do: everything below ships.

If you switch to **Selected scenes and dependencies**, add these to the preset's include filter:

```
addons/GAS_Engine/*, gas_engine/*
```

and select every scene a gameplay cue plays, the same way you would select any other scene the game reaches at runtime.

The reason is Godot's, not this addon's, and it is worth knowing because it is invisible: the exporter decides what to keep by walking `ResourceLoader.get_dependencies()`, and that returns nothing for a `.gd` file. A `preload()` in GDScript is a compile-time link, never an export dependency — measured on 4.7.2, where a scene reports its whole dependency list and every script reports zero. So under the selective mode nothing reached only through GDScript survives, including the scripts this addon's own autoload preloads. A build made that way starts with `No cue registry found at ...` in the log, which is the symptom to recognise.

## Quick start: a fireball in five minutes

Three scripts and a scene. Everything below is plain GDScript that runs the moment you save it; the [Quickstart](documentation/docs/quickstart.md) in the manual goes on to cast it in a scene and watch it in the runtime overlay.

### 1. Your first AttributeSet

An **AttributeSet** is everything about a character that a number can express. Declare each attribute as an `@export`; the engine finds them by reflection, so there is no registration step and no list to keep in sync.

```gdscript
class_name HeroAttributes extends AttributeSet

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"

@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)


## Fresh instances per set. Without this the `@export` defaults are evaluated
## once and every character built from this script shares one health pool -
## the whole party dies the moment anyone does.
func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)


## Asked before a durable write lands, so an overkill hit is clamped at the
## source instead of after several systems have already seen a negative pool.
func pre_attribute_base_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


## Asked again after modifiers compose, so a `max_health` buff that expires
## cannot leave `health` standing above the ceiling it just lost.
func pre_attribute_change(attribute_name: StringName, proposed: float) -> float:
	return _bounded(attribute_name, proposed)


func _bounded(attribute_name: StringName, value: float) -> float:
	if attribute_name == HEALTH:
		return clampf(value, 0.0, max_health.current_value)
	return maxf(value, 0.0)
```

The `_init()` block is not boilerplate you can skip. It is the most common first mistake with this framework.

### 2. Your first GameplayEffect

A **GameplayEffect** is what an ability lands. Here it is built in code, from a number the ability already declares:

```gdscript
func _payload() -> GameplayEffect:
	var how_much: GameplayScalableFloat = GameplayScalableFloat.new()
	how_much.value = -damage

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = how_much

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = HeroAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

The idea worth carrying forward: **a modifier is a contribution, not a write.** A `+5` attack buff does not set `attack` to `15`; it registers a contribution the engine folds in while the effect lives and withdraws when it ends. Nothing has to remember to undo anything, which is why a stack of buffs and debuffs expiring in any order still lands on the right number.

`INSTANT` applies its arithmetic once and vanishes. `DURATION`, `INFINITE` and `TURN_BASED` are the other three policies, and only those can grant tags.

### 3. Your first Ability

A **GameplayAbility** is a `Node`. It pays for itself, decides who it reaches, and applies its payload:

```gdscript
class_name Fireball extends GameplayAbility

## What this takes off a target's health.
@export var damage: float = 30.0

## Who it is aimed at. A real game decides targets outside the ability; a group
## keeps this example to one file.
@export var enemies_group: StringName = &"enemies"


func _activate_ability() -> bool:
	# Paid first. Nothing has happened yet, so a refusal costs nothing to undo.
	if not commit_ability().is_ok():
		return false

	var struck: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for enemy: Node in get_tree().get_nodes_in_group(enemies_group):
		var theirs: AbilitySystemComponent = AbilitySystemLocator.find_for_node(enemy)
		if theirs != null:
			struck.append_node(theirs)

	apply_effect_to_targets(_payload(), struck)
	end_ability()
	return true


func _payload() -> GameplayEffect:
	var how_much: GameplayScalableFloat = GameplayScalableFloat.new()
	how_much.value = -damage

	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = how_much

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = HeroAttributes.HEALTH
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier] as Array[GameplayEffectModifier]
	return effect
```

Save it as a scene — one `Node` with this script attached, `fireball.tscn` — and set `damage` in the Inspector. **The scene carries the numbers; the script carries the behaviour.** That is how every ability in this framework is authored.

An ability never subtracts a cost itself. It calls `commit_ability()`, and the engine refuses the whole activation when the cost cannot be paid, so an ability nobody can afford never half-happens.

> **One trap worth knowing now.** If you give an ability a cost or a cooldown, build it in a property setter or in `_init()`, never in `_ready()`. Granting an ability snapshots its definition immediately after `instantiate()`, and `_ready()` runs later — a cost built there never reaches the engine, the ability silently reads as free, and `commit_ability()` has nothing to refuse.

### 4. Give it to a character

A character is any node with an `AbilitySystemComponent` **as a child named `AbilitySystemComponent`** - the name is how `AbilitySystemLocator` finds the component from any node of the character. The component asks its parent what effects and cues act on, so it is never an orphan.

```gdscript
extends Node

const FIREBALL: PackedScene = preload("res://fireball.tscn")

var asc: AbilitySystemComponent = null


func _ready() -> void:
	asc = AbilitySystemComponent.new()
	asc.name = "AbilitySystemComponent"
	asc.attribute_sets = [HeroAttributes.new()] as Array[AttributeSet]
	add_child(asc)

	var handle: GameplayAbilityHandle = asc.give_ability(FIREBALL)
	asc.ability_runtime.try_activate(handle)
```

Put the same component on a second node, add that node to the `enemies` group, and the fireball takes it from 100 health to 70 while its caster is untouched. `give_ability()` returns a `GameplayAbilityHandle`; the handle, not the ability node, is how a grant is referred to from then on. The activation returns a result whose status says what happened - `SUCCESS`, or why it was refused, such as `ON_COOLDOWN` or `INSUFFICIENT_RESOURCES` - instead of collapsing into `false`.

This quick start is executed by the test suite, so it cannot quietly stop working. The manual's [Quickstart](documentation/docs/quickstart.md) aims at a chosen target instead of a group, through `try_activate_ability_handle()` and an activation context.

Read a value back with `asc.get_attribute_current(&"health")`, and watch it move by connecting `asc.attribute_changed`.

### Code or an effect asset

The effect above is built in GDScript so the whole example fits in one file. An effect can just as well be a `.tres` asset: **Project → Tools → Create Gameplay Effect** writes one, and selecting it opens the Inspector and the **Gameplay Effect** bottom panel, which lists its modifiers and saves them back. An ability exports the asset like any other resource. Both routes produce the same `GameplayEffect`, and nothing in the engine tells them apart.

### Where to go from here

- The [manual](documentation/README.md) explains every subsystem, with tutorials.
- `addons/GAS_Engine/reference/` holds six complete abilities, written by hand and commented - see [Examples](#examples).
- The **Ability Composer** draws any ability as a graph, and writes your edits back to the same file. Choose it from **Project → Tools** and it finds your abilities for you.
- The rest of this document explains what each subsystem guarantees, and why.

## Editor tools

Everything here is editor-only: nothing under `addons/GAS_Engine/editor/` is reachable from a running game.

| Tool | What it does |
|---|---|
| **Ability Composer** - **Project → Tools → Ability Composer**, or the **GAS_Engine** tab at the top of the editor | Draws an ability's `_activate_ability()` as a graph and writes edits back to the same `.gd`. See [Ability Composer](#ability-composer). |
| **Project → Tools → Create Gameplay Effect** | Writes a blank `GameplayEffect` asset and opens it. |
| **Gameplay Effect** bottom panel | Follows the Inspector. For the effect it has open: timing, stacking, a row per modifier, its components and cues, the asset validator's findings, and a save button. |
| Inspector pickers | A tag editor for tag properties, a tree editor for tag queries, and an attribute picker that offers the attributes the project declares and flags a name nothing declares. |
| **GAS_Engine** tab in the Debugger dock | Every entity a game running from the editor reports - its attributes, active effects, abilities and tags, kept current - with what happened to it beside them. See [Debugging](#debugging). |
| `GameplayAssetValidator` | Checks authored effects, ability scenes, tag queries and costs from editor code: an `EditorScript`, a test, a build step. |

The [editor tools page](documentation/docs/getting-started/editor-tools.md) covers each in full.

## Scope and support model

### Project Model

GAS_Engine is **source-available** and **free for use in games**.

GAS_Engine is maintained centrally by **MaliciaInc**. Bug reports and feature requests are handled through GitHub Issues. External modifications are not part of the supported distribution model.

### Networking

Multiplayer ships. What follows is the contract as it stands, not a roadmap:
every name below is a class or a value you can open, and the limitations at the
end are the real ones rather than the ones that sound modest.

**The wire.** `GameplayNetTransport` is the seam - two methods, send and
receive - and `GameplayNetTransportMultiplayer` is the implementation over
Godot's own `SceneMultiplayer`, using `send_bytes` and `peer_packet` rather than
RPCs. RPCs need a node path both peers agree on, and an ability system is a
component that may live anywhere in anybody's scene; bytes need nobody to agree
about a tree. Object decoding is never enabled: a peer that allowed it would be
constructing whatever class the far side named. Bring your own transport by
implementing the base class - Steam, WebRTC, a recording of yesterday's match -
and the runtime does not change.

**What crosses.** A bit stream, not text. A message is its kind in four bits, the
entity it is about, presence bits for the fields it carries, and only those
fields: a confirm is 5 bytes, a predicted request 11, and a whole character
reading - six attributes, four tags, three grants, five running effects, two
cues - about 160 once both machines share the project's tag table. Names cross
as their position in a table both machines build from the project's own tags, a
name outside it is spelled once per packet and pointed back at after, and a peer
holding a different table is refused as a protocol mismatch rather than reading
every tag as some other tag. Whole numbers are packed, attributes and durations
cross as 32-bit floats, a place is quantized to the centimetre and a normal to
sixteen bits a component, and every list has a bound. A packet that does not
read cleanly - a count past its bound, a presence bit followed by nothing, a
byte left over - is refused whole. The game's own `payload` crosses as the
values it holds, each as the type it left as, and never as an object.

**Authority.** One runtime authors. A runtime that does not own a thing refuses
to author it rather than being trusted not to, and every message is checked for
direction, ownership and having been seen before. A client's request is answered
with one of four things: run it, predict it and ask, ask and wait, or refused.

**State as readings.** Attributes, tag counts, granted abilities, which of them
are running, the cues in force, and each running effect with its definition,
stacks, remaining seconds and turns, and whether it is inhibited. Effects are
never re-applied on the receiving machine: the values that arrive already have
them in. Snapshots are the whole truth and deltas are what changed, and a
reading that arrives after a newer one is ignored rather than putting a
character back where it was half a second ago.

**Three replication modes, per entity.** `FULL` tells everybody everything.
`MIXED`, the default, sends the running effects to the owner alone and the
attributes, tags and cues to everyone. `MINIMAL` sends no effects at all. The
per-entity replication mode is what makes this usable at scale: a boss and a
villager are two different amounts of network, and a runtime with one setting
would make a game choose the expensive one for both.

**Three ability policies, and they are three.** `NetExecutionPolicy` decides
where and when an ability runs - `LOCAL_ONLY`, `LOCAL_PREDICTED`,
`SERVER_INITIATED`, `SERVER_ONLY`. `NetSecurityPolicy` decides what the
authority accepts from somebody else - `CLIENT_OR_SERVER`,
`SERVER_ONLY_EXECUTION`, `SERVER_ONLY_TERMINATION`, `SERVER_ONLY`. Neither is
derived from the other, and that is the point: an ability the server alone
executes can still be one whose owner is entitled to ask for it, and one a
client predicts can still be one a client may not call off.
`server_respects_remote_cancellation` is the second gate on ending one, and it
is false by default because a client that ends an ability after the authority
has committed its cost has taken the cost and given nothing back.
`ReplicationPolicy` decides whether the owning peer is told that an activation
is running at all - `REPLICATE_NO` for almost everything, `REPLICATE_YES` for
the ones whose middle a UI has to draw. Nothing ever serialises an ability
instance; what crosses is the definition both machines already agree about.

**`replicate_input_directly`.** For the abilities whose meaning is in the press
and the release - a charge, a hold, anything where letting go is the interesting
half. The press crosses instead of the activation it would cause, and the
authority resolves it against the grant it made rather than against a handle the
client invented.

**Target data validation.** An aim crosses as identities and numbers and is
checked on arrival: a claim that does not read as an aim, one naming an entity
this machine has never registered, one no waiting provider could have produced,
and one outside the range that provider enforces are four separate refusals. A
collider no registry knows is left out rather than sent as its address.

**Batching.** An activation is not one message - it is the activation, what it
cost, what it put on cooldown and what it confirmed - and a peer that saw three
of those four shows a character mid-cast with no cooldown. `begin_batch()` and
`end_batch()` gather; a batch is read whole, judged whole and only then applied,
so one member addressed to somebody who is not here applies none of it.

**Prediction, for six things.** A cost, a cooldown, an allowed attribute delta,
a cue, a tag with the counts either side of it, and an animation with the
ownership claim taken on its surface. Each can be undone from what the operation
itself remembers. `open_window()` and `close_window()` make the boundary a
refusal unwinds explicit, and a refused guess comes off newest first, once,
however many times the refusal arrives. A guess predicted while an earlier one
is still waiting on its own answer nests inside it rather than being refused a
window - `next_key_in_window()` stands the new one on whichever is open - so
rejecting the outer takes what stood on it with it, in whatever order the two
answers actually arrive in.

**Not predicted, deliberately.** A periodic tick, whose count is a clock the two
machines do not share. An arbitrary execution, because nothing wrote down the
inverse of whatever it decided. A custom cost with no prediction kind - which is
what `GameplayPredictionOperation.Kind.NONE` says out loud. A server-side effect
nothing on the client can observe. None of these is promised, and the journal
refuses them rather than guessing.

**Limitations, actually.**

- A cost and an attribute delta are guarded only by having been accepted. An
  authoritative reading that moved the same attribute between the guess and the
  refusal is undone along with the guess, and the next reading corrects it - a
  tag and an animation can say more, and do; those two cannot.
- Two machines have to hold the same table of names. A packet written against a
  different one is refused as a protocol mismatch, so two builds whose tags
  differ do not talk until one of them is updated - which is the honest failure,
  since the alternative is every tag arriving as some other tag.
- Numbers cross at the precision the state needs, not the precision a physics
  simulation would: attributes and durations at 32 bits, places at the
  centimetre, normals at sixteen bits a component.
- There is no interest management, no delta compression and no client-side
  interpolation. Which entities a peer hears about is the game's decision, made
  by choosing when to send.
- Two processes are checked by one scenario, in `examples/action_sample/network`
  and `tooling/run_multiplayer_sample.ps1`, not by a test matrix over
  connection conditions. The in-process suite covers those: three runtimes over
  a link that can be told to repeat, reorder, lose and delay messages, which is
  how every adverse condition here is reachable and deterministic.

Run the two-process sample to see all of it at once:

```powershell
pwsh -File tooling/run_multiplayer_sample.ps1
```

The [networking guide](documentation/docs/guides/networking.md) and the [two-process tutorial](documentation/docs/tutorials/multiplayer-across-two-processes.md) walk through it in code.

## Proven in a real game

A suite proves a framework against itself. It cannot prove that a game built on
the framework behaves, and several of this engine's defects were found exactly
there - invisible to every assertion in the suite, and plain the first time a
game used the engine for real.

So the engine is also driven through a complete integration: a turn-based RPG
whose combat system is built on GAS_Engine and nothing else, on the
`godot-open-rpg_GAS_Engine` branch. The addon is copied there from `main`
unchanged, and each harness ends with a line a runner can read:

| Harness | What it holds GAS_Engine to |
| --- | --- |
| `gas_probe` | Two arenas played from the game's real main scene, through the seams a player uses, to `combat_finished`. |
| `gas_contract_probe` | Damage and overkill, a downed target refused, healing and its ceiling, a cost refused and a cost paid, a cooldown counted in turns, buffs stacking and withdrawn to exactly base, and a swing cancelled mid-cast - on real battlers, through the game's own `Battler.act()`. |
| `composer_game_probe` | The game's abilities and the reference abilities read and printed back byte for byte, and an ability made through the Composer given to a battler and run. |
| `gas_overlay_probe` | The runtime overlay over the game's own theme, while paused and with the watched battler freed. |
| `dialogic_bridge_probe` | Real Dialogic timelines driving the bridge. |
| `composer_harness`, `composer_smoke` | The Composer in a real window; the smoke with pushed mouse and keyboard input. |
| `gas_editor_probe` | The Gameplay Effect panel and the Debugger tab inside a real editor, with the game running. |

A played fight is not reproducible round for round - accuracy is rolled off a
stream whose draw order moves with the wall clock - so the battle probe asserts
only that both arenas finish, and the contracts are held by the probe built for
them. Every defect the branch found, and how `main` closed it, is in its
`FINDINGS.md`.

## Design goals

GAS_Engine is built around a few non-negotiable rules:

- deterministic gameplay state;
- typed domain contracts instead of generic `Variant` / `Dictionary` APIs;
- atomic effect application and ability costs;
- explicit ownership of mutable runtime state;
- predictable lifecycle behavior;
- reusable 2D and 3D targeting;
- strict failure instead of silent partial application;
- testable gameplay rules that do not depend on editor state;
- extension points for game-specific logic without modifying the framework itself.

## Core systems

### Abilities

Abilities have explicit activation policies and a typed lifecycle.

Supported behavior includes:

- activation by call, by stable ability handle, on grant, passively, by a gameplay-event or owned-tag trigger, and by input - an input slot, an InputMap action, or both;
- `WHILE_INPUT_ACTIVE`: held down it runs, let go it ends;
- instancing per actor, per execution - several casts of one ability running at once - or not instanced at all;
- transactional commits: attribute costs (a fixed amount, or a percentage of another attribute), cost effects and custom costs, and cooldowns in seconds or in turns, shareable through their tags - all paid, or nothing paid;
- tag rules: requirements on the owner, the source and the target, tags held while running, blocking and cancelling other abilities, and a tag relationship table;
- ability sets that grant a whole loadout - attribute sets, abilities and effects - and take it back in one call;
- cancellable ability tasks, and removal policies that cancel a running activation or let it finish.

An activation returns a typed result describing what happened instead of collapsing every failure into a generic boolean, and a refusal carries a failure tag a game's UI can react to.

### Attributes

Attributes separate durable base state from derived current state.

Two aggregation profiles ship, chosen per component through
`compatibility_profile`. They are genuinely different arithmetic rather than a
setting on one formula, so both are written out.

**`GODOT_NATIVE`** - this engine's own, and the default:

```text
current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
```

followed by the last applicable override and the effective clamp. A base of
`10`, an additive `+10` and a multiplier of `x2` resolve to `40`, not `30`, and
two `+50%` buffs are worth `2.25x` because the products multiply.

**`CHANNEL_FOLDED`** - folded once per evaluation channel, over channels `0`
to `9`, each channel composing over the value the previous one produced:

```text
value =
(
	(value + sum(ADD))
	* (1 + sum(MULTIPLY_ADDITIVE - 1))
	/ (1 + sum(DIVIDE_ADDITIVE - 1))
)
* product(MULTIPLY_COMPOUND)
+ sum(ADD_FINAL)
```

with the override resolved per channel. Two `+50%` buffs authored as
`MULTIPLY_ADDITIVE` are worth `2.0x`, because the bonuses add and multiply
once; the same two authored as `MULTIPLY_COMPOUND` are worth `2.25x`. The
channels are what let a game say "this multiplies the buffed value, not the
base" without every effect having to know about every other one.

Neither profile is a bug and neither is the fix for the other. **Switching
profile rebalances every stat in a game that already shipped on the other one**,
so it is a decision made once, at the start.

Base and effective-value clamps are separate hooks so temporary presentation
constraints cannot silently corrupt durable state. Beyond them:

- **meta attributes** - incoming damage, say - are messages rather than stores: read once by the attribute set and returned to zero;
- **aggregator policies** decide per attribute which contributions count - every one, or only the one that leaves the value lowest or highest, so four slowing puddles slow a character once;
- an attribute can be named with its set, through `GameplayAttributeRef`, where two sets on one entity share a name - and a write to a name two sets share is refused rather than guessed.

### Gameplay effects

Gameplay effects support:

- instant, duration, infinite, periodic, and turn-based behavior;
- atomic evaluation and commit;
- typed modifier magnitudes: scalable values, attribute-based magnitudes, SetByCaller values, and custom calculations;
- magnitudes that stay live on a lasting effect - re-resolved when a captured attribute moves, or when a signal the magnitude depends on fires;
- execution calculations, with attribute captures, richer outputs and scoped modifiers;
- stacking with limits, overflow effects, and refresh and expiration policies;
- components: target and asset tags, application tag requirements, chance to apply, custom can-apply checks, immunity, removing other effects, blocking and cancelling abilities, additional effects, granted abilities, and UI data;
- effect inhibition without destroying runtime identity;
- pre/post gameplay-effect execute hooks on the attribute set;
- effect queries, explicit removal reasons, and bounded effect-chain recursion;
- effects authored as `.tres` assets or built in code, interchangeably.

A failed application leaves no half-applied modifiers, tags, cues, registrations, or observable partial state behind.

### Gameplay tags

Gameplay tags are hierarchical and query-driven. A project declares them once, in `res://gas_engine/gameplay_tags.gd` - by hand or through the Inspector's tag editor - with redirects for tags that were renamed after they shipped, and branches another team can own.

They are used for:

- activation requirements;
- ability identity;
- cancellation and blocking;
- effect requirements;
- effect queries;
- event routing;
- target validation;
- passive reevaluation;
- gameplay-state observation.

Tag semantics are centralized so different subsystems do not invent slightly different definitions of what a tag match means.

### Gameplay events

A gameplay event is a tagged message sent to one component - "this character parried" - with an instigator, a target, a magnitude and optional objects. Tasks waiting for it hear it first, then the component's signal, then abilities whose triggers match; matching is hierarchical and one-directional. Effects send events of their own as they apply, tick and stack, and the Dialogic and QuestSystem bridges carry events in from outside the ability system.

### Targeting

GAS_Engine supports typed targeting in both **2D and 3D**, and never reads the mouse, the camera or the input map itself: a game turns input into positions and rays, and the engine turns those into targets.

The targeting boundary handles:

- target data made of hits - on nodes, or at places - with each target of an area effect given only its own share;
- physics queries: raycasts and overlaps, with filters;
- presets: the same query authored as select, filter and sort steps;
- providers: a person aims over time, sees a preview and confirms - and over a network, the authority validates the aim;
- reticles that show where an aim will land;
- ability-system resolution, duplicate collider resolution and self-filtering.

One actor represented by several colliders resolves as one gameplay target rather than several accidental hits.

### Gameplay cues

Gameplay cues provide cosmetic feedback without making visual effects part of authoritative gameplay state. Gameplay code asks for a cue by tag, and it is answered by a scene whose root is a `GameplayCueNotify`, by a handler script with nothing to instantiate, or by the target's own `handle_gameplay_cue()`.

The cue system supports:

- bindings in `res://gas_engine/gameplay_cues.gd`, or bound at runtime;
- fallback up a tag's family, stopped where a tag overrides its parent;
- ready-made burst and looping templates, filled with sounds, particles and decals rather than code;
- one-shot, periodic and persistent cues, with typed parameters and handles;
- pooling;
- cues on effects and on abilities, with clean activation and removal when effects become inhibited or active again;
- replication chosen per binding.

A missing cosmetic cue cannot invalidate gameplay application.

### Ability tasks

The task layer provides reusable asynchronous gameplay operations owned by an ability lifecycle.

Examples include waiting for:

- delays, and input by slot or by action;
- target data, and confirmation or cancellation;
- gameplay events;
- attribute changes, thresholds and ratios;
- tags added, removed, counted, or matching a query;
- effects applied, removed, blocked by immunity, or changing their stack count;
- another ability activating, ending, or paying for itself;
- repeated ticks, a condition, a named state, and a network sync point;
- an animation playing to its end, root motion, moving to a point, an overlap, and a spawned actor's lifetime.

Ending or cancelling an ability cancels the tasks it owns, and each task completes exactly once. Await a task's `completed()` rather than its `finished` signal: a task can end before its caller gets to wait for it.

### Debugging

Every entity can be looked at while the game runs, with nothing attached to it:

- **`GasDebugOverlay`** draws one entity's attributes, active effects, abilities and tags over the game itself, so it also works away from the editor and while the game is paused;
- **`GasDebugCommands`** answers console lines - `gas.list`, `gas.attributes Hero`, `gas.activate Hero Fireball` - as text, for whatever console the game already has;
- **`GasDebugOptions`** switches costs and cooldowns off in debug builds, without touching an attribute or a tag;
- in the editor, the **Debugger** dock gains a **GAS_Engine** tab for each running game: the same four pages, kept current while it runs, and each entity's events newest first - refused commits and activations included.

Authored effects are checked by `GameplayAssetValidator`, and the **Gameplay Effect** bottom panel shows its findings for the effect it has open.

## Effect context

`GameplayEffectContext` carries typed game metadata rather than an unrestricted dictionary.

The built-in context can represent:

- instigator;
- causer;
- ability handle;
- source object;
- typed target data;
- extensible typed payload objects.

Games can define their own context payload classes for information such as weapon metadata, critical-hit data, surfaces, combat provenance, or project-specific schemas without requiring those concepts to become permanent fields in GAS_Engine.

## Optional integrations

The addon contains optional integration bridges for:

- **Dialogic** - timelines send gameplay events and add or remove tags;
- **GLoot** - equipping an item into a bound slot grants the abilities, passive effects and tags a catalog lists for it, and unequipping takes back exactly what was granted;
- **QuestSystem** - quests becoming available, accepted or completed send gameplay events, and gameplay events count as quest progress.

None of them is required by the core runtime. The integrations are intentionally kept at narrow public API boundaries so installing one optional addon does not turn it into an architectural dependency of the gameplay system.

Certified integration versions and third-party dependency information are documented in `THIRD_PARTY.md`, and each bridge has a page in the [manual](documentation/docs/guides/integrations/).

### Dialogic

A timeline reaches the ability system through Dialogic's own signal event, and nothing else. Put a `DialogicGasBridge` in the scene and bind it to the ability system a dialogue speaks for, on a channel you name:

```gdscript
var bridge: DialogicGasBridge = DialogicGasBridge.new()
add_child(bridge)
bridge.bind_installed(get_tree(), player_asc, &"Player")
```

A writer then adds a signal event whose argument is a dictionary. `bridge` addresses this addon, `channel` picks which bound ability system it is for, `command` is one of the three below, `tag` is the tag it is about, and `magnitude` is an optional number the event carries:

```text
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"send_event","tag":"Event.Dialogue.Accepted","magnitude":3}"]
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"add_tag","tag":"State.Sworn"}"]
[signal arg_type="dict" arg="{"bridge":"GAS_Engine","channel":"Player","command":"remove_tag","tag":"State.Sworn"}"]
```

- `send_event` sends a gameplay event. It wakes whatever ability is triggered on that tag or on a parent of it; a dialogue never activates an ability directly, so it cannot fire a cast the activation gate would have refused.
- `add_tag` and `remove_tag` grant and take away a loose tag.

The signal bus is shared with the rest of the game. A message addressed to another bridge or another channel is ignored without a word; one addressed to this bridge that is malformed — no channel, an unknown command, a tag that is not a tag, a magnitude that is not a number — is refused, and `command_rejected` says which.

## Ability Composer

The Composer is a visual editor for abilities that is a **view of the code**, not a second way to author them. There is no JSON, no cached graph, no `.tres`, no interpreter: the `.gd` file is the ability, and the canvas is read out of it every time it is opened. Opening an ability and saving it without changing anything gives the file back byte for byte, comments and formatting included.

Open it from **Project → Tools → Ability Composer**. It finds the abilities in your project for you — every script whose base chain reaches `GameplayAbility`, however many classes deep — and offers them; if you have exactly one, it simply opens it. Whatever the Script editor has open is drawn straight away when it is an ability, so moving between the two views costs nothing. The **Code** button in the top bar takes you back to the same file as text.

The list is kept between openings and refreshed whenever the editor reports a change on disk, with **Re-scan abilities** in the picker for anything that misses and **Browse** for a file you would rather point at yourself.

**New ability** writes an ability's script and, beside it, the scene `give_ability()` takes. Values are edited in the Composer's own Inspector; an execution cable is the order of statements in the file, a data cable is a typed local passed as an argument, and branches and matches are drawn from `if` and `match`. The **Output** panel lists everything wrong with the open ability, each row at a line - an ability with errors still saves, so a half-finished one can be put down and picked up later. Opening another ability with unsaved changes asks first, and closing the editor writes a recovery copy.

### What it can draw

An ability body is drawn when every line of it is one of these:

- a call to an engine method, with whatever it takes between its brackets;
- an assignment — to a local with a written type, or to a property;
- `await` on a signal, or on an ability task through the task -
  `await wait_delay(1.5).completed()`, which is what the palette writes. An
  `await` on the call itself does not wait (it takes the task and carries on),
  and the Output panel says so on that card;
- `if` / `elif` / `else`;
- `match`, with arms that are one name, one written-out value, or `_`;
- `return`;
- `super()`;
- `pass`.

Anything else is **kept**: it stays in the file byte for byte, is drawn as one card that cannot be edited, and the Output panel gives the line and the reason. Nothing around it is locked — the rest of the ability stays editable:

- `for` and `while` — a loop has no single place on a canvas, so the whole loop is one kept card;
- an inline `func` or `lambda` — code the graph cannot show;
- `assert` and `breakpoint` — a debugger statement has no node;
- `continue` and `break` — loop keywords;
- two calls side by side, such as `open() + shut()` — neither one is the statement;
- a local without a written type, such as `var level := 1.0` — a port shows the type of what flows through it, and inferring one would let the canvas and the file disagree until somebody ran the game.

Move a kept statement into a helper method of the same script and call the helper, and the call is drawn. Only an ability with no `_activate_ability()` of its own — one that inherits the body and overrides hooks — opens read-only, because there is nothing of its own to draw.

### Putting a node down

Click a call in the palette to write it after whatever is selected, or drag it
onto the canvas and drop it where you want it — a drop onto a card writes after
that card, a drop onto empty canvas writes at the end. Space opens a finder that
searches the same vocabulary by typing.

Click a group's header to open it, and click it again to close it.

### What is on the palette

Every method of `GameplayAbility`, `AbilitySystemComponent`, `GameplayTargetingService`, `AbilityTaskFactory` and `GameplayAbilityTargetData` whose doc comment carries an `## @composer` annotation, read from those scripts rather than listed anywhere. `## @composer: Group` files it under a named group, `## @composer_name:` gives it a title, and `## @composer_deprecated:` keeps it offered but marked with what to use instead. Methods the runtime only uses internally carry no annotation and are not offered. An annotated method added to the engine appears the next time the editor starts; one that is renamed takes its node with it.

A game can offer calls of its own through `ComposerCatalog.register(method, group, path, suspends)`, and they are admitted on exactly the same terms the engine's own are. There are no privileged nodes: every node prints as its own call and reads back the same way, so a custom one needs a signature and nothing else.

### It never reaches a running game

Nothing outside `addons/GAS_Engine/editor/` names anything inside it, so there is no path by which a running game loads any part of the Composer. That is checked by the test suite rather than promised here.

The [Ability Composer guide](documentation/docs/guides/ability-composer/index.md) covers every gesture, menu and key, and the [tutorial](documentation/docs/tutorials/build-an-ability-in-the-composer.md) builds an ability in it from scratch.

## Examples

- **`addons/GAS_Engine/reference/`** - six complete abilities, written by hand and commented, each adding one idea to the last: an instant hit (`instant_damage.gd`), a paid strike (`costly_strike.gd`), a timed buff (`timed_buff.gd`), an aimed-then-confirmed blast (`confirmed_blast.gd`), an area sweep (`sweeping_volley.gd`), and one that fires cues (`cued_dash.gd`). All six open in the Ability Composer.
- **`examples/action_sample/`** - a 3D hero with a loadout: an instant strike, a channel with a persistent cue, and an aimed ground slam with a reticle and a preset, three dummies to hit, and the runtime overlay. Play `examples/action_sample/main.tscn` inside this repository; it also runs as a project of its own, and as an authority and a client over ENet. Its [README](examples/action_sample/README.md) and the [walkthrough](documentation/docs/tutorials/action-sample-walkthrough.md) explain it.

## Repository layout

| Path | Holds |
|---|---|
| `addons/GAS_Engine/` | The addon - the only folder a game copies. |
| `addons/gut/` | GUT, vendored for the test suite. |
| `gas_engine/` | This project's own tag and cue registries, as the plugin writes them into any host project. |
| `documentation/` | The manual. |
| `examples/action_sample/` | The action sample. |
| `test/` | The GUT suite - `unit/`, `integration/`, `parity/` and `perf/` - with its fixtures. |
| `tooling/` | `verify.ps1`, the gates, and the scripts behind them. |
| `artifacts/` | Committed receipts: gate, parity and dependency evidence. |

The integration sandbox - the turn-based RPG under [Proven in a real game](#proven-in-a-real-game) - lives on its own orphan branch, `godot-open-rpg_GAS_Engine`, and is never merged into `main`.

## Runtime architecture

The `AbilitySystemComponent` acts as a facade rather than a single god object.

Mutable responsibilities are separated into focused runtimes:

- abilities - grants, activation lifecycle, instancing, activation policy, queries, tag semantics and cooldowns;
- ability tasks;
- attributes;
- effects - with their components, stacking, inhibition, effect chains and live magnitudes;
- gameplay tags;
- gameplay events;
- cue parameters, with playback and pooling in the `GameplayCueManager` autoload;
- networking - activations, requests, state and batches - one runtime per process rather than per component;
- a debug channel per component.

Targeting has no runtime of its own: `GameplayTargetingService` queries and presets produce target data per call, and a provider lives exactly as long as the aim it belongs to.

The goal is simple: every important piece of mutable state should have one clear owner.

## Correctness model

### Atomic failure

An operation that cannot be evaluated correctly is refused rather than partially committed.

Examples include:

- division by zero;
- non-finite values;
- invalid modifier references;
- unknown attributes;
- ambiguous writes;
- invalid effect chains;
- rejected application requirements.

When evaluation fails, GAS_Engine does not intentionally leave behind partial attribute mutations, active-effect registrations, granted tags, cues, or events.

### Stable handles

Abilities and active effects are addressed by handles rather than relying on mutable object references as identity.

This keeps runtime identity stable across systems such as removal, queries, stacking, granted abilities, tasks, and cues.

### Strict typing

The project treats GDScript typing as an architectural constraint rather than editor decoration.

Domain contracts avoid generic dictionaries where a closed type can express the same rule more safely.

## Verification

The repository itself is the executable specification: important gameplay rules are expected to have tests rather than exist only as comments or documentation claims.

```bash
# The GUT suite, headless. It ends with a line a runner reads:
# GAS_ENGINE_GUT_RESULT: PASS passed=N failed=0 pending=0 orphans=0
godot --headless --path . res://test/gut_headless_runner.tscn

# The gate chain. It ends with GAS_ENGINE_VERIFY_PASS or GAS_ENGINE_VERIFY_FAIL.
pwsh -File tooling/verify.ps1
```

`verify.ps1` runs, in order: the policy seal, the gates' own self-tests, the project invariants, the product identity check, the parity receipts and the self-test of their checker, the file and function size gate, the test-location gate, the magic-string gate, the duplicated-logic gate, the engine evidence for the import and the suite, and `git diff --check`. The engine evidence is checked against a content fingerprint of every tracked script and scene, so a receipt from before a change does not count for after it.

Beyond the chain, work is held to:

- zero test failures and zero orphan nodes after the suite;
- a strict typing pass - `tooling/strict_typing_pass.py` switches the project to warnings-as-errors with the addon included, for validating every script, and back;
- a fresh clone imported cold, where an uncommitted `.uid` file or local state cannot hide;
- bounded file and function size, and duplicated-logic review;
- deterministic gameplay arithmetic;
- the harnesses on the sandbox branch, above.

A suite proves the framework against itself. What a real game proved it does is at the top of this file, under [Proven in a real game](#proven-in-a-real-game).

## License

GAS_Engine uses a **source-available dual licensing model**.

### Community Use License: free

The root [`LICENSE`](LICENSE) contains the **GAS_Engine Community Use License 1.0**.

It allows you to use the **unmodified** GAS_Engine framework free of charge in:

- personal games;
- hobby projects;
- prototypes and demos;
- educational projects;
- free games;
- open-source games;
- proprietary games;
- commercial games.

You may sell and commercially distribute a game that uses unmodified GAS_Engine. You do **not** owe a royalty, revenue share, per-seat fee, or per-game fee merely because your game makes money.

Your game's own source code does not have to become open source simply because it uses GAS_Engine.

### What you may build on it

GAS_Engine is designed to be extended **around its public APIs**, not by editing framework internals for every game-specific mechanic.

Under the free Community Use License, you may build game-specific systems using techniques such as:

- composition;
- subclasses;
- resources and authored data;
- custom magnitude calculations;
- typed context payloads;
- adapters and integration scripts;
- project-side ability/effect definitions;
- public runtime APIs and signals.

These forms of normal game development do not become paid merely because the resulting game is commercial.

### Commercial Modification License: paid

A separate paid license is required if you want to exercise rights reserved by the Community Use License, including:

- modifying GAS_Engine source files;
- distributing a modified version of GAS_Engine;
- maintaining an authorized modified framework branch under commercial terms;
- creating or distributing a derivative framework based on copyrightable GAS_Engine code;
- redistributing GAS_Engine as a standalone development product beyond the Community Use Grant.

See [`COMMERCIAL-LICENSE.md`](COMMERCIAL-LICENSE.md) for the commercial licensing model.

**Commercial game does not mean commercial modification.**

A studio can sell a game built with unmodified GAS_Engine under the free Community Use License. The paid license applies when the studio wants to modify or derive from **GAS_Engine itself**.

### Source-available, not OSI open source

GAS_Engine source is publicly readable, but the Community Use License reserves modification and derivative-framework rights. For that reason, the project should be described as **source-available**, not as OSI-approved open source.

### Third-party material

Third-party software, where present, retains its own applicable license terms. Those notices are documented separately in `THIRD_PARTY.md` and do not relicense GAS_Engine itself.

## Copyright

Copyright © 2026 MaliciaInc.

GAS_Engine and its original source code are distributed under the terms in [`LICENSE`](LICENSE). Modification and derivative-development rights beyond that grant require a separate written commercial agreement as described in [`COMMERCIAL-LICENSE.md`](COMMERCIAL-LICENSE.md).
