---
title: Ability Tasks
sidebar_position: 6
description: Awaitable, cancellable steps inside an ability - delays, input, events, attributes, tags, effects, animation, movement, spawning - and writing your own.
---

# Ability Tasks

A **task** is one awaitable step inside an ability: wait half a second, wait for the button to be released, wait for health to drop below 30%, play an animation.

A bare `await` on a timer or a signal is owned by nothing: if the ability is cancelled, the wait keeps running and the ability resumes later into a fight that has moved on. A task is owned by its ability's component and is cancelled with the ability, however the ability ends.

## Using a task

```gdscript
func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	var windup: AbilityTaskWaitDelay = wait_delay(0.4)
	await windup.completed()
	if windup.state != GameplayAbilityTask.State.SUCCEEDED:
		return false

	# … land the hit
	return true
```

Three rules cover almost every use:

1. **Await `completed()`, not `finished`.** Some tasks end while they start - a threshold already crossed, an animation that does not exist. Awaiting `finished` then waits for a signal that has already fired, and the ability never resumes. `completed()` returns at once for a task that already ended.
2. **Check `state` after the await.** A task ends as `SUCCEEDED` or `CANCELLED`, and a cancelled wait means the ability is ending.
3. **Read the task's result fields** after it succeeds - `target_data`, `matched_event`, `outcome`.

| Member | Meaning |
|---|---|
| `state` | `CREATED`, `RUNNING`, `SUCCEEDED` or `CANCELLED`. One way only. |
| `finished(task, succeeded, reason)` | Emitted exactly once, on success and on cancellation. |
| `completed()` | Wait for the end, whether or not it already happened. |
| `is_finished()` | Whether it ended. |
| `instance_name` | A name other code can end the task by. |

When a task is cancelled, `reason` says why:

| `CancelReason` | Cause |
|---|---|
| `ABILITY_ENDED` | The ability ended normally. |
| `ABILITY_ABORTED` | `abort_ability()`, `cancel_all_abilities()`, or `cancel_task()`. |
| `ABILITY_REMOVED` | The grant was removed. |
| `ASC_CLEANUP` | The component was cleaned up or freed. |
| `CANCEL_TAG` | A cancel query, a cancelling effect, or a passive's requirements stopping. |
| `MANUAL` | Cancelled directly with `cancel(MANUAL)`. |

Tasks run on the component's `_process` clock - the same clock as effect durations - so pausing the scene tree pauses them.

## Tasks on the ability

These are methods on `GameplayAbility`:

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_delay(seconds)` | The time has passed. | - |
| `wait_input_pressed(slot = -1)` / `wait_input_released(slot = -1)` | The slot is pressed or released. `-1` means the ability's own input: its slot, and its action when the grant is bound to one. | - |
| `wait_gameplay_event(tag)` | An event under `tag` reaches the owner. | `matched_event` |
| `wait_gameplay_events(tag, only_match_exact, from_asc)` | Never on its own: emits `event_received(event)` for every match until the ability ends. | - |
| `wait_target_data()` | Target data is submitted to this ability. | `target_data` |
| `wait_overlap(area, filter)` | Something passing `filter` enters an `Area2D` or `Area3D` the game placed. | `overlapped_node` |
| `wait_velocity_change(direction, min_magnitude)` | The avatar moves at least that fast, along `direction` when it is not zero. | `reached` |
| `wait_effect_applied_to_target(query)` | The owner lands a matching effect on another component. | `matched_target`, `matched_spec` |
| `start_ability_state(state_name)` | Something ends the state by name. Emits `state_ended(state_name, was_cancelled)`. | - |

Related calls:

| Method | Purpose |
|---|---|
| `submit_target_data(data)` | Hand target data to this ability's `wait_target_data()`. |
| `aim_with(provider)` | Start an interactive targeting provider; what it confirms is submitted as target data. See [Targeting](../targeting.md#providers-interactive-aiming). |
| `end_ability_state(name)` / `cancel_ability_state(name)` | End or cancel every state of that name. Returns how many. |
| `end_task(name)` / `cancel_task(name)` | The same for any task with that `instance_name`. |

Named states let something outside the task end it: an animation method track can end a wind-up without holding the task.

## The task factory

`AbilityTaskFactory` builds every other task. Each method takes the ability first, registers the task and starts it. Methods that take a `target_asc` watch the owner when it is `null`.

### Attributes

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_attribute_change(ability, attribute, target_asc)` | The attribute's current value changes. | `old_value`, `new_value`, `source_spec` |
| `wait_attribute_threshold(ability, attribute, threshold, comparison, trigger_immediately_if_already_true)` | The value compares against `threshold`: `LESS`, `LESS_OR_EQUAL`, `GREATER`, `GREATER_OR_EQUAL` or `EQUAL_APPROX`. | `matched_value` |
| `wait_attribute_ratio_threshold(ability, of_attribute, over_attribute, ratio, direction)` | `of / over` is `AT_OR_BELOW` or `AT_OR_ABOVE` `ratio` - health under 30% of max health. | `crossed_at` |

### Tags

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_tag_added(ability, tag, target_asc)` | The tag is gained. | `matched_tag` |
| `wait_tag_removed(ability, tag, target_asc)` | The tag is lost. | - |
| `wait_tag_query(ability, query, desired, target_asc)` | The query's result becomes `desired`. | - |
| `wait_tag_count_change(ability, tag, target_asc)` | The tag's count changes. | `old_count`, `new_count` |

### Effects

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_gameplay_effect_applied(ability, query, target_asc, include_periodic, trigger_once)` | A matching effect is applied. With `trigger_once` off it keeps emitting `matched(result)`. | `last_result` |
| `wait_gameplay_effect_removed(ability, handle, target_asc)` | That effect is removed. | `matched_active_effect`, `removal_reason` |
| `wait_gameplay_effect_removed_matching(ability, query, target_asc)` | A matching effect is removed. | `matched_active_effect`, `removal_reason` |
| `wait_gameplay_effect_stack_change(ability, handle, target_asc)` | That effect's stack count changes. | `old_count`, `new_count` |
| `wait_effect_blocked_by_immunity(ability, target_asc)` | An application is refused by immunity. | `blocked` |

### Abilities

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_ability_activated(ability, handle, target_asc)` | That grant activates. | `matched_handle`, `matched_instance` |
| `wait_ability_activated_matching(ability, query, target_asc)` | An ability with matching tags activates. | `matched_handle`, `matched_instance` |
| `wait_ability_ended(ability, handle, target_asc)` | That grant's activation ends. | `matched_handle`, `was_cancelled`, `end_reason` |
| `wait_ability_ended_matching(ability, query, target_asc)` | An ability with matching tags ends. | `matched_handle`, `was_cancelled`, `end_reason` |
| `wait_ability_commit(ability, handle, target_asc)` | That grant - or any, when `handle` is `null` - pays for itself. A refused commit does not wake it. | `result`, `committed_handle` |

### Input and flow

| Method | Succeeds when | Read after |
|---|---|---|
| `wait_confirm_cancel(ability, confirm_input_id, cancel_input_id)` | Either slot is pressed, or a generic confirm or cancel is said. Pass `-1` for both to answer only the generic ones. | `decision`: `CONFIRMED` or `CANCELLED` |
| `repeat(ability, interval_seconds, repetitions)` | After `repetitions` intervals; `0` repeats until the ability ends. Emits `repeated(index)` each interval. | `completed_count` |
| `wait_state(ability, until, give_up_after)` | The `until` callable returns `true`, asked every frame. After `give_up_after` seconds (`0` waits forever) the task is cancelled instead, with `timed_out` set. | `timed_out` |

`wait_confirm_cancel` **succeeds** on a cancel as well - read `decision`. A long frame owes `repeat` every interval it spanned, up to 64 per frame; an interval of zero or less cancels the task at once.

### Animation and movement

| Method | Does |
|---|---|
| `play_animation_and_wait(ability, player, animation, stop_on_cancel)` | Plays an animation on an `AnimationPlayer` or `AnimationTree` and waits for it. |
| `root_motion(ability, tree, body, seconds)` | Takes ownership of an `AnimationTree`'s root motion for a `Node3D`. |
| `move_to_2d(ability, node, destination, seconds)` / `move_to_3d(…)` | Moves a node to a point over time. |

**Playing an animation.** The playback belongs to one activation, and the task says how it ended:

```gdscript
var swing: AbilityTaskPlayAnimationAndWait = AbilityTaskFactory.play_animation_and_wait(
	self, animation_player, &"attack_heavy", true
)
await swing.completed()
if swing.outcome != AbilityTaskPlayAnimationAndWait.Outcome.COMPLETED:
	return false
```

| `outcome` | Meaning |
|---|---|
| `COMPLETED` | The animation played to its end. |
| `INTERRUPTED` | Something else played on the same node - another ability's task, or any other code. |
| `CANCELLED` | The ability ended while it played. With `stop_on_cancel`, the animation is stopped too. |
| `BLEND_OUT` | The ability called `blend_out()`: it stopped waiting and left the animation to finish. |
| `FAILED` | It never started: no such animation, or nothing to play it on. |

For a playback rate, a start time or a section, build the task with a shape and register it yourself:

```gdscript
var shape: AbilityTaskAnimationShape = AbilityTaskAnimationShape.new()
shape.rate = 1.5
shape.section = &"recovery"
var task: AbilityTaskPlayAnimationAndWait = owner_asc.register_ability_task(
	AbilityTaskPlayAnimationAndWait.create_shaped(self, animation_player, &"combo", shape)
) as AbilityTaskPlayAnimationAndWait
```

To fire cues from the animation itself, call `GameplayCueAnimation.fire` from a method track. See [Gameplay cues](../gameplay-cues.md).

**Root motion.** The task claims the body while it runs and releases it however the ability ends. It exposes what the animation produced each frame in `last_motion`; applying it - `move_and_slide()`, collision - is the game's decision. `seconds` of `0` drives until the ability ends.

**Moving.** A cancelled move leaves the node where it got to. A duration of `0` places it at once.

### World

| Method | Does |
|---|---|
| `spawn_actor(ability, scene, parent)` | Instantiates a scene under `parent` - by default the avatar's parent - and emits `spawned_ready(node)`. |

The task stays open while the ability runs, holding what it spawned in `spawned`, and frees it when it ends unless `keep_on_finish` is `true`. A cancelled cast does not leave a turret behind.

### Networking

`network_sync_point(ability, for_whom, give_up_after, awaiting)` waits until the server, the client, or both reach the same point of a predicted ability. See [Networking](../networking.md).

### Targeting visuals

`AbilityTaskVisualizeTargeting.create(ability, provider, reticle_scene, into)` draws a reticle for a provider while it previews and removes it when the task ends. Register it with `owner_asc.register_ability_task()`. See [Targeting](../targeting.md#reticles).

## Writing your own task

Subclass `GameplayAbilityTask`, give it a static `create()`, and override the hooks it needs:

```gdscript
class_name AbilityTaskWaitLanded extends GameplayAbilityTask

var body: CharacterBody3D = null


static func create(ability: GameplayAbility, landing_body: CharacterBody3D) -> AbilityTaskWaitLanded:
	var task: AbilityTaskWaitLanded = AbilityTaskWaitLanded.new()
	task.owner_ability = ability
	task.body = landing_body
	return task


func _on_start() -> void:
	if body == null:
		cancel(GameplayAbilityTask.CancelReason.MANUAL)


func advance_time(_delta: float) -> void:
	if is_instance_valid(body) and body.is_on_floor():
		succeed()


func debug_description() -> String:
	return "landing of %s" % body.name if is_instance_valid(body) else "landing"
```

```gdscript
var landed: AbilityTaskWaitLanded = owner_asc.register_ability_task(
	AbilityTaskWaitLanded.create(self, body)
) as AbilityTaskWaitLanded
await landed.completed()
```

| Hook | Called |
|---|---|
| `_on_start()` | When the task starts. Finishing from here is allowed. |
| `_on_finish()` | Exactly once, on success and on cancellation. Disconnect everything `_on_start()` connected. |
| `advance_time(delta)` | Every frame. |
| `handle_input_pressed(id)` / `handle_input_released(id)` | Input on any slot. |
| `handle_gameplay_event(event)` | Every event sent to the owner, before triggers wake abilities. |
| `handle_confirm()` / `handle_cancel()` | A generic confirm or cancel. |
| `handle_target_data(data)` | Target data submitted to the owning ability. |
| `debug_description()` | What the task is waiting for, shown by the debugging tools. |

End the task with `succeed()` or `cancel(reason)`. `register_ability_task()` returns `null` for a task with no `owner_ability`.

To make a custom task available as a node in the Ability Composer, see [Custom nodes](../ability-composer/custom-nodes.md).
