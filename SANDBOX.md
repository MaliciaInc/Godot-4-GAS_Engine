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
| Engine under test | `addons/GAS_Engine`, copied from `main` at `6704f19`, with `gas_engine/` re-rendered here |
| Godot | 4.7, GL Compatibility |

## Why a whole game instead of a synthetic harness

The unit suite already covers what can be asserted in isolation - it is green at
67k+ assertions. What it cannot cover is a system meeting a real scene tree: node
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

### What a re-deploy is, in full

Copying `addons/GAS_Engine` is most of it, but not all of it, and the half that
was missed went unnoticed for two phases.

```text
1. copy addons/GAS_Engine from main, whole
2. re-render gas_engine/ with the generators that were just copied
```

`gas_engine/` is not the addon - it is what the addon generates *into* a host
project, and this project is a host. Its files are this project's own, down to
their `.uid`s, so they are never copied from main. They are re-rendered here,
by asking this project's freshly-copied generators to write back what this
project already declares:

```gdscript
GameplayTagGenerator.generate_tags_file(GameplayTagGenerator.tags_in_file())
GDScriptSource.write(
	GASEngineProjectSettings.get_generated_cue_script_path(),
	GameplayCueGenerator.render_source(
		GameplayCueGenerator.bindings_in_file(),
		GameplayCueGenerator.overrides_in_file(),
		GameplayCueGenerator.handlers_in_file()
	)
)
```

Skipping step 2 is quiet rather than loud: a declaration a newer engine writes
is simply absent, and every reader of an absent declaration reads it as empty.
So the project keeps running and the features that declaration carries test
nothing. That is what happened between `08bd807` and F6.4.3 - `REDIRECTS`,
`RESTRICTED`, `COMMENTS`, `HANDLERS` and `OVERRIDE_PARENT` were all missing
here while the addon beside them was current.

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

`addons/GAS_Engine` is MaliciaInc's GAS_Engine, under the GAS_Engine Community
Use License 1.0: free to use unmodified, with modification reserved to a
separate paid Commercial Modification License. Both are `LICENSE` and
`COMMERCIAL-LICENSE.md` on the `main` branch of `MaliciaInc/Godot-4-GAS_Engine`,
which is where the addon is copied from.
`addons/dialogic` ships with the base game under its own licence.

## What runs here, and what only runs here

All from the command line; only the last one opens the editor:

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path . res://test/gas_probe.tscn             # two arenas, to combat_finished
"$GODOT" --headless --path . res://test/composer_probe.tscn        # this game's abilities, read and printed back
"$GODOT" --headless --path . res://test/gas_contract_probe.tscn    # the engine's contracts, through Battler.act()
"$GODOT" --headless --path . res://test/composer_game_probe.tscn   # an ability made in the Composer, run in the game
"$GODOT" --headless --path . res://test/gas_overlay_probe.tscn     # the runtime overlay, over this game's theme
"$GODOT" --headless --path . res://test/dialogic_bridge_probe.tscn # real Dialogic timelines into the bridge
"$GODOT" --path . res://test/composer_harness.tscn                 # the Composer, 58 checks, needs a window
"$GODOT" --path . res://test/composer_smoke.tscn                   # the Composer, with a hand on the mouse
"$GODOT" --editor --path . -- --gas-editor-probe                   # the Gameplay Effect panel and the Debugger tab, in a real editor
```

### The four that hold the engine to its word in a real game

Each ends with a line a runner can read, and each checks that every one of its
cases ran to its last line - a case that stops part way fails the run instead of
quietly shrinking it, which is SBX-009's lesson applied from the start.

| Probe | Result line | What it holds GAS_Engine to |
|---|---|---|
| `gas_contract_probe` | `GAS_CONTRACT_RESULT: PASS passed=N failed=0` | Damage and overkill, a corpse refused, healing and its ceiling, a cost refused and a cost paid, a cooldown counted in turns, energy bounds, two buffs stacking and withdrawn to exactly base, percentages bounded, a ceiling dropping under its pool, and a swing cancelled in its windup and in the air - on real battlers, through `Battler.act()`, the seam the game itself uses. |
| `composer_game_probe` | `COMPOSER_GAME_RESULT: PASS passed=N failed=0` | Every ability in this game and the engine's reference abilities read and printed back byte for byte; a new ability made through the Composer's own document and statement operations, saved, given to Baloo and run - and it has to actually wait; refusals that say why rather than saying done. |
| `gas_overlay_probe` | `GAS_OVERLAY_RESULT: PASS passed=N failed=0` | `GasDebugOverlay` watching Baloo: its pages, attribute rows, an effect row that says which effect it is, cooldown tags, refreshing while the game is paused, the watched battler freed under it, and its text at its own size over a game theme that says 96. |
| `dialogic_bridge_probe` | `DIALOGIC_BRIDGE_RESULT: PASS passed=N failed=0` | Timelines built with `DialogicTimeline.from_text` and started with `Dialogic.start_timeline` against a real battler: tags added and removed, an event with a magnitude waking a listening ability, the game's own signal traffic left alone, malformed messages refused, channels, the legacy bridge name, two bridges on one bus, a freed target, a freed bridge, and unbinding. |

`test/dialogic_probe_listener.gd` is the listening ability the bridge probe
wakes. What the four found the first time they ran is in `FINDINGS.md`, GAS-011
to GAS-016 and SBX-010 to SBX-012.

### The one that opens the editor

`addons/gas_editor_probe/` is an `EditorPlugin`, enabled in this project and
inert unless the editor is started with `-- --gas-editor-probe`. The engine's
suite can prove the Gameplay Effect panel and the Debugger tab only in parts,
because an editor plugin refuses to exist outside an editor; this is the check
that an editor actually shows them.

It opens an effect whose modifier names its attribute the way the Inspector's
picker does, and looks for the panel, the modifier's row and the attribute's
name on it. It plays `test/gas_probe.tscn` and looks for the GAS_Engine tab
listing the running battlers, drawing a page and their events, and being sent
the same battler again several times in two seconds. Then it brings that tab up,
closes the editor, and ends with `GAS_EDITOR_PROBE_RESULT: PASS passed=N failed=0`.
Screenshots go to `user://gas_editor_probe`.

The editor rewrites `project.godot` as it opens, so run
`git checkout -- project.godot` afterwards, as after any editor run - the
probe's entry in `[editor_plugins]` is committed and comes back with it.

`gas_probe`, the first in that list, says one thing and one thing only: **both arenas reach
`combat_finished`**. It is not reproducible round for round - accuracy is rolled
off a stream whose draw order moves with the wall clock - so comparing a run
against the last one reads as a regression when nothing has changed. SBX-005 in
`FINDINGS.md` has the measurements; do not use round counts as evidence.

`composer_smoke` is the Composer 3.2 smoke, and it is the reason this branch exists.
The phase document expects a person to do it because `GraphEdit` reads picking,
dragging, sweeping, panning and zooming inside `_gui_input`, which no script can
call. It turns out a script does not have to: an event pushed into the viewport
is routed by Godot exactly as a real one is, once two things are right, and both
were measured rather than assumed (`test/composer_input.gd` says how).

It needs a window - no `--headless` - and it finishes with a line a runner can
read:

```text
SMOKE_RESULT: PASS passed=89 failed=0
```

Green at the re-deploy of `main`'s `6704f19`, as are the other eight: the four
in the table at 47, 28, 16 and 34 checks, `composer_harness` at 58, `gas_probe`
with both arenas reaching `combat_finished`, `composer_probe` printing this
game's ability back byte for byte, and the editor probe at 13. At the re-deploy
of `9a26ef6` the smoke ran 87 of 89 once, because the Windows clipboard could not
be opened on that machine at the time - see "Checked and not defects" in
`FINDINGS.md`. The smoke was first green at `aad0cbc`. It was not, and the two checks that were red were the
harness aiming at a card that was off the canvas rather than anything the engine
did - see GAS-009 under "Checked and not defects", which is worth reading before
writing up the next one.

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
