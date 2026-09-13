# Gate F6.5 — receipt

Package: F6.5 (F6.5.1 through F6.5.3), covering D-07, D-08 and D-11.
Baseline GAS_Engine: `a0bc379`. Reference ran at `010d257`.
Reference: Unreal Engine 5.7.4, CL 51494982 — **ran 2026-09-11**.

```text
CERTIFICATION_STATUS: status=CLOSED verified=10/10 numeric_mismatches=0 trace_mismatches=0 stop_code=none
```

Machine-checked against `artifacts/parity/f6_result.json` by
`python tooling/certification_consistency.py`.

All three tasks closed. This receipt used to say the third could not close on
this machine, and left that STOP written down for whoever read it next rather
than letting it be the absence of a file - "D-08 and D-11, and why they are
blocked" below is that record, kept because the wrong turn (a blocker recorded
as "the engine is missing" that was not) is exactly the kind of thing worth
being able to still read after it stops being true.

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_5.md
python tooling/parity_diff.py
```

## Findings

| Finding | Status | Evidence |
|---|---|---|
| D-07 application and reevaluation grew with the character, by global traversal | CLOSED | `test/unit/test_effect_index_scaling.gd::test_an_application_asks_only_what_grants_immunity` |
| D-08 the parity corpus was authored rather than produced by a real reference | CLOSED | `test/unit/test_ue_reference_corpus.gd::test_a_verified_golden_carries_what_a_run_produces` |
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

### D-08 closes: all ten

The last two took two more findings to measure, and both were the harness.

**The clock was never running.** `UWorld::Tick` advanced `TimeSeconds` and no
timer ever fired - proved with a timer of the harness's own, set for one second
and silent over two. `FTimerManager` ticks at most once per frame and the frame
counter was never moving. Unreal's own `GameplayEffectTests.cpp` does
`GFrameCounter++` between sub-ticks, with a comment calling it terrible and
doing it anyway. With it, the control that inhibits nothing executes three
times over 2.5 seconds at a period of 1.0 - which is the number that says the
clock and the period are real - and the inhibited run answers 80.

**The tag scenario was measuring the right thing all along.** All four variants
answer 10.0 under an infinite effect, and Unreal's own source says why, at the
line that does it: *"this is not an execution, so there are no 'source' and
'target' tags to fill out in the FAggregatorEvaluateParameters"*. A modifier's
own requirement is never met under a persistent effect, whatever either side
carries. The controls agree exactly: a requirement that must be present always
filters (`HasAll` of an empty container is false) and one that must be absent
never does (`HasAny` of an empty container is false). Asked as an execution
instead, the same reference answers 10, 15, 17 and 22 - the target requirement
read from the target and the source one from the source, which is the question
the scenario is named for.

### One declared deviation, and a corpus that can say so

This engine answers 10, 15, 17 and 22 under an infinite effect too. That is
deliberate - F5.2.3 added modifier requirements so one effect can hit harder
against the undead without being authored twice, and a condition that silently
never counts is a feature that does nothing.

A corpus that can only say "same" or "wrong" cannot say "different on purpose",
and this repository's traceability vocabulary already can: CLOSED,
EXPLICIT_DEVIATION, BLOCKED. A golden may now carry `engine_deviation`, a
written reason, and `parity_diff` reports the difference in full and does not
call it a fault. It is not a way to quiet a disagreement: the reason must be
there, it is only allowed on a golden that was actually run, and the numbers
are still printed - checked by
`test/unit/test_ue_reference_corpus.gd::test_a_declared_deviation_says_why_and_is_on_a_golden_that_ran`.

One other difference turned out to be this engine's own default rather than a
divergence. Unreal executes a periodic effect on application; this engine does
not, and says so in `gameplay_effect.gd` where the flag lives. The scenario
sets it, because the scenario is about what Unreal did.

```text
goldens: 10
UE_VERIFIED: 10
NOT_UE_VERIFIED: 0
declared deviations: 1
```


## D-08 and D-11, and why they were blocked

The corpus under `test/parity/goldens/` carries ten scenarios in the shape the
phase names. At the time this section was written, every one of them said
`NOT_UE_VERIFIED` — that was the honest state then: the numbers in them were
derived from this engine and from the reference's documentation, and neither
was a reference having been run. "The reference ran, 2026-09-11" above is what
changed it; every scenario now says `UE_VERIFIED`, and what follows is why it
took as long as it did to get there rather than a description of where things
still stand.

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

Installing the .NET Framework 4.8 SDK closed all three at once. The engine
install was deliberately left unmodified otherwise.

The phase forbade inventing the outputs while none of this was done. So, until
it was:

- `tooling/parity_diff.py` refused to compare and exited non-zero, which was
  the STOP rather than a failure of the engine;
- `tools/ue_reference/README.md` said exactly what had to be run and where the
  output went;
- nothing anywhere called these numbers parity —
  `test/unit/test_ue_reference_corpus.gd::test_a_verified_golden_carries_what_a_run_produces`
  still checks that a golden claiming `UE_VERIFIED` carries what a run
  produces, now that ten of them do.

Both findings closed once the .NET SDK went in, the harness ran, and
`artifacts/parity/results/ue_reference_run.json` and the ten re-stamped
goldens were the result - "The reference ran, 2026-09-11", above.

The work after this package proceeded on an explicit decision to carry the STOP
forward rather than to stop the phase on it. That decision is recorded here
rather than implied by the commits that follow.
