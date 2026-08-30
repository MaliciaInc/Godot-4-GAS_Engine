Clean-checkout verification (step 11.4)

RESULT: PASS

Procedure
---------
The 531 files git tracks were copied into an empty directory outside the
repository - no `.godot/`, no `mcp_interaction_server.gd`, no `artifacts/gut/`.
Godot imported the project once (MCP `launch_editor`, per Override 2, since the
CLI is not the path here), then the headless GUT runner ran there.

Result
------
14 scripts, 148 tests, 19001 asserts, 0 failures, written 2026-08-30T06:58:19.

This is not a re-reading of this machine's receipt: the evidence files were
deleted from the copy before the run, and the receipt it produced carries its
own timestamp.

What it found
-------------
Two defects that could not fail on a machine that had opened the project before.

1. `project.godot` declared the MCP's own autoload, whose script is gitignored.
   A clean checkout would have declared an autoload it does not have.

2. The GameplayCueManager autoload named global classes instead of preloading
   them. Godot initialises autoloads before it has scanned for `class_name`
   declarations, so on a fresh clone it failed to boot:

       Parser Error: Could not find type "GameplayCuePoolBucket" in the current scope
       Parser Error: Identifier not found: GameplayCueParams

   The second form is the sharper one: a file cannot resolve even its own class
   name as an identifier there, though a type annotation is fine. So four
   scripts preload themselves under an alias and construct through it.

Both are now rules in tooling/project_invariants.py, which verify.ps1 runs
before the gates. Reintroducing `GameplayCueParams.new()` makes it exit 1;
removing it again makes it exit 0.

A first import pass is required on any fresh clone, for GUT as much as for this
addon - `addons/gut/gut_config.gd` needs `GutUtils` in the class cache. That is
normal Godot, not a defect, and it is what the run above does first.

Orphan nodes (step 11.3)
------------------------
The headless runner now reads GUT's orphan counter on its `end_run` signal and
refuses the suite when it is non-zero, so the receipt states `orphans=N` rather
than being silent about a check nobody made.

Proved in both directions. A test that allocates a `Node` and never frees it:

    ARHALIES_GUT_RESULT: FAIL passed=19002 failed=1 pending=0 orphans=1
    detail: ORPHAN NODES: 1 node(s) outlived the run

Every assertion in that run passed. Removing the probe returns it to

    ARHALIES_GUT_RESULT: PASS passed=19001 failed=0 pending=0 orphans=0
