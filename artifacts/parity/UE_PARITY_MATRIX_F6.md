# UE parity matrix — FASE 6

Baseline GAS_Engine: `b5f4f3b`.
Reference: Unreal Engine 5.7.4, CL 51494982 — **not run**.

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
| `UE_VERIFIED` | **0** | no Unreal Engine 5.7.4 has been run against this repository |
| `ENGINE_EXTENSION` | 3 | below |
| `EXPLICIT_DEVIATION` | 2 | below |
| `LOCALLY_ASSERTED` | everything else | 66,000-odd assertions, none of them a comparison |

Zero is the honest number and it is not zero work. The ten scenarios the phase
names are written, in the shape a comparison needs, under
`test/parity/goldens/` — and every one of them says `NOT_UE_VERIFIED`, which is
what `test/unit/test_ue_reference_corpus.gd::test_every_golden_says_everything_and_invents_no_third_word`
checks. What this engine produces for those scenarios is written where a diff
would read it, by `test/unit/test_ue_reference_production.gd::test_what_this_engine_produces_is_written_where_the_diff_reads_it`.
The missing half is the reference's outputs, and `tools/ue_reference/README.md`
says exactly what to run to get them.

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

## What this means for FASE 6

The phase document's own rule: `BLOCKED` is a STOP and the phase stays open.
D-08 and D-11 are blocked — `artifacts/parity/GATE_F6_5.md` — so **FASE 6 is
not closed**, and no part of this repository claims otherwise. Every other
finding is closed, every package gate is green, and the two-process transport
runs; what is missing is a comparison nobody here can make.

`python tooling/traceability.py` exits non-zero while that is true, which is
the intended behaviour rather than a bug in it.
