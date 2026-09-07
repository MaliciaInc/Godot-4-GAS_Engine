# Gate F5.5 — receipt

Package: F5.5 (F5.5.1 through F5.5.7), covering G01 and G02.
Baseline GAS_Engine: `0db4c24441184a67c1b9b606af6ce9d8ec6b917c`.
Reference: Unreal Engine 5.7.4, CL 51494982.

The phase states this gate as thirteen multi-instance cases. Three machines in
one process answer them, over a link that can be told to repeat, reorder, lose
and delay — because none of those are reachable from a suite that hands
messages straight across, and every one of them is a thing a real socket does
without being asked.

Every reference here is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F5_5.md
```

## The thirteen cases

| # | Case | At the seam | On its own |
|---|---|---|---|
| 1 | listen server + 2 clients | `test/unit/test_gate_f5_5_network_walk.gd::test_case_one_a_listen_server_owns_a_character_and_still_authors` | `test/unit/test_network_authority.gd::test_only_the_authority_authors` |
| 2 | dedicated server + 2 clients | `test/unit/test_gate_f5_5_network_walk.gd::test_case_two_a_dedicated_server_owns_nobody` | `test/unit/test_network_authority.gd::test_nobody_owning_something_is_not_peer_zero_owning_it` |
| 3 | latency | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | `test/unit/test_network_replication.gd::test_a_peer_ends_at_the_newest_reading_it_was_sent` |
| 4 | duplicate packet | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | `test/unit/test_network_authority.gd::test_the_same_message_arriving_twice_is_acted_on_once`, `test/unit/test_network_replication.gd::test_applying_the_same_reading_twice_lands_in_the_same_place` |
| 5 | reordered packet | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | `test/unit/test_network_replication.gd::test_a_peer_ends_at_the_newest_reading_it_was_sent` |
| 6 | dropped request retry | `test/unit/test_gate_f5_5_network_walk.gd::test_case_six_a_dropped_request_is_asked_again_and_answered_once` | `test/unit/test_network_authority.gd::test_a_client_asks_only_for_what_its_policy_says_it_may` |
| 7 | predicted accepted | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once` | `test/unit/test_prediction_journal.gd::test_accepting_binds_the_guess_rather_than_repeating_it` |
| 8 | predicted rejected | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_eight_and_ten_a_refused_guess_takes_its_cooldown_with_it` | `test/unit/test_prediction_journal.gd::test_a_refused_request_unwinds_what_the_client_did_on_the_strength_of_it` |
| 9 | no double cost | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once` | `test/unit/test_prediction_journal.gd::test_a_guess_is_put_back_when_it_is_refused_and_kept_when_it_is_not` |
| 10 | no duplicate cooldown | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_eight_and_ten_a_refused_guess_takes_its_cooldown_with_it` | `test/unit/test_prediction_journal.gd::test_a_refused_guess_takes_back_everything_that_stood_on_it` |
| 11 | no ghost cue | `test/unit/test_gate_f5_5_network_walk.gd::test_case_eleven_a_refused_guess_leaves_no_cue_playing` | `test/unit/test_cue_hierarchy.gd::test_a_pooled_cue_holds_nothing_from_its_last_run` |
| 12 | late join | `test/unit/test_gate_f5_5_network_walk.gd::test_case_twelve_a_late_joiner_is_caught_up_before_it_is_kept_up` | `test/unit/test_network_replication.gd::test_a_delta_before_any_snapshot_is_refused` |
| 13 | respawn / avatar swap | `test/unit/test_gate_f5_5_network_walk.gd::test_case_thirteen_a_respawn_keeps_the_grants_and_the_state` | `test/unit/test_network_replication.gd::test_swapping_the_avatar_keeps_everything_the_component_owns` |

## What the engine gained, and what each of it is for

- **Five identities, and one refusal under all of them.** An ObjectID never
  crosses the network: it is a slot in one process's object table, different on
  every machine and handed out again the moment something is freed. That failure
  does not look like a failure, so the folder is scanned for it rather than
  asked to remember.
  `test/unit/test_networking_identity.gd::test_nothing_in_the_networking_folder_reaches_for_an_object_id`
- **One runtime, and nothing else sends anything.** RPCs scattered through a
  system are a system whose network behaviour can only be read by reading all of
  it, and whose authority rules end up written slightly differently in eleven
  places.
  `test/unit/test_network_authority.gd::test_a_message_going_the_wrong_way_is_not_acted_on`
- **A client does not author.** A grant it wrote itself, an effect it applied on
  its own authority, an id it invented are the same bug wearing different
  clothes, and the bug is a player giving themselves an ability.
  `test/unit/test_network_authority.gd::test_a_client_cannot_grant`
- **The client does not re-simulate.** What arrives is the authority's answer;
  a client that ran the same effects again would reach a second answer, and the
  two would drift the moment a tick landed on a different frame.
  `test/unit/test_network_replication.gd::test_a_snapshot_carries_the_base_attributes_and_the_tag_counts`
- **A prediction key is a place in a chain.** Being told no is the easy half;
  the hard half is that more was done on top of the guess, and taking the first
  thing back without the rest leaves a character holding a cooldown for an
  ability that never fired.
  `test/unit/test_prediction_journal.gd::test_a_refused_guess_takes_back_everything_that_stood_on_it`

## Deviations

**The addon owns no transport, and this is the deliberate one.** Messages come
out of a signal and go in through a call; how they travel is the game's
business. The phase asks for multi-instance tests and what answers them is
three runtimes in one process over a link fixture that misbehaves on demand.
That is a smaller claim than two operating-system processes talking over a
socket, and it is the larger part of what those tests would be checking: the
duplicate, the reorder, the loss and the delay are all reachable here and all
deterministic, where over a real socket they are none of those things. What is
not covered is Godot's own multiplayer plumbing, which this addon does not use
and does not wrap.
`test/fixtures/net_link.gd`

**Effects replicate as readings, not as running effects.** A snapshot carries
which effect, how many, how long is left in seconds and in turns, and whether it
is inhibited - for a game to show. It does not re-apply them on the receiving
machine, because the attribute values that arrive already have those effects in
them and applying the modifiers again would count everything twice. The
authority is the one machine that simulates.
`test/unit/test_network_replication.gd::test_a_snapshot_carries_each_running_effect_and_its_readings`

**Prediction is offered for four things and refused for the rest.** Cost,
cooldown, an allowed attribute delta and a cue, because each of those can be
undone with what the operation itself remembers. A periodic tick, an arbitrary
execution calculation and a server-only side effect cannot, and the phase says
not to promise them. A one-shot cue that has already played cannot be unplayed
either, which is why a game predicts the impact spark and not the death
animation.
`test/unit/test_prediction_journal.gd::test_accepting_binds_the_guess_rather_than_repeating_it`
