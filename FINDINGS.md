# Sandbox findings

Defects, gaps and rough edges the sandbox surfaces in `addons/GAS_Engine`.

**Nothing here is fixed in this branch.** Each entry is written up so it can be
reproduced on `main`, where the regression test and the repair belong. See
`SANDBOX.md` for the workflow.

## How to read an entry

| Field | Meaning |
|---|---|
| Status | `OPEN` · `FIXED ON MAIN <sha>` · `VERIFIED IN SANDBOX` · `NOT A DEFECT` |
| Where | the addon file and function, not the sandbox file that tripped it |
| Repro | the shortest sandbox path that shows it |
| Expected / Actual | what the addon's own contract promises, and what happened |
| Impact | what a game integrating GAS_Engine would suffer |

An entry stays `OPEN` until a regression test exists on `main`. It only becomes
`VERIFIED IN SANDBOX` after the addon is re-deployed here and the repro is run
again.

---

## Open

_None recorded yet - integration has not started._

---

## Closed

_None yet._
