# GAS_Engine Documentation

The user documentation for **GAS_Engine**, a production-oriented Gameplay Ability System for **Godot 4.7.2**. It covers the runtime API, the Ability Composer, and how to build a game on top of both.

| Section | What it is for |
|---|---|
| [Quickstart](docs/quickstart.md) | A damaging ability, cast on a character and visible in the runtime overlay, in about ten minutes. |
| [Getting Started](docs/getting-started/) | Installation, the core concepts, the project layout and the editor tools. |
| [Guides](docs/guides/) | One page per subsystem: what it guarantees, how to use it, and what to avoid. |
| [Tutorials](docs/tutorials/) | End-to-end walkthroughs, including GAS_Engine wired into a complete turn-based RPG. |

## Reading paths

| If you want to… | Read, in order |
|---|---|
| Learn GAS_Engine from scratch | [Quickstart](docs/quickstart.md) → [Core concepts](docs/getting-started/core-concepts.md) → [Attributes](docs/guides/attributes.md) → [Gameplay effects](docs/guides/gameplay-effects/index.md) → [Abilities](docs/guides/abilities/index.md) |
| Design abilities visually | [Editor tools](docs/getting-started/editor-tools.md) → [Ability Composer](docs/guides/ability-composer/index.md) → [Build an ability in the Composer](docs/tutorials/build-an-ability-in-the-composer.md) |
| Put GAS_Engine into an existing game | [Core concepts](docs/getting-started/core-concepts.md) → [Integrate GAS_Engine into a turn-based RPG](docs/tutorials/integrate-gas-into-a-turn-based-rpg.md) → [Common pitfalls](docs/guides/common-pitfalls.md) |
| Ship a multiplayer game | [Networking](docs/guides/networking.md) → [Multiplayer across two processes](docs/tutorials/multiplayer-across-two-processes.md) |

## Every page

```text
docs/
├── quickstart.md
├── getting-started/
│   ├── installation.md
│   ├── core-concepts.md
│   ├── project-layout.md
│   └── editor-tools.md
├── guides/
│   ├── ability-system-component.md
│   ├── attributes.md
│   ├── gameplay-effects/
│   │   ├── index.md
│   │   ├── modifiers-and-magnitudes.md
│   │   ├── duration-and-periodic-effects.md
│   │   ├── stacking.md
│   │   ├── components.md
│   │   └── executions-and-context.md
│   ├── abilities/
│   │   ├── index.md
│   │   ├── activation-and-input.md
│   │   ├── costs-and-cooldowns.md
│   │   ├── tag-rules.md
│   │   ├── granting-and-loadouts.md
│   │   └── ability-tasks.md
│   ├── gameplay-tags.md
│   ├── gameplay-events.md
│   ├── gameplay-cues.md
│   ├── targeting.md
│   ├── ability-composer/
│   │   ├── index.md
│   │   ├── editing-abilities.md
│   │   ├── what-the-composer-can-draw.md
│   │   └── custom-nodes.md
│   ├── debugging.md
│   ├── networking.md
│   ├── integrations/
│   │   ├── dialogic.md
│   │   ├── gloot.md
│   │   └── quest-system.md
│   ├── configuration-and-export.md
│   └── common-pitfalls.md
└── tutorials/
    ├── build-an-ability-in-the-composer.md
    ├── integrate-gas-into-a-turn-based-rpg.md
    ├── action-sample-walkthrough.md
    ├── custom-damage-execution.md
    ├── multiplayer-across-two-processes.md
    └── testing-your-gameplay.md
```

## Conventions

- **Code is strictly typed GDScript.** GAS_Engine promotes GDScript warnings to errors, so the samples declare every type and never use `:=`.
- **Names are exact.** Every class, method, signal, enum value and project setting in these pages exists in the addon under that name.
- **Format.** The pages are Docusaurus-flavoured Markdown: front matter, `_category_.json` files for the sidebar, and `:::tip` / `:::warning` admonitions. They also read as plain Markdown on GitHub, and cross-links are relative.
