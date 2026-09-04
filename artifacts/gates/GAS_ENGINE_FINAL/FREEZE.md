# Freeze

    commit   6db48dac670b22c38551eb21d34e8e78d0f515ee
    date     2026-09-03
    subject  The selective export smoke, and the claim it disproved
    engine   Godot 4.7.2.stable.steam (ed1daf0bf), Forward+

Every receipt in this directory was produced from that commit, with a clean
working tree. The consumer project the engine is developed against was on the
same engine bytes at the time, verified with a recursive diff.

The receipts are committed after the frozen commit, because a receipt cannot be
inside the tree it certifies. This file is the link between the two: the commit
named above is the release, and what sits beside this file is the evidence for
it.

Two things landed between that commit and the receipts, both belonging to the
freeze itself rather than to the release: the identity gate stopped skipping
this directory, and `tooling/RECEIPT-HYGIENE.md` was updated to say the
procedure had run. Neither touches anything the engine ships, and that is
checkable rather than asserted — `engine_evidence.py` fingerprints every
tracked `.gd`, `.tscn`, `project.godot` and `README.md`, and the fingerprint in
the two receipts beside this file is the one those files hash to at the commit
named above.

## Two acceptances that are not evidence of a defect

**OP025** — the twelve-step editor plugin sequence was not executed. The
decision to accept that as a tooling limitation was taken by the project owner
on 2026-09-01 and is unchanged; `OP025-known-limitation.md` beside this file
records why, what was tried, and which headless tests cover the ownership logic
it protects. Re-checked at this commit: both tests it names are present, and
the defect the attempt surfaced is still fixed.

**Selective export** — `export-cue-smoke.md` beside this file records what a
build actually contains when a cue is bound. It found no defect in the engine's
behaviour; it found a false statement about it, which is corrected in this
commit, and it produced the export instruction now in `README.md`.

## What was verified at this commit

    suite            1093 passing of 1093, 37475 asserts, 0 risky, 0 orphans
    strict typing    197 engine scripts, 0 with problems
    verify.ps1       PASS on every stage
