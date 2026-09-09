# Gate F5.2 — receipt

Package: F5.2 (F5.2.1 through F5.2.10), covering G03–G13, G15–G19 and G30.
Baseline GAS_Engine: `0db4c24441184a67c1b9b606af6ce9d8ec6b917c`.
Reference: Unreal Engine 5.7.4, CL 51494982.

The phase lists twelve mandatory cases for this gate. Each one below names the
automated scenarios that answer it, because a case is closed by a test that
fails when the behaviour goes away, never by a class existing. Every reference
here is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F5_2.md
```

## The twelve cases

| # | Case | Scenarios |
|---|---|---|
| 1 | Two sets declaring `health` | `test/unit/test_attribute_reference.gd::test_a_bare_name_that_means_two_things_is_refused`, `test/unit/test_attribute_reference.gd::test_naming_the_set_answers_each_health_separately`, `test/unit/test_typed_execution_output.gd::test_a_write_the_entity_cannot_aim_is_refused` |
| 2 | UE algebra against the legacy one | `test/unit/test_ue_aggregate_algebra.gd::test_the_two_profiles_fold_the_same_authoring_differently`, `test/unit/test_ue_aggregate_algebra.gd::test_each_arm_of_the_unreal_formula_composes_as_written`, `test/unit/test_ue_aggregate_algebra.gd::test_a_second_channel_multiplies_what_the_first_one_produced` |
| 3 | Source and target filters on one modifier | `test/unit/test_ue_aggregate_algebra.gd::test_a_modifier_only_counts_where_its_source_qualifies`, `test/unit/test_ue_aggregate_algebra.gd::test_a_modifier_only_counts_where_its_target_qualifies` |
| 4 | Source/target snapshot timing | `test/unit/test_snapshot_depth_and_source_tags.gd::test_a_source_snapshot_is_what_it_had_and_not_what_it_gained`, `test/unit/test_snapshot_depth_and_source_tags.gd::test_a_second_capture_does_not_re_read_the_source`, `test/unit/test_snapshot_depth_and_source_tags.gd::test_an_application_copy_carries_the_capture_that_was_already_taken` |
| 5 | Stack math | `test/unit/test_ue_aggregate_algebra.gd::test_a_stack_scales_a_magnitude_by_what_its_operation_means`, `test/unit/test_live_stack_scaling_and_purge.gd::test_two_stacks_are_worth_two_whether_applied_or_re_resolved`, `test/unit/test_effect_mutation_and_timing.gd::test_changing_the_stack_count_changes_what_the_effect_is_worth` |
| 6 | Duration as a magnitude | `test/unit/test_effect_mutation_and_timing.gd::test_a_duration_authored_as_a_magnitude_is_what_the_effect_lasts`, `test/unit/test_effect_mutation_and_timing.gd::test_an_effect_with_no_magnitude_keeps_the_number_it_was_authored_with`, `test/unit/test_effect_mutation_and_timing.gd::test_a_periodic_effect_ticks_on_application_only_if_it_says_so` |
| 7 | The whole event payload | `test/unit/test_event_activation_payload.gd::test_the_event_that_woke_an_ability_reaches_it_whole`, `test/unit/test_event_activation_payload.gd::test_an_ability_activated_by_a_call_reports_no_event`, `test/unit/test_handle_facade.gd::test_the_activation_context_travels_through_the_handle_door` |
| 8 | Explicit ability lifecycle | `test/unit/test_explicit_ability_lifecycle.gd::test_an_ability_ends_when_it_returns_only_if_it_says_so`, `test/unit/test_explicit_ability_lifecycle.gd::test_retriggering_ends_what_was_running_before_starting_again`, `test/unit/test_explicit_ability_lifecycle.gd::test_two_non_instanced_activations_share_nothing` |
| 9 | Costs priced against the current value under UE | `test/unit/test_commit_preflight_contract.gd::test_a_buff_pays_for_a_cost_under_one_profile_and_not_the_other`, `test/unit/test_commit_preflight_contract.gd::test_neither_profile_lets_an_ability_spend_what_is_not_there`, `test/unit/test_commit_preflight_contract.gd::test_a_listener_that_spends_the_mana_mid_commit_is_caught` |
| 10 | Parent-aware tag counts | `test/unit/test_hierarchical_tag_counts.gd::test_a_listener_on_the_parent_hears_the_family_change`, `test/unit/test_hierarchical_tag_counts.gd::test_the_exact_count_is_the_tag_and_the_family_count_is_all_of_it`, `test/unit/test_hierarchical_tag_counts.gd::test_a_count_change_that_is_not_a_state_change_announces_nothing` |
| 11 | Mutating a running effect by handle | `test/unit/test_effect_mutation_and_timing.gd::test_every_mutation_refuses_a_handle_that_names_nothing`, `test/unit/test_effect_mutation_and_timing.gd::test_a_value_that_is_not_a_value_is_refused`, `test/unit/test_effect_mutation_and_timing.gd::test_a_running_effect_can_be_given_longer` |
| 12 | Legacy behaviour stays green under `GODOT_NATIVE` | `test/unit/test_compatibility_profile.gd::test_a_new_component_does_not_use_unreal_contracts`, `test/unit/test_compatibility_profile.gd::test_a_component_with_no_profile_falls_back_to_godot_native`, and the suite itself — every test in it that does not set a profile runs under `GODOT_NATIVE`, which is what the default is |

## Case 12, said precisely

Case 12 is the one a table cannot carry on its own, because it is a claim about
every other test rather than about three of them.
`GameplayCompatibilityProfile` defaults to `GODOT_NATIVE` and a component
without one answers the same, so every scenario in the suite that never
mentions a profile is a legacy scenario. The two named above are what makes
that true rather than merely likely: the first asserts the default, the second
asserts the fallback for a component carrying no profile at all.

The UE contracts are therefore reachable only where a test asks for them, and
each place that asks is a scenario in cases 2, 3 and 9.

## Verdict

Twelve of twelve cases carry named automated scenarios. Recorded against the
suite as it stood at the close of F5.2.10:

```text
GAS_ENGINE_GUT_RESULT: PASS passed=48259 failed=0 pending=0 orphans=0
GAS_ENGINE_VERIFY_PASS
```
