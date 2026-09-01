# Third-party dependencies and notices

GAS_Engine is licensed under the **GAS_Engine Community Use License 1.0** at the repository root. Third-party software and third-party source portions, where present, are not relicensed by the GAS_Engine license and retain their own applicable terms.

This file records third-party dependencies, compatibility targets, and notices separately from the license governing original GAS_Engine material.

## Godot Engine

| | |
|---|---|
| Version | `4.7.2.stable.steam` |
| Build hash | `ed1daf0bf` |
| Renderer | Forward+ |
| Source | Steam |

The exact patch version, rather than only `4.7`, matters because GDScript warnings promoted to errors can change between patch releases.

Godot Engine is a separate third-party project and is not relicensed by this repository.

## Legacy MIT source notice

The current repository history and vendored source tree include material that originated from the project previously tracked at:

| | |
|---|---|
| Repository | `https://github.com/yulrun/godot-gas` |
| Pinned commit | `d1cb86de608050f3bc390064719e7d2830601047` |
| Commit date | 2026-08-14 14:12:14 -0400 |
| Commit subject | `feat(network): implement automatic server-authority interceptors` |
| Author | Matthew Janes (YulRun) |
| Original license | MIT |
| Historical vendored path | `addons/GodotGAS/` |
| Current canonical product path | `addons/GAS_Engine/` |
| Vendored on | 2026-08-30 |

The applicable MIT notice is retained alongside any material for which that notice is required. This third-party notice does **not** make Arhalies GAS as a whole MIT-licensed and does not replace the root Arhalies GAS Community Use License.

As the Arhalies GAS codebase is independently rewritten and its repository paths are normalized, third-party notices should be retained only for material to which they remain legally applicable.

## GUT (Godot Unit Test)

| | |
|---|---|
| Repository | `https://github.com/bitwes/Gut` |
| Pinned tag | `v9.7.1` |
| Pinned commit | `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605` |
| Commit date | 2026-07-09 13:04:12 -0400 |
| Author | Tom "Butch" Wesley |
| License | MIT (`addons/gut/LICENSE.md`, retained in the vendored tree) |
| Vendored to | `addons/gut/` |
| Vendored on | 2026-08-30 |

GUT ships a different release per Godot minor version. v9.7.1 from its Godot 4.7 line is the version used by this repository.

GUT is a third-party test dependency. Its MIT license applies to GUT itself, not to original GAS_Engine source code.

## Optional integration compatibility

The following projects are **not bundled as core dependencies**. GAS_Engine can operate without them. They are listed because optional integration bridges are tested against specific versions.

### Dialogic

| | |
|---|---|
| Repository | `https://github.com/dialogic-godot/dialogic` |
| Certified version | `2.0-alpha-20` |
| Certified commit | `e301e1bb5e62e6de22c6b7748c4372d0570bb4a7` |
| License | MIT |
| Bundled | No; optional integration only |

The bridge depends on a narrow published surface, including the Dialogic autoload and its signal interface. Compatibility is certified only for the commit listed above unless a later version is explicitly tested.

### GLoot

| | |
|---|---|
| Repository | `https://github.com/peter-kish/gloot` |
| Certified version | `v3.0.2` |
| Certified commit | `ce88b7adc7b952b4df8ebe4836339de334d0d0cc` |
| License | MIT |
| Bundled | No; optional integration only |

The bridge uses GLoot's published item-slot surface. GLoot remains a separate project under its own license.

### QuestSystem

| | |
|---|---|
| Repository | `https://github.com/shomykohai/quest-system` |
| Certified version | `2.0.2.4_4` |
| Certified commit | `d1d933c7b1822aceb637e3d6fe3a4814f973c3ee` |
| License | MIT |
| Bundled | No; optional integration only |

The bridge uses QuestSystem's published signals and public update/completion surface. QuestSystem remains a separate project under its own license.

## License boundary

The repository intentionally separates two categories:

1. **Original GAS_Engine material**: governed by the root `LICENSE`, the GAS_Engine Community Use License 1.0, with modification rights available only through a separate Commercial Modification License.
2. **Third-party material**: governed by the applicable third-party license accompanying that material or identified here.

A third-party dependency using MIT does not convert original GAS_Engine code to MIT. Conversely, the GAS_Engine Community Use License does not remove rights or notices that apply to third-party code.

See `COMMERCIAL-LICENSE.md` for the paid modification licensing model covering rights MaliciaInc owns or is legally entitled to license.
