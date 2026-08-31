## When effects tick and when they expire.
##
## Real time and turns are separate axes on purpose. `advance_time` never
## consumes a turn, and `advance_turn` never consumes seconds, so a hundred
## frames advance a turn-based effect by exactly zero turns.
##
## Periodic ticks are derived from elapsed time rather than a decrementing
## accumulator. A frame long enough to span three periods owes three ticks and
## pays all three from their theoretical indices. An accumulator would pay one
## and silently drop two, and the drift would compound for the effect's life.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectScheduler extends RefCounted

## Ticks paid per effect per update. A backlog beyond this is carried, never
## discarded and never fast-forwarded: `completed_ticks` advances only by ticks
## actually executed, so the next update pays the rest before expiry is even
## considered. Without the cap, one enormous delta could run thousands of ticks
## in a single frame and freeze the game.
const MAX_PERIODIC_CATCH_UP_TICKS_PER_FRAME: int = 64

var effects: GameplayEffectRuntime = null

## Effects that reported a backlog last update, so the diagnostic is emitted
## once per effect rather than once per frame for as long as it lasts.
var _reported_backlog: Array[ActiveGameplayEffect] = []


#region Real time
## Advance every real-time effect by `delta` seconds.
##
## A negative or non-finite delta is an invalid update and is refused outright.
## Accepting one would run the catch-up loop backwards or forever.
func advance_time(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_error("GodotGAS: refused a non-finite or negative delta of " + str(delta))
		return
	if effects == null:
		return

	# The live array on purpose: walking it backwards is what makes an effect
	# removing itself mid-walk safe, and this runs every frame.
	var active: Array[ActiveGameplayEffect] = effects.live_active_effects()
	for index: int in range(active.size() - 1, -1, -1):
		if index >= active.size():
			continue
		_advance_one(active[index], delta)


func _advance_one(active: ActiveGameplayEffect, delta: float) -> void:
	var policy: GameplayEffect.DurationPolicy = active.get_effect_def().policy
	if policy == GameplayEffect.DurationPolicy.TURN_BASED:
		return

	var backlog: int = _pay_ticks(active, delta)
	if backlog > 0:
		# Expiry waits until the backlog is paid: an effect must not expire
		# owing ticks it never ran.
		return

	if policy != GameplayEffect.DurationPolicy.DURATION:
		return
	active.time_remaining -= delta
	if active.time_remaining <= 0.0:
		effects.expire(active)


## Run the ticks this effect owes, up to the per-update cap. Returns the
## remaining backlog.
func _pay_ticks(active: ActiveGameplayEffect, delta: float) -> int:
	if not active.is_periodic():
		active.advance_clock(delta)
		return 0
	if not is_finite(active.spec.period) or active.spec.period <= 0.0:
		push_error("GodotGAS: periodic effect with a non-positive period; not ticking.")
		return 0

	var owed: int = active.advance_clock(delta)
	if active.inhibited:
		_skip_ticks_while_inhibited(active, owed)
		return 0

	var payable: int = mini(owed, MAX_PERIODIC_CATCH_UP_TICKS_PER_FRAME)
	for _tick: int in payable:
		effects.run_periodic_tick(active)
	active.consume_ticks(payable)

	var backlog: int = owed - payable
	_diagnose_backlog(active, backlog)
	return backlog


## No policy runs a tick while inhibited - they only differ in what happens
## on uninhibit (see GameplayEffectInhibitionRuntime._resume_periodic_clock).
## The whole backlog is consumed at once, uncapped: an effect inhibited for
## a long time must not arrive at uninhibit still owing thousands of ticks.
func _skip_ticks_while_inhibited(active: ActiveGameplayEffect, owed: int) -> void:
	if owed <= 0:
		return
	active.consume_ticks(owed)
	if active.get_effect_def().period_inhibition_policy == GameplayEffect.PeriodInhibitionPolicy.EXECUTE_IMMEDIATELY_ON_UNINHIBIT:
		active.missed_tick_while_inhibited = true


## One diagnostic per effect per backlog episode, not one per frame.
func _diagnose_backlog(active: ActiveGameplayEffect, backlog: int) -> void:
	if backlog <= 0:
		_reported_backlog.erase(active)
		return
	if _reported_backlog.has(active):
		return
	_reported_backlog.append(active)
	push_warning(
		"GodotGAS: periodic effect is " + str(backlog)
		+ " ticks behind; the backlog will be paid over the following updates."
	)
#endregion


#region Turns
## Advance turn-based effects by whole turns.
##
## Called by an external turn manager, never by the frame loop.
func advance_turn(turns: int = 1) -> void:
	if turns <= 0 or effects == null:
		return
	for _turn: int in turns:
		_advance_single_turn()


func _advance_single_turn() -> void:
	var active: Array[ActiveGameplayEffect] = effects.live_active_effects()
	for index: int in range(active.size() - 1, -1, -1):
		if index >= active.size():
			continue
		_advance_one_turn(active[index])


func _advance_one_turn(active: ActiveGameplayEffect) -> void:
	var effect: GameplayEffect = active.get_effect_def()
	if effect.policy != GameplayEffect.DurationPolicy.TURN_BASED:
		return

	if active.is_periodic() and effect.tick_on_turn_start:
		effects.run_periodic_tick(active)
		active.consume_ticks(1)

	active.spec.remaining_turns -= 1
	if active.spec.remaining_turns <= 0:
		effects.expire(active)
#endregion
