# Gate F6.0 — receipt

Package: F6.0 (F6.0.1 through F6.0.9), the corrections that come before any
surface is widened.
Baseline: `6ed67750110b1cf194b799c8cb0dad8273f6e8bb`.
Reference: Unreal Engine Gameplay Ability System 5.7.4, CL 51494982.

Every reference below is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_0.md
```

## What this package closed

| Finding | State | Evidence |
|---|---|---|
| D-02 legacy `MULTIPLY`/`DIVIDE` compound under the Unreal profile | CLOSED | `test/unit/test_ue_aggregate_algebra.gd::test_the_legacy_multiply_name_folds_the_way_the_reference_folds_it` |
| D-02, the other profile is untouched | CLOSED | `test/unit/test_ue_aggregate_algebra.gd::test_the_legacy_multiply_name_still_compounds_under_godot_native` |
| D-02, stack scaling agrees with the fold | CLOSED | `test/unit/test_ue_aggregate_algebra.gd::test_a_stack_scales_a_magnitude_by_what_its_operation_means` |
| D-03 `EXECUTE_IMMEDIATELY_ON_UNINHIBIT` skipped a short inhibition | CLOSED | `test/unit/test_periodic_effects.gd::test_uninhibiting_executes_even_when_no_tick_was_missed` |
| D-04 unfalsifiable validity guard on PER_EXECUTION release | CLOSED | `test/unit/test_ability_instancing.gd::test_a_per_execution_instance_is_retired_exactly_once` |
| D-05 Composer getters could hand back a freed child | CLOSED | `test/unit/test_composer_chrome.gd::test_a_screen_whose_children_are_gone_answers_null` |
| D-06 eight ability operations reachable only from `AbilityRuntime` | CLOSED | `test/unit/test_ability_spec_and_handle.gd::test_the_component_answers_for_every_grant_it_holds` |
| D-06, the activation result survives the pass-through | CLOSED | `test/unit/test_ability_spec_and_handle.gd::test_a_refused_grant_and_run_once_still_says_why` |
| D-06, held inputs stay `Array[int]` | CLOSED | `test/unit/test_ability_spec_and_handle.gd::test_the_component_reports_the_input_slots_it_is_holding` |
| D-09 stacking default differs from the reference without saying so | CLOSED | `test/unit/test_gameplay_asset_validator.gd::test_a_stacking_effect_that_never_answered_the_stack_question_is_said_out_loud` |
| D-10 the README documented one aggregation profile of two | CLOSED | `test/unit/test_readme_quick_start.gd::test_the_readme_documents_both_aggregation_profiles` |
| D-01 the README's networking section | **PREPARED, closed by F6.6.8** | `test/unit/test_readme_quick_start.gd::test_the_readme_says_what_the_network_layer_actually_ships` |

D-01 is not closed here and is not claimed to be. The section at this point
described the authority, replication and prediction the repository contained,
the three replication modes, and the transport it did not yet have. F6.6 shipped
the wire and F6.6.8 rewrote the section as a final state, which is where D-01
closes: `artifacts/parity/GATE_F6_6.md`. The owner named here was F6.6.6, which
was wrong - the phase document's traceability matrix says F6.6.8, and that is
the one that did it.

## The changes of behaviour, and the proof each one can fail

A change nothing can disagree with is a change nobody verified. Each of these
was reverted on its own and the suite was watched go red.

| Change | Reverted | Result |
|---|---|---|
| The legacy names fold into the additive arms | the fold arm alone | 3 cases red |
| A stack scales the arm it is folded into | the profile branch in `stack_scaled` | 1 case red |
| Uninhibiting executes unconditionally | the whole match arm | 1 case red, from the short-inhibition side |
| The Composer getters answer `null` | both getters | 1 case red — and the first version of that test passed either way, because a freed object compares equal to `null` in GDScript. It asserts by `typeof` now. |

`release_execution_instance` is the exception and is recorded as one: removing a
guard that could never be false is not observable, by construction. What the
test beside it holds is the behaviour the guard pretended to protect.

## Two things found on the way and fixed here

Neither was in the phase document. Both were left in a worse state than the work
that uncovered them.

- **A field with two writers and no readers.** `missed_tick_while_inhibited`
  existed to tell the uninhibit path whether a catch-up tick was owed. That path
  stopped asking, so the field was removed along with both writes and the
  docstring that still described the old rule.
- **An assertion that could not fail.** The first version of the Composer getter
  test used `assert_null`, which passes on a freed object as happily as on
  nothing at all. Every other `assert_null` in the suite that follows a `free()`
  was checked; the three bridge cases are real, because those bridges null their
  reference rather than leaving it dangling.

## What the quality gates said

| Gate | Result |
|---|---|
| GUT suite | `passed=1843 failed=0 pending=0` |
| loc | PASS |
| duplication | PASS |
| magic-string | PASS |
| test-location | PASS |
| gate self-tests | 192 passed |
| project invariants | `project.godot is sound` |

Two ceilings moved, both by the mechanism that exists for it. The component's
file limit went 920 to 1000 with the reason written beside it in
`tooling/.quality-gates.json`, because the eight pass-throughs are the package.
`composer_screen.gd` was three lines over and all three were this package's own
prose, so it was trimmed instead of given a raise.

Three duplicate test shapes this package introduced were folded rather than
allowlisted: a shared README section reader, one table for the validator's two
quiet cases, and one test with one helper for the two stacking assertions. A
table and then a typed case class were both tried for that last one, and each
read as a clone of something else in the suite — which is the gate doing its
job on the fix as well as on the original.

## The measurement F6.4.7 will be compared against

F6.0.9 took the authoring-friction baseline before anything in this phase
touched it, and wrote it to `artifacts/parity/AUTHORING_UX.md`. The test derives
each number from the engine and fails when the receipt disagrees with what it
measured — verified by editing one number and watching it go red.

| What | Measured on the baseline |
|---|---|
| Resources built for a `+10` | 4 |
| A misspelled attribute caught before runtime | no |
| A sound-and-particle cue with no script | no |
| A debug surface a running game can show | no |
| Pieces shipped towards an aimed area effect | 0 |
| Calls to put a kit on, and take it off | 5 and 5 |

`test/unit/test_authoring_friction.gd::test_the_six_authoring_frictions_are_measured_as_they_stand_today`
