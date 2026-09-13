# UE reference corpus — F6.5.3

```text
CERTIFICATION_STATUS: status=CLOSED verified=10/10 numeric_mismatches=0 trace_mismatches=0 stop_code=none
```

Machine-checked against `artifacts/parity/f6_result.json` and the goldens
themselves by `python tooling/certification_consistency.py`. AUD-01 found this
file still claiming the stop below after the reference had actually run - the
correction is the line above, generated from the one place these numbers are
now typed, and this file is one of the three it must appear in verbatim.

## What this says

F6.5.3 asked for a corpus of ten scenarios produced by a real Unreal Engine
5.7.4 run, and stated the rule the corpus exists to enforce: evidence is either
`UE_VERIFIED` or `NOT_UE_VERIFIED`, and `AUTHORED` is not presented as parity.
All ten now say `UE_VERIFIED` - `artifacts/parity/GATE_F6_5.md` has the run
itself, what it measured, and the two findings it decided.

## What exists

| Piece | State |
|---|---|
| `tools/ue_reference/README.md` | the procedure, written |
| `test/parity/goldens/` | ten scenarios, all ten `UE_VERIFIED` |
| `tooling/parity_diff.py` | validates the corpus, compares verified goldens, and stops on unverified ones |
| `artifacts/parity/results/ue_reference_run.json` | what UE 5.7.4 CL 51494982 actually produced, per scenario |
| `artifacts/parity/results/ue_scenarios.json` | what this engine produces for each scenario, written by the suite |

Each golden carries its `ue_version`, `changelist`, scenario id, inputs,
outputs, numeric tolerance, and - where the reference makes it observable -
`execution_order`.

```text
python tooling/parity_diff.py
```

exits zero: ten verified, zero mismatches, one declared deviation (the
tag-qualification scenario under a persistent effect - `parity_diff.py`
prints why, and `GATE_F6_5.md` has the reference source it quotes).

## What this closed

- **F6.5 closes.** F6.5.1, F6.5.2 and F6.5.3 are all done; F6.5.1 and F6.5.2
  are recorded in `artifacts/parity/PERFORMANCE_F6.md`, F6.5.3 here and in
  `GATE_F6_5.md`.
- **D-08 and D-11 close.** D-11 is decided by the double-override golden,
  measured rather than assumed: the reference answers 40.0, the first override
  registered is the one that stands, and this engine already produced that
  before the measurement existed to check it against.

## What is not affected

The authored corpus under `test/parity/contracts/` is unchanged and is still
what it always said it was: expectations taken from the reference's documented
behaviour, stamped with the version they were taken from, with no Unreal process
run. It is reviewable and it is useful. It is not this, and F6.5.3 exists
because the two are different things.
