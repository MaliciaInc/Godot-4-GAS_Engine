# Third-party dependencies

Step 1.6 of the Phase 1 plan. Every vendored dependency is pinned to an exact
commit — never a branch, never "latest" — and the pin is verified against the
live remote before the files are copied. Evidence of that verification lives in
[`artifacts/deps/pinned-dependency-verification.md`](artifacts/deps/pinned-dependency-verification.md).

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

The upstream `LICENSE` is reproduced at the repository root as `LICENSE`, per
step 1.3, because this project is a derivative work of GodotGAS.

This pin is upstream `HEAD`, three commits past the `v1.0.6` tag. It carries the
undocumented server-authority networking layer, which Task 10 removes. The pin
is deliberate: it is the exact tree the phase was planned against, so the
removal is a reviewable diff rather than an absence nobody can check.

The GodotGAS `EditorPlugin` is **not enabled** in `project.godot` this phase.
Upstream registers the `GameplayCueManager` autoload from `_enable_plugin()`,
and `project.godot` declares that autoload directly; enabling both would create
two authorities over the same singleton. Re-enabling the dashboard requires a
deliberate task that makes the registration idempotent and proves there is no
double authority. It is not a Phase 1 runtime requirement.

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
