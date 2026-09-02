# GAS_Engine

**GAS_Engine** is a production-oriented Gameplay Ability System for **Godot 4.7.2**, built for games that need deterministic attributes, effects, abilities, gameplay tags, targeting, cues, and extensible combat rules without turning gameplay state into a pile of loosely typed dictionaries and side effects.

It is developed as a standalone reusable Godot addon.

> **License model:** use GAS_Engine unmodified in personal or commercial games for free. Modifying GAS_Engine itself, distributing modified versions, or creating a derivative framework requires a separate paid Commercial Modification License.

See [License](#license) for the exact distinction.

## Proven in a real game

A suite proves a framework against itself. It cannot prove that a game built on
the framework behaves, and several of this engine's defects were found exactly
there - invisible to thirty thousand assertions, and plain the first time a game
used the engine for real.

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

## Using GAS_Engine in a game

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

Third-party software or historical third-party portions, where present, retain their own applicable license terms. Those notices are documented separately in `THIRD_PARTY.md` and do not make the root GAS_Engine project MIT-licensed.

## Copyright

Copyright © 2026 MaliciaInc.

GAS_Engine and its original source code are distributed under the terms in [`LICENSE`](LICENSE). Modification and derivative-development rights beyond that grant require a separate written commercial agreement as described in [`COMMERCIAL-LICENSE.md`](COMMERCIAL-LICENSE.md).
