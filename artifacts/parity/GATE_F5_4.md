# Gate F5.4 — receipt

Package: F5.4 (F5.4.1 through F5.4.5), covering G20–G24.
Baseline GAS_Engine: `0db4c24441184a67c1b9b606af6ce9d8ec6b917c`.
Reference: Unreal Engine 5.7.4, CL 51494982.

The phase states this gate as ten cases. Each is a place where two subsystems
meet — aiming and applying, applying and animating, animating and announcing —
and each of them is a place the road has actually broken. So the walk that
answers the gate is one file that goes down that road once, and every case is
also proved on its own, in the suite of the package that built it.

Every reference here is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F5_4.md
```

## The ten cases

| # | Case | At the seam | On its own |
|---|---|---|---|
| 1 | target preview + confirm + cancel | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_one_previewing_confirming_and_cancelling` | `test/unit/test_target_provider_lifecycle.gd::test_a_provider_ends_exactly_once`, `test/unit/test_target_provider_lifecycle.gd::test_what_a_provider_confirms_reaches_the_ability` |
| 2 | target destroyed during preview | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_two_a_target_destroyed_during_the_preview_is_not_confirmed` | `test/unit/test_target_provider_lifecycle.gd::test_a_target_that_dies_during_the_preview_is_gone_from_the_next_one` |
| 3 | two colliders on one target are one | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_three_two_hits_on_one_actor_are_one_target` | `test/unit/test_targeting_3d.gd::test_one_actor_with_two_shapes_arrives_once`, `test/unit/test_targeting_2d.gd::test_one_actor_with_two_shapes_arrives_once` |
| 4 | an area effect does not contaminate hits | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_four_an_area_effect_does_not_contaminate_hits` | `test/unit/test_context_per_target.gd::test_an_area_effect_never_tells_one_victim_about_the_other`, `test/unit/test_context_per_target.gd::test_each_victim_is_told_about_itself` |
| 5 | channel cancel | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_five_cancelling_a_channel_releases_its_tasks_and_its_aiming` | `test/unit/test_target_provider_lifecycle.gd::test_an_ability_that_ends_calls_off_its_providers`, `test/unit/test_ability_tasks.gd::test_cleanup_cancels_every_task` |
| 6 | animation replaced becomes interrupted | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_six_a_replaced_animation_interrupts_the_task_that_owned_it` | `test/unit/test_animation_ownership.gd::test_another_animation_starting_interrupts_it`, `test/unit/test_animation_ownership.gd::test_losing_the_claim_interrupts_it_on_the_next_tick` |
| 7 | movement cancel | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_seven_a_cancelled_move_stops_where_it_was` | `test/unit/test_new_ability_task_behaviour.gd::test_a_cancelled_move_leaves_the_body_where_it_got_to` |
| 8 | parent cue fallback | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_eight_a_cue_falls_back_to_its_parent` | `test/unit/test_cue_hierarchy.gd::test_a_request_nobody_bound_falls_back_up_the_family`, `test/unit/test_cue_hierarchy.gd::test_a_silenced_branch_stops_the_walk_before_its_parent` |
| 9 | persistent cue purge | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_nine_removing_an_effect_purges_its_persistent_cue` | `test/unit/test_gameplay_cue_effects.gd::test_removing_the_effect_pools_the_persistent_cue_exactly_once`, `test/unit/test_gameplay_cue_effects.gd::test_cleanup_ends_persistent_cues_exactly_once` |
| 10 | pooling with no residual state | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_ten_a_reused_cue_carries_nothing_of_the_previous_one` | `test/unit/test_cue_hierarchy.gd::test_a_pooled_cue_holds_nothing_from_its_last_run`, `test/unit/test_cue_hierarchy.gd::test_a_reused_cue_answers_with_the_new_run` |

## What changed in the engine while this was closed

Five things that were not reachable before, each of which was a seam rather
than a feature:

- **Choosing a target had no middle.** Targeting was one call into physics,
  which is right for a fireball and wrong for everything a person aims by hand.
  A provider now begins, previews as often as anybody asks, and ends exactly
  once — and an ability that ends calls off whatever it was waiting on.
  `test/unit/test_target_provider_lifecycle.gd::test_an_ability_that_ends_calls_off_its_providers`
- **An area effect told every victim about all of them.** One context travelled
  to every application, so a victim could read where somebody else had been
  struck. Each application now derives a context that carries the origin and
  that victim's aim, and nothing mutable is shared between two of them.
  `test/unit/test_context_per_target.gd::test_two_copies_share_nothing_that_either_of_them_changes`
- **A task waiting on an animation somebody else replaced waited for ever.**
  Godot's `play()` replaces what was running and says nothing to whoever asked
  first, so the first task waited for an `animation_finished` that would never
  carry its name — holding the ability's cost and tags until the ability ended.
  `test/unit/test_animation_ownership.gd::test_losing_the_claim_interrupts_it_on_the_next_tick`
- **A cue had to be bound at the exact tag it was announced under.** A game
  says `Cue.Damage.Fire.Critical` and has art for `Cue.Damage`; the request now
  walks up its own family, and a project can end that walk where it likes.
  `test/unit/test_cue_hierarchy.gd::test_the_nearest_binding_is_the_one_that_answers`
- **Target data handed out targets that were gone.** `confirm()` gives back the
  last preview rather than a fresh look at the world, so a target that died
  during the aiming reached the ability. A freed Node compares equal to null in
  Godot, so a caller skipping nulls was already skipping it and a caller
  counting them was being told an ability hit one more thing than it did.
  `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_two_a_target_destroyed_during_the_preview_is_not_confirmed`

## Deviations

`GameplayCueParams` carries the requested cue tag under the name it has always
had, `cue_tag`, rather than under a new `requested_cue_tag`. The phase lists
"requested cue tag" and "matched cue tag" as two things the params must carry,
and they carry both; renaming the one every caller and every cue script already
uses would buy a matching identifier and cost every consumer of the addon.
`matched_cue_tag` is the one that did not exist.
`test/unit/test_cue_hierarchy.gd::test_a_cue_is_told_what_was_asked_for_and_what_answered`

`override_parent` is authored as a list of tags under `OVERRIDE_PARENT` in the
project's cues file rather than as a flag on `GameplayCueEntry`. The entry
resource is the pre-file registry that `SourceMigration` exists to migrate away
from; the file is the authoring surface now, and a binding's value there is a
`PackedScene` whose type says so, which leaves no room for a third column. A
tag in that list with no binding is the useful case — it says "nothing plays
under here" once, instead of binding every leaf to an empty scene.
`test/unit/test_project_gameplay_cues.gd::test_only_the_real_override_body_counts`
