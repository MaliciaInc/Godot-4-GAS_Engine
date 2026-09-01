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

## Status

Wiring in progress. The base game's own turn-based combat is being replaced by
GAS_Engine-driven combat; see the commit history on this branch.
