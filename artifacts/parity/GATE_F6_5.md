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
| D-11 override order has to be checked against the real reference | **BLOCKED** | `test/unit/test_ue_reference_corpus.gd::test_every_golden_says_everything_and_invents_no_third_word` |

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

## D-08 and D-11, and why they are blocked

The corpus under `test/parity/goldens/` carries ten scenarios in the shape the
phase names, and every one of them says `NOT_UE_VERIFIED`. That is the honest
state: the numbers in them were derived from this engine and from the
reference's documentation, and neither is a reference having been run.

Unreal Engine 5.7.4 is not installed on this machine and the phase forbids
inventing the outputs. So:

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
