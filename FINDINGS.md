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

**Status:** `OPEN`
**Severity:** blocker - the addon does not compile at all in this project
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

# Closed

_None yet._
