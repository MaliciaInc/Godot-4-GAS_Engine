# Gate F5.3 — receipt

Package: F5.3 (F5.3.1 through F5.3.6), covering G25–G29 and part of G27/G30.
Baseline GAS_Engine: `0db4c24441184a67c1b9b606af6ce9d8ec6b917c`.
Reference: Unreal Engine 5.7.4, CL 51494982.

The phase states this gate as a UX scenario of eleven steps rather than as a
list of cases. What answers it is the walk itself: one suite that goes from an
empty project to a running ability and asserts the joins, because every step
below already works on its own and the gate is asking something else - that a
person can get through without falling into a gap between two tools that each
work.

Every reference here is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F5_3.md
```

## The eleven steps

| # | Step | Scenario |
|---|---|---|
| 1 | Create a new ability | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_step_one_creating_leaves_a_script_and_a_scene`, `test/unit/test_ability_creation.gd::test_creating_an_ability_writes_the_script_and_the_scene` |
| 2 | It leaves a script and a scene | `test/unit/test_ability_creation.gd::test_the_scene_root_is_the_ability_the_script_describes`, `test/unit/test_ability_creation.gd::test_the_scene_it_wrote_can_be_granted_as_it_is` |
| 3 | Create a reusable GE asset | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_step_three_an_effect_asset_is_created_and_is_a_gameplay_effect`, `test/unit/test_effect_asset_authoring.gd::test_creating_an_asset_writes_a_gameplay_effect` |
| 4 | Configure cost and cooldown | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_four_to_six_configure_grant_and_run`, `test/unit/test_effect_asset_authoring.gd::test_the_asset_is_the_object_the_engine_applies` |
| 5 | Grant it on a fixture | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_four_to_six_configure_grant_and_run`, `test/unit/test_ability_creation.gd::test_the_scene_it_wrote_can_be_granted_as_it_is` |
| 6 | Run it | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_four_to_six_configure_grant_and_run`, `test/unit/test_ability_creation.gd::test_and_what_it_wrote_runs` |
| 7 | See the refusal in Output | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_seven_and_eight_a_draft_says_what_is_wrong_and_where`, `test/unit/test_gameplay_compile_service.gd::test_a_draft_that_does_not_compile_is_still_read_and_still_says_why` |
| 8 | Go to the line and the node | `test/unit/test_gameplay_compile_service.gd::test_a_finding_carries_every_way_of_going_to_it`, `test/unit/test_gameplay_compile_service.gd::test_the_plugin_takes_the_editor_to_the_line`, `test/unit/test_composer_chrome.gd::test_clicking_an_output_row_reveals_that_node_on_the_canvas` |
| 9 | Edit and save | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_nine_and_ten_editing_saving_and_reopening_loses_nothing`, `test/unit/test_composer_kept_regions.gd::test_a_region_the_reader_kept_is_written_back_exactly` |
| 10 | Close and reopen with nothing lost | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_nine_and_ten_editing_saving_and_reopening_loses_nothing`, `test/unit/test_composer_unsaved_and_conflict.gd::test_the_plugin_wires_every_answer_to_the_unsaved_question` |
| 11 | The debugger sees the running instance | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_step_eleven_the_debugger_sees_the_running_instance`, `test/unit/test_gas_runtime_debugger.gd::test_a_snapshot_carries_grants_by_handle`, `test/unit/test_gas_runtime_debugger.gd::test_the_editor_registers_the_debugger_and_takes_it_back` |

## What changed in the tool while this was closed

Three things the walk could not have gone through before, each of which was a
gap between pieces that individually worked:

- **A block the Composer cannot read used to cost the whole ability.** A `for`
  loop anywhere in a body opened the file read-only, so the twenty statements
  around it were unreachable. A region is now drawn, kept and written back byte
  for byte, and a file is unreadable for exactly one reason: it has no
  `_activate_ability()`. `test/unit/test_composer_ir.gd::test_a_loop_is_one_event_that_reaches_the_end_of_its_body`
- **The palette offered every public method.** `dispose()` and `cleanup()` were
  on it, which is the runtime talking to itself rather than anything anybody
  authors. An operation says so beside the code now.
  `test/unit/test_composer_operation_metadata.gd::test_the_runtime_s_own_plumbing_is_not_offered`
- **Clicking a finding answered only half of where it is.** The line came with
  the row and was dropped, so a finding about the file went nowhere.
  `test/unit/test_composer_chrome.gd::test_clicking_an_output_row_reveals_that_node_on_the_canvas`

## Deviations

`EditorPlugin` and `EditorDebuggerPlugin` refuse to be instantiated outside the
editor, so neither can be driven headless. What is asserted for those two is
their source - that the wiring lines are present - and everything they decide
was moved into classes that can be constructed: `GasRuntimeDebuggerLog` for the
debugger, `GameplayEffectAsset` and `ComposerAbilityTemplate` for the creators.
The manual step that remains is a person opening the editor and watching a
running game populate the panel.

## Verdict

Eleven of eleven steps carry named automated scenarios. Recorded against the
suite as it stood at the close of F5.3.6:

```text
GAS_ENGINE_GUT_RESULT: PASS passed=51583 failed=0 pending=0 orphans=0
GAS_ENGINE_VERIFY_PASS
```
