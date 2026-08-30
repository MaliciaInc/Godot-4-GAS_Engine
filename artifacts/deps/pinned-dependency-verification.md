# Pinned dependency verification

Evidence for step 1.2 of the Phase 1 plan ("Dependencias pinneadas") and for the
"Verificar SHA antes de copiar" instruction in steps 1.3 and 1.4. Performed
ahead of Task 1 so a wrong pin could not block the bootstrap.

Verified: 2026-08-30 (UTC), against the live upstream remotes.

## GodotGAS

```text
repository: https://github.com/yulrun/godot-gas
pinned:     d1cb86de608050f3bc390064719e7d2830601047
vendor to:  addons/GodotGAS/
```

| Check | Result |
|---|---|
| Commit reachable on the remote | Yes, shallow fetch succeeded |
| Resolved SHA | `d1cb86de608050f3bc390064719e7d2830601047` — exact match |
| Author date | 2026-08-14 14:12:14 -0400 |
| Author | Matthew Janes |
| Subject | `feat(network): implement automatic server-authority interceptors` |

Note: this is the upstream HEAD, three commits past the `v1.0.6` tag. It
carries the undocumented server-authority networking layer, which Task 10
removes. That is expected — the pin is deliberate, not a mistake.

## GUT

```text
repository: https://github.com/bitwes/Gut
pinned tag: v9.7.1
pinned sha: aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605
vendor to:  addons/gut/
```

| Check | Result |
|---|---|
| Tag exists on the remote | Yes |
| `refs/tags/v9.7.1` resolves to | `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` — exact match |
| Highest `v9.x` tag published | `v9.7.1` |
| `addons/gut/gut_cmdln.gd` present | Yes |
| `addons/gut/plugin.cfg` version | `9.7.1` |

### Why this pin is the only correct one

GUT ships a different release per Godot minor. From its own README table:

| GUT release | Supports |
|---|---|
| **v9.7.1** (branch `godot_4_7`) | **4.7.x** |
| main branch | 4.6.x |
| v9.6.1 | 4.6.x |
| v9.5.0 | 4.5.x |

The project targets Godot 4.7.2, so v9.7.1 is the only compatible release.

**GUT's `main` branch trails the release**: it supports 4.6.x, not 4.7.x.
Cloning `main` — the reflexive move — would vendor a version that does not
support this engine. The pin protects against that, and this is the concrete
reason the plan forbids floating branches and "latest".

## Reproducing this check

```bash
git init -q probe && cd probe
git remote add origin https://github.com/yulrun/godot-gas.git
git fetch --depth 1 origin d1cb86de608050f3bc390064719e7d2830601047
git log -1 --format='%H %ci %s' FETCH_HEAD

git ls-remote https://github.com/bitwes/Gut.git refs/tags/v9.7.1
```
