# Sandbox findings

Defects, gaps and rough edges the sandbox surfaces in `addons/GAS_Engine`.

**Nothing in the addon is fixed in this branch.** Each entry is written up so it
can be reproduced on `main`, where the regression test and the repair belong.
See `SANDBOX.md` for the workflow.

Problems in the *host game* - Dialogic, the base project - are fixed here
directly, since the sandbox has to be in working order to test anything. Those
are recorded under **Sandbox-side** below.

## How to read an entry

| Field | Meaning |
|---|---|
| Status | `OPEN` · `FIXED ON MAIN <sha>` · `VERIFIED IN SANDBOX` · `NOT A DEFECT` |
| Where | the addon file and function, not the sandbox file that tripped it |
| Repro | the shortest path that shows it |
| Expected / Actual | what the addon's own contract promises, and what happened |
| Impact | what a game integrating GAS_Engine would suffer |

An entry stays `OPEN` until a regression test exists on `main`. It becomes
`VERIFIED IN SANDBOX` only after the addon is re-deployed here and the repro is
run again.

---

# Open — GAS_Engine

## GAS-001 — a file-local enum loses its name to a host project's autoload · **BLOCKER**

**Status:** `VERIFIED IN SANDBOX` — fixed on main at `ad10a2b`, re-deployed here
**Severity:** was a blocker - the addon did not compile at all in this project
**Where:** `addons/GAS_Engine/abilities/tasks/ability_task_wait_input.gd:13,19,22,31,35,39`

### Repro

The host game declares an autoload named `Transition`:

```text
project.godot
[autoload]
Transition="*res://src/common/screen_transitions/ScreenTransition.tscn"
```

The addon file declares its own enum with the same name and then uses the bare
name as a type annotation:

```gdscript
enum Transition { PRESSED, RELEASED }
var transition: Transition = Transition.PRESSED
static func create(ability: GameplayAbility, slot: int, wanted: Transition) -> AbilityTaskWaitInput:
func _answer(slot: int, arrived: Transition) -> void:
```

Open the project. Godot reports:

```text
ability_task_wait_input.gd:19 - Parse Error: Cannot assign a value of type
  AbilityTaskWaitInput.Transition to variable "transition" with specified type ScreenTransition.
ability_task_wait_input.gd:31 - Parse Error: Invalid argument for "_answer()" function:
  argument 2 should be "ScreenTransition" but is "AbilityTaskWaitInput.Transition".
ability_task_wait_input.gd:35 - (same)
```

Reproducible from a clean state with the class cache already built:

```powershell
# in the sandbox project
godot --validate  # or: MCP validate_script on that path
```

### Expected / Actual

**Expected:** inside the file that declares `enum Transition`, the bare name
`Transition` means that enum.

**Actual:** an autoload's name is registered in global scope and outranks the
file's own enum in a *type annotation* position. The annotation resolves to the
autoload's type (`ScreenTransition`), the enum value cannot be assigned to it,
and the file fails to parse. Note the error message itself distinguishes them -
Godot knows the value is `AbilityTaskWaitInput.Transition`; it is the
annotation that binds to the wrong thing.

### Impact

The failure is not contained to one task. It cascades through every dependent:

```text
ability_task_wait_input.gd
 └─ ability_task_runtime.gd
     └─ ability_runtime.gd
         └─ ability_system_component.gd
             ├─ gameplay_effect.gd
             ├─ gameplay_effect_cancel_ability_tags_component.gd
             └─ gameplay_ability_cost_resolver.gd
```

Every one of those reports `Compile Error: Failed to compile depended scripts`.
**A consumer project with an autoload named `Transition` cannot use GAS_Engine
at all.** `Transition` is a common autoload name in Godot games - screen
transitions are exactly what the host game uses it for.

The addon's own unit suite cannot catch this by construction: GAS_Engine's
project declares only one autoload, `GameplayCueManager`. The collision only
exists in a consumer's project.

### The class, not just this instance

`Transition` is one of **44** enums the addon uses as a bare type annotation.
Every one is the same landmine for a project that happens to declare a global
with that name. Sorted by how likely a game is to own that name:

```text
high risk:  Transition, State, Status (x11 files), Mode (x2), Type (x2),
            Shape, Actor, Value, Change, Code, Operation, Decision,
            Comparison, Severity, Policy, Moment, Operator
lower risk: ActivationError, ActivationPolicy, AbilityRemovalPolicy,
            CancelReason, DurationPolicy, InhibitionFilter, InstancingPolicy,
            PeriodInhibitionPolicy, RemovalPolicy, SpaceKind, StackingType,
            StackDurationRefreshPolicy, StackExpirationPolicy,
            StackPeriodResetPolicy, InhibitionFilter,
            EditorTagsTagEditorPropertyMatchType
```

Command that produced the list, from the sandbox root:

```bash
for f in $(find addons/GAS_Engine -name '*.gd'); do
  for e in $(grep -oP '^enum \K\w+' "$f"); do
    n=$(grep -cP ":\s*$e\b|->\s*$e\b" "$f")
    [ "$n" -gt 0 ] && echo "$e <- $(basename $f) ($n)"
  done
done | sort -u
```

### Attribution — is this the addon's defect or the game's?

Asked deliberately, because the rule is that `main` stays agnostic of any game
and the game is built on the addon, never the reverse. If the game were at
fault, the game is what gets fixed. Measured in an isolated project with
neither the addon nor the game present - one autoload, four scripts:

| Probe | Declares | Annotation | Result |
|---|---|---|---|
| A | `enum Transition` + autoload `Transition` exists | bare `Transition` | **fails** |
| B | same | `BQualified.Transition` | passes |
| C | `enum Zzzz`, no global by that name | bare `Zzzz` | passes |
| D | `enum ScreenTransition` + **`class_name ScreenTransition`** exists | bare | **fails** |

Confirmed by the engine at runtime, not only by the validator:

```text
Debugger Break, Reason: 'Parser Error: Cannot assign a value of type
  ABare.Transition to variable "transition" with specified type ScreenTransition.'
*Frame 0 - res://a_bare_with_autoload.gd:3
```

Two facts come out of this that the original write-up did not have:

1. **It is not autoloads.** Probe D shows a plain `class_name` in the consumer's
   project shadows a file-local enum exactly the same way. Any global does.
2. **The shadowing is annotation-only.** In probe A the right-hand side still
   resolved to `ABare.Transition` - the enum wins for value access and loses for
   the type annotation, in the same statement. That asymmetry is why the message
   reads as a type mismatch against a name the file never mentions.

**Verdict: this is GAS_Engine's defect, not the game's.** Four reasons, in order
of weight:

- **The addon does not own the name.** `Transition` here is
  `AbilityTaskWaitInput.Transition` - a file-local implementation detail. The
  addon declares no `class_name` called `Transition`, `State`, `Status`, `Mode`,
  `Type`, `Shape`, `Actor` or `Value`. It never claimed the global name, so the
  game did not take anything from it.
- **The game cannot honour a contract that was never published.** Staying safe
  would mean avoiding all 44 internal enum names - among them `State`, `Status`,
  `Type`, `Mode`, `Value`, `Actor`, `Code`, `Change`, `Operation`. The addon's
  README publishes no such list, and no README could: those are the most
  ordinary words in game code. A consumer cannot avoid names it cannot see.
- **The addon already knows the right form.** `gameplay_ability.gd:423,427,431`
  writes `AbilityTaskWaitInput.Transition`, qualified. Qualifying is already the
  convention; `ability_task_wait_input.gd` is the file that departs from it,
  inside its own declaration file, where the bare name felt safe.
- **This is what "agnostic" has to mean.** An addon is agnostic when nothing a
  consumer does inside their own namespace can break it. One that works only
  while the consumer avoids 44 specific words is not agnostic - it imposes a
  naming contract it never stated and cannot enforce.

The case where the game *would* be at fault is a real one and worth naming: if a
game collided with something GAS_Engine publishes globally - `class_name
GameplayAbility`, `GameplayEffect`, `AbilitySystemComponent` - then the game
renames, because the addon owns those names and says so. That is not this.

Cost of each direction, for completeness: qualifying the annotation is a
three-line internal change that makes the addon robust for every consumer
forever. The alternative asks every consumer, forever, to avoid words like
`State` and `Type`.

### Suggested shape of the fix (for `main`, not here)

Qualify the annotation with its declaring class - `AbilityTaskWaitInput.Transition`
- which is what `gameplay_ability.gd:434` already does correctly for the same
enum, and what the error message reports as the real type. A gate that fails
when an addon enum is used as a bare annotation would close the class rather
than this one instance; the sandbox is not the place to decide that.

---

# Sandbox-side — fixed here

## SBX-001 — Dialogic does not parse under Godot 4.7 · **FIXED**

**Status:** `FIXED IN SANDBOX`
**Where:** the host game's vendored Dialogic, not GAS_Engine

Two parse errors stopped Dialogic loading entirely, which took
`DialogicGameHandler` and the default layout with it:

```text
addons/dialogic/Modules/Wait/subsystem_wait.gd:13 - Cannot infer the type of
  "clear_flag" parameter because the value doesn't have a set type.
addons/dialogic/Modules/Text/node_name_label.gd:18 - Not all code paths return a value.
```

`subsystem_wait.gd` defaulted a parameter to `Dialogic.ClearFlags.FULL_CLEAR`
with `:=`. `Dialogic` is the autoload, and an autoload's type is not resolvable
while the subsystem it loads is being parsed, so there was nothing to infer
from. Typed against the class instead of the autoload -
`DialogicGameHandler.ClearFlags` - which is resolvable and is the same int enum.

`node_name_label.gd::_set` returned `true` down one path and fell off the end
down the other. Godot's `_set` contract is "did I handle this property", so the
fall-through now says `false` out loud.

Same family as the fix the base project already carries in
`subsystem_variables.gd`: this Dialogic build predates Godot 4.7's stricter
inference.

## SBX-002 — Dialogic empties its own directories on first import · **NOT A DEFECT**

**Status:** `NOT A DEFECT` (of GAS_Engine, and not persistent)

Opening the project with no `.godot/` present rewrites `project.godot` with

```text
directories/dch_directory={}
directories/dtl_directory={}
```

losing 25 character and timeline path entries.

**Attribution, measured rather than assumed.** Three runs:

| Run | GAS_Engine plugin | `.godot` | dch entries after |
|---|---|---|---|
| 1 | enabled | fresh | wiped |
| 2 | **disabled** | fresh | wiped |
| 3 | enabled | **existing** | intact |

Run 2 rules GAS_Engine out - the wipe happens with the plugin disabled. Run 3
shows it is a first-import artifact, not an ongoing one: with a cache present,
`project.godot` is not touched at all.

The committed `project.godot` on this branch holds the correct entries. After a
fresh clone, let the editor import once and then `git checkout -- project.godot`
before committing anything.

---

# Milestones

## 2026-09-01 — combat runs on GAS_Engine end to end

A battle was played through: entered from the field, action menu, target
selection, attacks resolved, battle won. No console errors.

That is the first time the engine has been exercised by a game rather than by
its own suite - the whole reason this sandbox exists. What it proves: attribute
composition, ability activation and commit, effect application through
`apply_effect_to_targets`, per-target accuracy, turn order read live from an
attribute, defeat detection through a tag, and the AI asking the component what
is legal instead of guessing.

Not yet exercised, and worth aiming at next: energy costs (every authored
ability costs 0, so the commit path has never refused), the `Focus` buff and
therefore the contribution-and-withdrawal that justifies effects over
arithmetic, evasion and misses, and losing a battle.

# Checked and not defects

Recorded because a question asked and answered is worth as much as a bug found,
and because the next person to wonder should not have to re-measure.

## `can_activate(get_spec(handle))` with a stale handle

The obvious line a consumer writes, and it is safe: `get_spec()` returns null
for a handle that no longer resolves, and `activation_error(null)` returns
INTERNAL_ERROR rather than dereferencing it. No crash, and `can_activate`
answers false.

## Handle to instance takes two steps

Getting the ability behind a handle is `get_spec(handle).per_actor_instance`
with a null check at each step, and this sandbox writes it in five places.
Ergonomics, not a defect - and the component states plainly that handle-keyed
operations live on the runtime while the facade carries the instance-shaped
conveniences. Noted rather than changed: inventing a shortcut against a stated
design is worse than the five lines.

## The paths a played battle has not reached are covered by the suite

Both of the behaviours the playthrough could not exercise are already pinned on
main: an unaffordable cost reports INSUFFICIENT_RESOURCES and starts no
cooldown, and a buff's contribution withdrawn on expiry lands "exactly back to
base, no float drift". What a playtest would add is confirmation that this game
wires them correctly - not evidence about the engine.

# Closed

## GAS-002 — no safe way to await an ability that may already have ended

**Status:** `FIXED ON MAIN 321a020` — deployed here, awaiting a played battle

`try_activate()` returns when activation BEGINS. An ability that refuses - an
unaffordable cost, nothing left to aim at - runs, fails and finishes inside that
same call, so its end has already been announced by the time the caller reads
the result. Awaiting it then waits for something that will not happen again.

The addon offered no counterpart to `GameplayAbilityTask.completed()`, so every
consumer had to hand-roll the race guard. This sandbox hand-rolled it and only
noticed because the rebuilt combat was swept the way the addon is; a played
battle could not have found it, because every authored ability costs zero energy
and no activation has ever been refused.

`GameplayAbility.completed()` now returns at once for an ability that has ended
and awaits `ability_ended` otherwise. The battler uses it, and no longer watches
`ability_runtime_ended` for every ability on the component when it cares about
one.


## GAS-001 — verified

Fixed on `main` at `ad10a2b`, closed as a class rather than as one name: all 45
bare enum annotations across 34 files are qualified, and `project_invariants.py`
now fails the build when any addon enum is used as a bare annotation. Two files
qualify through a self-preload instead of a class name and say why - one is in
the autoload's parse closure where a global name does not resolve, the other
declares no `class_name` at all.

Re-deployed into this branch from `main` and verified **in the running game**,
not only by the validator:

```gdscript
var asc := AbilitySystemComponent.new()          # the class that would not compile
var t := AbilityTaskWaitInput.Transition.RELEASED # the shadowed enum
get_tree().current_scene.add_child(asc)           # a real tree, real _ready
```

```text
ASC instanciado: true
AbilityTaskWaitInput.Transition.RELEASED = 1
autoload Transition sigue siendo: CanvasLayer
GameplayCueManager en el arbol: true
runtimes cableados tras _ready: true
tags iniciales: 0, efectos activos: 0
```

The third line is the one worth keeping: the game's own `Transition` autoload is
still a `CanvasLayer`, unchanged. The addon stopped taking the name rather than
the game giving it up - which is what "agnostic of the game" had to mean.

The eight scripts that previously reported `Failed to compile depended scripts`
- ability_task_runtime, ability_runtime, ability_system_component,
gameplay_effect, the cancel-tags component, the cost resolver, project_settings
and the tag editor property - all validate clean here.

Suite on `main`: 30192 assertions, 0 failures, 0 orphans. Unchanged, as expected
- qualifying an annotation changes no behaviour.
