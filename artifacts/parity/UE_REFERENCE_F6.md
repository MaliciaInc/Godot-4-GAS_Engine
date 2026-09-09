# UE reference corpus — F6.5.3

```text
STOP: UE_REFERENCE_UNAVAILABLE
PACKAGE: F6.5
```

## What this says

F6.5.3 asks for a corpus of ten scenarios produced by a real Unreal Engine
5.7.4 run, and states the rule the corpus exists to enforce: evidence is either
`UE_VERIFIED` or `NOT_UE_VERIFIED`, and `AUTHORED` is not presented as parity.
It then names the stop outright — if UE 5.7.4 cannot be run and the corpus
cannot be produced or validated, F6.5 does not close and F6.6 does not proceed
as though certification had happened.

Unreal Engine 5.7.4 is not available on the machine this was implemented on. No
Unreal process has been run against any of these scenarios. So every golden says
`NOT_UE_VERIFIED`, and this is that stop, recorded rather than worked around.

## What exists

| Piece | State |
|---|---|
| `tools/ue_reference/README.md` | the procedure, written |
| `test/parity/goldens/` | ten scenarios, every field filled in except the ones only Unreal can answer |
| `tooling/parity_diff.py` | validates the corpus, compares verified goldens, and stops on unverified ones |
| `artifacts/parity/results/ue_scenarios.json` | what this engine produces for each scenario, written by the suite |

Each golden carries its `ue_version`, `changelist`, scenario id, inputs, numeric
tolerance, and whether execution order is observable in it. `outputs` and
`execution_order` are null, because those are the two things a run produces and
nothing else may.

```text
python tooling/parity_diff.py
```

exits non-zero today, printing the stop above and naming all ten.

## What this blocks

- **F6.5 does not close.** F6.5.1 and F6.5.2 are done and are recorded in
  `artifacts/parity/PERFORMANCE_F6.md`; F6.5.3 is not, and the package gate is
  the three together.
- **D-08 and D-11 stay open.** D-11 in particular is decided outright by the
  double-override golden: whichever override the reference produces is what this
  engine implements, and the contract matrix is updated to match. Deciding it
  from this engine's current behaviour would be writing down the answer we
  already have and calling it agreement.
- **F6.6 does not proceed as though certification happened.** Whether it
  proceeds at all is a decision for whoever owns the phase, and it is a
  different decision from this one.

## What would close it

Somebody with UE 5.7.4 (CL 51494982) works through
`tools/ue_reference/README.md`: builds each scenario from its `inputs` block,
records what the reference produced into `outputs`, fills in `execution_order`
where it is observable, and flips that scenario's `evidence` to `UE_VERIFIED` —
one at a time, as each is actually run. `parity_diff.py` then compares each
verified golden with what this engine produced, to that golden's tolerance, and
says where the two disagree.

Nothing in this repository can perform that step, and nothing in it should
pretend to.

## What is not affected

The authored corpus under `test/parity/contracts/` is unchanged and is still
what it always said it was: expectations taken from the reference's documented
behaviour, stamped with the version they were taken from, with no Unreal process
run. It is reviewable and it is useful. It is not this, and F6.5.3 exists
because the two are different things.
