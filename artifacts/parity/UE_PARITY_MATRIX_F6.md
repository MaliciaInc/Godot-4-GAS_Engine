# UE parity matrix — FASE 6

Baseline GAS_Engine: `b5f4f3b`.
Reference: Unreal Engine 5.7.4, CL 51494982 — **run 2026-09-11**, ten of ten
scenarios, zero mismatches — `artifacts/parity/GATE_F6_5.md`.

```text
CERTIFICATION_STATUS: status=CLOSED verified=10/10 numeric_mismatches=0 trace_mismatches=0 stop_code=none
```

Machine-checked against `artifacts/parity/f6_result.json` by
`python tooling/certification_consistency.py`. AUD-01 found this matrix
still declaring the run below **not run** at the same commit `GATE_F6_5.md`
already recorded it on - the line above is the correction, generated from
the one place these numbers are now typed rather than repeated by hand in
every file that mentions them.

The phase document asks this matrix to distinguish three states, and the reason
is the one thing this file is for: a behaviour that mirrors the reference and
has a local test proving the engine does what the engine was written to do has
not been compared to anything. Calling that parity is the failure the whole
corpus exists to prevent.

## The three states, and what each one costs to claim

| State | What it means | What it takes |
|---|---|---|
| `UE_VERIFIED` | this engine and Unreal Engine 5.7.4 were both run on the same scenario and agreed | a golden under `test/parity/goldens/` stamped `UE_VERIFIED`, and `python tooling/parity_diff.py` exiting zero |
| `ENGINE_EXTENSION` | GAS_Engine does something the reference does not do at all | a named scenario, and a sentence saying what the reference does instead |
| `EXPLICIT_DEVIATION` | GAS_Engine deliberately differs where the reference has an answer | a named scenario, and the reason the difference was chosen |

A fourth thing exists in this repository and is not one of the three:
**LOCALLY_ASSERTED** — behaviour written to match the reference's documented
contract, checked by this engine's own suite, and never compared against a
running copy of it. It is spelled out here rather than folded into one of the
three, because folding it into `UE_VERIFIED` is exactly the claim D-08 is
about.

## Where FASE 6 actually stands

| State | Count | Why |
|---|---|---|
| `UE_VERIFIED` | **10** | Unreal Engine 5.7.4 CL 51494982 ran against all ten scenarios the phase names, 2026-09-11 |
| `ENGINE_EXTENSION` | 3 | below |
| `EXPLICIT_DEVIATION` | 3 | below |
| `LOCALLY_ASSERTED` | everything else | 66,000-odd assertions; the ten above are the only ones that are also a comparison |

Ten is the measured number, not an authored one. The ten scenarios the phase
names are written, in the shape a comparison needs, under
`test/parity/goldens/` — and every one of them now says `UE_VERIFIED`, which is
what `test/unit/test_ue_reference_corpus.gd::test_a_verified_golden_carries_what_a_run_produces`
checks; `test/unit/test_ue_reference_corpus.gd::test_every_golden_says_everything_and_invents_no_third_word`
still holds, since `UE_VERIFIED` is one of the same two words `AUTHORED` was
never allowed to be a third of. What this engine produces for those scenarios
is written where a diff would read it, by
`test/unit/test_ue_reference_production.gd::test_what_this_engine_produces_is_written_where_the_diff_reads_it`,
and `tooling/parity_diff.py` compares the two: zero numeric mismatches, one
declared deviation. `artifacts/parity/GATE_F6_5.md` has the run itself and
what closed the two findings that were waiting on it.

## The extensions

Things the reference does not have. They are not parity gaps and they are not
deviations: there is nothing on the other side to differ from.

| What | Where | What the reference does instead |
|---|---|---|
| Turn-based duration and period, counted in turns rather than seconds | `test/unit/test_periodic_effects.gd::test_a_turn_based_effect_expires_on_its_last_turn` | nothing — UE effects are clocked in seconds |
| The Ability Composer, a graph view over ability and effect authoring | `test/unit/test_composer_chrome.gd::test_a_screen_whose_children_are_gone_answers_null` | Blueprint, which is the engine's own graph rather than the ability system's |
| The runtime debug overlay, drawn by the game rather than by the editor | `test/unit/test_gas_debug_overlay.gd::test_the_history_records_what_the_component_announces` | `showdebug abilitysystem`, which is an editor and PIE facility |

## The deviations

Places where the reference has an answer and this engine deliberately gives a
different one.

| What | Where | Why |
|---|---|---|
| `factor_in_stack_count` defaults to false; UE folds stack count in by default | `test/unit/test_gameplay_asset_validator.gd::test_a_stacking_effect_that_never_answered_the_stack_question_is_said_out_loud` | changing the default would rebalance every effect already authored against it. The validator says so out loud under the `UE_5_7` profile rather than the default being changed under somebody's project. |
| Two aggregation profiles, where UE has one | `test/unit/test_ue_aggregate_algebra.gd::test_a_stack_scales_a_magnitude_by_what_its_operation_means` | `GODOT_NATIVE` predates the reference work and is what existing projects are balanced against. `UE_5_7` is the reference's arithmetic, selectable per project, and the README says switching rebalances a game. |
| `NON_INSTANCED` gets a fresh Node per activation; UE's runs on the ability's shared class default object | `test/unit/test_explicit_ability_lifecycle.gd::test_two_non_instanced_activations_share_nothing` | Godot has no class-default-object equivalent, and `GameplayAbility` stores its actor and spec on the instance (`owner_asc`, `current_spec`) rather than threading them through every call the way UE's CDO methods do - sharing one Node across concurrent, unrelated owners would hand each one the other's fields, which is the exact bug the policy exists to prevent. The Godot-side answer keeps the one property `NonInstanced` is actually for - no state survives past the activation it belongs to, and nothing is shared between concurrent ones - by giving each activation a Node of its own that is never adopted as the spec's instance, rather than by literally sharing one object. |

## What this means for FASE 6

D-08 and D-11 are closed — `artifacts/parity/GATE_F6_5.md` has the run that
closed them, 2026-09-11. Every finding the phase names is closed, every
package gate is green, and the two-process transport runs.

`python tooling/traceability.py` exits zero, and
`python tooling/certification_consistency.py` checks that this file,
`UE_REFERENCE_F6.md` and `GATE_F6_5.md` all still agree with
`artifacts/parity/f6_result.json` and with the goldens - the check AUD-01
asked for, so the three of them cannot quietly drift apart again the way they
already had once.
