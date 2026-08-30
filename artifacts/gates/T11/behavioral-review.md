Behavioral duplication findings, reviewed (criterion 24)

The duplication gate blocks on structural and masked findings, both at zero. It
reports behavioral findings without blocking, because similarity of shape is not
duplication: a test that builds a fixture, applies an effect and asserts looks
like every other test that does, and that is the point of the shape.

63 behavioral pairs. Read for real duplication rather than counted.

Dismissed
---------
Most pairs cross the production/test boundary - `_build_attribute_row` against
`test_losing_the_buff_discards_the_excess_permanently`, for instance. A row
builder and a lifecycle test share a statement skeleton and nothing else.
Collapsing them is not available and would not be wanted.

Pairs between two tests are the same story. The suite's tests deliberately share
an arrangement: create fixture, set base, apply, assert. Where three of them
genuinely were one procedure with different data they were already parameterised
with use_parameters, which is what removed them from the structural list.

Acted on
--------
Two were real.

1. `_show_dialog` existed twice, in attribute_sets_tab.gd and tag_manager_tab.gd,
   with the same body and one extra parameter. The body is not incidental: a
   hand-built AcceptDialog that is add_child()ed and never freed leaks a node
   per message, so both copies had to remember the same thing. Now
   DashboardDialogs.show_message, once.

2. `recompose` and `commit_base_write` in gameplay_attribute_runtime.gd matched
   at 0.935. They are NOT one function: one writes current from an evaluation,
   the other writes base from a staged mutation with its own finiteness guard
   and clamp bookkeeping. Merging them behind a flag would be worse than the
   repetition. But four lines of "record what the mutation started from" were
   verbatim in both, and a new field on the result would need remembering twice.
   Extracted as _snapshot(); the arithmetic is untouched, which the 19001
   asserts confirm.

The count went 64 -> 63. That is the honest number: fixing a real pair removes
one, and the rest were never duplication.
