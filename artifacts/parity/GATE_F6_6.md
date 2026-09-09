# Gate F6.6 — receipt

Package: F6.6 (F6.6.1 through F6.6.8), covering D-01, D-04, D-05 and G-08.
Baseline GAS_Engine: `f4fce1da80f35004b9f32a7a463c62a8f8cd2df6`.
Reference: Unreal Engine 5.7.4, CL 51494982 — not verified against a running
copy, for the reason F6.5.3 records.

F6.6 gave this addon a transport. Everything before it stopped at the seam:
messages left through a signal, arrived through a call, and a project carried
them over its own connection. What this gate is about is that the carrying now
happens here, and that it happens the same way whether a fixture or Godot's own
`SceneMultiplayer` is underneath.

```powershell
pwsh -File tooling/verify.ps1 -TaskId F6.6
pwsh -File tooling/run_multiplayer_sample.ps1
```

Every reference here is checked against the repository:

```text
python tooling/parity_receipt.py artifacts/parity/GATE_F6_6.md
```

## Findings

| Finding | Status | Evidence |
|---|---|---|
| D-01 the README's networking section described an engine this is not | CLOSED | `test/unit/test_readme_quick_start.gd::test_the_readme_describes_the_final_network_contract` |
| D-04 nothing said which machine an ability runs on | CLOSED | `test/unit/test_network_ability_policies.gd::test_the_execution_policy_does_not_decide_what_the_authority_accepts` |
| D-05 an authority that accepted a request did nothing about it | CLOSED | `test/unit/test_gate_f6_6_real_transport.gd::test_cases_seven_and_nine_an_accepted_guess_is_answered` |
| G-08 replication, security and input policies per ability | CLOSED | `test/unit/test_network_ability_policies.gd::test_a_remote_request_is_asked_of_the_security_policy` |
| G-17 wire, transport, per-entity mode, batching, target and event messages | CLOSED | `test/unit/test_gate_f6_6_real_transport.gd::test_a_message_crosses_as_bytes_and_arrives_whole` |

D-04 and D-05 were closed by F6.0.5 and F6.0.6 and are named again here because
F6.6 is where they became answerable across two machines rather than within one.

## NetLink against the real transport, case by case

The F5.5 walk runs over `NetLink`, which can be told to repeat, reorder, lose
and delay — none of which a socket will do on request. The same outcomes are
checked again over `GameplayNetTransportMultiplayer`, real `SceneMultiplayer`
instances and a `MultiplayerPeer` that is a dictionary rather than a port. Both
carry bytes: `NetLink` encodes and decodes every message it hands over, so the
two columns differ in the transport and in nothing else.

| # | Case | Over NetLink | Over GameplayNetTransportMultiplayer |
|---|---|---|---|
| 0 | the wire carries bytes | `test/unit/test_gate_f5_5_network_walk.gd::test_case_zero_the_wire_carries_bytes_and_nothing_else` | `test/unit/test_gate_f6_6_real_transport.gd::test_a_message_crosses_as_bytes_and_arrives_whole` |
| 1 | listen server + 2 clients | `test/unit/test_gate_f5_5_network_walk.gd::test_case_one_a_listen_server_owns_a_character_and_still_authors` | `test/unit/test_gate_f6_6_real_transport.gd::test_case_one_a_grant_from_the_authority_reaches_both_clients` |
| 2 | a client does not author | `test/unit/test_gate_f5_5_network_walk.gd::test_case_two_a_dedicated_server_owns_nobody` | `test/unit/test_gate_f6_6_real_transport.gd::test_case_two_a_grant_a_client_invented_is_refused` |
| 3 | latency | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | NetLink only — see below |
| 4 | duplicate packet | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | NetLink only — see below |
| 5 | reordered packet | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading` | NetLink only — see below |
| 6 | dropped request retry | `test/unit/test_gate_f5_5_network_walk.gd::test_case_six_a_dropped_request_is_asked_again_and_answered_once` | NetLink only — see below |
| 7 | predicted accepted | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once` | `test/unit/test_gate_f6_6_real_transport.gd::test_cases_seven_and_nine_an_accepted_guess_is_answered` |
| 8 | predicted rejected | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_eight_and_ten_a_refused_guess_takes_its_cooldown_with_it` | `test/unit/test_gate_f6_6_real_transport.gd::test_cases_eight_and_ten_a_refused_guess_is_answered_no` |
| 9 | no double cost | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once` | `test/unit/test_gate_f6_6_real_transport.gd::test_cases_seven_and_nine_an_accepted_guess_is_answered` |
| 10 | no duplicate cooldown | `test/unit/test_gate_f5_5_network_walk.gd::test_cases_eight_and_ten_a_refused_guess_takes_its_cooldown_with_it` | `test/unit/test_gate_f6_6_real_transport.gd::test_cases_eight_and_ten_a_refused_guess_is_answered_no` |
| 11 | no ghost cue | `test/unit/test_gate_f5_5_network_walk.gd::test_case_eleven_a_refused_guess_leaves_no_cue_playing` | NetLink only — see below |
| 12 | late join | `test/unit/test_gate_f5_5_network_walk.gd::test_case_twelve_a_late_joiner_is_caught_up_before_it_is_kept_up` | `test/unit/test_gate_f6_6_real_transport.gd::test_case_twelve_a_late_joiner_is_caught_up_with_a_snapshot` |
| 13 | respawn / avatar swap | `test/unit/test_gate_f5_5_network_walk.gd::test_case_thirteen_a_respawn_keeps_the_grants_and_the_state` | NetLink only — see below |

### Why five cases are NetLink only, and what covers them instead

Cases 3 to 6 are a wire misbehaving. A transport whose job is to deliver has no
way to be asked to repeat, reorder, lose or delay, so reproducing them over
`SceneMultiplayer` would mean writing the misbehaviour into the fixture peer —
at which point the misbehaviour under test is the fixture's rather than a
socket's, and NetLink already is that fixture. The rules those cases check are
the receiving runtime's and are the same code on both paths: one arrival table,
one sequence check, one refusal.

Cases 11 and 13 need a cue manager autoload and an avatar swap, which are about
the ability system rather than about the transport. Running them a second time
would run the same code with a different byte carrier under it.

What does cover the real socket is `tooling/run_multiplayer_sample.ps1`: two
operating-system processes with ENet between them, running the fourteen-step
scenario in `test/integration/test_network_two_processes.gd`. That is one
scenario rather than a matrix, and this receipt says so rather than implying
otherwise.

## What the two-process run found

Three defects, none of which any in-process test could see. They are listed
because the gate's value is exactly this:

- **JSON has one number type.** Every integer written to the wire comes back a
  float, and every reader comparing `typeof(value)` against `TYPE_INT` refused
  every message that had actually crossed. Gameplay events and aims both. Fixed
  in `addons/GAS_Engine/networking/gameplay_wire_reader.gd::is_a`, and both wire
  suites now round-trip through a real `JSON.stringify` rather than handing the
  dictionary back.
- **JSON has no vectors.** `JSON.stringify` writes a `Vector3` as the text
  `(3, 0, 0)` and the far side reads a String, so no aim with a position in it
  ever reached an authority. Positions now cross as the numbers they are made
  of — `addons/GAS_Engine/networking/gameplay_target_data_translator.gd`.
- **An accepted request was answered and then nothing happened.** The runtime
  answers; it does not activate, because what activating means belongs to the
  game. `GameplayNetworkRuntime.activation_requested` is the announcement the
  authority was missing.

And one more the real-transport suite found on its own: **a state reading
computed for one peer was broadcast to every peer.** Under `MIXED` the owner is
told the running effects and nobody else is, and under F6.6.5 only the owner is
told which of its abilities are running — so the filtering was there and the
sending ignored it. A message now carries who it is for:
`addons/GAS_Engine/networking/gameplay_network_runtime.gd::_recipients`.

## What the package added

| Task | What | Where |
|---|---|---|
| F6.6.1 | bytes on a wire, and a codec that refuses what it cannot read | `addons/GAS_Engine/networking/gameplay_net_codec.gd::decode` |
| F6.6.2 | the transport seam and Godot's own implementation of it | `addons/GAS_Engine/networking/transport/gameplay_net_transport_multiplayer.gd::bind` |
| F6.6.3 | the five things a client may ask for beyond a request | `addons/GAS_Engine/networking/gameplay_net_request_runtime.gd::honour_target_data` |
| F6.6.4 | several messages that arrive together, or not at all | `addons/GAS_Engine/networking/gameplay_net_batch_runtime.gd::honour` |
| F6.6.5 | what an ability accepts from somebody else, which is not where it runs | `addons/GAS_Engine/networking/gameplay_net_authority.gd::accepts_remote_start` |
| F6.6.6 | the boundary a refusal unwinds, and two more receipts | `addons/GAS_Engine/networking/gameplay_prediction_journal.gd::open_window` |
| F6.6.7 | the sample as two processes | `examples/action_sample/network/server_main.gd::_on_request_accepted` |
| F6.6.8 | the README as a final state | `test/unit/test_readme_quick_start.gd::test_the_readme_describes_the_final_network_contract` |

## Suites

```text
test/unit/test_networking_identity.gd
test/unit/test_network_codec.gd
test/unit/test_network_transport.gd
test/unit/test_network_replication.gd
test/unit/test_network_entity_replication.gd
test/unit/test_network_authority.gd
test/unit/test_network_authority_requests.gd
test/unit/test_network_ability_policies.gd
test/unit/test_network_activation_replication.gd
test/unit/test_network_batching.gd
test/unit/test_network_sync_point.gd
test/unit/test_prediction_journal.gd
test/unit/test_prediction_window.gd
test/unit/test_gameplay_cue_effects.gd
test/unit/test_gate_f5_5_network_walk.gd
test/unit/test_gate_f6_6_real_transport.gd
test/integration/test_network_two_processes.gd
```
