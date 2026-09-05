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

## GAS-010 — Ctrl-drag between two argument pins refuses with the wrong reason · **OPEN**

**Status:** `OPEN` — reproduced here, no regression test on main yet
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

---

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

## GAS-009 — Alt over a data argument's pin does nothing · **OPEN**

**Status:** `OPEN` — reproduced here, no regression test on main yet
**Severity:** medium - one of the four documented pin gestures, on one family of pins
**Where:** `addons/GAS_Engine/editor/composer/composer_card.gd` (a `GraphNode`)

### Repro

`test/composer_smoke.gd` case 7, against
`addons/GAS_Engine/reference/sweeping_volley.gd`, whose
`apply_effect_to_targets(damage, found)` takes a cable on its second argument.

Alt+LMB exactly on that argument's pin. The harness checks its aim first and the
engine agrees with it:

```text
ok    7 · the argument's pin is the one the engine finds there   aimed at n36.arg_1, engine finds n36.arg_1
FAIL  7 · and the canvas heard the gesture                        0 events reached it
FAIL  7 · Alt over the argument's pin takes the cable off         14 -> 14
```

### Expected / Actual

**Expected**, from section 2.4 of the phase document: "Alt+LMB sobre un pin
rompe todas las conexiones de ese pin en una sola transacción." A pin, not an
execution pin.

**Actual:** nothing happens and nothing is said. The canvas never receives the
event: `ComposerCard` is a `GraphNode`, a press inside its rectangle is the
node's, and an argument's pin sits against the left edge well inside it. The
execution output pins that do work sit on the outer edge, which is why case 4
passes and this does not.

### Impact

A cable a person can see and cannot clear with the gesture the editor documents.
The Inspector's disconnect still works, so nothing is stuck - it is the gesture
that is missing.

### Suggested shape of the fix (for `main`, not here)

Not by overriding `_gui_input`: GraphNode's own handler is not callable from
GDScript (`super._gui_input()` is refused at parse time), so an override would
replace dragging and selection wholesale. The card's `gui_input` **signal** is
emitted before the widget's handler and `accept_event()` from it stops that
handler, which is the same door the canvas already uses. A card that recognised
a press within reach of one of its own pins, accepted it and passed it on would
close the whole family - inputs, arguments and outputs alike - rather than the
one case measured here.

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
