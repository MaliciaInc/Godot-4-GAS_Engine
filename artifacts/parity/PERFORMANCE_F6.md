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
| apply effects | 100 | 5 | 14058.0 | 14409.0 | 14409.0 | 0 |
| apply effects | 1000 | 5 | 143394.0 | 146114.0 | 146114.0 | 0 |
| apply effects | 10000 | 5 | 1508574.0 | 1518642.0 | 1518642.0 | 0 |
| apply effects across twenty targets | 100 | 5 | 27389.0 | 27774.0 | 27774.0 | 0 |
| grant abilities | 10 | 5 | 727.0 | 844.0 | 844.0 | 50 |
| grant abilities | 100 | 5 | 7992.0 | 8266.0 | 8266.0 | 500 |
| grant abilities | 1000 | 5 | 153685.0 | 156198.0 | 156198.0 | 5000 |
| tag lookups | 10000 | 5 | 6388.0 | 6440.0 | 6440.0 | 0 |
| tag-change reevaluations | 1000 | 5 | 71055.0 | 72182.0 | 72182.0 | 0 |
| stack candidate searches | 1000 | 5 | 1789.0 | 1884.0 | 1884.0 | 0 |

## What the suite actually fails for

The work that used to read every effect, or every set, on a character
does not grow with how many there are. Asserted rather than reported,
because the counts are the same on every machine:

- a stack search compares at most the effects sharing its definition,
  whether a hundred or ten thousand are standing;
- a tag change reevaluates only the effects whose requirements name that
  tag or an ancestor of it;
- a thousand applications and removals leave the index holding nothing;
- effects coming and going never ask a set again which attributes it
  declares, and granting a tag asks only the effects whose requirements
  are about it - those two in `test/unit/test_effect_application_certification.gd`.

`test/unit/test_indexed_search_performance_certification.gd::test_the_stack_search_does_not_grow_with_the_crowd`
