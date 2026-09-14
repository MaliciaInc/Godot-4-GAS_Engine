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

Nothing. Every defect this sandbox found in the addon is fixed on `main`,
re-deployed here and re-run - the last were GAS-011 to GAS-013, closed
2026-09-14 and moved below, beside GAS-014 to GAS-024, which had no repro in
this game to re-run and are closed by their regression tests on `main`. A finding is only allowed to leave this section by being
re-measured here, never by a fix existing somewhere else.

## Open questions - for a decision, not defects

Found by the same sweep, and left alone on purpose: each is a choice about what
the engine should be, and fixing either one would be deciding it.

1. **A tag nobody declared.** The Dialogic bridge checks that a tag is spelled
   like a tag and deliberately does not repair it; it does not check that the
   project declares it. A typo in a timeline - `State.Sword` for `State.Sworn` -
   is granted as a new tag that nothing listens for, and nothing says so. Whether
   the runtime refuses, warns, or allows an undeclared tag decides what a game may
   do at runtime, so it is not a bug fix.
2. **Abilities written as a base class with hooks.** Five of this game's six
   abilities open read-only in the Composer. They extend `BattlerAbility` and
   fill in `_perform()` and `_payload()`, and the Composer draws an ability's own
   body. That is the structure this game chose, and a common one. Whether the
   Composer should draw a hook override is a question about its scope.

## GAS-006 — a call from the palette was written after the return · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 8fe0919+` — regression tests first, re-deployed here, repro re-run
**Severity:** high - the first thing anybody does with a new ability
**Where:** `addons/GAS_Engine/editor/composer/composer_document.gd:after()`

### Repro

Composer → New Ability, then click any call in the palette with nothing
selected. `test/composer_smoke.gd` case 3 does exactly this.

The body that came out:

```gdscript
func _activate_ability() -> bool:
	# @composer-virtual-position __composer_entry 160.00 220.00
	return true
	await wait_delay(0.0)
```

### Expected / Actual

**Expected:** the call is written where it runs - above the return - and the
graph draws `Entry → Wait Delay → End`.

**Actual:** it was written after the return, where nothing runs. The graph drew
`Entry → End` with the new card hanging off nothing, and the smoke reported
`fed by nothing, feeding nothing; wires: Entry->End`.

`ComposerDocument.after()` answered "the line something new goes in after" with
the last line of the *body* when nothing was picked. The end of the body and the
end of the ability are different lines, and everything between them is
unreachable. `ComposerCreation._plain()` - the path a context menu uses - had
this right all along and said so in its own comment; the palette path did not
go through it.

### Impact

A call that never ran, in a file that still compiled, with a card on the canvas
that looked no different from a working one. Picking the End card and adding a
call had the same result.

### The class, not just this instance

`after()` now never answers past the End, whatever is picked - so the same
mistake cannot be made by any future caller either.

---

## GAS-007 — a card made from a menu landed wherever the layout put it · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 8fe0919+` — regression tests first, re-deployed here, repro re-run
**Severity:** medium
**Where:** `composer_canvas.gd` (the two `connection_*_empty` signals),
`composer_menus.gd`, `composer_wiring_routes.gd:create_and_connect()`

### Repro

Right-click empty canvas, search a call, create it - or drag a cable into empty
space and pick one. `test/composer_smoke.gd` cases 9 and 10.

### Expected / Actual

**Expected:** the card appears roughly where the click was, and that position is
written into the ability so reopening puts it back there.

**Actual:** the card went wherever the automatic layout put it, and nothing was
written. Underneath were two separate faults:

1. `ComposerCanvas` declared `connection_to_empty_requested` and
   `connection_from_empty_requested` with three parameters and emitted three,
   although the phase document declares four. The graph position - the whole
   point of knowing where the cable was let go - was never emitted.
2. What *was* emitted was the screen position, and `ComposerMenus` read it into
   a handler whose third parameter it treated as the point to open the menu at.
   Godot allows a three-argument handler on a four-argument signal silently, so
   after (1) was fixed the menu would have opened at a graph coordinate - a
   point in a scrolled, zoomed space, rarely anywhere near the pointer.

### Impact

Every card made from a menu appeared somewhere the person did not choose, and
nothing in the file said otherwise, so closing and reopening put it there again.

---

## GAS-008 — the widget's own toolbar covered the graph and ate every click on it · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 8fe0919+` — regression tests first, re-deployed here, repro re-run
**Severity:** was a blocker in this project - the Composer could not be used at all
**Where:** `addons/GAS_Engine/editor/composer/composer_canvas.gd:_ready()`

### Repro

Draw the Composer in this game rather than in the Godot editor - which is what
`test/composer_smoke.gd` does - and click any card near the top-left.

### Expected / Actual

**Expected:** the click picks the card.

**Actual:** nothing happened. The hovered control at that point was
`GraphEdit/@Control/@PanelContainer/@HBoxContainer/@SpinBox` - GraphEdit's own
zoom row and grid-snap box, drawn at this project's theme size (96) rather than
the Composer's, large enough to cover the first several cards. Every click on
them went into the toolbar.

Two things were wrong and both are fixed:

- the canvas took its chrome's font from the ambient theme, so it looked right
  in the editor by accident and enormous here;
- that row floats over the top-left corner, which is exactly where the layout
  puts the first card. Even at the right size it covered the Entry card's title
  bar - the strip somebody grabs it by - and its output pin, in the editor as
  much as here. The Composer has a bar of its own, zoom is on the wheel, and the
  snap box is a second opinion about where a card lands, so the row is off.

### Impact

In the editor: the first card of every ability was partly unusable. Here: the
Composer was unusable, and no test could have seen it - the suite runs headless
and the editor's own theme hides it.

---

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

## SBX-003 — the choreography ran on a clock the engine does not own · **FIXED**

`BattlerAbility._pause()` waited on `tree.create_timer(seconds).timeout`. That is
the one thing `AbilityTaskWaitDelay` was written to refuse, and its doc says why:
a tree timer keeps its own clock, so it answers to a different authority than the
effect scheduler running beside it.

The consequence here was not cosmetic. `Battler.act()` awaits
`ability.completed()`, so a cancelled ability ends the turn - but the body stayed
suspended on the tree timer, woke up afterwards, and called `_land()`. **A swing
cancelled mid-air still applied its payload, into a fight that had already moved
on.** The `is_instance_valid(caster)` guards covered only the freed-node case.

Fixed with the ability's own `wait_delay()`, which is registered through
`register_ability_task()` and therefore cancelled with the ability, and with an
`is_active` check after each tween - a tween finishes on its own clock too.

**Not an engine defect, and worth saying why.** The first read of this was that
`AbilityTaskFactory` is missing `wait_delay` - four of its seventeen task classes
have no factory entry. They are all reachable on `GameplayAbility` itself
(`wait_delay`, `wait_input_pressed`, `wait_input_released`, `wait_gameplay_event`,
`wait_target_data`), which is the surface the engine's own tests use. The engine
was complete; the game had simply not used it.

## SBX-004 — a turn spent swinging at a corpse · **FIXED**

Intentions are declared for a whole round and resolved in speed order, so a
target chosen at the start can be downed by someone faster before the ability
that named it ever runs. `possible_targets()` filters `is_targetable()` at menu
time, which is the wrong moment and the only moment the game checked. `act()`
takes the targets as given.

Reachable in any fight with more than one enemy: a fast ally finishes the ghost
a slower ally had aimed at, and the slower one still swings, still rolls for
accuracy, still applies its effect to a battler that is already down.

**The gate was already there with nothing written on it.** `GameplayAbility`
exports `target_blocked_query`, `accepts_target()` reads it, and
`apply_effect_to_targets()` - which `_land()` already calls - is what the engine's
own doc calls the sole enforcement route. The game had no target queries at all.
`BattlerAbility._init()` now blocks `State.Downed`.

Built in `_init()`, not `_ready()`: the definition is frozen at grant, so
`_ready()` would be reported as drift and never read - the lesson GAS-003 left.
The ability scenes store no override for that property, so the assignment
survives instantiation.

Known consequence: a target downed mid-round is dropped inside
`apply_effect_to_targets()`, after `_connects_with()` has already rolled for
accuracy, so nothing is shown for it. Left that way on purpose - filtering in
`_land()` as well would put the same rule in two places, and the engine's gate
is the one that cannot be forgotten.

## SBX-005 — the GAS probe is not reproducible, and says it is · **FIXED**

`test/gas_probe.gd` opens by promising a record: *"Plays a fixed hand rather
than a random one - same ability, same target, every run. Random play makes a
failure unreproducible, and the point of this is a record that can be re-run and
disagreed with."* The hand is fixed. The fight is not.

### Repro

The unchanged engine, the same seed, three runs:

```text
--seed=8  arena1: ended=true victory=false rounds=3 reason=combat_finished
--seed=8  arena1: ended=true victory=false rounds=2 reason=combat_finished
--seed=8  arena1: ended=true victory=false rounds=4 reason=combat_finished
```

### Why

Accuracy is rolled with `randf()` - `src/combat/abilities/battler_ability.gd`
`_connects_with()` - which draws from the process-wide stream the probe seeds.
That would be reproducible if the draws happened in a fixed order, and they do
not: the probe drives the fight on a wall clock (`HASTE`, `TICK`, `SETTLE`, and a
`STALL` deadline), so which battler acts inside which frame moves with the
machine, and the order of the draws moves with it. Same seed, different
sequence, different fight.

### Why it matters more than it looks

It is a trap for exactly the person doing the right thing. A re-deploy of the
addon is supposed to be checked by re-running this probe, and the natural check
is to compare the run against the last one - which produces a different fight
every time and reads as a regression in the engine. That happened: a deploy of
FASE 6 showed arena1 finishing in 3 rounds where the previous run took 5, and it
took six runs across both engines to establish that the unchanged engine does
the same thing.

### What was done

The promise was removed and replaced with what the probe actually guarantees,
which is the thing its pass condition has always been: **both arenas reach
`combat_finished`**. Round counts, who falls and in what order are not
comparable between runs and are not to be read as evidence of anything.

Making it genuinely reproducible would mean taking the wall clock out of the
fight - the combat loop's own timing, not the probe's - and that is a change to
the game rather than to the harness. Left undone deliberately, and written down
here so the next person does not rediscover it by mistaking noise for a defect.

## SBX-006 — the Composer smoke swept half of what it made · **FIXED**

`ComposerAbilityTemplate.create()` writes a pair - the script and the scene
beside it, because `give_ability()` takes a PackedScene and an ability is a Node
with authored state on it. `test/composer_smoke.gd` removed the script and left
the scene, both before the run and after it.

The engine is right to refuse the second run: `create()` stops if **either**
file exists, so the next run failed at `2 · New Ability writes a file` and every
check standing on it fell with it - six failures where there were two. The
teardown's own check, `13 · and the ability this run made is cleared away`,
asserted only that the script was gone and passed over the litter beside it.

Found on a re-deploy: the run before had left
`src/combat/abilities/_smoke_new_ability.tscn` in the tree, untracked.
`src/combat/new_ability.gd` and its `.uid` were the same litter from an editor
session on 2026-09-04.

Fixed here, in the harness: one place says what a run makes - the script, its
`.uid` and the scene path the engine itself computes - the setup and the
teardown both clear all of it, and the final check names what is left rather
than asserting about one file.

## SBX-007 — the smoke aimed at a card that was off the canvas · **FIXED**

The canvas is a window onto a graph larger than it. A card the layout puts near
the right edge is drawn mostly outside, and a press aimed at a pin on the sliver
that is left arrives at nothing - no card, no canvas, no control. From the
outside that is indistinguishable from the Composer ignoring the gesture, and it
is what GAS-009 turned out to be.

`bring_into_view()` scrolls the card somewhere a pointer can reach before the
aim is taken, and answers where the view was so it can be put back. Putting it
back is not tidiness: cases 11 and 12 aim at cards where the layout left them,
and a view left somewhere else made all seven of their checks miss - which is
the same failure one step along, and it appeared the moment the scroll was
added without the restore.

With it, the Composer smoke is green for the first time: **82 checks, 82
passed**.

# Milestones

## SBX-008 — the re-deploy copied the addon and left the generated half behind · **FIXED**

A re-deploy was understood as "copy `addons/GAS_Engine` from `main`", and by
that definition every re-deploy since `08bd807` was complete. The addon here is
byte for byte `main`'s - same git tree, `2d53709`, 817 files. `gas_engine/` was
not, and had not been for two phases.

### Repro

```bash
git rev-parse origin/main:addons/GAS_Engine
git rev-parse origin/godot-open-rpg_GAS_Engine:addons/GAS_Engine   # the same
git rev-parse origin/main:gas_engine
git rev-parse origin/godot-open-rpg_GAS_Engine:gas_engine          # not the same
```

### Expected / Actual

Five declarations a current engine writes were absent here:

| declaration | in | added by |
|---|---|---|
| `REDIRECTS`, `RESTRICTED`, `COMMENTS` | `gameplay_tags.gd` | F6.4.3 |
| `HANDLERS` | `gameplay_cues.gd` | F6.2.5 |
| `OVERRIDE_PARENT` | `gameplay_cues.gd` | `d2f0588` |

### Why it was silent

Both registries are read as *text*, not loaded as scripts, and both readers walk
the file looking for a declaration to step inside - `_body_of()` in each
generator. A declaration that is not there is not an error; the walk simply
never steps in and the reader returns empty. An absent `OVERRIDE_PARENT` reads
exactly like an `OVERRIDE_PARENT` nobody filled in.

So nothing broke, and that is the whole problem: the cue family walk, tag
redirects, restricted tags and tag comments were all live in the addon here
while the file they read from could not express any of them. Any probe written
to exercise them would have passed against nothing.

### The class, not just this instance

The fix is not to copy `main`'s two files - their `.uid`s belong to `main`'s
project and this project's own must survive. It is to notice that a host project
has a *generated* surface as well as a copied one, and that only the copied half
had a procedure. `SANDBOX.md` now defines a re-deploy as both steps, and the
second is the generators writing back what this project already declares, so it
stays correct for whatever declaration the next phase adds.

### Fix

Re-rendered here with the deployed generators. The result is byte for byte
`main`'s content with this project's `.uid`s untouched. All four probes green
afterwards: `gas_probe` both arenas to `combat_finished`, `composer_probe`
`8 nodes, 7 wires, 0 notes, byte for byte`, `composer_harness` 58/58,
`composer_smoke` `PASS passed=82 failed=0`.

### Noticed on the way - fixed on main at `76958eb`

`GameplayCueGenerator.generate_cues_file()` called `render_source(bindings,
overrides)` and never passed `handlers`, so a regeneration would drop a
project's cue handlers - where the tag generator round-trips all three of its
declarations. Recorded here as latent, because it was: the only two callers are
the legacy `.tres` migration, which predates handlers, and the first-run seed,
which is guarded by `file_exists`.

Repairing it on `main` ran the strict-typing pass over the cue files for what
looks like the first time, and that found something that was **not** latent:
`gameplay_cue_catalog.gd:61` called `new()` on a var typed `Script` and put the
result straight into a `Dictionary[StringName, CueHandler]`. A `HANDLERS` entry
naming a loadable script that is not a handler therefore ended
`load_from_project()` with an invalid-assignment error and took every cue after
it with it. `HANDLERS` is hand-authored - no editor writes it - so that is a
normal way for a host project to be wrong. It now names the tag and the file,
skips that one and loads the rest.

---


## SBX-009 — a case that stopped part way left the smoke saying PASS · **FIXED**

Found by tripping it rather than by reading: a check written against
`_it.refusal()`, which does not exist, made case 6 stop three checks early. The
run reported `SMOKE_RESULT: PASS passed=87 failed=0` and looked completely
healthy. The only reason it was noticed is that seven checks had just been added
and the total went up by five.

### Why it is silent

A GDScript runtime error - a call to something that is not there - aborts the
function it happens in and resumes the caller. The `await` in the runner
returns normally, the next case starts, and every check after the error simply
never runs. The result line counts what ran, so fewer checks is not fewer
passes: it is a smaller, still-green run.

That is the worst shape a harness can have. It does not fail when it breaks; it
quietly asks less, and it asks least exactly when somebody has just changed
something.

### Fix

Each case says so as its last line, and the run checks that all thirteen did:

```text
FAIL every case ran to its last line    stopped part way: 6
SMOKE_RESULT: FAIL passed=88 failed=1
```

Proved by breaking case 6 on purpose - a call to a function that is not there,
in front of its marker - and confirming the run names it and fails. Restored
afterwards.

---

## SBX-010 — a cancelled swing left the caster standing out there · **FIXED**

`test/gas_contract_probe.gd`, case `cancel_travel` - the wolf sets off, and its
ability is cancelled on the way:

```text
ok    cancel_travel · a swing cancelled on its way never lands
ok    cancel_travel · its turn still ends, once
FAIL  cancel_travel · and the caster comes home rather than staying out there   (0, 0) -> (350, 0)
```

`BattlerAbility._lunge()` returned at every await a cancel can land across, which
is right - the payload must not land - and every one of those returns skipped the
way home. Not the engine's: the cancel reached the ability, its task stopped and
the turn ended exactly once. The game forgot where it had put its battler.

Fixed here: the swing is its own function, and `_lunge()` puts the caster back
where it started however the swing ended. Put back rather than tweened back, so
the next ability never reads a position that is still moving.

## SBX-011 — health nobody could see, under a ceiling that came down · **FIXED**

`test/gas_contract_probe.gd`, case `max_drop`:

```text
ok    max_drop · with max health raised to 150, health may reach 150
ok    max_drop · when the raise ends, max health is 100 again
ok    max_drop · and health is not left standing above it
FAIL  max_drop · and the next hit of thirty takes thirty off what is shown     health 100.0, base 100.0
```

`BattlerAttributes` bounded what is shown (`pre_attribute_change`) and what is
written (`pre_attribute_base_change`), and nothing brought the base down when the
ceiling dropped. So the battler read 100 and carried 150 underneath; a blow of
thirty wrote 120, was clamped to 100, and took nothing off the bar.

The engine names the hook for exactly this - `post_attribute_change`, "e.g.
clamping Health when MaxHealth drops" - and its own test attribute set does it.
The game had not used it. Fixed here: health and energy are brought down to a
ceiling that dropped under them, through `set_attribute_base`, so the change is
recomposed and announced like any other.

## SBX-012 — this game's effects had no names · **FIXED**

The overlay's effects page showed Focus as a row with an empty name. Every
effect this game applies is built in code - the payloads, the cooldowns, the
energy tick - and none was named, so the debugger had nothing to show.

Fixed here: `_land()` names a payload after its ability, a cooldown is named by
its tag, and the energy tick by what it is. `test/gas_overlay_probe.gd` checks
that the row says Focus. Asking why it was blank also turned up GAS-014.

## SBX-013 — this branch called the engine MIT · **FIXED**

`SANDBOX.md` said `addons/GAS_Engine` was MIT and pointed at a
`addons/GAS_Engine/LICENSE` that does not exist. The engine is under the
GAS_Engine Community Use License 1.0, with modification reserved to a paid
Commercial Modification License, and both files live at the root of `main`.
Found while writing the manual's installation page.

Fixed here: `SANDBOX.md` names both licences and where they are.

---

## 2026-09-01 — combat runs on GAS_Engine end to end

A battle was played through: entered from the field, action menu, target
selection, attacks resolved, battle won. No console errors.

That is the first time the engine has been exercised by a game rather than by
its own suite - the whole reason this sandbox exists. What it proves: attribute
composition, ability activation and commit, effect application through
`apply_effect_to_targets`, per-target accuracy, turn order read live from an
attribute, defeat detection through a tag, and the AI asking the component what
is legal instead of guessing.

## 2026-09-01 — losing a battle, exercised by losing one

A fight against the ghost was lost, then won on the third attempt. Losing
exercises what winning does not: `State.Downed` cascading until a whole side is
out, `is_side_defeated` on the player's side, `_finish(false)` and the loss
timeline. No errors.

Feedback from that session, and it was a regression rather than a taste: the
fight read as hurried. The original combat held ~0.1s beats between the phases
of a swing and the rewrite dropped them, so impact and recovery landed in the
same instant and the damage number was gone before it could be read. Restored as
named, exported beats - windup, impact_hold, recovery - rather than the bare
sleeps they were.

Not yet exercised, and worth aiming at next: energy costs (every authored
ability costs 0, so the commit path has never refused), the `Focus` buff and
therefore the contribution-and-withdrawal that justifies effects over
arithmetic, evasion and misses, and losing a battle.

## 2026-09-01 — the engine's refusal, verified by playing it

Baloo's energy and Punch's availability, round by round, from screenshots:

| Round | Energy | Punch |
|---|---|---|
| 1 | 1 | dimmed |
| 2 | 2 | dimmed |
| 3 | 3 | full brightness, usable |

That is `INSUFFICIENT_RESOURCES` refusing an activation, the action menu asking
the engine rather than deciding for itself, and the answer reaching the player.
The last of the paths flagged as never-exercised. Battle won, no console errors.

Worth keeping in mind about what this took: the cost was silently free for one
whole session, and the only reason anyone noticed is that a screenshot showed a
bright button next to one energy. A green console said nothing, and neither
would any number of clean runs - the ability worked, it simply worked for free.

## 2026-09-01 — a screenshot proved a cost was never charged

Play showed `Punch` offered at full brightness on round one, with one energy
against a cost of three. It should have been unpressable. It was not merely
mis-drawn: the cost never reached the engine at all, so the ability was free.

Granting an ability snapshots its definition immediately after
`instantiate()` - `GameplayAbilityDefinitionSnapshot` copies `costs` there, and
its own header warns that mutating the instance afterwards changes nothing. The
cost was being built in `_ready()`, which runs later, when the instance is added
to the tree. The engine was right and said so in its documentation; the sandbox
read it wrong.

Built in the exported property's setter now, which runs while the scene is being
instantiated - before the snapshot is taken.

Second, smaller, and also from the screenshot: a disabled `TextureButton` looks
exactly like a live one. The engine refused the press and the player was left
without a reason, which reads as the game ignoring them. Unavailable entries are
dimmed now, and still legible, because a player deciding what to save energy for
is reading them.

## GAS-003 — a cost written after the grant was swallowed in silence

**Status:** `FIXED ON MAIN 440a5d8` — deployed here

The behaviour was correct and documented: granting freezes the definition, the
commit prices from it, and costs assigned to a running instance are ignored.
What was missing is that nothing said so. This sandbox shipped a free ability
for a whole session on exactly that, and a screenshot caught it rather than any
log - the ability worked, it simply worked for free.

`GameplayAbilityDefinitionSnapshot.report_drift()` now pushes an error naming
the ability and which fields drifted. Once per instance, through the error
channel alone: a game that wired up no listener is still told, and two ways to
learn the same thing is the shape this codebase keeps removing.

Closed as a class rather than as the cost that exposed it. The snapshot freezes
seventeen fields and all seventeen are watched - a cooldown that never arrives
leaves an ability with none, a blocked-tag query that never arrives leaves it
ungated, and both look exactly like an ability behaving correctly. A test reads
`from_probe()` and fails when anything it captures is missing from the list, so
the guard cannot rot back into the silence it exists to end.

## GAS-004 — attribute sets handed over after _ready were dropped in silence

**Status:** `FIXED ON MAIN 3ba3233` — deployed here

A component given its sets after it was running kept neither of the things
`_ready()` does with them: the runtime held the array it was wired with, so new
sets were never read, and isolation was skipped, so two components handed the
same authored resource shared one pool of health.

This sandbox never hit it, and only because its battler happens to assign
`attribute_sets` before `add_child`. Nothing would have said so had it done the
reverse - and a game that builds its actors in code naturally does the reverse.
The shared-pool half is the one that would have shipped: it looks like a working
game until the whole party dies at once.

Found by asking what ordering the engine requires and does not enforce - the
same question that produced GAS-003.

## GAS-005 — the handover rewrote the caller's array and read its policy once

**Status:** `FIXED ON MAIN 1b980dd` — deployed here

Three failures with one root: the runtime aliased the array it was handed and
applied the copy policy in place, at a single moment.

- **Isolation wrote into the caller's array.** It replaced the elements rather
  than the array, to avoid re-entering the setter. Those elements belong to the
  game: one array assigned to two components left the second holding the first's
  live, already-damaged copies, and left the game's own variable no longer
  holding what it authored.
- **`share_attributes` was read only at the handover.** Assigning it to a
  running component was ignored in silence - the same ordering trap GAS-004
  found in the sets themselves, one export over.
- **`_wire_runtimes()` handed the sets over a second time without isolating**,
  immediately before the real handover did it properly. Two ways in, and the
  shorter one was the unsafe one. `isolate` also lost its default value: the
  protective choice must not be the one a caller has to remember to ask for.

Found by generalising GAS-004 rather than waiting to trip over it: every
`@export` in the addon, asked whether the engine reads it again after start-up.
`share_attributes` was the only other one, and pulling on it exposed the rest.

The unit test for GAS-004's isolation asserted that the export had been
overwritten with the copies - the first bug above, stated as the contract. A
test that verifies a property by observing the side effect that caused it will
defend the side effect. It asks the runtime for its live sets now.

**Deployed here, and this sandbox now leans on the fix.** `battler.gd` used to
hand over `attributes.duplicate()`, defending itself against exactly this; its
comment gave a reason ("a runtime write would reach the file on disk") that was
never quite right and is now not true at all. It hands over the authored
resource directly. Two battlers sharing one `.tres` get the same cached
Resource, so if the engine ever stops copying, they share a health pool and the
next battle says so.

# Deployed from main, not found here

The sandbox runs whatever `main` runs, so this section says which engine it is.
None of these were found by playing: they came from sweeping the addon itself,
mostly by asking where a rule is applied in one place and not in its neighbour.
They are listed so that a behaviour change noticed here has somewhere to be
looked up.

| commit | what changed |
| --- | --- |
| `1b980dd` | The attribute-set handover stopped rewriting the caller's array, and `share_attributes` became assignable to a running component. |
| `426c3dd` | `AbilityTaskRepeat` with an interval of zero or INF ends itself instead of waiting forever. |
| `20aa035` | A spec whose `duration` or `period` is not a finite number is refused rather than applied. |
| `fc08af7` | One period-clock restart instead of two that disagreed; `tick_time()` now answers the same way whoever restarted it. |
| `23fd19d` | The Dialogic/GLoot/QuestSystem bridges survive the node they watch being freed first. |
| `ae713db` | A capture left blank reports INVALID_DEFINITION rather than MISSING_CAPTURE. |
| `7afb25e` | An overlap sweep is no longer capped at 32 targets by Godot's own default; `max_results` is authored. |
| `f4653ad` | The dashboard refuses an attribute named for a GDScript keyword, which used to generate a file that would not parse. |
| `bab301b` | The asset validator reports an empty row in an authored array instead of stepping over it. |

Of these, `7afb25e` is the one this game could meet: a crowded battle sweeping
for targets was silently answered with at most thirty-two colliders.

# Checked and not defects

## GAS-009 — Alt over a data argument's pin does nothing · **NOT A DEFECT**

**Status:** `NOT A DEFECT` (of GAS_Engine). Re-measured against `main` at
`6187444`; the smoke was aiming at a card that was not on the canvas.

This was written up as an engine defect and it was not one. The write-up is kept
rather than deleted, because the way it went wrong is worth more than the entry
was.

### What was reported

`test/composer_smoke.gd` case 7 Alt-clicked a data argument's pin and nothing
happened - not the disconnect, and not even an event on the canvas:

```text
ok    7 · the argument's pin is the one the engine finds there   aimed at n36.arg_1, engine finds n36.arg_1
FAIL  7 · and the canvas heard the gesture                        0 events reached it
FAIL  7 · Alt over the argument's pin takes the cable off         14 -> 14
```

The cause written down was a hypothesis: `ComposerCard` is a `GraphNode`, a
press inside its rectangle is the node's, and the execution pins that do work
sit on the outer edge. It reads well and it was wrong.

### What it actually was

The card was not on the canvas. The layout had put it at `x = 1607` and the
canvas ends at `x = 1630`; the pin was on the 23-pixel sliver still drawn, and
the press landed on nothing at all. Measured by walking the tree at the point
and by pressing at the card's own centre - `x = 1658`, past the edge - which
was received by nobody either:

```text
canvas rect=[P: (251, 54), S: (1379, 894)]
card   rect=[P: (1607, 442), S: (102, 107)]
```

Scrolling the card into view first makes the whole case pass, with the engine
unchanged. That is the check now: `bring_into_view()` before aiming, and the
view put back afterwards so the cases that follow still find their cards where
the layout left them. SBX-007.

### What it cost, and what it bought

An engine change was written for the hypothesis before it was measured - a card
that hands a press on one of its own controls back to the canvas - and it is on
`main` at `6187444`. It is a real fix for a real case: a host theme that sets
`port_h_offset` draws the port dots inside the card, on rows that are
`MOUSE_FILTER_STOP`, and every modifier gesture on every pin then does nothing.
That case is proved red and green in the engine's own suite. **It is not what
GAS-009 was**, and the smoke passes with it disabled - which is how this was
settled rather than assumed.

The lesson is the cheap one and it was skipped: the entry said "the canvas never
receives the event" and never asked *what did*. Nothing did.

Recorded because a question asked and answered is worth as much as a bug found,
and because the next person to wonder should not have to re-measure.

## A wait begun inside a long frame is charged for that frame · **NOT A DEFECT**

**Status:** `NOT A DEFECT` (of GAS_Engine). Measured 2026-09-14, after GAS-011 was
re-deployed and the half-second wait ended after 256 ms of wall time.

It looked like a clock running double. It was not: the probe reloaded the
script, packed the scene and granted the ability in one long frame, and
activated it straight afterwards. Measured on the deltas themselves:

```text
wall 248 ms, frames 38
delta of the frame the wait began in   0.150 s
deltas of the frames after it          0.357 s
```

The ASC advances a task once per `_process`, with that frame's delta, and the
frame a wait begins in is one of them - so the wait was handed exactly the half
second, 0.15 s of it time spent before the wait existed. Godot's own timers
count the same way, and a clock is what `AbilityTaskWaitDelay` promises. Started
at the top of an ordinary frame, the probe measures 517 ms.

A game that grants and activates in the frame it loads something will see the
same thing, and the answer there is the one the probe now uses: activate on the
next frame.

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

## The smoke's paste checks, on a machine whose clipboard would not open · **NOT A DEFECT**

**Status:** `NOT A DEFECT` - of GAS_Engine; measured 2026-09-14 at the re-deploy
of `main`'s `9a26ef6`

`composer_smoke` ran 87 of 89 twice in a row. The two red checks were
`12 · Ctrl+V puts it back` and `12 · Ctrl+C then Ctrl+V adds one`, each after
`ERROR: Unable to open clipboard.`

Measured rather than reasoned:

- No file under `addons/GAS_Engine/editor/composer/` changed in that deploy.
- A script that does nothing but `DisplayServer.clipboard_get()` failed the same
  way - three times at start-up, and twice more five frames after its window was
  up.
- On the same machine, .NET's single attempt to open the clipboard failed as
  well, while PowerShell's `Get-Clipboard`, which retries, got through.

Something outside Godot held the clipboard open often enough that a single
attempt to open it lost, and Godot makes a single attempt. Before writing up a
paste failure here, run a one-line `clipboard_get()` script first: if that fails
too, the machine is the subject, not the Composer.

Later the same day, with nothing contending for the clipboard - 120 single
attempts to open it in six seconds, none refused - the same script read it, and
the smoke ran 89 of 89 on the same deploy.

---

# Closed

## GAS-011 — a wait the Composer wrote did not wait · **VERIFIED IN SANDBOX**

**Status:** `VERIFIED IN SANDBOX` — fixed on `main` at `4bbfca0`, re-deployed here
2026-09-14 and re-run: `COMPOSER_GAME_RESULT: PASS passed=28 failed=0`, the wait
holding the ability 517 ms
**Severity:** high - every wait, and every other ability task, the palette puts down
**Where:** `addons/GAS_Engine/editor/composer/composer_statement_factory.gd:_invocation()`,
`composer_writer.gd:render_with_field_overrides()`

### Repro

`test/composer_game_probe.gd`, case `run`: a new ability made through the
Composer's own document and statement operations, `Wait Delay` put in from the
palette and given half a second, saved, granted to Baloo and activated.

```text
FAIL  run · the ability is still waiting when the call that started it returns
FAIL  run · and waits the half second                     ended after 0 ms
```

### Expected / Actual

**Expected:** the wait holds the ability for its seconds.

**Actual:** the palette wrote `await wait_delay(0.5)`. `wait_delay()` hands back
an `AbilityTaskWaitDelay`, which is neither a signal nor a coroutine, and
GDScript's `await` on such a value returns it straight away. The ability ran its
whole body inside `try_activate()` and ended after 0 ms. Every test on `main`
read the text the palette wrote and agreed with it; running it is what did not.

### Fix

- A call whose result is a `GameplayAbilityTask` is written
  `await wait_delay(0.5).completed()` - `completed()` is the engine's own wait
  that returns at once for a task already finished.
- The reader keeps what follows the call's closing bracket, so editing a wait's
  seconds keeps `.completed()`, and editing a wait written the old way repairs it.
- A file that already holds a bare `await` on a task opens and draws as before,
  with a warning on that card (`gas.await_without_waiting`) saying it does not
  wait. A call a game registers as suspending is a coroutine and is left alone.
- The README says which form waits.

Regression on `main`: `test/unit/test_composer_waits.gd` runs the body - a wait
of one second still holds the ability at 0.4 and has let it go at 1.0.

### Impact

A windup, a channel, a pause before the hit - anything put together in the
Composer with a wait did all of it in one frame, and looked right on the canvas
and in the file.

---

## GAS-012 — the runtime overlay drew its text at the game's size · **VERIFIED IN SANDBOX**

**Status:** `VERIFIED IN SANDBOX` — fixed on `main` at `4bbfca0`, re-deployed here
2026-09-14 and re-run: `GAS_OVERLAY_RESULT: PASS passed=16 failed=0`, heading and
table at 16 over this game's 96
**Severity:** medium - the overlay was unreadable in this game
**Where:** `addons/GAS_Engine/debug/gas_debug_overlay.gd:_ready()`

### Repro

`test/gas_overlay_probe.gd`, case `theme`, in this project, whose theme says 96:

```text
FAIL  theme · heading 96, table 96; the table 1248 px wide and about 8 rows tall;
              a panel anchored to half of 1920x1080 needed 1193x1408
```

### Expected / Actual

**Expected:** an overlay anchored to half the screen fits in it, at a size of its own.

**Actual:** none of its controls said how big their text was, so every one took
the game's size. GAS-008 again, one folder over: the Composer learned this, the
overlay did not, and in the editor both looked right because its theme is quiet.

### Fix

The overlay builds its own theme in `_ready()`, naming the size for Label,
Button, Tree and the Tree's column titles, with `font_size` exported at 16 for a
game that wants it larger. Godot's theme names now have one owner outside
`editor/`, `GASThemeNames`, which the editor's themes and the overlay both read.

Regression on `main`: `test/unit/test_gas_debug_overlay_in_a_themed_game.gd`
raises Godot's fallback theme to 96 and proves the raise on a bystander Label
before measuring the overlay - a theme set on the root window does not reach a
CanvasLayer's controls, and the first version of that test passed against nothing.

---

## GAS-013 — the Composer answered "done" for things it did not do · **VERIFIED IN SANDBOX**

**Status:** `VERIFIED IN SANDBOX` — fixed on `main` at `4bbfca0`, re-deployed here
2026-09-14 and re-run: the unknown key and the call into a read-only file are
both refused with their reason, inside the 28 of 28 above
**Severity:** medium - a click that does nothing and says nothing
**Where:** `addons/GAS_Engine/editor/composer/composer_statement_ops.gd`

### Repro

`test/composer_game_probe.gd`, cases `author` and `read`:

```text
FAIL  author · a call the catalog does not have is refused                  null
FAIL  read   · a palette call into a file drawn read-only says why           null
ok    read   · and a paste into it is refused     that would leave a file the Composer cannot read
```

### Expected / Actual

**Expected:** an operation that changes nothing says why.

**Actual:** `insert_call()` and `insert_call_at()` with a key the catalog no
longer has, or into a file the Composer draws read-only, returned null - which
the screen redraws as success. Paste was refused, but for the wrong reason: the
edit was attempted first and then refused as one that "would leave a file the
Composer cannot read", so a person looks for something wrong with what they pasted.

### Fix

Every operation that writes asks first whether anything can be written - nothing
open, a file drawn read-only (with that file's own reason), a key no longer in
the catalog, nothing to paste - and refuses with the answer. Remove and repeat
with nothing selected still do nothing quietly: that is not a refusal.

Regression on `main`: `test/unit/test_composer_statement_ops.gd`, region
"Refusing, and saying why".

---

## GAS-014 — an effect saved as a file showed with no name · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 4bbfca0` — deployed here. Nothing this game applies is
an effect file, so there is no repro here to re-run; the regression test on
`main` is what closes it
**Severity:** low
**Where:** `addons/GAS_Engine/debug/gas_runtime_snapshot.gd:_effects_of()`

The runtime debugger named an effect by `resource_name`, which the Inspector
leaves empty unless somebody fills it in. An effect authored as
`smouldering.tres` was a row with nothing where the name goes, in the overlay and
in the editor's debugger alike.

Found by asking why this game's Focus row was blank (SBX-012). The game's half
was that it named nothing; the engine's half was that a file-authored effect
came out blank too.

**Fix:** the name it was given, or else the file it was saved as. An effect built
in code has neither, and a game that wants it shown names it - as the engine's
own sample does. Regression on `main`: `test/unit/test_gas_runtime_debugger.gd`.

---

## GAS-015 — nothing told a writer what to type into a timeline · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 4bbfca0` — the README is `main`'s. Against real Dialogic
here the bridge stays at `DIALOGIC_BRIDGE_RESULT: PASS passed=34 failed=0`
**Severity:** medium - the bridge was usable only by reading its parser
**Where:** `README.md`, Optional integrations

The Dialogic bridge is a protocol - a dictionary carrying `bridge`, `channel`,
`command`, `tag` and `magnitude` - and the README named the bridge and nothing
else. `test/dialogic_bridge_probe.gd` had to be written from
`dialogic_gas_command_parser.gd`, which is the only place the keys were written.

**Fix:** a Dialogic section with the binding, the three timeline lines a writer
types, what each command does, and how a refusal is reported. On `main`,
`test_dialogic_bridge.gd` reads every such line out of the README, sends it
through the bridge, and fails when one is not applied or a command in the
vocabulary is not shown - so the page cannot drift away from the parser.

---

## GAS-016 — the Dialogic double sent a message no timeline can send · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 4bbfca0` — a test fixture, which is not part of the
addon and never reaches this branch
**Severity:** low - no wrong behaviour, a suite that could not have seen one
**Where:** `test/fixtures/fake_dialogic.gd:say()`

Measured here against real Dialogic: `DialogicSignalEvent` parses what the writer
typed as JSON, so a message arrives with String keys and float numbers, frozen.
The double handed over whatever a test built - StringName keys, int magnitudes -
so the bridge's tests proved it against a shape it never meets. The bridge was
right, because its parser reads both; the suite could not have said so if that
ever stopped being true.

**Fix:** the double parses what it is given as JSON and freezes it, as Dialogic
does, and a test pins the shape it hands over.

---

GAS-017 to GAS-024 were found while writing the GAS_Engine manual, by checking
every sentence of it against the code. None of them is reachable from this
game's own content, so each is closed by its regression test on `main`, and the
probes below re-ran green on the re-deploy.

## GAS-017 — an attribute chosen with the picker was never read · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — deployed here. This game names every
attribute by its bare name, so there is no repro here to re-run
**Severity:** high - an effect authored the way the Inspector invites did nothing,
and said nothing
**Where:** every runtime reader of `GameplayEffectModifier`,
`GameplayAttributeCaptureDefinition` and `GameplayAbilityCost`

The attribute picker writes the typed references - `attribute`, `target`,
`reference` - and leaves the bare names beside them empty. The runtime read only
the bare names: a modifier chosen with the picker was skipped, and a capture or a
cost was refused as an invalid definition. The manual's first draft had to tell
every reader to fill in both.

**Fix:** every reader asks the resource which attribute it names, reference first;
a capture and a cost's percentage reference read the set their reference names.
Regression on `main`: `test/unit/test_attribute_reference.gd`, region "What the
runtime reads".

---

## GAS-018 — the Gameplay Effect editor was never in the editor · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — editor-only, nothing headless here reaches it
**Severity:** medium - a finished screen nobody could open
**Where:** `addons/GAS_Engine/editor/effects/gameplay_effect_editor_plugin.gd`

The effect editor existed as an `EditorPlugin` of its own that nothing
registered, so its bottom panel never appeared.

**Fix:** the addon's plugin attaches the panel through `GameplayEffectPanelHost`,
which follows the Inspector; the orphan plugin is gone. Regression on `main`:
`test/unit/test_gameplay_effect_editor.gd`, region "The bottom panel".

---

## GAS-019 — the editor's debugger kept what the game said and drew none of it · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — editor-only, nothing headless here reaches it
**Severity:** medium
**Where:** `addons/GAS_Engine/editor/debugger/gas_runtime_debugger_plugin.gd`,
`addons/GAS_Engine/debug/gas_debug_channel.gd`

Every component reported snapshots and traces to the editor, and the editor
kept them in a log with no screen. The snapshot was sent once, when watching
began, so a screen would have shown each entity as it started. And the console
had no word for the Abilities page the overlay drew.

**Fix:** a GAS_Engine tab per session in the Debugger dock, drawn with the
overlay's own pages; a snapshot resent four times a second while watched; one
list of pages for the overlay, the console and the tab. Regression on `main`:
`test/unit/test_gas_runtime_debugger_panel.gd`, `test_gas_runtime_debugger.gd`
and `test_gas_debug_commands.gd`.

---

## GAS-020 — a magnitude's declared dependencies were never followed · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — deployed here; this game's magnitudes read
attributes only
**Severity:** medium
**Where:** `addons/GAS_Engine/magnitudes/gameplay_magnitude.gd:external_dependencies()`

Declared and documented as how a magnitude says it reads something outside the
attribute system, and read by nothing: a lasting contribution drawn from the
weather kept the value it had when the effect landed.

**Fix:** the live-magnitude registry subscribes to those signals for as long as a
lasting effect carries the modifier, and `GameplayCustomMagnitude` answers with its
calculation's. Regression on `main`: `test/unit/test_gameplay_live_magnitudes.gd`.

---

## GAS-021 — a press by action name did half of what a press by slot does · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — this game acts through `Battler.act()`, not
input, so there is no repro here to re-run
**Severity:** medium
**Where:** `addons/GAS_Engine/components/ability_runtime.gd:_route_action()`

The route by action carried its own copy of the delivery and had lost two halves
of it: a `PER_EXECUTION` grant was never started, and no task heard the press - an
ability bound by action and waiting on its own input waited forever.

**Fix:** one press path for both routes, tasks hear actions, and `wait_input_*`
waits on the grant's action as well as its slot. Regression on `main`:
`test/unit/test_ability_instancing.gd` and `test_ability_input.gd`.

---

## GAS-022 — a refused commit was never announced · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — deployed here; `composer_game_probe`, which
counts the commits of the ability it runs, still counts one
**Severity:** low - a debugger never showed the commit somebody was debugging
**Where:** `addons/GAS_Engine/abilities/gameplay_ability.gd:commit_ability()`

`ability_committed` and the comment beside the call promised every attempt; the
code emitted only on success.

**Fix:** every attempt is announced with its status, and `wait_ability_commit`
still wakes only on a commit that paid. Regression on `main`:
`test/unit/test_ability_commit.gd` and `test_new_ability_task_behaviour.gd`.

---

## GAS-023 — the reference abilities awaited a signal a task may already have fired · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6` — `composer_game_probe` reads them back byte for
byte here
**Severity:** low - the examples a reader copies taught the unsafe wait
**Where:** `addons/GAS_Engine/reference/`

Four of the six awaited `task.finished`, which never returns for a task that ended
inside its own `start()` - the trap `GameplayAbilityTask.completed()` exists for.

**Fix:** `completed()`, in them and in the suite's fixtures.

---

## GAS-024 — the READMEs described an engine that had moved on · **FIXED ON MAIN**

**Status:** `FIXED ON MAIN 9a26ef6`
**Severity:** low
**Where:** `README.md`; `examples/action_sample/README.md` and two of its scripts

The README said the Composer opens anything it cannot draw read-only (it keeps
the statement and leaves the rest editable), that every public method is on the
palette (only those marked `@composer`), and that effects have no authored-resource
alternative (`.tres` effect assets exist). The action sample told a project to
list its cues where the `registry_file` setting points - a setting that now only
says where a registry from before the generated file used to live, so its
bindings can be folded in once - and named an effect editor by a phase number.

**Fix:** rewritten against the code, and the manual in `documentation/` beside it.

---

## GAS-025 — the Debugger tab left an entity's table two rows · **VERIFIED IN SANDBOX**

**Status:** `VERIFIED IN SANDBOX` — fixed on main at `3b3ae38`, found and then
re-checked by `gas_editor_probe`'s screenshot: at the re-deploy of `cd7134f` the
same dock shows all six of a battler's attributes, with its events beside them
**Severity:** low - everything was there, and most of it out of sight
**Where:** `addons/GAS_Engine/editor/debugger/gas_runtime_debugger_panel.gd:_build()`

The tab stacked the page above the list of what happened. The Debugger dock is
wide and short, so the two shared its height: at the dock's usual size in a real
editor the attributes table showed its heading and two rows, and the rest sat
behind a scrollbar.

Nothing headless could have seen it. The suite asks the table how many rows it
holds, and it held all of them.

**Fix:** the page and what happened side by side, in a split. Checked by the
editor probe's screenshot rather than by a test, because the defect was the
room on a screen.

---

## GAS-010 — Ctrl-drag between two argument pins refuses with the wrong reason · **VERIFIED IN SANDBOX**

**Status:** `VERIFIED IN SANDBOX` — fixed on `main`, re-run here 2026-09-11 and
it does what section 2.4 says. The entry below is what was reproduced; what
follows the rule is what closed it.
**Severity:** low - one direction of one gesture, and it refuses rather than damages
**Where:** `addons/GAS_Engine/editor/composer/composer_connection_controller.gd:move_connections()`

### Repro

Two statements taking the same kind of value, one of them fed by a local.
Ctrl+LMB drag from the fed argument's pin onto the other argument's pin. The
smoke aims with the engine's own arithmetic and both ends check out, so the
gesture lands where it says it does.

```text
refused: Target Data is declared after this statement, so it does not exist here yet
```

### Expected / Actual

**Expected**, from section 2.4: "Ctrl+LMB y drag desde un pin conectado mueve
sus conexiones a otro pin de la misma dirección, familia y compatibilidad." An
argument's pin is a connected pin, and two argument pins are the same direction.

**Actual:** the data half of `move_connections()` is written for the *other*
direction - output to output, re-sourcing every consumer to a different local.
It reads the destination's `label` as the name of a local (`named = to_port.label`)
and checks `_in_scope(destination, consumer)`. Handed two inputs it passes the
direction check, then reasons about them as if they were producers, and refuses
with a message about declaration order that has nothing to do with what was
asked.

### Impact

The supported direction works and the smoke covers it (case 6). This one refuses
safely, so nothing is damaged - but the reason given is wrong, and a person
reading it would go looking for a scope problem that is not there.

### How it closed

`main` grew the consuming half - `ComposerConnectionMoves._data_input()`, with
`test/unit/test_composer_data_moves.gd` covering both destinations and all three
refusals, including the scope one this was mistaken for. Reading that test is
not what closes a finding here, though: the smoke said in a comment that the
direction "is not implemented" and asserted nothing, so nothing in this branch
could have told the difference.

Case 6 asserts it now. The fixture grew a second statement reading a value, and
the case drags one argument's pin onto the other's: the value arrives, the slot
it left goes back to a valid default, and it is one undo step.

    6 · two statements read a value                       2
    6 · one of them is fed and the other is not           found /
    6 · the value moved to the other argument             found
    6 · and the slot it left is valid rather than empty
    6 · the consuming move is one step too                0 -> 1

---

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
