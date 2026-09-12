# Gate F6.5 — receipt

Package: F6.5 (F6.5.1 through F6.5.3), covering D-07, D-08 and D-11.
Baseline GAS_Engine: `a0bc379`.
Reference: Unreal Engine 5.7.4, CL 51494982 — **not run**, which is what this
receipt is mostly about.

Two of the three tasks closed. The third cannot, on this machine, and the phase
document says what that means: `BLOCKED` is a STOP and the package stays open.
This receipt exists so the STOP is written down rather than being the absence
of a file.

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_5.md
python tooling/parity_diff.py
```

## Findings

| Finding | Status | Evidence |
|---|---|---|
| D-07 application and reevaluation grew with the character, by global traversal | CLOSED | `test/unit/test_effect_index_scaling.gd::test_an_application_asks_only_what_grants_immunity` |
| D-08 the parity corpus was authored rather than produced by a real reference | **BLOCKED** | `test/unit/test_ue_reference_corpus.gd::test_every_golden_says_everything_and_invents_no_third_word` |
| D-11 override order has to be checked against the real reference | CLOSED | `test/unit/test_ue_reference_corpus.gd::test_a_verified_golden_carries_what_a_run_produces` |

## D-07, and how it was found

By profiling rather than by reading. The phase asks for the real global
traversals, and the one that dominated was not the one the document guessed at:
`_is_immune_to` walked every active effect on every application, so a character
with a hundred effects paid a hundred reads per effect applied. Indexing the
immunity sources took the certification benchmark from seven and a half minutes
to thirty-seven seconds.

Three searches are indexed now, and each of them is a different question:

- what a new effect could stack onto — `test/unit/test_effect_index_scaling.gd::test_a_stack_search_does_not_read_a_crowd_it_cannot_join`;
- what a tag change could have changed — `test/unit/test_effect_index_scaling.gd::test_a_tag_change_reevaluates_only_what_depends_on_it`;
- what grants immunity — `test/unit/test_effect_index_scaling.gd::test_an_application_asks_only_what_grants_immunity`.

The index is an accelerator and not a second source of truth: a scoped pass
leaves the same state a full one would, and that is asserted rather than
assumed — `test/unit/test_effect_index_scaling.gd::test_the_scoped_pass_leaves_the_same_state_as_a_full_one`.

## The reference ran, 2026-09-11

Unreal Engine 5.7.4 CL 51494982 - the build every golden names - produced eight
of the ten scenarios. `tools/ue_reference/harness/` is the project that did it
and `artifacts/parity/results/ue_reference_run.json` is what came out.

| scenario | reference | this engine |
|---|---|---|
| `legacy_multiply_one_and_a_half_twice` | 20.0 | 20.0 |
| `multiply_compound_one_and_a_half_twice` | 22.5 | 22.5 |
| `legacy_divide` | 5.0 | 5.0 |
| `double_override_same_channel` | **40.0** | 40.0 |
| `override_across_channels` | 70.0 | 70.0 |
| `stack_count_factor_off_and_on` | 15.0 / 25.0 | 15.0 / 25.0 |
| `bonus_magnitude` | 105.0 | 105.0 |
| `magnitude_up_to_channel` | health 85.0, attack 115.0 | the same |

Eight comparisons, eight agreements, to each golden's tolerance.

### D-11 closes

The phase says the double-override golden decides the order and that the
behaviour Unreal produces is the one to implement. Unreal produces **40.0**:
the first override registered is the one that stands. This engine already
produced 40.0, so there was nothing to implement - but that is now a
measurement rather than a coincidence nobody had checked.

It is a measurement of *order* and not of magnitude, which took a second run to
establish: the same pair swapped answers 70.0. `override_across_channels` was
swapped too, and answers 40.0 - so a later channel's override stands whatever
its magnitude, and the two rules are different rules.

### D-08 does not close, and its scope is now two scenarios

Eight goldens say `UE_VERIFIED` and carry what the run produced. Two do not,
and are written up as not measured rather than filled in:

`modifier_source_and_target_tag_qualification` answered 10.0 in all four
variants, and the controls say that is the harness rather than Unreal. A
modifier with no requirement across the same source-to-target path applies
(10.0 -> 15.0); a modifier whose target requirement *is* met answers 10.0, with
the tag added before the effect and again after, with the target's owned tags
read back as `Status.Burning` both times, and with the requirement written both
as `RequireTags` and as a `TagQuery`.

`short_inhibition_with_execute_and_reset_period` has a control that executes
zero times over a world that reaches 5.1 seconds, when it should execute most
often of all. The period is not what is missing, and that was measured: the
definition says 1.0, the spec built from it says 1.0, the duration says
infinite, and `bExecutePeriodicEffectOnApplication` is on - which should have
executed once at application with no clock in it at all.

Four identical variants and an idle clock are also what a harness that applied
nothing produces. Writing either set of numbers down as Unreal's answer is the
one thing this corpus exists to refuse, so neither is written down.

## D-08 and D-11, and why they are blocked

The corpus under `test/parity/goldens/` carries ten scenarios in the shape the
phase names, and every one of them says `NOT_UE_VERIFIED`. That is the honest
state: the numbers in them were derived from this engine and from the
reference's documentation, and neither is a reference having been run.

**Correction, 2026-09-11.** This receipt said "Unreal Engine 5.7.4 is not
installed on this machine". That was not measured, and it was false: UE 5.7.4
CL 51494982 - the exact build these goldens name - is installed at
`C:/Program Files/Epic Games/UE_5.7`, with the GameplayAbilities plugin and its
prebuilt binaries. The STOP is real and stands, but not for the reason written
here, and a blocker recorded as "the engine is missing" is one nobody re-checks.

What actually blocks it is one missing component, and `tools/ue_reference/`
now carries a harness that proves where the wall is rather than describing it.
The editor target will not build because `SwarmInterface.Build.cs` throws
without a .NET Framework 4.6+ SDK, which is not installed. The game target
builds and links against real GAS but cannot run, because a monolithic binary
needs cooked content and cooking needs the editor. Driving it from the editor's
Python plugin gets as far as building modifiers exactly and then dies on
`Ensure condition failed: AbilityActorInfo.IsValid()`, because
`InitAbilityActorInfo` is not a `UFUNCTION` - which is why the harness has a
C++ module at all, and that module compiles.

Installing the .NET Framework 4.8 SDK closes all three at once. The engine
install was deliberately left unmodified.

The phase forbids inventing the outputs. So:

- `tooling/parity_diff.py` refuses to compare and exits non-zero, which is the
  STOP rather than a failure of the engine;
- `tools/ue_reference/README.md` says exactly what has to be run and where the
  output goes;
- nothing anywhere calls these numbers parity —
  `test/unit/test_ue_reference_corpus.gd::test_a_verified_golden_carries_what_a_run_produces`.

Both findings close the moment a real 5.7.4 produces
`artifacts/parity/results/ue_scenarios.json` and the goldens are re-stamped
`UE_VERIFIED`. Until then F6.5 is open, and F6 is not closeable — which is the
phase document's own rule and not a judgement made here.

The work after this package proceeded on an explicit decision to carry the STOP
forward rather than to stop the phase on it. That decision is recorded here
rather than implied by the commits that follow.
