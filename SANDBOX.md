# GAS_Engine Sandbox — godot-open-rpg

This branch is **not** the GAS_Engine addon. It is the integration sandbox: a
real, playable game that GAS_Engine is wired into, so the engine is exercised by
gameplay rather than only by its unit suite.

The roadmap calls this the *development host / integration harness / manual repro
environment*. It is deliberately not part of the distributed addon.

## What this is

| | |
|---|---|
| Base game | [godot-open-rpg](https://github.com/gdquest-demos/godot-open-rpg) by GDQuest |
| Upstream commit | `19bd328` |
| Engine under test | `addons/GAS_Engine`, copied from `main` at `66ceb1c` |
| Godot | 4.7, GL Compatibility |

## Why a whole game instead of a synthetic harness

The unit suite already covers what can be asserted in isolation - it is green at
30k+ assertions. What it cannot cover is a system meeting a real scene tree: node
lifetimes, autoload ordering, a real Dialogic install, input routing, and the
order real gameplay happens in. Every defect found here is one the suite could
not have found by construction.

## Bug workflow - nothing is fixed in this branch

A defect found here is **recorded, not repaired**. `FINDINGS.md` on this branch
is the list, and the order is fixed:

```text
1. reproduce it here and write it up in FINDINGS.md
2. later, on main: failing regression test first, then the fix
3. re-deploy the addon into this branch
4. re-test the scenario here and mark the finding closed
```

Fixing an engine defect inside the sandbox would put the repair somewhere the
addon is never built from, and the next re-deploy would silently overwrite it.
The sandbox reports; `main` repairs.

## Branch relationship

This is an **orphan branch**. It shares no history with `main`, on purpose:

```text
main                     the addon, its suite, its gates
godot-open-rpg_GAS_Engine  this sandbox game
```

A defect found here is fixed in `main` - with its regression test - and the
addon is then re-copied into this branch. Fixes do not flow the other way, and
this branch is never merged into `main`.

## Licensing

The base game is MIT (GDQuest, 2018) - see `LICENSE`. Its third-party assets and
their licences are listed in `CREDITS.md`. Both are preserved unchanged;
redistribution here relies on them.

`addons/GAS_Engine` is MIT, MaliciaInc - see `addons/GAS_Engine/LICENSE`.
`addons/dialogic` ships with the base game under its own licence.

## What runs here, and what only runs here

Three things, all from the command line, none of them needing the editor:

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path . res://test/gas_probe.tscn      # two arenas, to combat_finished
"$GODOT" --headless --path . res://test/composer_probe.tscn # this game's abilities, read and printed back
"$GODOT" --path . res://test/composer_smoke.tscn            # the Composer, with a hand on the mouse
```

The last one is the Composer 3.2 smoke, and it is the reason this branch exists.
The phase document expects a person to do it because `GraphEdit` reads picking,
dragging, sweeping, panning and zooming inside `_gui_input`, which no script can
call. It turns out a script does not have to: an event pushed into the viewport
is routed by Godot exactly as a real one is, once two things are right, and both
were measured rather than assumed (`test/composer_input.gd` says how).

It needs a window - no `--headless` - and it finishes with a line a runner can
read:

```text
SMOKE_RESULT: PASS passed=N failed=0
```

Every check is a real press, a real travel and a real release. Nothing calls a
handler, which is the whole point: the four defects in `FINDINGS.md` numbered
GAS-006 to GAS-009 were all invisible to the engine's own suite, and three of
them were invisible inside the Godot editor as well.

## First import after a fresh clone

Dialogic rewrites `project.godot` the first time the project is imported with no
`.godot/` present, emptying its own character and timeline directories. It is a
one-time artifact - see `FINDINGS.md` SBX-002. Let the editor finish importing,
then:

```bash
git checkout -- project.godot
```

## Status

Wiring in progress. The base game's own turn-based combat is being replaced by
GAS_Engine-driven combat; see the commit history on this branch.
