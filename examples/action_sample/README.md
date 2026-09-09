# Action sample

A 3D character with three abilities, three things to hit, and the engine's own
debugger drawn by the game rather than by the editor. It is the answer to "how
do I use this", and it is checked on every run of the engine's suite by
`test/unit/test_action_sample_probe.gd`, so it cannot quietly stop working.

## What it demonstrates

| # | What | Where |
|---|---|---|
| 1 | An instant attack with a burst cue | `abilities/sample_basic_attack.gd` |
| 2 | A channel with a persistent looping cue | `abilities/sample_channel.gd` |
| 3 | A ground area effect with a reticle and a preset | `abilities/sample_ground_slam.gd`, `targeting/sample_targeting.gd` |
| 4 | A loadout granted and taken back in one call each | `scripts/sample_loadout.gd` |
| 5 | The runtime overlay, outside the editor | `scripts/sample_world.gd` |
| 6 | A refusal visible as a failure tag | `tests/sample_probe.gd` |
| 7 | A deterministic automated probe | `tests/sample_probe.gd` |

## Running it inside the engine's repository

Open the engine's project and play `examples/action_sample/main.tscn`. Nothing
else is needed: the addon is already there and its autoload is already running.

## Running it as a project of its own

The sample carries no copy of the engine, deliberately - a vendored runtime goes
stale the first time the engine changes, and teaches whoever reads it the
version it was copied from. So:

1. Copy this folder out of the engine's repository.
2. Rename `project.godot.standalone` to `project.godot`. It is not called that
   here because Godot skips any directory containing a file by that name - the
   sample would stop being compiled and stop being checked by the engine's own
   suite, which is the one thing keeping it from quietly going stale.
3. Put `addons/GAS_Engine` beside it, from the asset library or by copying it
   out of the engine's repository.
4. Open the folder in Godot and enable the plugin if it is not already.
5. Play.

## What is authored in code, and why

Every effect, cue and preset here is built by a static function rather than
saved as a `.tres`. That is a decision about this sample rather than a
recommendation: it keeps every number in the diff, under the same gates as the
rest of the engine, so a reader can see what a strike costs without opening an
inspector. A project of your own authors these in the effect editor the addon
ships, which produces exactly these objects.

The cues are bound in code for a different reason: this sample lives inside the
engine's own repository and must not rewrite the repository's cue registry to
run. A project of your own lists them in the registry file the
`gas_engine/resources/cues/registry_file` setting points at.

## What comes next

F6.6 runs `SampleProbe` against a server and a client of this same sample and
asks whether the two agree.
