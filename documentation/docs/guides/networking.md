---
title: Networking
sidebar_position: 11
description: The network runtime, transports, entities and definitions, ability network policies, prediction and rollback, aiming over the wire, and replication modes.
---

# Networking

GAS_Engine's networking is one object per process: a `GameplayNetworkRuntime`. It decides what may be sent and what may be acted on, turns ability system state into messages, and applies what arrives. It does not choose how bytes travel.

- The **authority** is the one machine that simulates. It grants abilities, answers requests and sends state.
- A **client** asks, may predict, and applies the authority's readings. It never re-runs effects to reach its own answer.

A single-player game needs none of this: a component with no network runtime behaves exactly as described everywhere else in these guides.

## Setting up a runtime

```gdscript
var network: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
network.role = GameplayNetAuthority.Role.AUTHORITY   # or CLIENT

var transport: GameplayNetTransportMultiplayer = GameplayNetTransportMultiplayer.new()
var api: SceneMultiplayer = get_tree().get_multiplayer() as SceneMultiplayer
transport.bind(api)
network.set_transport(transport)
network.peer = api.get_unique_id()
```

| Transport | Use |
|---|---|
| `GameplayNetTransportMultiplayer` | Godot's `SceneMultiplayer`, over raw packets rather than RPCs. Object decoding is never enabled. |
| Your own `GameplayNetTransport` subclass | Any other socket layer: override `send()`, `local_peer()`, `peers()` and `is_connected_to_network()`, and emit `packet_received(packet, from_peer)`. |
| None | Carry messages yourself: send what `message_ready(message)` emits and hand what arrives to `receive(message)`. |

## Entities and definitions

Both machines must agree on **which character** and **which ability** a message is about.

```gdscript
const HERO: int = 1

network.attach(hero.asc, GameplayNetEntityId.of(HERO), owner_peer)
for spec: GameplayAbilitySpec in hero.asc.get_ability_specs():
	network.registry.register_definition(spec.definition.ability_scene)
```

- `attach(asc, id, owner_peer)` puts a component on the network under an id, owned by a peer. Both processes attach the same character under the same id and owner.
- `registry.register_definition(scene)` names an ability scene. Definitions are identified by the scene's resource path, so a scene built in code needs a path (`take_over_path()`), and both processes must register the same ones.
- `detach(asc)` takes an entity off; `dispose()` releases everything.

A message about an entity or a definition the receiver does not know is refused.

## Ability network policies

Four fields on `GameplayAbility`, frozen at grant, describe an ability on a network:

**`net_execution_policy`** - where it runs, and what a client does when starting it:

| Policy | A client starting it | `network.start()` answers |
|---|---|---|
| `LOCAL_ONLY` | Runs it locally; nobody else is involved. The default. | `RUN_NOW` |
| `LOCAL_PREDICTED` | Runs it now and asks; a refusal is rolled back. | `PREDICT_AND_ASK` |
| `SERVER_INITIATED` | Asks and waits; nothing happens until the answer. | `ASK_AND_WAIT` |
| `SERVER_ONLY` | May not start it. | `REFUSED` |

On the authority every policy answers `RUN_NOW`.

**`net_security_policy`** - what the authority accepts from a remote machine:

| Policy | A remote request to start | A remote request to end |
|---|---|---|
| `CLIENT_OR_SERVER` | Accepted | Accepted |
| `SERVER_ONLY_EXECUTION` | Refused | Accepted |
| `SERVER_ONLY_TERMINATION` | Accepted | Refused |
| `SERVER_ONLY` | Refused | Refused |

**`replication_policy`** - `REPLICATE_YES` tells the owning peer while an activation is running (`activation_replicated`), for a cast bar or a visible stance. `REPLICATE_NO` is the default.

| Also | Meaning |
|---|---|
| `server_respects_remote_cancellation` | Whether the authority honours a remote cancel. Off by default, so a client cannot cancel after the authority committed the cost. |
| `replicate_input_directly` | Send the input's press and release rather than an activation - for charge and hold abilities. |

## Granting over the network

Only the authority grants. When a client connects, the authority attaches its entity, grants each definition, and sends one whole snapshot before any delta:

```gdscript
func _on_peer_connected(peer_id: int) -> void:
	var entity: GameplayNetEntityId = GameplayNetEntityId.of(HERO)
	network.attach(hero.asc, entity, peer_id)
	for spec: GameplayAbilitySpec in hero.asc.get_ability_specs():
		network.grant(entity, spec.definition.ability_scene)
	network.snapshot_for(entity, peer_id)
```

The client hears `ability_granted_by_authority(entity, definition)`; `revoke()` and `ability_revoked_by_authority` take a grant back. `GameplayAbilitySet.grant()` on a networked client is refused with a warning.

## Starting an ability

**On a client:**

```gdscript
var decided: GameplayNetAuthority.Start = network.start(hero.asc, strike_scene)
if decided == GameplayNetAuthority.Start.RUN_NOW or decided == GameplayNetAuthority.Start.PREDICT_AND_ASK:
	hero.asc.try_activate_ability_handle(strike_handle, context)
```

`start()` sends the request when the policy asks for one. The answer arrives as `activation_answered(key, activation, accepted)`.

**On the authority**, an accepted request is announced rather than performed, because what activating means - which grant, aimed at what - is your game's decision:

```gdscript
network.activation_requested.connect(_on_request_accepted)


func _on_request_accepted(
	_entity: GameplayNetEntityId, definition: Resource, _key: GameplayPredictionKey, activation: GameplayNetActivationId
) -> void:
	if definition == strike_scene:
		hero.asc.try_activate_ability_handle(strike_handle, context_for_strike())
```

## Prediction and rollback

A predicting client does things before it is allowed to. The `journal` records them under the prediction key of the guess, so a refusal can unwind everything that guess caused, newest first:

```gdscript
network.journal.record(GameplayPredictionOperation.cost(null, &"mana", 12.0))
```

What can be predicted and undone is closed, one `GameplayPredictionOperation.Kind` each: a cost, a cooldown, an attribute change, a cue, a tag with its counts on either side, and an animation with the claim it took on its surface. Periodic ticks, execution calculations, custom costs whose `prediction_kind()` is `NONE`, and anything the client cannot observe are not predicted.

## Aiming over the network

An ability that aims interactively is aimed on the client and checked on the authority:

1. The client asks with `start()` and, when accepted, aims locally.
2. The authority, on `activation_requested`, starts the same ability and claims its provider for that run: `provider.claim(activation)`.
3. The client sends where it aimed: `send_target_data(entity, data, activation, key)`.
4. The authority checks the claim with the provider's `validate_authoritative(data, source_asc)` and refuses a target that is unknown, out of reach, impossible, or addressed to a run nobody is aiming for.

See [Writing a provider](targeting.md#writing-a-provider).

## Other client requests

| Method | Sends |
|---|---|
| `send_generic_confirm(entity)` / `send_generic_cancel(entity)` | A confirm or cancel for the entity's abilities. |
| `send_gameplay_event(entity, event)` | A gameplay event to the authority's copy of the entity. |
| `send_input(entity, definition, input_id, pressed)` | A press or release, for `replicate_input_directly`. |
| `release(asc, definition)` | Letting go of an input-driven ability. |

## State

| Method | Sends |
|---|---|
| `snapshot_for(entity, peer)` | Everything about an entity that peer may be told. Send one first. |
| `delta_for(entity, peer)` | What changed since that peer was last told, or nothing. Call it at a steady rate. |

A client applies readings in order and emits `state_applied(entity, state)`. Attributes arrive as values and tags as counts; effects arrive as readings - which effect, how many stacks, how long left - for your UI to show.

`replication_mode` decides how much each peer is told:

| Mode | Effects are told to | Everyone else gets |
|---|---|---|
| `FULL` | Everybody. For co-op, where every player sees every buff. | - |
| `MIXED` | The owning peer only. The default. | Attributes, tags and cues. |
| `MINIMAL` | Nobody. | Attributes, tags and cues. |

Cue bindings choose separately whether a cue is sent: `REPLICATED` or `LOCAL_ONLY`. A dedicated server can set `suppress_cues` on its components and still send cues to clients.

## Batching and refusals

Wrap several messages that must arrive together in `begin_batch()` and `end_batch()`; call `flush_deferred_batch()` from wherever you tick the network.

Every message that is not acted on is reported through `message_refused(message, reason)`. The reasons include `wrong_direction`, `unknown_entity`, `unknown_definition`, `not_owned`, `policy_refuses`, `already_applied`, `out_of_order`, `peer_mismatch`, `target_unknown`, `target_unreachable`, `target_invalid` and `activation_unknown`. Log them: a refusal otherwise looks exactly like a lost packet.

## Next

The [Multiplayer across two processes](../tutorials/multiplayer-across-two-processes.md) tutorial walks through a complete authority and client built from the action sample.
