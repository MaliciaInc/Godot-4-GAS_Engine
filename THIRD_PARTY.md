# Third-party dependencies and notices

GAS_Engine is licensed under the **GAS_Engine Community Use License 1.0** at the repository root. Third-party software and third-party source portions, where present, are not relicensed by the GAS_Engine license and retain their own applicable terms.

This file records third-party dependencies, compatibility targets, and notices separately from the license governing original GAS_Engine material.

## Origin

GAS_Engine began as a fork of `github.com/yulrun/godot-gas`, at commit
`d1cb86de608050f3bc390064719e7d2830601047`, and was then rebuilt. The
subsystems were rewritten, the architecture and the public surface were
replaced, the name changed, and what is here is a different product.

That origin is recorded because it is true, not because anything of it survives.
Of the 24 script files in that project at that commit, **none is present in this
tree**: not one is byte-identical, and the closest surviving resemblance is a
class name plus two field names that GAS_Engine takes from Unreal's Gameplay
Ability System - which is where the upstream project took them from as well.

Nothing in this repository is therefore governed by that project's terms. **Every
file here that MaliciaInc wrote is licensed only under the GAS_Engine Community
Use License 1.0 at the repository root, and under nothing else.** A permissive
license upstream of a rewrite does not reach across it, and no notice anywhere in
this repository should be read as granting rights over GAS_Engine.

## Godot Engine

| | |
|---|---|
| Version | `4.7.2.stable.steam` |
| Build hash | `ed1daf0bf` |
| Renderer | Forward+ |
| Source | Steam |

The exact patch version, rather than only `4.7`, matters because GDScript warnings promoted to errors can change between patch releases.

Godot Engine is a separate third-party project and is not relicensed by this repository.

## GUT (Godot Unit Test)

| | |
|---|---|
| Repository | `https://github.com/bitwes/Gut` |
| Pinned tag | `v9.7.1` |
| Pinned commit | `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` |
| Commit date | 2026-07-09 13:04:12 -0400 |
| Author | Tom "Butch" Wesley |
| License | Its own, retained verbatim at `addons/gut/LICENSE.md` |
| Vendored to | `addons/gut/` |
| Vendored on | 2026-08-30 |

GUT ships a different release per Godot minor version. v9.7.1 from its Godot 4.7 line is the version used by this repository.

GUT is a third-party test tool, not part of the engine and not shipped in a game. Its own license, in its own folder, applies to GUT and to nothing else in this repository.

## Optional integration compatibility

The following projects are **not bundled as core dependencies**. GAS_Engine can operate without them. They are listed because optional integration bridges are tested against specific versions.

### Dialogic

| | |
|---|---|
| Repository | `https://github.com/dialogic-godot/dialogic` |
| Certified version | `2.0-alpha-20` |
| Certified commit | `e301e1bb5e62e6de22c6b7748c4372d0570bb4a7` |
| Bundled | No; optional integration only |

The bridge depends on a narrow published surface, including the Dialogic autoload and its signal interface. Compatibility is certified only for the commit listed above unless a later version is explicitly tested.

### GLoot

| | |
|---|---|
| Repository | `https://github.com/peter-kish/gloot` |
| Certified version | `v3.0.2` |
| Certified commit | `ce88b7adc7b952b4df8ebe4836339de334d0d0cc` |
| Bundled | No; optional integration only |

The bridge uses GLoot's published item-slot surface. GLoot remains a separate project under its own license.

### QuestSystem

| | |
|---|---|
| Repository | `https://github.com/shomykohai/quest-system` |
| Certified version | `2.0.2.4_4` |
| Certified commit | `d1d933c7b1822aceb637e3d6fe3a4814f973c3ee` |
| Bundled | No; optional integration only |

The bridge uses QuestSystem's published signals and public update/completion surface. QuestSystem remains a separate project under its own license.

## License boundary

The repository intentionally separates two categories:

1. **Original GAS_Engine material**: governed by the root `LICENSE`, the GAS_Engine Community Use License 1.0, with modification rights available only through a separate Commercial Modification License.
2. **Third-party material**: governed by the applicable third-party license accompanying that material or identified here.

The terms of a third-party dependency do not travel to GAS_Engine, and the GAS_Engine Community Use License does not travel to that dependency. Neither direction is a grant.

See `COMMERCIAL-LICENSE.md` for the paid modification licensing model covering rights MaliciaInc owns or is legally entitled to license.
