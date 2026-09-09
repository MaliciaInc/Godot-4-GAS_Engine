# Gate F6.1 — receipt

Package: F6.1 (F6.1.1 through F6.1.12), the everyday ability surface.
Baseline: `1d00bff` — the tree F6.0 closed on.
Reference: Unreal Engine Gameplay Ability System 5.7.4, CL 51494982.

Every reference below is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_1.md
```

## What this package closed

| Finding | State | Evidence |
|---|---|---|
| G-01 triggers that answer a tag, and the difference between an edge and a level | CLOSED | `test/unit/test_ability_activation_policies.gd::test_losing_the_tag_cancels_a_level_trigger_and_not_an_edge_one` |
| G-01, a level that was already true when the ability arrived | CLOSED | `test/unit/test_ability_activation_policies.gd::test_owned_tag_present_fires_when_the_tag_is_already_present_at_grant` |
| G-01, the source gates read the instigator, not the owner | CLOSED | `test/unit/test_ability_tag_semantics.gd::test_source_required_query_reads_the_event_instigator_snapshot` |
| G-02 an event wait that stays, that is exact, and that listens elsewhere | CLOSED | `test/unit/test_new_ability_task_behaviour.gd::test_a_continuous_gameplay_event_task_receives_more_than_one_event` |
| G-02, and lets go of the component it borrowed | CLOSED | `test/unit/test_new_ability_task_behaviour.gd::test_gameplay_event_wait_disconnects_from_external_asc_on_finish` |
| G-03 the payload has all ten fields | CLOSED | `test/unit/test_gameplay_events.gd::test_an_event_carries_all_ten_payload_fields` |
| G-03, and survives a round trip with no object in it | CLOSED | `test/unit/test_gameplay_events.gd::test_gameplay_event_wire_round_trips_without_object_references` |
| G-03, a malformed wire is refused rather than repaired | CLOSED | `test/unit/test_gameplay_events.gd::test_a_malformed_wire_is_refused_rather_than_repaired` |
| G-04 the component answers by query, by slot and by script | CLOSED | `test/unit/test_ability_query_surface.gd::test_specs_are_found_by_query_in_the_order_they_were_granted` |
| G-04, an external block is counted, not a flag | CLOSED | `test/unit/test_ability_query_surface.gd::test_external_ability_blocks_are_reference_counted` |
| G-05 confirm and cancel with no key named | CLOSED | `test/unit/test_ability_query_surface.gd::test_a_generic_answer_reaches_tasks_before_target_providers` |
| G-05, and a provider that already finished is not told | CLOSED | `test/unit/test_ability_query_surface.gd::test_finished_target_provider_does_not_receive_generic_input` |
| G-06 an effect can be a cost, if it can be undone exactly | CLOSED | `test/unit/test_ability_custom_costs.gd::test_an_irreversible_cost_effect_is_rejected_at_definition_validation` |
| G-06, a game's own cost is inside the same atomic commit | CLOSED | `test/unit/test_ability_custom_costs.gd::test_a_failure_after_custom_cost_commit_restores_the_exact_previous_state` |
| G-07 a cooldown says what it was authorised for, not only what is left | CLOSED | `test/unit/test_cooldown_state.gd::test_cooldown_state_reports_original_seconds_and_remaining_seconds` |
| G-07, in turns as well as seconds | CLOSED | `test/unit/test_cooldown_state.gd::test_turn_cooldown_state_reports_original_turns_and_remaining_turns` |
| G-09 overlap, velocity, named states and effect-to-target | CLOSED | `test/unit/test_new_ability_tasks.gd::test_wait_effect_applied_to_target_hears_what_this_ability_landed` |
| G-09, and every one of them ends when the ability does, exactly once | CLOSED | `test/unit/test_new_ability_tasks.gd::test_every_task_ends_exactly_once` |
| G-21 a loadout goes on and comes off as one thing | CLOSED | `test/unit/test_ability_set.gd::test_granting_and_taking_back_leaves_the_component_as_it_was` |
| G-21, taking it back walks the sequence backwards | CLOSED | `test/unit/test_ability_set.gd::test_take_back_walks_the_published_sequence_backwards` |
| G-21, input by action name beside input by slot | CLOSED | `test/unit/test_ability_input.gd::test_input_id_and_input_action_can_coexist` |
| G-21, one place for the rules about kinds of ability | CLOSED | `test/unit/test_ability_tag_relationships.gd::test_tag_relationships_can_block_and_cancel` |
| G-21, and that place can only ever say no | CLOSED | `test/unit/test_ability_tag_relationships.gd::test_tag_relationships_never_override_an_ability_refusal` |
| G-20 suppression of cues and of grants | **PREPARED, owner F6.4.5** | `test/unit/test_ability_query_surface.gd::test_suppressed_grants_are_refused_in_the_shape_a_grant_refuses_in` |
| G-20, a name for every refusal | **PREPARED, owner F6.4.5** | `test/unit/test_ability_tag_relationships.gd::test_every_activation_error_has_a_stable_failure_tag` |

G-20 is not claimed closed here. F6.1.9 and F6.1.12 built the two halves the
phase document assigns them — the suppression switches and the failure-tag
mapping — and F6.4.5 owns the rest of that finding, which is ignore-cost and
ignore-cooldown for debugging.

## The walk

Pieces that pass separately can still be wrong together. The gate scenario the
phase document specifies runs all of them on one character, in order, and ends
by proving the component is exactly what it was before the loadout went on.

`test/unit/test_gate_f6_1_ability_contract_walk.gd::test_the_whole_ability_contract_walks_and_leaves_nothing_behind`

## Two things found while auditing this package, and fixed here

Neither was reported by a gate. Both were found by asking what reads each thing
this package wrote.

- **A table with two arms nobody had wired.** `GameplayAbilityTagRelationships`
  published `blocks_for()` and `cancels_for()`, and nothing in the engine called
  either. The refusal arm worked, so the tests passed and the table's other two
  columns were decoration. Both now go through the one algorithm that already
  existed — `addons/GAS_Engine/abilities/ability_tag_semantics_runtime.gd::cancel_matching_query`,
  with the same self-exclusion rule an ability's own cancel query obeys — so an
  ability cancelled by a row is cancelled exactly the way one cancelled by an
  ability is. Proven by reverting: the new test fails on both assertions.
- **Half of the action routing had no reader.** `input_action_pressed` was
  tested; `input_action_released` was not, which is the call that ends a
  `WHILE_INPUT_ACTIVE` ability held by name rather than by slot. The
  held-input test is now parameterised over both spellings. Proven by making
  the release a no-op: the by-name case goes red and the by-slot case does not.

## Where the tests are, when the document named a different one

The phase document names five test functions this package does not contain
under those names, because each is one arm of a test that covers both arms.
Splitting them would have produced pairs the duplication gate reads as clones
of each other, and the behaviour is what is being kept, not the spelling.

| Named in the document | Where the behaviour is proven |
|---|---|
| `test_owned_tag_present_cancels_when_the_tag_is_removed` | `test/unit/test_ability_activation_policies.gd::test_losing_the_tag_cancels_a_level_trigger_and_not_an_edge_one` |
| `test_owned_tag_added_does_not_cancel_when_the_tag_is_removed` | the same test, the other assertion |
| `test_generic_confirm_reaches_tasks_before_target_providers` | `test/unit/test_ability_query_surface.gd::test_a_generic_answer_reaches_tasks_before_target_providers` |
| `test_generic_cancel_reaches_tasks_before_target_providers` | the same test, parameterised over yes and no |
| `test_tag_relationships_can_add_a_requirement` | `test/unit/test_ability_tag_relationships.gd::test_a_relationship_row_adds_a_restriction_and_only_a_restriction` |

## What the quality gates said

| Gate | Result |
|---|---|
| GUT suite | `passed=57976 failed=0 pending=0 orphans=0` |
| loc | PASS |
| duplication | PASS |
| magic-string | PASS |
| test-location | PASS |
| gate self-tests | 192 passed |
| project invariants | `project.godot is sound` |
| godot import | PASS |

Four ceilings moved, each with its reason written beside it in
`tooling/.quality-gates.json`: `ability_system_component.gd` to 1260 because
this package is largely what a game asks the component, `gameplay_ability.gd`
to 1050 for the task and cost surface, `ability_runtime.gd` to 660, and
`gameplay_attribute_runtime.gd` to 620 for adopting one attribute set at a time.

One duplication pair was allowlisted and the rest were folded: the event
codec's `to_wire` and `from_wire` are deliberate mirrors of one another, and a
reader checking that the wire round-trips has to read both halves side by side.
