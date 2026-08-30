# Third-party dependencies

Every vendored dependency is pinned to an exact commit — never a branch, never
"latest" — and each pin was verified against the live remote before the files
were copied.

## Godot Engine

| | |
|---|---|
| Version | `4.7.2.stable.steam` |
| Build hash | `ed1daf0bf` |
| Renderer | Forward+ |
| Source | Steam |

The exact patch version, not the `4.7` that `project.godot` records in
`config/features`. The GDScript warnings this project promotes to errors are the
ones this version defines: a different patch release can add a warning and turn
a green tree red without a line of this repository changing.

## GodotGAS

| | |
|---|---|
| Repository | https://github.com/yulrun/godot-gas |
| Pinned commit | `d1cb86de608050f3bc390064719e7d2830601047` |
| Commit date | 2026-08-14 14:12:14 -0400 |
| Commit subject | `feat(network): implement automatic server-authority interceptors` |
| Author | Matthew Janes (YulRun) |
| License | MIT |
| Vendored to | `addons/GodotGAS/` |
| Vendored on | 2026-08-30 |

The upstream `LICENSE` is reproduced at the repository root as `LICENSE`,
because this project is a derivative work of GodotGAS.

This pin is upstream `HEAD`, three commits past the `v1.0.6` tag. It carries an
undocumented server-authority networking layer, which this fork removes. The pin
is deliberate: pinning the tree that still contains it makes the removal a
reviewable diff rather than an absence nobody can check.

The GodotGAS `EditorPlugin` is enabled in `project.godot`. Upstream registered
the `GameplayCueManager` autoload unconditionally from `_enable_plugin()`, and
`project.godot` declares that autoload directly, so enabling both would have
created two authorities over one singleton. The fork's registration is
idempotent instead: it adds the autoload only when the project does not already
declare it, and removes it on disable only when it was the one that added it.

## GUT (Godot Unit Test)

| | |
|---|---|
| Repository | https://github.com/bitwes/Gut |
| Pinned tag | `v9.7.1` |
| Pinned commit | `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` |
| Commit date | 2026-07-09 13:04:12 -0400 |
| Author | Tom "Butch" Wesley |
| License | MIT (`addons/gut/LICENSE.md`, retained in the vendored tree) |
| Vendored to | `addons/gut/` |
| Vendored on | 2026-08-30 |

GUT ships a different release per Godot minor version. v9.7.1 (branch
`godot_4_7`) is the only release supporting 4.7.x, which is what this project
targets.

**GUT's `main` branch trails the release**: it supports 4.6.x. Cloning `main` —
the reflexive move — would vendor a version that does not support this engine.
That is the concrete reason the plan forbids floating branches.

## Optional integration compatibility

These three are **not bundled**: no part of them is in this repository, none is
a dependency, and the engine runs without any of them installed. They are listed
because the addon ships an optional bridge for each, and a bridge is only worth
calling official if it names the version it was proved against.

Each bridge was run against the commit below - not against a description of it -
in a project containing that addon and nothing else of the three.

### Dialogic

| | |
|---|---|
| Repository | https://github.com/dialogic-godot/dialogic |
| Certified version | `2.0-alpha-20` |
| Certified commit | `e301e1bb5e62e6de22c6b7748c4372d0570bb4a7` |
| License | MIT |
| Bundled | No; optional integration only |

Deliberately an alpha, and its API can move between releases. The bridge depends
on the `Dialogic` autoload and its published `signal_event` signal, and on
nothing else - no subsystem, no internal class, no editor structure. One signal
is a small enough surface to be worth betting on; the guarantee still applies
only to the commit above.

### GLoot

| | |
|---|---|
| Repository | https://github.com/peter-kish/gloot |
| Certified version | `v3.0.2` |
| Certified commit | `ce88b7adc7b952b4df8ebe4836339de334d0d0cc` |
| License | MIT |
| Bundled | No; optional integration only |

The bridge listens to an `ItemSlot`: its `item_equipped` and `cleared` signals,
its `get_item()`, and the equipped item's `get_prototype().get_id()`. GLoot
registers no autoload and the bridge needs none.

### QuestSystem

| | |
|---|---|
| Repository | https://github.com/shomykohai/quest-system |
| Certified version | `2.0.2.4_4` |
| Certified commit | `d1d933c7b1822aceb637e3d6fe3a4814f973c3ee` |
| License | MIT |
| Bundled | No; optional integration only |

The bridge uses the `QuestSystem` autoload's three published signals, its
`update_quest` and `complete_quest`, and a quest's `id`. It never touches the
addon's quest pools, so a project that configures its own pools does not change
how the bridge behaves.

Their licenses are not reproduced here. This repository does not distribute
their bytes, so there is nothing of theirs to license onward; each project's own
terms travel with the copy a user installs.

## Reproducing the vendor

```bash
git clone https://github.com/yulrun/godot-gas.git /tmp/godot-gas-src
git -C /tmp/godot-gas-src checkout d1cb86de608050f3bc390064719e7d2830601047
cp -r /tmp/godot-gas-src/GodotGAS addons/GodotGAS
cp /tmp/godot-gas-src/GodotGAS/LICENSE LICENSE

git clone https://github.com/bitwes/Gut.git /tmp/gut-src
git -C /tmp/gut-src checkout aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605
cp -r /tmp/gut-src/addons/gut addons/gut
```

Verify each SHA with `git rev-parse HEAD` before copying. A mismatch means the
vendor is not reproducible and the tree must not be committed.
