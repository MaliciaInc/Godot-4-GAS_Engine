# GAS_Engine

**GAS_Engine** is a production-oriented Gameplay Ability System for **Godot 4.7.2**, built for games that need deterministic attributes, effects, abilities, gameplay tags, targeting, cues, and extensible combat rules without turning gameplay state into a pile of loosely typed dictionaries and side effects.

It is developed as a standalone reusable Godot addon.

> **License model:** use GAS_Engine unmodified in personal or commercial games for free. Modifying GAS_Engine itself, distributing modified versions, or creating a derivative framework requires a separate paid Commercial Modification License.

See [License](#license) for the exact distinction.

## Requirements

| | |
|---|---|
| Godot | **4.7.2** |
| Language | GDScript |
| Dependencies | none |

The exact patch version is named rather than "4.7" because GDScript warnings promoted to errors can change between patch releases, and this framework is strictly typed throughout.

## Installation

1. Copy the `addons/GAS_Engine/` folder into your project's `addons/` folder.
2. **Project → Project Settings → Plugins**, and tick **GAS_Engine**.

Enabling the plugin adds one autoload, `GameplayCueManager`. If your project already declares an autoload by that name, GAS_Engine leaves your declaration alone and warns rather than overwriting it.

That is the whole installation. There is no build step, and nothing needs configuring before the next section works.

## Quick start: a fireball in five minutes

Two scripts and a scene. Everything below is plain GDScript that runs the moment you save it.

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

A **GameplayEffect** is what an ability lands. It is built in code, from numbers the ability already declares:

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

A character is any node with an `AbilitySystemComponent` **as a child named `AbilitySystemComponent`**. The component asks its parent what effects and cues act on, so it is never an orphan.

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

Put the same component on a second node, add that node to the `enemies` group, and the fireball takes it from 100 health to 70.

Read a value back with `asc.get_attribute_current(&"health")`, and watch it move by connecting `asc.attribute_changed`.

### Why the effect is built in code

Effects, costs and cooldowns are built in GDScript from numbers authored on the ability's scene, never as an authored resource beside them. There is deliberately no authored-resource alternative sitting beside them: two ways to say what an ability does is two places to look when it does the wrong thing, and the hand-written one is the one nothing can check.

### Where to go from here

- `addons/GAS_Engine/reference/` holds six complete abilities, written by hand and commented: an instant hit, a paid strike, a timed buff, an aimed-then-confirmed blast, an area sweep, and one that fires cues.
- The **Ability Composer** below draws any ability as a graph, and writes your edits back to the same file. Choose it from **Project → Tools** and it finds your abilities for you.
- The rest of this document explains what each subsystem guarantees, and why.


## Scope and support model

### Project Model

GAS_Engine is **source-available** and **free for use in games**.

GAS_Engine is maintained centrally by **MaliciaInc**. Bug reports and feature requests are handled through GitHub Issues. External modifications are not part of the supported distribution model.

### Networking

GAS_Engine does **not** provide built-in network replication, client-side prediction, reconciliation, or other multiplayer networking infrastructure.

Networking is intentionally outside the scope of the framework and may be implemented separately according to the needs of each project.

## Proven in a real game

A suite proves a framework against itself. It cannot prove that a game built on
the framework behaves, and several of this engine's defects were found exactly
there - invisible to every assertion in the suite, and plain the first time a
game used the engine for real.

So the engine is also driven through a complete integration: a turn-based RPG
whose combat system is built on GAS_Engine and nothing else. An automated probe
plays real battles from a fixed seed, through the same seams a player goes
through, and records what the engine did at the top of every round.

| Checked | Observed |
| --- | --- |
| Attribute isolation | Three battlers built from one authored `AttributeSet`. Damaging one left it at `0/50` and the other two at `50/50`. |
| Ability cost | Refused as `INSUFFICIENT_RESOURCES` while the resource was short, allowed on the round it arrived. |
| Attribute clamping | A heal on a wounded battler stopped exactly at the ceiling instead of overflowing it. |
| Downed targets | A defeated battler left the target set and could not be aimed at again. |
| Cross-battle persistence | Authored resources were not written through. A second battle began from the authored values, not from the first battle's damage. |
| Turn-based cooldown | Refused as `ON_COOLDOWN` for exactly the declared number of turns - including a round where the cost was affordable and the refusal stood - then allowed. |

The engine emitted no errors across the run. The probe, the arenas and the
transcript live on the `godot-open-rpg_GAS_Engine` branch, and the seed is
recorded so a run can be repeated and disagreed with.

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

- manual activation;
- activation on grant;
- gameplay-event activation;
- passive abilities;
- activation by stable ability handle;
- cancellable ability tasks;
- transactional costs and cooldown commits;
- removal policies for active abilities;
- gameplay-tag requirements, blocking, and cancellation;
- target requirements enforced by the runtime rather than left to UI code.

An activation returns a typed result describing what happened instead of collapsing every failure into a generic boolean.

### Attributes

Attributes separate durable base state from derived current state.

The standard aggregation model is:

```text
current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
```

followed by the last applicable override and the effective clamp.

This means, for example, that a base value of `10`, an additive `+10`, and a multiplier of `x2` resolve to `40`, not `30`.

Base and effective-value clamps are separate hooks so temporary presentation constraints cannot silently corrupt durable state.

### Gameplay effects

Gameplay effects support:

- instant, duration, infinite, periodic, and turn-aware behavior;
- atomic evaluation and commit;
- typed modifier magnitudes;
- scalable values;
- attribute-based magnitudes;
- SetByCaller values;
- custom magnitude calculations;
- stacking policies and overflow behavior;
- application, ongoing, and removal tag requirements;
- effect immunity;
- effect inhibition without destroying runtime identity;
- chained additional effects;
- granted abilities;
- pre/post gameplay-effect execute hooks;
- explicit removal reasons;
- bounded effect-chain recursion.

A failed application leaves no half-applied modifiers, tags, cues, registrations, or observable partial state behind.

### Gameplay tags

Gameplay tags are hierarchical and query-driven.

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

### Targeting

GAS_Engine supports typed targeting in both **2D and 3D**.

The targeting boundary handles:

- traces;
- overlaps;
- target-data conversion;
- duplicate collider resolution;
- self-filtering;
- ability-system resolution;
- per-target application copies.

One actor represented by several colliders resolves as one gameplay target rather than several accidental hits.

### Gameplay cues

Gameplay cues provide cosmetic feedback without making visual effects part of authoritative gameplay state.

The cue system supports:

- one-shot execution cues;
- periodic cues;
- persistent cue lifecycle;
- typed cue parameters;
- cue handles;
- pooling;
- effect-handle association;
- clean activation and removal when effects become inhibited or active again.

A missing cosmetic cue cannot invalidate gameplay application.

### Ability tasks

The task layer provides reusable asynchronous gameplay operations owned by an ability lifecycle.

Examples include waiting for:

- delays;
- input;
- target data;
- gameplay events;
- attribute changes and thresholds;
- tag changes and tag queries;
- gameplay-effect application/removal/stack changes;
- ability activation/end;
- confirmation or cancellation;
- repeated runtime ticks;
- animation completion.

Ending or cancelling an ability cancels the tasks it owns, and each task completes exactly once.

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

- **Dialogic**;
- **GLoot**;
- **QuestSystem**.

None of them is required by the core runtime. The integrations are intentionally kept at narrow public API boundaries so installing one optional addon does not turn it into an architectural dependency of the gameplay system.

Certified integration versions and third-party dependency information are documented in `THIRD_PARTY.md`.

## Ability Composer

The Composer is a visual editor for abilities that is a **view of the code**, not a second way to author them. There is no JSON, no cached graph, no `.tres`, no interpreter: the `.gd` file is the ability, and the canvas is read out of it every time it is opened. Opening an ability and saving it without changing anything gives the file back byte for byte, comments and formatting included.

Open it from **Project → Tools → Ability Composer**. It finds the abilities in your project for you — every script whose base chain reaches `GameplayAbility`, however many classes deep — and offers them; if you have exactly one, it simply opens it. Whatever the Script editor has open is drawn straight away when it is an ability, so moving between the two views costs nothing. The `Code` chip takes you back to the same file as text.

The list is kept between openings and refreshed whenever the editor reports a change on disk, with **Re-scan abilities** in the picker for anything that misses and **Browse** for a file you would rather point at yourself.

### What it can draw

An ability body is drawn when every line of it is one of these:

- a call to an engine method, with whatever it takes between its brackets;
- an assignment — to a local with a written type, or to a property;
- `await`, on an ability task or on a signal;
- `if` / `elif` / `else`;
- `match`, over an enum;
- `return`;
- `super()`;
- `pass`.

Everything else opens **read-only**, with the line and the reason on the Output panel. This is not an error in your file — it is the Composer saying it cannot draw something, and declining to touch a file it does not fully understand:

- `for` and `while` — a loop has no single place on a canvas;
- an inline `func` or `lambda` — code the graph cannot show;
- `assert` and `breakpoint` — a debugger statement has no node;
- `continue` and `break` — loop keywords;
- two calls side by side, such as `open() + shut()` — neither one is the statement.

A local must carry a written type. `var level := 1.0` is refused where `var level: float = 1.0` is drawn, because a port shows the type of what flows through it and inferring one here would let the canvas and the file disagree until somebody ran the game.

### Putting a node down

Click a call in the palette to write it after whatever is selected, or drag it
onto the canvas and drop it where you want it — a drop onto a card writes after
that card, a drop onto empty canvas writes at the end. Space opens a finder that
searches the same vocabulary by typing.

Click a group's header to open it, and click it again to close it.

### What is on the palette

Every public method of `GameplayAbility`, `AbilitySystemComponent`, `GameplayTargetingService`, `AbilityTaskFactory` and `GameplayAbilityTargetData`, read from those scripts rather than listed anywhere. A method added to the engine appears the next time the editor starts; one that is renamed takes its node with it.

A game can offer calls of its own through `ComposerCatalog.register(method, group, path, suspends)`, and they are admitted on exactly the same terms the engine's own are. There are no privileged nodes: every node prints as its own call and reads back the same way, so a custom one needs a signature and nothing else.

### It never reaches a running game

Nothing outside `addons/GAS_Engine/editor/` names anything inside it, so there is no path by which a running game loads any part of the Composer. That is checked by the test suite rather than promised here.

## Runtime architecture

The `AbilitySystemComponent` acts as a facade rather than a single god object.

Mutable responsibilities are separated into focused runtimes for areas such as:

- abilities;
- activation policy;
- ability tasks;
- attributes;
- effects;
- stacking;
- effect chains;
- gameplay tags;
- cooldowns;
- cues;
- events;
- targeting.

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

The repository contains an automated GUT test suite and a headless runner.

The project is developed against structural and behavioral gates including:

- strict parsing of framework scripts;
- zero test failures;
- zero orphan nodes after the suite;
- reproducible fresh-project import behavior;
- bounded file and function size;
- duplicated-logic review;
- deterministic gameplay arithmetic.

The repository itself is the executable specification: important gameplay rules are expected to have tests rather than exist only as comments or documentation claims.

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
