# Indexed search performance certification

Written by `test/unit/test_indexed_search_performance_certification.gd` on every
suite run. Microseconds, on the machine named below: a number here is a
fact about that machine and nothing in the suite fails for it. What the
suite does fail for is structural and is in the table after this one.

## The machine and the build

| what | value |
|---|---|
| CPU | Intel(R) Core(TM) i7-14700F |
| cores | 28 |
| RAM (MiB) | 65370 |
| OS | Windows 10.0.26200 |
| Godot | 4.7.2-stable (steam) |
| build | debug |
| warmup runs | 1 |
| measured runs | 5 |

## What each load cost

| load | scale | runs | p50 us | p95 us | p99 us | objects left |
|---|---|---|---|---|---|---|
| apply effects | 100 | 5 | 40223.0 | 51864.0 | 51864.0 | 0 |
| apply effects | 1000 | 5 | 417626.0 | 442333.0 | 442333.0 | 0 |
| apply effects | 10000 | 5 | 4355199.0 | 4533497.0 | 4533497.0 | 0 |
| grant abilities | 10 | 5 | 800.0 | 871.0 | 871.0 | 50 |
| grant abilities | 100 | 5 | 9131.0 | 10101.0 | 10101.0 | 500 |
| grant abilities | 1000 | 5 | 197331.0 | 217446.0 | 217446.0 | 5000 |
| tag lookups | 10000 | 5 | 6732.0 | 7469.0 | 7469.0 | 0 |
| tag-change reevaluations | 1000 | 5 | 252535.0 | 292797.0 | 292797.0 | 0 |
| stack candidate searches | 1000 | 5 | 3806.0 | 4114.0 | 4114.0 | 0 |

## What the suite actually fails for

The two searches that used to read every effect on a character do not
grow with how many there are. Asserted rather than reported, because the
counts are the same on every machine:

- a stack search compares at most the effects sharing its definition,
  whether a hundred or ten thousand are standing;
- a tag change reevaluates only the effects whose requirements name that
  tag or an ancestor of it;
- a thousand applications and removals leave the index holding nothing.

`test/unit/test_indexed_search_performance_certification.gd::test_the_stack_search_does_not_grow_with_the_crowd`
