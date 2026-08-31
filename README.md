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
- **Effects are composed from components, not a growing bag of flags.**
  `GameplayEffectComponent` is immutable authored data - target tags,
  application tag requirements, chance to apply, a custom can-apply
  requirement, UI data - never per-application state. Preflight
  (`validate` → every `can_apply`) refuses before anything observable
  happens; preparation is ephemeral and reversible; a rejection at either
  stage discards everything already prepared, in reverse order.
  `apply_effect_spec_result()`/`apply_gameplay_effect_result()` return one
  typed `GameplayEffectApplicationResult`, with the F2 `ActiveGameplayEffect`
  getters kept as thin wrappers over it.
- **Active effects are addressed by handle, not by reference.**
  `GameplayEffectHandle` identity is `(owner ASC, monotonic id)` - never
  reused, never resolving on a different ASC even when the numeric id
  matches. `GameplayEffectQuery` is a declarative, AND-combined filter (asset,
  effect definition, granted/source/target tags, source actor, modified
  attribute) used to find, count or remove active effects; target tags are
  read live from the target ASC, source tags are a snapshot taken once at
  application. `GameplayEffectRemoveOtherEffectsComponent` replaces the old
  flat tag array with a query, resolved before the new effect is evaluated.
- **Immunity moves to the target's own state.** A `GameplayEffectImmunity-
  Component`, carried by an effect already active on the target, blocks any
  incoming application its `GameplayEffectQuery` matches - asset/granted/
  source tags, definition, modified attribute, and the target's own live
  tags - before the incoming effect's own preflight, purge or evaluation
  ever run. Fireball never has to know every ward that might stop it; the
  ward declares what it stops. The first matching immunity wins; removing
  it lets the same application through again.
- **An active effect can stay registered but inhibited.**
  `GameplayEffectTargetTagRequirementsComponent` gains `ongoing_query` and
  `removal_query` alongside `application_query`. While `ongoing_query` fails,
  the effect's contributions and granted tags detach - the clock, the
  registration and the logical receipt of what it grants all survive - and
  they reattach unchanged the moment it is satisfied again; no
  `active_effect_added`/`removed` pair, one `active_effect_inhibition_changed`
  per real transition. `removal_query` removes the effect outright, and
  refuses application outright if already satisfied. A periodic effect's
  `period_inhibition_policy` (`SKIP_MISSED_TICKS`, default;
  `EXECUTE_IMMEDIATELY_ON_UNINHIBIT`; `RESET_PERIOD_ON_UNINHIBIT`) decides
  what happens to ticks owed while inhibited. Reevaluation runs from
  `GameplayEffectRuntime` alone, behind a reentrancy guard and a pass cap -
  an effect whose own granted tag falsifies its own `ongoing_query` settles
  inhibited rather than oscillating or hanging.
- **Stacking has identity, limits and overflow**, replacing the old
  FREE/REFRESH_DURATION pair. `stacking_type` (`NONE`,
  `AGGREGATE_BY_SOURCE`, `AGGREGATE_BY_TARGET`) decides which applications
  join one `ActiveGameplayEffect` instead of becoming independent ones;
  `stack_limit_count` (unlimited at `<= 0`) caps how far a join can grow. A
  reapplication always replaces the authoritative spec/contributions/tags
  with its own - never an incremental delta - and `factor_in_stack_count`
  decides whether a standard modifier's magnitude is scaled by the current
  count (an execution calculation is never auto-scaled; it reads
  `spec.stack_count` itself). Hitting the limit is overflow: it always
  signals and fires `overflow_effects` on the same target,
  `deny_overflow_application` refuses the join outright instead of
  accepting it as a non-growing refresh, and `clear_stack_on_overflow` can
  drop the whole stack afterward, independently of that. Overflow (and,
  from Task 13, Additional Effects) specs carry a `chain_depth`, refused
  past `GameplayEffectRuntime.MAX_EFFECT_CHAIN_DEPTH` so a cycle cannot
  recurse forever. `stack_duration_refresh_policy`/`stack_period_reset_policy`
  govern whether a successful reapplication restarts those clocks;
  `stack_expiration_policy` (`CLEAR_ENTIRE_STACK`,
  `REMOVE_SINGLE_STACK_AND_REFRESH_DURATION`, `REFRESH_DURATION`) decides
  what a naturally-expiring clock does to the stack - always restarting it,
  which is what tells a survived expiration apart from an ordinary
  reapplication.
- **Effects can chain other effects at declared lifecycle points, without a
  script.** `GameplayEffectAdditionalEffectsComponent` applies
  `GameplayEffectConditionalEffect` entries - each gated by an optional
  `target_query`/`source_query`, every configured one required to match -
  `on_application` once this effect's own application commits,
  `on_natural_expiration`/`on_premature_removal`/`on_any_removal` once it is
  removed. A typed `ActiveGameplayEffect.RemovalReason`
  (`NATURAL_EXPIRATION`, `EXPLICIT`, `CLEANSE`, `SOURCE_REMOVED`,
  `STACK_OVERFLOW`, `ASC_CLEANUP`) travels every removal path - the
  scheduler, remove-by-handle/query, the cleanser, a stack overflow, GLoot
  unequip - and decides which arrays fire; `ASC_CLEANUP` fires none. Every
  child reuses the exact `chain_depth`/`MAX_EFFECT_CHAIN_DEPTH` guard
  `overflow_effects` introduced, so a cycle refuses past the limit instead
  of recursing forever, and a child's own refusal never undoes an already-
  committed parent. `gameplay_effect_removal_finished(active_effect,
  reason)` carries the reason to listeners; `active_effect_removed` keeps
  emitting for every removal as the untyped legacy signal.
- **Effects can grant abilities while they are active.**
  `GameplayEffectGrantAbilitiesComponent` reuses Task 4's grant pipeline
  exactly - `prepare_ability_grant` in `prepare_application()`,
  `commit_prepared_grant` in `on_effect_applied()`, matching cleanup in
  `discard_prepared()` - never a second validator. Each
  `GameplayEffectAbilityGrant` names a scene, a `GameplayScalableFloat`
  level, an input slot, and a `RemovalPolicy`:
  `CANCEL_AND_REMOVE_ON_EFFECT_END` cuts a running activation off
  immediately, `REMOVE_ON_ACTIVE_END` blocks new activations and waits for
  the current one to finish, `KEEP_AFTER_EFFECT_END` never retires it. The
  granted spec's source is a typed `GameplayAbilityEffectSource`, never a
  bare `Variant`, naming the granting effect's own handle. A stack grants
  once per active effect, never once per join - a component that reads
  `GameplayEffectComponentApplyRequest.existing_active_effect` skips
  re-preparing on a reapplication, and the stack runtime preserves its
  state across the join instead of erasing it.
- **Gameplay tag semantics are queries, not tag arrays.** `ability_tags` is
  identity, combined with `spec.dynamic_tags` into one *effective tags* set
  every other rule reads - never activation gating on its own.
  `activation_required_query`/`activation_blocked_query` gate a single
  activation; `activation_owned_tags` are granted once per definition on the
  0→1 `active_count` edge and retired once on the 1→0 edge, never once per
  `PER_EXECUTION` instance. A successful activation cancels every other
  granted spec its `cancel_abilities_query` matches (never itself unless
  `allow_self_cancel`), and is refused with `BLOCKED_BY_ACTIVE_ABILITY` -
  never the generic `BLOCKED_TAG` - by another spec's `block_abilities_query`
  or an uninhibited `GameplayEffectBlockAbilityTagsComponent` on an active
  effect. `GameplayEffectCancelAbilityTagsComponent` reaches the identical
  cancellation algorithm from the effect side, never a second one.
  `target_required_query`/`target_blocked_query` gate `accepts_target()`,
  enforced once inside `apply_effect_to_targets()` so nothing can reach a
  target by skipping a UI check. Every rule is read from the frozen
  `GameplayAbilityDefinitionSnapshot`, immune to a template edited after the
  grant. `AbilityTagSemanticsRuntime` owns all of it as one collaborator, the
  same shape as `AbilityInstancingRuntime`/`AbilityTaskRuntime`.
- **An ability declares how it activates.** `activation_policy` (`MANUAL`,
  `ON_GRANTED`, `ON_GAMEPLAY_EVENT`, `PASSIVE`) replaces the old implicit
  "trigger tag means event ability" rule. `MANUAL` behaves like F2. `ON_GRANTED`
  tries once when the spec registers, stays granted-but-idle on failure, and is
  never auto-retried. `ON_GAMEPLAY_EVENT` abilities declare one or more
  `GameplayAbilityEventTrigger`s - each an `event_query` matched hierarchically
  against the dispatched tag, replacing the old singular `trigger_event_tag`.
  `PASSIVE` is continuously reevaluated by `AbilityActivationPolicyRuntime`: it
  starts the moment its `activation_required_query`/`activation_blocked_query`
  allow, cancels the instant they stop (checked through
  `active_requirements_error()`, which never answers `ALREADY_ACTIVE` or gates
  on cost/cooldown - continuity is not a purchase), and can restart once its
  conditions hold again. Reevaluation runs on every tag change, attribute
  change, ability start/end and grant/remove, guarded by a reentrancy flag and
  a 64-pass cap so a passive's own activation-owned tag reacting to itself
  still converges in one call; a spec that already tried to (re)activate this
  cycle is not retried again within the same cycle, so an ability whose
  `_activate_ability()` completes synchronously starts once per external
  trigger, not once per pass. `PASSIVE` + `PER_EXECUTION` is refused outright
  at grant time - several automatic executions of one continuous state have no
  stable meaning. `AbilityRuntime.abort_all()` suspends reevaluation for its
  own duration and skips it entirely for `ASC_CLEANUP`, so a passive aborted by
  a tearing-down ASC cannot restart itself an instant before its own removal.
- **Activation by handle, and a lifecycle that never leaves a dead grant
  behind.** `AbilityRuntime.try_activate(handle, context)` is the canonical
  entry point - input, event routing and passives all call it - and returns
  a `GameplayAbilityActivationResult` (a closed `Status`, the handle, the
  instance) the instant activation *starts*, never waiting for
  `_activate_ability()` to finish: a channelled ability reports `SUCCESS`
  immediately and keeps running. `GameplayAbility._begin_runtime_activation()`
  is the shared synchronous primitive both this and the compat
  `GameplayAbility.try_activate()` wrapper start from; the compat wrapper
  still blocks until its own instance ends, for every caller that already
  relies on that. Two ASC signals mirror it: `ability_activated` the moment
  a handle starts, `ability_runtime_ended` the moment it stops, superseding
  the instance-only `ability_ended` for anything that only has a handle.
  `remove_ability(handle, policy)` takes an `AbilityRemovalPolicy` -
  `CANCEL_IMMEDIATELY` aborts and drops the spec now (marking it
  `pending_remove` *before* aborting, so an ability that reacts to its own
  cancellation - a passive's reevaluation, chief among them - can never
  restart what is already being torn down); `AFTER_ACTIVE_END` (also
  `remove_ability_on_end()`) lets the current run finish and retires the
  spec the instant `active_count` returns to 0, immediately if it already
  has - the same mechanism Task 14's `REMOVE_ON_ACTIVE_END` effect grants
  use, never a second one. `give_and_activate_once()` composes `give_ability`
  + `try_activate` + `remove_ability(..., AFTER_ACTIVE_END)`: never started
  removes the spec on the spot, started marks it `pending_remove` before the
  call even returns - so PENDING_REMOVAL, not a bespoke flag, is what stops
  a second activation of the same handle, PER_EXECUTION included.
- **A standard task library for observation and reactivity**, all
  `AbilityTaskRuntime`-owned, none inventing a second async framework:
  `AbilityTaskWaitAttributeChange`/`WaitAttributeThreshold` (five
  comparisons, optional immediate trigger, no per-frame polling);
  `WaitTagAdded`/`WaitTagRemoved` (hierarchical, the same rule every tag
  match in this addon already uses) and `WaitTagQuery` for an arbitrary
  `GameplayTagQuery` reaching a desired bool; `WaitGameplayEffectApplied`
  (matches by `GameplayEffectQuery.matches_incoming()`, observes an INSTANT
  success even with no active handle, and can stay `RUNNING` across several
  matches when `trigger_once` is false); `WaitGameplayEffectRemoved` (by
  exact handle or by query) and `WaitGameplayEffectStackChange`;
  `WaitAbilityActivated`/`WaitAbilityEnded`, watching Task 17's own
  `ability_activated`/`ability_runtime_ended`, by handle or by a
  `GameplayTagQuery` over effective ability tags; `WaitConfirmCancel` (two
  input ids, one `Decision` enum, no UI of its own);
  `AbilityTaskRepeat` (runtime-driven, never a `SceneTreeTimer` - a large
  delta pays owed repetitions from elapsed time, capped and carried as
  backlog exactly the way `GameplayEffectScheduler` already paces periodic
  ticks); `AbilityTaskPlayAnimationAndWait` (Godot-native, never an
  AnimMontage reimplementation, `stop_on_cancel` defaulting false since the
  `AnimationPlayer` may be shared). A new ASC signal,
  `gameplay_effect_executed(spec, active_effect)`, extends the existing
  application/execution protocol to periodic ticks specifically, rather than
  a task inferring them from attribute changes. Every task with no place in
  `AbilityTaskRuntime`'s dispatch protocol connects straight to the ASC
  signal it needs and disconnects in `_on_finish()` - never a second bus.
  Factories live in `AbilityTaskFactory`, called as
  `AbilityTaskFactory.wait_tag_added(self, tag)` from inside an ability,
  rather than fifteen more one-line wrappers on `GameplayAbility` itself.
  Overlap detection was deliberately not built as its own task: it is
  `wait_target_data()` plus the existing targeting pipeline, the one
  physical boundary this addon already has for "who did a cast reach".
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
  effects/components/ GameplayEffectComponent and the ten concrete kinds
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
