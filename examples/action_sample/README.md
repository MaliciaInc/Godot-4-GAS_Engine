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
| 8 | The same sample across two processes, over a real wire | `network/server_main.gd`, `network/client_main.gd` |

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

## Running it as two processes

The sample is also the engine's only check that bytes actually cross. Every
other networking test in this repository puts two runtimes in one process, which
checks the rules and cannot check the wire - and the difference is not
academic. The first run of this harness found two defects that had been
invisible for the whole of F6.6: this addon's wire is JSON, JSON has a single
number type, and every reader comparing `typeof(value)` against `TYPE_INT`
refused every message that had actually crossed one. Beside it, a `Vector3`
written to JSON arrives as the text `(3, 0, 0)`, so no aim with a position in it
ever reached an authority.

```powershell
pwsh -File tooling/run_multiplayer_sample.ps1
```

It launches an authority and a client as separate operating-system processes
with an ENet connection between them, runs the scenario below, and fails unless
both exited zero, neither reported a fault, and the two ended on the same
reading of the same character. The receipt goes to
`artifacts/gates/F6.6/multiplayer-sample.json`, and
`test/integration/test_network_two_processes.gd` reads it - refusing one older
than the code it vouches for.

Either half can also be run by hand:

```powershell
godot --headless --path . -s res://examples/action_sample/network/server_main.gd -- --server --port=47921 --automation --out=server.json
godot --headless --path . -s res://examples/action_sample/network/client_main.gd -- --client=127.0.0.1:47921 --automation --out=client.json
```

What happens, in order: the client connects and both halves bind the same
character under the same entity id; the authority grants the loadout and sends
one whole snapshot; the client predicts a strike and is told yes; it aims the
slam and sends where it aimed, and the authority validates that against its own
provider; it predicts the channel, spends on it, and is told no - because the
channel's `net_security_policy` reserves starting it to the authority - and the
spending goes back; the client says it has settled, reads the closing snapshot,
and both processes exit.

The three abilities carry the network policies that make this work, and they
are worth reading as three different answers:

| Ability | Where it runs | What the authority accepts | Notes |
|---|---|---|---|
| Strike | `LOCAL_PREDICTED` | `CLIENT_OR_SERVER` | The ordinary predicted ability. |
| Slam | `LOCAL_PREDICTED` | `CLIENT_OR_SERVER` | Predicted so the ring appears now; where it lands is still checked. |
| Channel | `LOCAL_PREDICTED` | `SERVER_ONLY_EXECUTION` | Only the authority starts it, and it replicates while it runs. |
