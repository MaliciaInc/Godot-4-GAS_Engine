# Arhalies GAS

A Gameplay Ability System for Godot 4.7.2: attributes, effects, tags, abilities,
events and cues, with the arithmetic pinned down and tested.

A fork of [GodotGAS](https://github.com/yulrun/godot-gas) (MIT, Matthew Janes /
YulRun), rewritten deeply enough that it is no longer the same engine. It is the
combat foundation of the RPG *Arhalies*, and it is built before the game.

## Features

- **Transactional ability commit.** Paying for an ability is one operation with
  one outcome. Cooldowns go on first, the cost is charged second, and if the
  charge fails the cooldowns are taken back off - an ability is never left on
  cooldown for something the caster did not pay for. The result is a typed
  value naming what happened, not a bare `false`.
- **Absolute and percentage costs.** A cost is a fixed amount, or a percentage
  of any attribute's base or current value - 10% of MaxMana, 5% of Health.current,
  25% of Attack.base. A fraction is 0.0 to 1.0; anything outside that range is
  refused, as is a non-finite one. Several costs on the same attribute are
  aggregated into one charge before affordability is asked. A percentage is
  resolved once, against the attributes as they stand, and the resulting amount
  is what the commit charges - a buff that raises what an attribute shows never
  creates durable funds a percentage can spend that were not there before it.
  A multiplier, a divisor, an override or an execution calculation still cannot
  express a cost: only an absolute amount or a percentage can.
- **Cancellable ability tasks.** Waiting for a delay, an input, a gameplay
  event or target data is a task the ability owns. Ending, cancelling or
  removing the ability cancels every task it started, and a task reports
  finishing exactly once whether it succeeded or was cancelled.
- **Typed cooldown state.** How long an ability has left, in seconds or in
  turns, answered by asking rather than by reading the tag stack. Asking
  changes nothing.
- **2D and 3D targeting.** Traces and overlaps in either space, converted once
  at the physics boundary into typed hits. One actor wearing several colliders
  arrives as one target, the caster is left out of its own sweep, and anything
  without an ability system is not a target.
- **Typed modifier magnitudes.** A modifier's "how much" is a
  `GameplayScalableMagnitude` (a flat value, optionally scaled by a curve
  against the effect's level), a `GameplayAttributeBasedMagnitude`
  (`((captured + pre_add) * coefficient) + post_add`, from a source or target
  attribute), a `GameplaySetByCallerMagnitude` (a value the caster supplies at
  cast time, required or defaulted), or a `GameplayCustomMagnitude` (an
  arbitrary calculation). An attribute-based magnitude may capture LIVE - a
  persistent contribution then updates on its own as the captured attribute
  moves, with a direct self-reference refused outright and an indirect
  reaction cycle bounded so it cannot hang a frame.
- **Optional official bridges** for Dialogic, GLoot and QuestSystem. See below.

## The arithmetic

For every attribute, exactly this, and nothing else may implement it:

```text
current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
```

then the last applicable OVERRIDE, then the effective clamp.

**Base 10, with +10 and x2, is 40.** Not 30. Adds are summed before multipliers
apply; multipliers compound with each other rather than becoming additive
percentages, so x1.5 twice is x2.25.

`base_value` is the durable underlying value after permanent and instant
changes, with no active contributions applied. `current_value` is what the base
becomes once the active stack and the clamp are applied. It is derived, never a
second source of truth.

### Last applied override wins

Between effects, the OVERRIDE from the later application wins. Within one
effect, the higher modifier index wins. Removing the winner makes the previous
one visible again — an outranked override was never destroyed, only outranked.

### Two clamps, not one

```gdscript
pre_attribute_base_change(attribute_name, proposed_base_value)   # guards the durable value
pre_attribute_change(attribute_name, proposed_current_value)     # guards the derived value
```

With only the second, 500 damage against 100 health leaves `base = -400` while
the display clamps to 0, and a later heal of 30 arrives at 0 rather than 30.

### Failure is atomic

An application either happens entirely or not at all. A division by zero, a
non-finite value, an unknown attribute or an out-of-range modifier index refuses
the whole thing: no attribute moves, no effect registers, no tag is granted, no
cue plays, no event is dispatched, and no partial signal is emitted.

An attribute written by both an execution calculation and a standard modifier in
one evaluation has no defined order, so it fails with
`AMBIGUOUS_ATTRIBUTE_WRITE` rather than the engine picking one and being quietly
wrong.

## What differs from upstream

- **Runtime specs are isolated per application and per target.** An AoE gives
  each target its own spec and context; upstream passed one mutable spec to
  every target.
- **Attributes have a real aggregator.** Contributions are typed and
  recomposition recomputes from scratch. Upstream applied a flat delta per
  modifier and reversed it on removal, which is order-dependent and cannot
  recover.
- **Magnitudes are keyed by modifier index**, so an effect with `Attack +10` and
  `Attack x2` keeps both. Upstream keyed by attribute name and the second
  overwrote the first.
- **A magnitude is a typed Resource, not a bare float plus an optional
  Curve.** Attribute-based, SetByCaller and custom-calculation magnitudes
  resolve once per evaluation and are cached for its duration, so a PERIODIC
  tick never answers with a value an earlier tick resolved.
- **Base and effective clamps are separate hooks.**
- **Preview and commit share one evaluator**, so a cost prediction cannot
  disagree with the payment it predicted.
- **Periodic and turn lifecycles are tested**, and ticks derive from elapsed
  time rather than a countdown, so a long frame pays every tick it owes.
- **Events match hierarchically in one direction.** `Event.Damage` receives
  `Event.Damage.Critical`, but not `Event.Damages`, and never its own ancestor.
- **Event and cue payloads are typed**, not `Variant` and `Dictionary`.
- **Target hits are typed**, converted once at the physics boundary.
- **Networking is removed.** The behaviour of this release is local.
- **GDScript strict typing is mandatory**: no `:=`, no `Variant` or `Dictionary`
  as a domain contract, and eight warnings promoted to errors.
- **Hard structural limits, enforced rather than intended**: 450 lines per
  file, 120 per function, no repeated literal that could have been named,
  no duplicated logic.

## Layout

```text
addons/GodotGAS/
  abilities/       GameplayAbility, the transactional commit, typed results
  abilities/tasks/ cancellable async ability tasks
  attributes/      AttributeData, AttributeSet, the aggregator, typed results
  components/      the ASC facade, ability runtime, tag runtime
  cooldowns/       typed cooldown state
  effects/         the pure evaluator, the effect runtime, the scheduler
  magnitudes/      typed modifier magnitudes: scalable, attribute-based,
                   SetByCaller, custom calculations
  events/          typed event data and hierarchical dispatch
  cues/            typed cue params, pooling
  gameplay_tag/    the tag registry and its one grammar
  target_data/     typed hits and effect context
  targeting/       ASC resolution and 2D/3D acquisition
  integrations/    optional official bridges
  managers/        the GameplayCueManager autoload
  utilities/       project settings, the GDScript the generators emit
  editor/          the dashboard
addons/gut/        GUT v9.7.1, vendored and immutable
godot_gas/         the tag and cue registries, and the constants generated
                   from them
test/              fixtures, the unit suite, the headless runner
```

The `AbilitySystemComponent` is a facade. Tags, attributes, effects, timing and
abilities each live in their own runtime, so every piece of mutable state has
exactly one owner.

## Optional integrations

Three bridges ship with the addon: one for [Dialogic](
https://github.com/dialogic-godot/dialogic), one for
[GLoot](https://github.com/peter-kish/gloot), and one for
[QuestSystem](https://github.com/shomykohai/quest-system).

**The core works without any of them.** None of the three is included in this
repository, none is a dependency, and nothing in the engine requires one to be
installed. Each bridge detects whether its addon is actually present and
validates the surface it needs before connecting to anything; on a project
without that addon it declines quietly instead of failing.

Each bridge depends on the smallest published surface it can: a single signal,
a single node shape. It does not reach into subsystems, internal pools or
editor structure, so a release that changes those does not change this.

The certified versions are in `THIRD_PARTY.md`. Later versions may well work,
but only the certified ones are a guarantee of this release: compatibility was
established by running these bridges against those exact commits, and a version
that has not been through that is a reasonable expectation rather than a
promise.

## Running the tests

Open the project in Godot and run the suite from the GUT panel against
`res://test/unit`. Everything the suite needs is in this repository.

Let the first import finish before running it. A project that has never been
imported has no global class cache, and GUT's own configuration needs one.

`test/gut_headless_runner.tscn` runs the same suite without the panel and writes
its verdict to a file. It refuses two greens the assertions cannot see: a run
where fewer scripts loaded than exist on disk, and a run that leaves orphan
nodes behind. The verdict is timestamped, so a stale one cannot be read as a
fresh pass.

## The autoload constraint

Godot initialises autoloads before it has scanned the project for `class_name`
declarations, so a global class name does not resolve inside an autoload or
anything it preloads. In that closure a reference must be a `preload`:

```gdscript
const CueParams = preload("res://addons/GodotGAS/cues/gameplay_cue_params.gd")
```

A type annotation survives without the cache; an identifier does not. `->
GameplayCueParams` parses where `GameplayCueParams.new()` fails with *Identifier
not found* - which is why four scripts in that closure preload themselves under
an alias and construct through it.

None of this shows on a machine that has opened the project before, because
`.godot/global_script_class_cache.cfg` already exists there. It shows on a fresh
clone, and nowhere else, which is why it is written down here rather than
left to be rediscovered.

Everywhere outside that closure, global class names are the right thing to use.

## How this is verified

Every change is held to the same standards. They are written here rather than
asserted, so they can be checked against the code:

- no file over 450 lines and no function over 120;
- no repeated literal that could have been named, and no duplicated logic;
- every script under `addons/GodotGAS/` parses with the eight warnings above
  promoted to errors;
- the suite passes with zero failures and zero orphan nodes;
- a checkout containing only the tracked files imports and runs that suite.

The suite is here and is the part you can run yourself.

## Strict typing

`project.godot` promotes eight GDScript warnings to errors. Godot excludes
`addons/` from warnings by default, which would exempt the entire engine - the
engine lives in `addons/GodotGAS/` - and setting `exclude_addons=false`
permanently is impossible, because the vendored GUT is not strictly typed and
fails to parse under it, taking the suite with it.

So the project ships permissive and is verified strict: the flag is flipped,
every engine script is validated, and it is flipped back. Neither mode weakens a
warning. Only the trees they apply to differ.

## Licence and attribution

MIT. See `LICENSE` for the upstream copyright and `THIRD_PARTY.md` for the
pinned dependencies. This is a fork and is no longer byte-identical to upstream
GodotGAS; it does not claim to be. `addons/gut` is unmodified and matches its
pin.
