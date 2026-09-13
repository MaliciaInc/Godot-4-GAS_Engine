# Gate F6.2 — receipt

Package: F6.2 (F6.2.1 through F6.2.8), effects, magnitudes and presentation.
Baseline: `cfdb63d` — the tree F6.1 closed on.
Reference: Unreal Engine Gameplay Ability System 5.7.4, CL 51494982.

Every reference below is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_2.md
```

## What this package closed

| Finding | State | Evidence |
|---|---|---|
| G-10 a cue reads its own loudness off its binding | CLOSED | `test/unit/test_gameplay_cue_effects.gd::test_cue_magnitude_attribute_produces_raw_and_normalized_values` |
| G-10 an effect that changed no number can be silent | CLOSED | `test/unit/test_gameplay_cue_effects.gd::test_cue_can_require_a_successful_modifier` |
| G-10 ten arrows in a second can be one sound | CLOSED | `test/unit/test_gameplay_cue_effects.gd::test_stacking_cue_can_be_suppressed_after_the_first_stack` |
| G-10 a cue crosses a wire as identities, never as objects | CLOSED | `test/unit/test_gameplay_cue_effects.gd::test_cue_params_wire_contains_ids_not_nodes` |
| G-11 four readings of one capture, and they disagree | CLOSED | `test/unit/test_attribute_based_readings.gd::test_a_calculation_picks_which_reading_of_the_capture_is_taken` |
| G-11 the attribute as it stood before the later channels | CLOSED | `test/unit/test_attribute_based_readings.gd::test_up_to_channel_reads_the_attribute_before_the_later_channels` |
| G-11 tag gates make a magnitude worth nothing, not refused | CLOSED | `test/unit/test_attribute_based_readings.gd::test_requirements_make_the_magnitude_worth_nothing_rather_than_refuse` |
| G-11 the curve bends the finished number | CLOSED | `test/unit/test_attribute_based_readings.gd::test_the_attribute_curve_is_applied_to_the_finished_number` |
| G-11 a custom magnitude's four dials, in one order | CLOSED | `test/unit/test_gameplay_magnitudes.gd::test_a_custom_magnitude_applies_its_dials_in_the_documented_order` |
| G-12 an execution is told what the application carried | CLOSED | `test/unit/test_execution_scope.gd::test_execution_receives_passed_in_tags` |
| G-12 scratch space lives for one run | CLOSED | `test/unit/test_execution_scope.gd::test_transient_aggregators_do_not_escape_the_execution` |
| G-12 an adjustment changes what the execution reads and nothing else | CLOSED | `test/unit/test_execution_scope.gd::test_scoped_modifiers_only_affect_the_execution` |
| G-12 the stack is applied once, or not at all | CLOSED | `test/unit/test_execution_scope.gd::test_manual_stack_count_flag_prevents_the_automatic_second_factor` |
| G-13 an attribute that is a message, read and then cleared | CLOSED | `test/unit/test_attribute_evaluation.gd::test_a_meta_attribute_is_read_and_then_returned_to_zero` |
| G-13 nothing lasting may contribute to one | CLOSED | `test/unit/test_attribute_evaluation.gd::test_a_lasting_contribution_to_a_meta_attribute_is_refused` |
| G-13 a set says how many of one kind count | CLOSED | `test/unit/test_aggregator_policy.gd::test_a_policy_decides_how_many_of_one_kind_count` |
| G-13 and never chooses between two kinds | CLOSED | `test/unit/test_aggregator_policy.gd::test_the_policy_never_chooses_between_two_kinds` |
| G-15 a cue that is a script, needing no scene instance | CLOSED | `test/unit/test_cue_hierarchy.gd::test_a_handler_answers_without_a_node_being_made` |
| G-15 both kinds of binding in one resolution walk | CLOSED | `test/unit/test_cue_hierarchy.gd::test_a_handler_and_a_scene_are_consulted_in_the_same_walk` |
| G-15 a burst and a loop, authored as data | CLOSED | `test/unit/test_cue_templates.gd::test_a_loop_starts_recurs_and_stops` |
| G-15 camera shake and haptics leave as requests | CLOSED | `test/unit/test_cue_templates.gd::test_a_burst_plays_its_set_once_and_asks_for_a_shake` |
| G-15 how many of one cue may run at once | CLOSED | `test/unit/test_cue_manager_surface.gd::test_a_unique_cue_started_twice_by_one_instigator_runs_once` |
| G-15 what is running, and ending all of it | CLOSED | `test/unit/test_cue_manager_surface.gd::test_a_running_cue_can_be_asked_about_and_ended_with_the_rest` |
| G-15 paying for the instantiating early | CLOSED | `test/unit/test_cue_manager_surface.gd::test_preallocation_fills_the_pool_from_what_each_cue_asked_for` |
| G-15 the target hears too, beside the binding | CLOSED | `test/unit/test_cue_manager_surface.gd::test_a_target_that_says_so_hears_about_its_own_cues` |
| G-15 an ability cannot leave a persistent cue running | CLOSED | `test/unit/test_ability_persistent_cues.gd::test_an_ability_takes_its_persistent_cues_with_it` |
| G-15 and never ends another activation's | CLOSED | `test/unit/test_ability_persistent_cues.gd::test_one_activation_never_ends_anothers_cue` |

G-15 is marked closed for what F6.2.5 through F6.2.8 own. The phase document's
traceability names F6.6.2 as its second owner, for replicating a cue rather than
playing one; nothing here claims that half.

## The walk

`test/unit/test_effect_authoring_one_hit_walk.gd::test_the_whole_authoring_contract_walks_on_one_hit`

One hit on one buffed character, with every piece of the package in the same
application: a scoped modifier whose magnitude is the bonus part of the target's
own speed, an execution told what the hit was and reading through that
adjustment, a meta attribute the set reads and the runtime clears, a burst
scaled by the fraction its binding declared, the target itself told about its
own cue, and an aura that stops when the effect behind it is removed.

## Two decisions this package made that the document left open

Both are recorded because a reader will otherwise wonder why the engine does
something the reference does differently.

- **An execution's numbers are scaled by the stack count only under Unreal's
  contracts.** The reference multiplies; this engine never has, and a project on
  the native profile that started having its executions doubled would be a
  project whose damage changed under it. So the factor exists where parity is
  the contract, `stack_count_handled_manually` turns it off there, and the
  native profile is untouched.
- **`MAGNITUDE_UP_TO_CHANNEL` answers the whole composition on the native
  profile.** That profile is a single pass with no channels in it, so every
  ceiling is above everything. Answering rather than refusing, because a project
  asking is asking what the attribute is worth.

## Five things found on the way and fixed here

None was in the phase document, and each was left closed rather than noted.

- **A stack reapplication played its application cues unconditionally**, so an
  execution that had already declined them was overruled by the join - the one
  path that was not reading the decision.
- **Preallocation asked the pool for the instances it was about to give back**,
  and took the same one out again every round. The loop never terminated. Making
  a cue and taking a pooled one are two functions now.
- **The freed-target trap, twice.** A freed instance handed to a typed `Node`
  parameter is refused by the engine before the function body runs, so a guard
  inside the callee never gets the chance. Both guards moved to the call site.
- **A `while_active` with no producer.** The scriptless cue endpoint declares one
  and a RefCounted has no frame of its own, so the manager gives it one - and
  only while a handler-backed cue is actually running.
- **Three dictionaries keyed by one handle id** had already started disagreeing
  by the time a second kind of endpoint arrived. They are one record now.

## What the quality gates said

| Gate | Result |
|---|---|
| GUT suite | `passed=59770 failed=0 pending=0 orphans=0` |
| loc | PASS |
| duplication | PASS |
| magic-string | PASS |
| test-location | PASS |
| gate self-tests | 192 passed |
| project invariants | `project.godot is sound` |
| godot import | PASS |

Three files were split rather than given a raise. Building a cue's parameters
left the file that commits transactions; the cue manager became a catalogue, a
playback registry and the records they pass between them; and what a magnitude
reads left the file about what it does with what it read. Two ceilings did move,
each for an authoring surface: `gameplay_ability.gd` for the persistent-cue
ledger and `ability_system_component.gd` for the door that ends every cue on an
entity.

Four duplication pairs were folded and two allowlisted. The folded ones: one
context builder for the four places that made one by hand, one bench for the two
magnitude suites, one entry reader for the registry's two tag-and-path
declarations, and one test over both meta-attribute hit counts. The allowlisted
ones are a codec's two directions - which are the same list of fields read the
other way, and which no reflection could replace without turning a rename into a
field that silently stops crossing - and two authoring Resources that share a
shape and nothing else.

Four preload paths were allowlisted for the magic-string gate. Every one is
inside the GameplayCueManager autoload's parse-time closure, where a type has to
arrive by preload rather than by name and a const holding the path once would
have to live in a file both ends could resolve - which inside that closure is
the same problem again.

## The friction this package closed

F6.0.9 measured "a sound-and-particle cue with no script" as **no**. F6.2.6
ships a burst and a loop that read a `GameplayCueEffectSet`, so a cue is a
Resource of sounds, particles and decals bound to a tag. The `now` column of
`artifacts/parity/AUTHORING_UX.md` says **yes**, changed in the commit that made
it true.

`test/unit/test_authoring_friction.gd::test_the_six_authoring_frictions_are_measured_as_they_stand_today`
