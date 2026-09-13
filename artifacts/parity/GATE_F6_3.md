# Gate F6.3 — receipt

Package: F6.3 (F6.3.1 through F6.3.4), targeting.
Baseline: `1a28510` — the tree F6.2 closed on.
Reference: Unreal Engine Gameplay Ability System 5.7.4, CL 51494982.

Every reference below is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_3.md
```

## What this package closed

| Finding | State | Evidence |
|---|---|---|
| G-16 an aim can be a place with nothing standing at it | CLOSED | `test/unit/test_target_data_locations.gd::test_a_location_is_recorded_without_inventing_anything_to_stand_there` |
| G-16 a place and nobody at all are different answers | CLOSED | `test/unit/test_target_data_locations.gd::test_applying_to_a_location_reaches_nobody_and_says_so` |
| G-16 an aim crosses a wire as identities and numbers | CLOSED | `test/unit/test_target_data_locations.gd::test_an_aim_round_trips_as_identities_and_numbers` |
| G-16 an unknown entity does not come back as somebody else | CLOSED | `test/unit/test_target_data_locations.gd::test_a_hit_on_an_unknown_entity_does_not_come_back_as_somebody_else` |
| G-16 a reticle is told where, whether, how big and which way | CLOSED | `test/unit/test_targeting_reticle.gd::test_a_reticle_is_told_where_whether_how_big_and_which_way` |
| G-16 the task owns the reticle's whole life | CLOSED | `test/unit/test_targeting_reticle.gd::test_the_task_draws_what_the_provider_announces_and_takes_it_away` |
| G-16 and no provider holds one | CLOSED | `test/unit/test_targeting_reticle.gd::test_no_provider_holds_a_reticle` |
| G-16 four ways an aim can be finished | CLOSED | `test/unit/test_target_confirmation_policy.gd::test_an_instant_aim_confirms_itself_once_it_has_something` |
| G-16 and the one that answers more than once | CLOSED | `test/unit/test_target_confirmation_policy.gd::test_a_multi_aim_answers_more_than_once_and_keeps_going` |
| G-16 a server refuses what a provider could not have produced | CLOSED | `test/unit/test_target_confirmation_policy.gd::test_a_radius_provider_refuses_a_target_outside_its_circle` |
| G-16 a ground trace answers with a place, never an actor | CLOSED | `test/unit/test_target_confirmation_policy.gd::test_a_ground_trace_refuses_a_claim_that_names_an_actor` |
| G-16 a placement out of range aims at nothing rather than stopping | CLOSED | `test/unit/test_target_confirmation_policy.gd::test_a_placement_out_of_range_aims_at_nothing_rather_than_stopping` |
| G-16 an aim authored as a list of steps, in order | CLOSED | `test/unit/test_targeting_presets.gd::test_steps_run_in_authored_order_each_handed_the_last_ones_answer` |
| G-16 and the same list answers the same way twice | CLOSED | `test/unit/test_targeting_presets.gd::test_the_same_preset_on_the_same_world_answers_the_same_way` |
| G-16 select, filter, sort and take, against real physics | CLOSED | `test/unit/test_targeting_presets.gd::test_an_area_of_enemies_nearest_first_keeps_the_nearest_one` |
| G-16 sorting does not drop the place an earlier step found | CLOSED | `test/unit/test_targeting_presets.gd::test_sorting_carries_the_place_an_earlier_step_found` |

The phase document's traceability names F6.1.5 and F6.6.3 as G-16's other
owners. F6.1.5 shipped the generic confirm this package aims through; F6.6.3
owns replicating an aim rather than taking one, and nothing here claims it.

## The walk

`test/unit/test_targeting_to_three_victims_walk.gd::test_the_whole_targeting_contract_walks_from_a_spot_to_three_victims`

One aim end to end: a person points at the ground, a reticle follows the spot,
the component's generic confirm takes it, a preset turns the place into
everything within six metres that is an enemy nearest-first, the first three,
and the effect lands on exactly those three and on nobody else.

## Two decisions this package made that the document left open

- **The target-data codec is its own file rather than two methods on the
  payload.** The document names `to_wire(registry)` and `from_wire(wire,
  registry)`; those exist with those shapes on `GameplayTargetDataTranslator`.
  They cannot live on `GameplayAbilityTargetData`: that payload is inside the
  GameplayCueManager autoload's parse-time closure, and a registry-typed
  parameter there would pull the network registry and the ability system
  component into a closure Godot parses before any of it can resolve. The
  project invariant that protects that closure is what refuses it, not taste.
- **The two providers that answer with a place share a subclass.** The document
  says to extend the existing provider rather than create another base, and
  `GameplayLocationProvider3D` is a `GameplayTargetProvider` like every other -
  it exists because a ground trace and a placement are the same kind of aim and
  the rule about what a claim of one may contain is one sentence, not two.

## Three things found on the way and fixed here

- **A hit could not say it knew where it was.** `has_position` did not exist, so
  a hit at the origin and a hit with no position at all read identically - and a
  non-spatial target records exactly the second. Added and set on every path
  that records a position.
- **`_get_or_create_cue`-shaped bug, in miniature.** The first version of
  `TargetingSortByDistance` used `Array.sort_custom`, which Godot does not
  guarantee to be stable; two equidistant targets would come back in whichever
  order the sort happened to leave them, which is a preset a server cannot
  reproduce. It is an insertion that breaks ties by discovery order now.
- **A reticle parented under the cue sits at the world origin.** Not this
  package's own bug - the same trap F6.2.6 hit - but the reason the reticle task
  puts its instance beside the avatar rather than under itself.

## What the quality gates said

| Gate | Result |
|---|---|
| GUT suite | `passed=61401 failed=0 pending=0 orphans=0` |
| loc | PASS |
| duplication | PASS |
| magic-string | PASS |
| test-location | PASS |
| gate self-tests | 192 passed |
| project invariants | `project.godot is sound` |
| godot import | PASS |

No ceiling moved. Three duplication pairs were folded rather than allowlisted:
the two location providers share the rule about what a claim may contain, the
two aiming suites share a bench that stands the character up, and the registry's
two tag-and-path readers became one. Three allowlist rules were widened, each
with the reason written beside it: the 2D/3D mirror now reaches the reticles and
the providers directory, a task's `create` is a constructor like any other, and
a wire contract's `_expected` table is data rather than logic.

## The friction this package closed

F6.0.9 measured "pieces shipped towards an area effect a person aims and sees
before confirming" as **0**. F6.3.2 shipped the reticle and the task that owns
its life; F6.3.3 shipped four providers. The `now` column of
`artifacts/parity/AUTHORING_UX.md` says **5**, changed in the two commits that
made it true.

`test/unit/test_authoring_friction.gd::test_the_six_authoring_frictions_are_measured_as_they_stand_today`
