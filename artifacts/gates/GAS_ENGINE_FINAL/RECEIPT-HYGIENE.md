# What has to be true of this receipt set when it is regenerated

The receipts in this directory are the release evidence. They are deliberately
**stale** right now — regenerating them was deferred until the freeze, because
work was still landing — so everything below describes the check that belongs to
the regeneration, not a claim about the files as they stand today.

## What is stale here, measured

    duplication.log, duplication.md, gate-self-tests.log, loc.log, loc.md,
    magic-string.log, magic-strings.md, test-location.log, test-location.md
        carry `C:\Users\<name>\Documents\Projectos\Arhalies_GAS`

    mcp-gut.txt
        carries `ARHALIES_GUT_RESULT: PASS passed=29970`

Both are from before the rename, and both are why this note exists.

## The generator produced them that way, and no longer does

The absolute path was not something that crept in. It was rendered on purpose,
in three places - and the third only turned up because the check below was run
against a freshly generated set instead of being taken on trust:

- `tooling/gates/lib/gate_report.py` wrote the resolved project root into the
  `- Project:` header row of every gate's Markdown. It writes `` `<repo>` `` now,
  and `Report` no longer has a root to be given — an unread field on a dataclass
  every gate fills in is an invitation to print it again.
- `tooling/verify.ps1` wrote the full command line into every `.log`, with the
  repository spelled absolutely on both the runner and the receipt directory.
  It is written relative to the repository now; the child process already runs
  with the repository as its working directory, so that is the command that
  actually ran.
- `verify.ps1` also captured the gate self-tests' own output into
  `gate-self-tests.log`, and two of those tests point a gate at a missing path
  under the user's profile on purpose. The gate is right to name the path it
  could not read; the stage now runs `unittest --buffer`, which holds a passing
  test's output and shows it only for a failing one. Fixing those two tests
  would have left the next one free to do the same thing.

`tooling/gates/tests/test_gate_report.py` pins the first of those. The other two
have no unit harness — PowerShell has no test runner here — so they are checked
by running `verify.ps1` and reading the receipts it produced. That check is what
found the third.

## The check that belongs to the freeze

After regenerating this directory, and **before committing it**, the whole set
must satisfy all four:

1. no absolute path — nothing matching `:\`, `:/`, `/home/`, `/Users/`
2. no legacy identity — nothing matching `arhalies`, case-insensitively
3. no legacy verdict prefix — the suite receipt says `GAS_ENGINE_GUT_RESULT:`
4. the fingerprint in `mcp-gut.txt` and `mcp-godot-import.txt` is the one
   `python tooling/engine_evidence.py <this directory>` computes at the frozen
   commit, and both say `RESULT: PASS`

Points 1 to 3 can be read straight off the directory:

```bash
grep -rn -i -F -e ':\' -e ':/' -e '/home/' -e '/Users/' -e 'arhalies' artifacts/gates/GAS_ENGINE_FINAL/
```

That command has to print nothing. Run against
`artifacts/gates/source-fold-tests`, a set generated after all three fixes, it
does.

`-F` is not decoration. Without it the first pattern ends in a backslash, which
is a regex escape with nothing after it, so grep exits with `Trailing backslash`
and prints no matches — which reads exactly like a clean set. That happened
while this note was being written.

## Why this is not a gate today

`tooling/product_identity.py` skips `artifacts/gates/` entirely. That is
correct while this set is deliberately old: scanning it would fail
`verify.ps1` on every run between now and the freeze, over files nobody is
allowed to touch yet.

Turning the skip off is therefore a **freeze-day** step, not one to take early.
Once this directory is clean, `artifacts/gates/` can stop being skipped, and
points 1 to 3 stop being a procedure and become a gate. Do it in that order:
clean the set first, then let the gate hold it.
