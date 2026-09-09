# Gate F6.4 — receipt

Package: F6.4 (F6.4.1 through F6.4.7), authoring, editor and runtime debug.
Baseline: `bfc13dd` — the tree F6.3 closed on.
Reference: Unreal Engine Gameplay Ability System 5.7.4, CL 51494982.

Every reference below is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_4.md
```

## What this package closed

| Finding | State | Evidence |
|---|---|---|
| G-19 a modifier row is one authoring action, not four | CLOSED | `test/unit/test_gameplay_effect_editor.gd::test_adding_a_modifier_builds_the_whole_chain` |
| G-19 the editor holds no second copy of the effect | CLOSED | `test/unit/test_gameplay_effect_editor.gd::test_opening_and_saving_without_editing_changes_nothing` |
| G-19 a component the runtime reads once cannot be added twice | CLOSED | `test/unit/test_gameplay_effect_editor.gd::test_a_component_the_runtime_reads_once_cannot_be_added_twice` |
| G-19 the editor reports what the engine would refuse | CLOSED | `test/unit/test_gameplay_effect_editor.gd::test_the_editor_reports_what_the_engine_would_refuse` |
| G-19 an attribute is chosen from what the project declares | CLOSED | `test/unit/test_gameplay_attribute_inspector.gd::test_the_catalogue_finds_the_attributes_the_project_declares` |
| G-19 a misspelled attribute is caught before runtime | CLOSED | `test/unit/test_gameplay_attribute_inspector.gd::test_a_misspelled_attribute_is_caught_before_runtime` |
| G-19 and reported by the validator, not only by a row somebody opens | CLOSED | `test/unit/test_gameplay_asset_validator.gd::test_a_modifier_naming_an_attribute_nobody_declares_is_reported` |
| G-19 either way a modifier names its attribute | CLOSED | `test/unit/test_gameplay_asset_validator.gd::test_a_typed_reference_is_checked_the_same_way` |
| G-14 an old tag name still resolves | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_a_chain_of_renames_resolves_to_the_last_name` |
| G-14 a cycle answers with the tag as it arrived | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_a_chain_that_leads_into_a_cycle_still_answers_with_what_arrived` |
| G-14 a chain past sixty-four is not followed | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_a_chain_past_the_limit_is_not_followed` |
| G-14 the author is told once per run, not once per frame | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_a_rename_is_mentioned_once_and_then_again_after_forgetting` |
| G-14 nothing is rewritten by resolving | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_resolving_a_rename_never_rewrites_the_tags_file` |
| G-14 a rename is in force where it matters | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_an_old_name_grants_the_tag_the_project_has_now` |
| G-14 redirects, restricted prefixes and comments survive a tag being added | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_adding_a_tag_keeps_what_the_file_already_declared` |
| G-14 a branch somebody else owns names its owner | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_the_registry_refuses_a_tag_in_somebody_else_s_branch` |
| G-14 the nearest owner answers | CLOSED | `test/unit/test_gameplay_tag_redirects.gd::test_the_owner_of_a_branch_is_the_nearest_one` |
| G-14 a tag's comment shows on its own row in the picker | CLOSED | `test/unit/test_gameplay_tag_tree.gd::test_a_leaf_shows_what_its_tag_is_for` |
| G-14 ALL/ANY/NONE nested means what the nesting says | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_a_query_built_by_editing_means_what_the_nesting_says` |
| G-14 the editor draws the nesting the runtime evaluates | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_the_rows_are_the_nesting_the_runtime_evaluates` |
| G-14 a leaf knows which expression its picker is picking for | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_a_tag_row_carries_the_expression_it_belongs_to` |
| G-14 a corrupted query is drawn once rather than followed | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_a_cycle_is_drawn_once_rather_than_followed` |
| G-14 a node with no ability system can still have tags | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_a_node_with_no_ability_system_answers_for_itself` |
| G-14 both sources of a node's tags count | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_both_sources_of_tags_count` |
| G-14 a target filter sees a node that answers for itself | CLOSED | `test/unit/test_gameplay_tag_query_editor.gd::test_a_target_filter_sees_a_node_that_answers_for_itself` |
| G-18 a debug surface the running game draws | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_the_overlay_watches_an_entity_and_draws_its_pages` |
| G-18 four pages, each a transformation with no screen | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_every_page_says_what_it_would_draw_without_a_screen` |
| G-18 an effect applied but not in force says so | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_the_effects_page_says_which_effect_is_not_in_force` |
| G-18 a grant carries its cooldown and its last result | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_a_snapshot_carries_a_grant_s_cooldown_and_last_result` |
| G-18 a tag held only through its children is not held | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_the_tags_page_tells_a_family_apart_from_a_tag_that_is_held` |
| G-18 attribute history is bounded at a hundred and twenty-eight | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_the_history_keeps_the_last_hundred_and_twenty_eight` |
| G-18 and records what the component announces | CLOSED | `test/unit/test_gas_debug_overlay.gd::test_the_history_records_what_the_component_announces` |
| G-20 the two ignores exist in debug builds and nowhere else | CLOSED | `test/unit/test_gas_debug_commands.gd::test_a_debug_switch_does_nothing_in_a_release_build` |
| G-20 ignoring costs neither adds resources nor takes them | CLOSED | `test/unit/test_gas_debug_commands.gd::test_ignoring_costs_neither_adds_resources_nor_takes_them` |
| G-20 nor takes an authored cost effect | CLOSED | `test/unit/test_gas_debug_commands.gd::test_ignoring_costs_does_not_take_an_authored_cost_effect` |
| G-20 ignoring cooldowns clears nothing already running | CLOSED | `test/unit/test_gas_debug_commands.gd::test_ignoring_cooldowns_clears_nothing_that_is_already_running` |
| G-20 and starts none while it is on | CLOSED | `test/unit/test_gas_debug_commands.gd::test_ignoring_cooldowns_starts_no_new_cooldown` |
| G-20 suppression is asked process-wide beside the component's own | CLOSED | `test/unit/test_gas_debug_commands.gd::test_the_process_wide_suppression_is_asked_beside_the_component_s_own` |
| G-20 a refusal is reported with its failure tag | CLOSED | `test/unit/test_gas_debug_commands.gd::test_activate_starts_an_ability_and_reports_a_refusal_with_its_tag` |
| G-20 the console prints what the overlay draws | CLOSED | `test/unit/test_gas_debug_commands.gd::test_the_console_shows_what_the_overlay_would_draw` |
| G-22 the sample demonstrates all seven things | CLOSED | `test/unit/test_action_sample_probe.gd::test_the_sample_demonstrates_everything_it_claims_to` |
| G-22 the probe is deterministic | CLOSED | `test/unit/test_action_sample_probe.gd::test_the_probe_answers_the_same_way_every_time` |
| G-22 the sample carries no copy of the runtime | CLOSED | `test/unit/test_action_sample_probe.gd::test_the_sample_carries_no_copy_of_the_runtime` |
| G-22 the scene that ships is the one that is checked | CLOSED | `test/unit/test_action_sample_probe.gd::test_the_scene_that_ships_is_the_one_that_is_checked` |

G-19's third owner in the traceability is F6.4.3's query editor, which is listed
under G-14 above because that is where the phase document puts the tag work.
G-18's overlay and G-20's commands are both here; F6.6 owns nothing of either.

## The walk

`test/unit/test_gate_f6_4_authoring_walk.gd::test_the_whole_authoring_contract_walks_from_an_empty_effect_to_an_aimed_area`

One authoring session end to end: an effect authored in one action, its
attribute chosen from what the project declares - and the misspelling of it
reported before anything runs - a query nested as `(stunned or immune) and not
immune`, a tag renamed without touching the asset that named it, the effect
applied through the gate the author nested, four overlay pages read with no
editor anywhere, and the sample's own area effect aimed and landed.

## Three decisions this package made that the document left open

- **The two snapshot classes became one.** The document asks for
  `debug/gas_runtime_snapshot.gd`, and there was already an
  `editor/debugger/gas_runtime_snapshot.gd` rebuilding one from a wire message.
  Adding the second would have been the same four inner types spelled twice,
  which disagree the first time one of them learns about a field the other has
  not got. There is one, under `debug/` where a running game may name it, with a
  way in from each side: `of()` from a live component and `from_message()` from
  the wire.
- **The sample's standalone project file is not called `project.godot`.** Godot
  skips any directory containing a file by that name, so the sample would stop
  being compiled, stop registering its classes, and stop being checked by the
  engine's own suite - which is the one thing keeping it from going stale. It
  ships as `project.godot.standalone`, the README says to rename it on the way
  out, and a test fails if a live one ever appears.
- **There are seven numbers in the friction receipt for six frictions.** The
  target for the modifier row is "one editor action", and the number F6.0.9 took
  counts Resources - four Resources built by four clicks and four built by one
  are the same four Resources. The count of authoring actions is measured too,
  by driving the editor's document and then checking that what came back is a
  complete row. `modifier_plus_ten_resources` is still four, deliberately: that
  is the engine's model, and collapsing it would take away the magnitude kinds
  an author picks between.

## Four gaps found on the way and closed here

- **The tags file lost its own declarations whenever a tag was added.** The
  generator renders the whole file from the tag list, so adding one tag would
  have deleted every redirect, owned branch and comment in the project - work
  nobody asked to lose, removed by an unrelated action, in a file nobody thinks
  of as theirs to check. It reads them back and writes them again.
  `test/unit/test_gameplay_tag_redirects.gd::test_adding_a_tag_keeps_what_the_file_already_declared`
- **The cue manager had no public way to bind a tag.** Loading a registry file
  was the only path, so a game that builds its cues - a mod, a tool, this
  sample - had to reach into the pool the manager keeps privately, which is what
  six test files were already doing. `bind_cue`/`unbind_cue` are what
  `_load_registry()` already did, said out loud, and unbinding frees what was
  pooled under the tag rather than leaving those nodes parented to the manager
  answering to a tag nothing resolves.
  `test/unit/test_action_sample_probe.gd::test_the_sample_binds_its_cues_and_gives_them_back`
- **An ability could not read what it was aimed at.** The doors in were a task
  that waits and a provider that confirms, both for an aim with a middle; a hit
  that lands on the frame it was pressed has no middle and was reduced to
  finding its own target in a world the caller had already decided about.
  `get_activation_target_data()` is the other half of `get_activation_event()`.
  `test/unit/test_action_sample_probe.gd::test_the_sample_demonstrates_everything_it_claims_to`
- **`RESTRICTED` would have been a declaration nothing read.** The phase names
  the map without saying who enforces it. A prefix somebody else owns is refused
  at the one door tags are added through, with the owner named, rather than
  added and then redefined out from under the project at their next update.
  `test/unit/test_gameplay_tag_redirects.gd::test_the_registry_refuses_a_tag_in_somebody_else_s_branch`

## What the quality gates said

| Gate | Result |
|---|---|
| GUT suite | `passed=64689 failed=0 pending=0 orphans=0` |
| loc | PASS |
| duplication | PASS |
| magic-string | PASS |
| test-location | PASS |
| gate self-tests | 192 passed |
| project invariants | `project.godot is sound` |
| product identity | `GAS_Engine identity is canonical` |
| policy seal | verified |
| godot import | PASS |

Three ceilings moved, each with the reason written beside it in
`tooling/.quality-gates.json`: `gameplay_ability.gd` twice - once for the two QA
switches read where a commit would take something, once for the accessor that
lets an ability read what it was aimed at - and the cue manager's first ceiling,
for the public binding door. Two duplication pairs were folded rather than
allowlisted: the attribute picker and the query editor now share
`GASResourceInspectorPlugin`, and every popup in the addon opens through
`GASEditorPopup`. Two rules were declared: the debug channel's four projectors
are one codec into the wire message, on the same terms the networking
translators already are, and `off` is a word the gates' own CLI and the QA
console each own in their own language.

## The frictions this package closed

F6.0.9 measured six. Three of them were still open when this package started,
and all three are closed here: a misspelled attribute is visible before runtime,
a debug surface works outside the editor, and a modifier row takes one authoring
action rather than four. F6.4.7 writes a verdict against every target the phase
set, derived from the measurement rather than from anybody's reading of it.

`test/unit/test_authoring_friction.gd::test_every_target_the_phase_set_has_the_verdict_the_measurement_gives`
