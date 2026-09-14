# Gate F6.5 — receipt

Package: F6.5 (F6.5.1 through F6.5.3), covering D-07, D-08 and D-11.
Baseline GAS_Engine: `a0bc379`. Reference ran at `010d257`.
Reference: a published GAS reference, revision 5.7.4-51494982 — ran 2026-09-11.

All three tasks closed. This receipt used to say the third could not close on
this machine, and left that STOP written down for whoever read it next rather
than letting it be the absence of a file - "D-08 and D-11, and why they were
blocked" below is that record, kept because the wrong turn (a blocker recorded
as "the engine is missing" that was not) is exactly the kind of thing worth
being able to still read after it stops being true.

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_5.md
```

The corpus that D-08 and D-11 measured against (`test/parity/goldens/`), the
harness that produced the run below (`tools/ue_reference/`) and the two
scripts that machine-checked this receipt against it (`tooling/parity_diff.py`,
`tooling/certification_consistency.py`) were retired once Phase 6 closed:
proving parity against the reference was their whole job, the comparison below
is that proof, and a comparison already made does not need permanent machinery
standing by to keep re-proving it. What follows is kept as history rather than
as something still runnable.

## Findings

| Finding | Status | Evidence |
|---|---|---|
| D-07 application and reevaluation grew with the character, by global traversal | CLOSED | `test/unit/test_effect_index_scaling.gd::test_an_application_asks_only_what_grants_immunity` |
| D-08 the parity corpus was authored rather than produced by a real reference | CLOSED | a real reference run, 2026-09-11 - corpus and harness retired, see below |
| D-11 override order has to be checked against the real reference | CLOSED | the same run - see "D-11 closes" below |

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

The published reference build named by every golden produced eight of the ten
scenarios. `tools/ue_reference/harness/` was the project that did it and
`artifacts/parity/results/ue_reference_run.json` was what came out.

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
behaviour the reference produces is the one to implement. The reference
produces **40.0**: the first override registered is the one that stands. This
engine already produced 40.0, so there was nothing to implement - but that is
now a measurement rather than a coincidence nobody had checked.

It is a measurement of *order* and not of magnitude, which took a second run to
establish: the same pair swapped answers 70.0. `override_across_channels` was
swapped too, and answers 40.0 - so a later channel's override stands whatever
its magnitude, and the two rules are different rules.

### D-08 closes: all ten

The last two took two more findings to measure, and both were the harness.

**The clock was never running.** The reference's own world-tick advanced its
simulated time and no timer ever fired - proved with a timer of the harness's
own, set for one second and silent over two. The reference's timer manager
ticks at most once per frame and the frame counter was never moving. The
reference's own test suite advances that counter by hand between sub-ticks,
with a comment calling it terrible and doing it anyway. With it, the control
that inhibits nothing executes three times over 2.5 seconds at a period of
1.0 - which is the number that says the clock and the period are real - and
the inhibited run answers 80.

**The tag scenario was measuring the right thing all along.** All four variants
answer 10.0 under an infinite effect, and the reference's own source says why,
at the line that does it: a persistent modifier is evaluated outside of an
execution, and outside of an execution there are no source or target tags to
fill out at all. A modifier's own requirement is never met under a persistent
effect, whatever either side carries. The controls agree exactly: a requirement
that must be present always filters (an "all of" match against nothing is
false) and one that must be absent never does (an "any of" match against
nothing is also false). Asked as an execution instead, the same reference
answers 10, 15, 17 and 22 - the target requirement read from the target and
the source one from the source, which is the question the scenario is named
for.

### One declared deviation, and a corpus that could say so

This engine answers 10, 15, 17 and 22 under an infinite effect too. That is
deliberate - F5.2.3 added modifier requirements so one effect can hit harder
against the undead without being authored twice, and a condition that silently
never counts is a feature that does nothing.

A corpus that can only say "same" or "wrong" cannot say "different on purpose",
and this repository's traceability vocabulary already could: CLOSED,
EXPLICIT_DEVIATION, BLOCKED. A golden was allowed to carry `engine_deviation`,
a written reason, and the corpus's own comparison tool reported the difference
in full rather than calling it a fault. It was not a way to quiet a
disagreement: the reason had to be there, it was only allowed on a golden that
had actually run, and the numbers were still printed - checked at the time by
the now-retired corpus's own test suite.

One other difference turned out to be this engine's own default rather than a
divergence. The reference executes a periodic effect on application; this
engine does not, and says so in `gameplay_effect.gd` where the flag lives. The
scenario sets it, because the scenario is about what the reference did.

```text
goldens: 10
VERIFIED: 10
NOT_VERIFIED: 0
declared deviations: 1
```


## D-08 and D-11, and why they were blocked

The corpus under `test/parity/goldens/` carried ten scenarios in the shape the
phase named. At the time this section was written, every one of them said
NOT_VERIFIED — that was the honest state then: the numbers in them were
derived from this engine and from the reference's documentation, and neither
was a reference having been run. "The reference ran, 2026-09-11" above is what
changed it; every scenario went on to say VERIFIED, and what follows is why it
took as long as it did to get there rather than a description of where things
still stand.

**Correction, 2026-09-11.** This receipt said the reference build was not
installed on this machine. That was not measured, and it was false: the exact
build these goldens named was installed, with its ability-system plugin and
prebuilt binaries. The STOP was real and stood, but not for the reason written
here, and a blocker recorded as "the engine is missing" is one nobody re-checks.

What actually blocked it was one missing component, and `tools/ue_reference/`
carried a harness that proved where the wall was rather than describing it.
The editor build target would not build because a network-swarm module threw
without a .NET Framework 4.6+ SDK, which was not installed. The game build
target built and linked against the real reference plugin but could not run,
because a monolithic binary needs cooked content and cooking needs the editor.
Driving it from the editor's own scripting plugin got as far as building
modifiers exactly and then died on an actor-info validity assertion, because
the initializer it needed was not exposed to that scripting layer - which is
why the harness had a compiled module at all, and that module compiled.

Installing the .NET Framework 4.8 SDK closed all three at once. The engine
install was deliberately left unmodified otherwise.

The phase forbade inventing the outputs while none of this was done. So, until
it was:

- `tooling/parity_diff.py` refused to compare and exited non-zero, which was
  the STOP rather than a failure of the engine;
- `tools/ue_reference/README.md` said exactly what had to be run and where the
  output went;
- nothing anywhere called these numbers parity — the now-retired corpus's own
  test suite still checked that a golden claiming VERIFIED carried what a run
  produced, once ten of them did.

Both findings closed once the .NET SDK went in, the harness ran, and
`artifacts/parity/results/ue_reference_run.json` and the ten re-stamped
goldens were the result - "The reference ran, 2026-09-11", above.

The work after this package proceeded on an explicit decision to carry the STOP
forward rather than to stop the phase on it. That decision is recorded here
rather than implied by the commits that follow.
