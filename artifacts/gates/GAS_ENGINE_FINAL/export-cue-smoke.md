# Selective export smoke: what actually ships when a cue is bound

Run against the consumer project this engine is developed against
(`godot-open-rpg`, branch `godot-open-rpg_GAS_Engine`), on Godot 4.7.2.stable.

The question was the one left open at the end of the cue-parser work: a cue
scene reachable only through a `preload()` in `gas_engine/gameplay_cues.gd` —
does it survive an export, and does a binding somebody commented out correctly
fail to?

## How it was run

`--export-pack` needs no export templates, so the pack could be produced
without installing any. The pack was then read from its own index rather than
from the exporter's console output: format 4 keeps a directory offset at byte
32 and the index at the end, so the file list is exact.

One cue was bound to a scene the game does not otherwise reach, and a second
binding to another such scene was commented out by hand. Both scenes were
confirmed absent from a baseline pack first, so neither could arrive by any
other route.

## What was measured

| export mode | `gameplay_cues.gd` | active cue's scene | commented-out scene |
|---|---|---|---|
| Selected scenes and dependencies | absent | absent | absent |
| the same, plus `gas_engine/*` in the include filter | present | **absent** | absent |
| Export all resources (Godot's default) | present | present | **present** |
| Selected, plus the include filters and the scene selected | present | present | absent |

Only the last row is the behaviour the design intends, and it is the one the
README now documents.

## Why

`ResourceLoader.get_dependencies()` returns **0** for every `.gd` file —
measured directly on `gameplay_cues.gd` and on the cue manager's own script —
while `src/main.tscn` returns 79. That call is what the exporter walks, so a
`preload()` in GDScript is a compile-time link and never an export dependency.

Two consequences, neither of them specific to cues:

- Row 2 is not a partial fix. An include filter adds the file itself and
  follows nothing from it, so the scene it preloads still does not ship.
- Under the selective mode the addon's own eight scripts, preloaded by the
  `GameplayCueManager` autoload, do not ship either. The autoload does; what it
  preloads does not.

Row 3 ships everything, including the binding a person deliberately commented
out — so "export everything" is not the intended semantics either, it is the
absence of a decision.

## What changed as a result

The engine's behaviour did not change; a false claim about it did.
`gameplay_cue_generator.gd` stated that binding by `preload()` rather than by
path string was what made the exporter aware of the scene. That is not true on
4.7.2 and the header now says what was measured instead. `preload()` stays, for
what it does buy: a parse-time check and a rename the editor can follow.

`README.md` gained an **Exporting** section: nothing to do on Godot's default
mode, and on the selective mode add `addons/GAS_Engine/*, gas_engine/*` to the
include filter and select the cue scenes. The last row of the table above is
that instruction, run.

A build made the wrong way says so at startup — the cue manager pushes
`No cue registry found at ...` when the file is not in the pack — so this fails
loudly rather than silently playing no cues.
