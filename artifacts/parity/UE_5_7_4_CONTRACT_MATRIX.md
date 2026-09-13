# GAS_Engine — UE 5.7.4 Contract Matrix

Baseline GAS_Engine: 0db4c24441184a67c1b9b606af6ce9d8ec6b917c
Reference: Unreal Engine 5.7.4, CL 51494982

Allowed states:
- COMPLETE
- PARTIAL
- ABSENT
- EXPLICIT_DEVIATION

Rules:
1. COMPLETE requires a named automated scenario and evidence.
2. PARTIAL is mandatory when any documented case is still absent.
3. EXPLICIT_DEVIATION is not failure, but cannot be counted as Unreal parity.
4. A class name or unit-test count is never evidence by itself.
5. TURN_BASED and external bridges are GAS_Engine extensions.

| Area | State at phase start | Closure package |
|---|---|---|
| Runtime correctness | PARTIAL | F5.1 |
| Attribute aggregation | PARTIAL | F5.2 |
| Ability lifecycle/commit | PARTIAL | F5.2 |
| Specs/captures/stacking | PARTIAL | F5.2 |
| Tags/events | PARTIAL | F5.2 |
| Authoring/Composer | PARTIAL | F5.3 |
| Targeting/tasks/animation/cues | PARTIAL | F5.4 |
| Authority/replication/prediction | ABSENT | F5.5 |
| Performance/determinism certification | ABSENT | F5.6 |

## Closed packages

The table above is the state at phase start and stays that way. What a package
closed is its own receipt, whose every named scenario is checked against the
suite by `tooling/parity_receipt.py`.

| Package | Receipt |
|---|---|
| F5.2 | `artifacts/parity/GATE_F5_2.md` |
| F5.3 | `artifacts/parity/GATE_F5_3.md` |
| F5.4 | `artifacts/parity/GATE_F5_4.md` |
| F5.5 | `artifacts/parity/GATE_F5_5.md` |
| F5.6 | `artifacts/parity/DISTRIBUTION.md`, and the corpus and measurements below |

## Final state

One row per area, and a row may say COMPLETE only where a named scenario
exists, is green, and hides no deviation. Where a deviation exists the row says
so instead, and the deviation is written out below rather than left in a commit
message.

| Area | Final state | Evidence |
|---|---|---|
| Runtime correctness | COMPLETE | `test/unit/test_parity_corpus.gd::test_godot_agrees_with_the_reference_on_every_case` |
| Attribute aggregation | EXPLICIT_DEVIATION | `test/unit/test_parity_corpus.gd::test_godot_agrees_with_the_reference_on_every_case` — see 1 |
| Ability lifecycle/commit | COMPLETE | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_four_to_six_configure_grant_and_run` |
| Specs/captures/stacking | EXPLICIT_DEVIATION | `test/unit/test_parity_corpus.gd::test_godot_agrees_with_the_reference_on_every_case` — see 1 |
| Tags/events | COMPLETE | `test/unit/test_hierarchical_tag_counts.gd::test_the_exact_signal_still_reports_the_exact_count` |
| Authoring/Composer | COMPLETE | `test/unit/test_ability_authoring_end_to_end_walk.gd::test_steps_nine_and_ten_editing_saving_and_reopening_loses_nothing` |
| Targeting/tasks/animation/cues | EXPLICIT_DEVIATION | `test/unit/test_targeting_lifecycle_end_to_end_walk.gd::test_case_one_previewing_confirming_and_cancelling` — see 2 and 3 |
| Authority/replication/prediction | EXPLICIT_DEVIATION | `test/unit/test_network_conditions_end_to_end_walk.gd::test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once` — see 4, 5 and 6 |
| Performance/determinism certification | EXPLICIT_DEVIATION | `test/unit/test_performance_and_determinism.gd::test_every_workload_is_measured_at_every_scale` — see 7, 8 and 9 |
| Distribution | COMPLETE | `artifacts/parity/DISTRIBUTION.md`, written by `tooling/distribution_check.py` — see 10 |

## The deviations, in full

**1. A stacking effect does not scale its modifiers by the stack count unless
it is told to.** The reference does it by default; `factor_in_stack_count`
defaults to false here and the export says what it does. The reference's
arithmetic is reachable and the corpus exercises it, so this is a different
default rather than a missing behaviour - but a project that assumed the
reference's default would get different numbers, which is why it is a deviation
and not a footnote.
`test/unit/test_parity_corpus.gd::test_godot_agrees_with_the_reference_on_every_case`

**2. `GameplayCueParams` carries the requested cue tag as `cue_tag`.** The
phase names "requested cue tag" and "matched cue tag" as two things the params
must carry, and they carry both; renaming the one every caller and every cue
script already uses would buy a matching identifier and cost every consumer.
`test/unit/test_cue_hierarchy.gd::test_a_cue_is_told_what_was_asked_for_and_what_answered`

**3. `override_parent` is authored in the cues file, not on `GameplayCueEntry`.**
The entry resource is the pre-file registry `SourceMigration` exists to migrate
away from; the file is the authoring surface now, and a binding's value there is
a `PackedScene` whose type leaves no room for a third column.
`test/unit/test_project_gameplay_cues.gd::test_only_the_real_override_body_counts`

**4. The addon owns no transport.** Messages come out of a signal and go in
through a call. The phase asks for multi-instance tests; what answers them is
three runtimes in one process over a link fixture that repeats, reorders, loses
and delays on demand. That is a smaller claim than two processes over a socket,
and the larger part of what those tests would check - every adverse condition is
reachable here and deterministic, where over a real socket none of them are.
Godot's own multiplayer plumbing is not covered, and this addon neither uses nor
wraps it.
`test/unit/test_network_conditions_end_to_end_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading`

**5. Effects replicate as readings, not as running effects.** Which effect, how
many, how long is left in seconds and in turns, whether it is inhibited - for a
game to show. They are not re-applied on the receiving machine: the attribute
values that arrive already have those effects in them, and applying the
modifiers again would count everything twice. The authority is the one machine
that simulates.
`test/unit/test_network_replication.gd::test_a_snapshot_carries_each_running_effect_and_its_readings`

**6. Prediction is offered for four things and refused for the rest.** Cost,
cooldown, an allowed attribute delta and a cue, because each can be undone with
what the operation itself remembers. A periodic tick, an arbitrary execution
calculation and a server-only side effect cannot, and the phase says not to
promise them. A one-shot cue that has already played cannot be unplayed either.
`test/unit/test_prediction_journal.gd::test_accepting_binds_the_guess_rather_than_repeating_it`

**7. No Unreal process is run.** The corpus is authored from the reference's
documented behaviour and every case is stamped with the version it was taken
from. That is what makes it reviewable - a wrong expectation is a wrong sentence
in a file rather than an invisible disagreement with a binary nobody has - and
it is not the same claim as a differential run against the reference itself.
`test/unit/test_parity_corpus.gd::test_every_case_names_the_reference_it_was_taken_from`

**8. Physics query order is not a determinism contract.** The order a query
reports overlapping bodies in is the physics server's. What this engine does
promise is that targets are reported in the order they were captured, and that
the one place gameplay depends on chance takes a seed.
`test/unit/test_performance_and_determinism.gd::test_targets_are_reported_in_the_order_they_were_captured`

**9. One measured hotspot is named and not optimised.** Applying effects to one
character is super-linear. Composing an attribute used to walk every
contribution on the entity once per channel and is indexed by attribute now; a
thousand effects went from six seconds to under four. What is left is the passes
each application makes over every effect already running - inhibition, stacking,
the effect components - and indexing those changes how application is ordered,
which belongs in a package of its own.
`test/unit/test_performance_and_determinism.gd::test_every_workload_is_measured_at_every_scale`

**10. The bridges are proved against doubles of their published surface.** No
Dialogic and no quest system addon is installed in this repository. Each double
implements exactly the one published signal its bridge depends on, and its
minimality is itself the check: if a double ever needs a second member for these
tests to pass, the bridge has reached past the surface it promised to depend on.
What the distribution check proves is the other half - that the addon runs in a
project where neither is present at all.
`test/unit/test_dialogic_bridge.gd::test_a_message_for_another_channel_is_ignored_without_complaint`

## Every finding, one line each

The phase closes only when B01-B16 and G01-G32 each have an explicit
contractual status, so here they are: what the document called the finding
at the start, the package that closed it, and whether closing it left a
deviation. Two kinds of row say EXPLICIT_DEVIATION - one the phase itself
opened as a deliberate GAS_Engine extension, and one whose closure produced
a numbered deviation above. Neither is a gap and neither is Unreal parity.

| Finding | What it was | Package | State | Note |
|---|---|---|---|---|
| B01 |  | F5.1.1 | COMPLETE | closed by F5.1.1 |
| B02 |  | F5.1.1 | COMPLETE | closed by F5.1.1 |
| B03 |  | F5.1.1 | COMPLETE | closed by F5.1.1 |
| B04 |  | F5.1.1 | COMPLETE | closed by F5.1.1 |
| B05 |  | F5.1.2 | COMPLETE | closed by F5.1.2 |
| B06 |  | F5.1.2 | COMPLETE | closed by F5.1.2 |
| B07 |  | F5.1.3 + F5.2.4 | COMPLETE | closed by F5.1.3 + F5.2.4 |
| B08 |  | F5.1.3 + F5.2.4 | COMPLETE | closed by F5.1.3 + F5.2.4 |
| B09 |  | F5.1.3 | COMPLETE | closed by F5.1.3 |
| B10 |  | F5.1.4 + F5.2.3 | COMPLETE | closed by F5.1.4 + F5.2.3 |
| B11 |  | F5.1.4 | COMPLETE | closed by F5.1.4 |
| B12 |  | F5.1.5 | COMPLETE | closed by F5.1.5 |
| B13 |  | F5.1.5 | COMPLETE | closed by F5.1.5 |
| B14 |  | F5.1.4 | COMPLETE | closed by F5.1.4 |
| B15 |  | F5.1.4 | COMPLETE | closed by F5.1.4 |
| B16 |  | F5.1.4 | COMPLETE | closed by F5.1.4 |
| G01 | capa server-authoritative y replicación | F5.5 | EXPLICIT_DEVIATION | see 4, 5 and 6 |
| G02 | prediction keys, confirm/reject y reconciliation | F5.5 | EXPLICIT_DEVIATION | see 4, 5 and 6 |
| G03 | ActorInfo owner/avatar desacoplado | F5.2.1 | COMPLETE | closed by F5.2.1 |
| G04 | preservar multiply compuesto; añadir álgebra UE por perfil | F5.2.3 | EXPLICIT_DEVIATION | a GAS_Engine extension the phase opened as one |
| G05 | canales, filtros source/target y override policy | F5.2.3 | COMPLETE | closed by F5.2.3 |
| G06 | Check/Apply Cost y Cooldown + commit transaccional | F5.2.4 | COMPLETE | closed by F5.2.4 |
| G07 | auto-end legacy preservado; explicit end en perfil UE | F5.2.5 | EXPLICIT_DEVIATION | a GAS_Engine extension the phase opened as one |
| G08 | retrigger + non-instanced stateless path | F5.2.5 | COMPLETE | closed by F5.2.5 |
| G09 | payload completo de GameplayEvent | F5.2.6 | COMPLETE | closed by F5.2.6 |
| G10 | referencia set+attribute | F5.2.2 | COMPLETE | closed by F5.2.2 |
| G11 | capture timing explícito | F5.2.7 | COMPLETE | closed by F5.2.7 |
| G12 | copia/spec y mutación dinámica validadas | F5.2.7 | COMPLETE | closed by F5.2.7 |
| G13 | duration/period magnitudes | F5.2.7 | COMPLETE | closed by F5.2.7 |
| G14 | TURN_BASED se conserva; tick-on-application UE se añade | F5.2.7 + F5.1.1 | EXPLICIT_DEVIATION | a GAS_Engine extension the phase opened as one |
| G15 | stacking math/identity/ExtendDuration | F5.2.3/F5.2.7 | EXPLICIT_DEVIATION | see 1 |
| G16 | mutaciones de active effect por handle | F5.2.7 | COMPLETE | closed by F5.2.7 |
| G17 | typed ExecCalc output | F5.2.8 | COMPLETE | closed by F5.2.8 |
| G18 | dependencias LIVE declarativas para cualquier magnitude | F5.2.7 | COMPLETE | closed by F5.2.7 |
| G19 | hierarchical counts/events | F5.2.9 | COMPLETE | closed by F5.2.9 |
| G20 | targeting provider lifecycle | F5.4.1 | COMPLETE | closed by F5.4.1 |
| G21 | contexto derivado por target sin perder payload | F5.4.2 | COMPLETE | closed by F5.4.2 |
| G22 | tasks de commit/immunity/count/spawn/state/movement/sync | F5.4.3 | COMPLETE | closed by F5.4.3 |
| G23 | animation ownership + interrupted/cancelled/blend-out | F5.4.4 | COMPLETE | closed by F5.4.4 |
| G24 | hierarchical cue dispatch y parámetros completos | F5.4.5 | EXPLICIT_DEVIATION | see 2 and 3 |
| G25 | authoring reusable asset-first | F5.3.2 | COMPLETE | closed by F5.3.2 |
| G26 | AST/IR del Composer más expresivo | F5.3.3 | COMPLETE | closed by F5.3.3 |
| G27 | crear ability debe producir script+scene usable | F5.3.1/F5.3.4 | COMPLETE | closed by F5.3.1/F5.3.4 |
| G28 | cubierto primero por B12/B13; después document manager | F5.1.5/F5.3 | COMPLETE | closed by F5.1.5/F5.3 |
| G29 | runtime debugger/trace/breakpoints | F5.3.5/F5.3.6 | COMPLETE | closed by F5.3.5/F5.3.6 |
| G30 | façade uniforme por handles/resultados | F5.2.10 | COMPLETE | closed by F5.2.10 |
| G31 | perfiles de carga, memoria y determinismo | F5.6.2 | EXPLICIT_DEVIATION | see 8 and 9 |
| G32 | matriz versionada + differential corpus | F5.0/F5.6 | EXPLICIT_DEVIATION | see 7 and 10 |
