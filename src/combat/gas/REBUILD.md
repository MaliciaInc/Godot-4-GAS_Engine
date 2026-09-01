# Combat, rebuilt on GAS_Engine

Not a migration. The old turn-based combat is deleted and combat is written as
it would have been written if GAS_Engine had been there from the first commit.
No compatibility shims, no legacy path, no `BattlerStats` kept alive behind an
adapter. If a concept survives, it survives because a GAS-native design wants
it, not because something used to depend on it.

## What is being deleted

`src/combat/` in full - 28 scripts, 2037 lines:

```text
actions/    battler_action.gd + attack, heal, modify_stats, projectile, hit
battlers/   battler.gd, battler_anim.gd, battler_roster.gd, battler_stats.gd
            combat.gd, combat_ai_random.gd, combat_arena.gd, combat_events.gd
            elements.gd
ui/         action_menu, battler_entry, cursors, effect_labels, ui_combat
```

Plus the authored resources those classes back: the `BattlerStats` and
`BattlerAction` `.tres` files under `combat/battlers/`.

## The model it is rebuilt as

| Concern | Where it lives now |
|---|---|
| Stats | `BattlerAttributes`, an `AttributeSet` - one source of truth per battler |
| A battler | a Node with an `AbilitySystemComponent`; no stats of its own |
| An action | a `GameplayAbility` scene, granted to the ASC |
| Its energy cost | a `GameplayAbilityCost`, paid on commit, refused when unaffordable |
| Damage / healing | `GameplayEffect` with INSTANT modifiers |
| Buffs, debuffs, poison | `GameplayEffect` with a duration, and periodic where it ticks |
| Elements, states, immunity | gameplay tags and tag queries |
| "Can this act right now?" | activation policy plus blocked/required tag queries |
| Targeting | `GameplayAbilityTargetData`, filled by the arena's own selection UI |
| Death | `health` reaching zero, observed through the ASC's attribute signal |

The rule that decides every design question here: **a number is never written,
it is contributed.** A +5 attack buff registers a contribution the engine folds
in while the effect lives and withdraws when it ends. That is what makes a stack
of buffs and debuffs expiring in any order still land on the right number, and
it is why nothing in the rebuilt combat keeps a private copy of a stat.

## Seams with the rest of the game

Combat does not live alone. Seven files outside `src/combat/` reach into it, and
each is a seam the rebuild has to honour - rebuilt on its own terms, not
preserved:

```text
src/main.tscn                                   hosts the combat scene
src/field/field.gd                              enters and leaves combat
src/field/cutscenes/templates/combat/combat_trigger.gd   starts a battle
overworld/maps/town/conversation_encounter.gd   starts one from dialogue
src/common/player.gd                            carries the party
overworld/maps/town/battles/test_combat_arena*.tscn      two authored arenas
```

The field layer asks for a battle and is told how it ended. That contract stays
a contract; what is behind it is new.

## Order of work

1. **Attributes** - `BattlerAttributes`. Done.
2. **The battler** - a Node owning an `AbilitySystemComponent`, its attribute set
   and its granted abilities. Nothing else.
3. **Abilities** - the four authored actions rebuilt as `GameplayAbility` scenes
   with costs, target data and effects.
4. **The arena** - turn order from the `speed` attribute, selection, and the
   ability activation loop.
5. **UI** - reads the ASC's public signals; no polling, no private state.
6. **Seams** - the field/cutscene entry points rewritten against the new arena.
7. **Delete** - `src/combat/` old files and their authored resources, once
   nothing points at them.

Step 7 is last on purpose. Deleting first would leave the project unopenable and
every intermediate step unverifiable, and the whole reason this sandbox exists
is that it can be run.
