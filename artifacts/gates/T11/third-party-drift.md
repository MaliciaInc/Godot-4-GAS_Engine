GUT pin verification (step 11.6)

The vendored dependency was compared against a fresh checkout of
aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605 (v9.7.1) and matched byte for byte.
That comparison is recorded in this repository's history.

This run does not re-clone upstream. It verifies the weaker, sufficient fact
that addons/gut has not moved since: git reports 0 changed files across the
259 tracked files under addons/gut, against 5b50900302bfc38e13737c49e3af6dd1b55cd4ce.

RESULT: PASS

The strict-typing pass drops a .gdignore into addons/gut while it runs and
removes it on leave; it is absent here, which the count above confirms.

GodotGAS is deliberately NOT byte-identical to upstream: it is a fork, and
THIRD_PARTY.md and the commit history record what changed.
