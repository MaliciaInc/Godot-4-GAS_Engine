# Authoring friction — measured

Six things a person does while building a game on this engine, measured before
the phase touches any of them and measured again when it is done. "Smaller"
needs a number that existed first, and this is that number.

The measurements are taken by `test/unit/test_authoring_friction.gd`, which
derives each one from the engine itself — an object graph walked, the project's
class list asked, calls actually made and counted — and then checks this file
says the same thing. It does **not** fail because a number is bad: a bad
baseline is why the phase exists. It fails when a measurement cannot be taken,
or when this receipt disagrees with what was measured.

`before` was taken on the F6 baseline `6ed67750110b1cf194b799c8cb0dad8273f6e8bb`,
during F6.0.9, and is history: it is never re-measured.

`now` is what the engine measures today, and it is the column the test checks.
Whoever closes a friction updates it in the same commit that closes it - which
is the discipline this receipt exists to enforce, and the reason the test fails
when the two disagree rather than quietly agreeing with whatever it just found.

F6.4.7 reads both columns and writes the verdict.

| key | before | now | what it counts |
|---|---|---|---|
| modifier_plus_ten_resources | 4 | 4 | Resources a person constructs to put a `+10` on an attribute: the effect, the modifier, the magnitude, and the scalable float it reads. Each is a separate "New Resource" in the inspector. |
| attribute_ref_typo_caught_before_runtime | no | yes | Whether a misspelled attribute name is caught before the game runs. On the baseline `GameplayAttributeRef.is_valid()` only asked whether the fields were filled in, which a typo passes, and the asset validator had nothing to say about a name that does not exist. F6.4.2 ships the catalogue and the inspector picker, which shows a typo in red to whoever opens that row; the validator now asks the same catalogue, so an effect naming an attribute nothing declares is a finding wherever assets are validated rather than only where somebody happens to look. |
| cue_authored_without_a_script | no | yes | Whether a cue with a sound and a particle can be authored as data. On the baseline every cue was a scene whose root carried a `GameplayCueNotify` subclass somebody wrote. F6.2.6 ships two templates - a burst and a loop - that read a `GameplayCueEffectSet`, so a cue is now a Resource of sounds, particles and decals bound to a tag. |
| debug_surface_outside_the_editor | no | yes | Whether a running game can show ability-system state. On the baseline the runtime debugger was an `EditorDebuggerPlugin`, so QA on an exported build saw nothing. F6.4.4 ships `GasDebugOverlay`, a scene the game instantiates itself: four pages - attributes, effects, abilities and tags - each a transformation from a `GasRuntimeSnapshot` to rows, with a bounded 128-entry attribute history behind them. |
| aoe_preview_pieces_shipped | 0 | 5 | What ships towards an area effect a person aims and sees before confirming: a provider that selects by radius, ground trace or placement, and anything that draws the aim. On the baseline four providers shipped and all four were raycast or overlap, with no reticle. F6.3.2 ships the reticle and the task that owns its whole life; F6.3.3 adds four providers - a radius in each dimension, a ground trace and a placement - so the five counted are those four and the reticle. |
| kit_grant_calls | 5 | 1 | Calls to put a loadout of three abilities, one effect and one attribute set onto a character, made one at a time because there is no way to say it once. |
| kit_remove_calls | 5 | 1 | Calls to take the same loadout off again. |

## What each number is expected to become

Written here rather than only in the phase document so the two columns can be
read side by side without one.

| key | target | closed by |
|---|---|---|
| modifier_plus_ten_resources | 1 authoring action produces the whole chain | F6.4.1 |
| attribute_ref_typo_caught_before_runtime | yes, in the inspector | F6.4.2 |
| cue_authored_without_a_script | yes, from a data-driven effect set | F6.2.6 |
| debug_surface_outside_the_editor | yes, four pages with `Engine.is_editor_hint() == false` | F6.4.4 |
| aoe_preview_pieces_shipped | at least a radius provider and a reticle | F6.3.2, F6.3.3 |
| kit_grant_calls | 1 | F6.1.10 |
| kit_remove_calls | 1 | F6.1.10 |

A row that does not reach its target is written as it landed, with the reason.
A receipt that only records what went well is not a receipt.
