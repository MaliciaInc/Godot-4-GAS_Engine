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
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
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
		push_error("GAS_Engine: refused a non-finite or negative delta of " + str(delta))
		return
	if effects == null:
		return

	# Snapshot identities. A callback may remove an earlier element, remove
	# itself, or add a new effect. Each identity present at the beginning is
	# considered at most once; new effects begin on the next update.
	var snapshot: Array[ActiveGameplayEffect] = effects.active_effects()
	for index: int in range(snapshot.size() - 1, -1, -1):
		var active: ActiveGameplayEffect = snapshot[index]
		if not effects.contains_active(active):
			continue
		_advance_one(active, delta)


func _advance_one(active: ActiveGameplayEffect, delta: float) -> void:
	if not effects.contains_active(active):
		return

	var definition: GameplayEffect = active.get_effect_def()
	if definition == null:
		return

	var policy: GameplayEffect.DurationPolicy = definition.policy
	if policy == GameplayEffect.DurationPolicy.TURN_BASED:
		return

	# A finite effect may only create ticks inside the part of this delta where
	# it is logically alive. Existing backlog remains payable with tick_delta=0.
	var tick_delta: float = delta
	if policy == GameplayEffect.DurationPolicy.DURATION:
		tick_delta = minf(delta, maxf(active.time_remaining, 0.0))

	var backlog: int = _pay_ticks(active, tick_delta)
	if not effects.contains_active(active):
		return

	if policy != GameplayEffect.DurationPolicy.DURATION:
		return

	# Lifetime advances independently from the per-frame work cap.
	active.time_remaining = maxf(0.0, active.time_remaining - delta)

	# If a pre-expiry backlog is larger than the cap, the active object remains
	# only long enough to pay that already-created debt. Later updates pass a
	# zero tick horizon, so no post-expiry tick can be invented.
	if active.time_remaining <= 0.0 and backlog <= 0:
		effects.expire(active)


## Run the ticks this effect owes, up to the per-update cap. Returns only debt
## that was already due inside the logical lifetime.
func _pay_ticks(active: ActiveGameplayEffect, delta: float) -> int:
	if not effects.contains_active(active):
		return 0

	if not active.is_periodic():
		active.advance_clock(delta)
		return 0
	if not is_finite(active.spec.period) or active.spec.period <= 0.0:
		push_error("GAS_Engine: periodic effect with a non-positive period; not ticking.")
		return 0

	var owed: int = active.advance_clock(delta)
	if active.inhibited:
		_skip_ticks_while_inhibited(active, owed)
		return 0

	var payable: int = mini(owed, MAX_PERIODIC_CATCH_UP_TICKS_PER_FRAME)
	var paid: int = 0

	for _tick: int in payable:
		if not effects.contains_active(active):
			return 0
		if active.inhibited:
			_skip_ticks_while_inhibited(active, owed - paid)
			return 0

		effects.run_periodic_tick(active)

		# The callback may remove/inhibit this effect.
		if not effects.contains_active(active):
			return 0

		active.consume_ticks(1)
		paid += 1

		if active.inhibited:
			_skip_ticks_while_inhibited(active, owed - paid)
			return 0

	var backlog: int = owed - paid
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
		"GAS_Engine: periodic effect is " + str(backlog)
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
	var snapshot: Array[ActiveGameplayEffect] = effects.active_effects()
	for index: int in range(snapshot.size() - 1, -1, -1):
		var active: ActiveGameplayEffect = snapshot[index]
		if not effects.contains_active(active):
			continue
		_advance_one_turn(active)


func _advance_one_turn(active: ActiveGameplayEffect) -> void:
	if not effects.contains_active(active):
		return

	var effect: GameplayEffect = active.get_effect_def()
	if effect == null or effect.policy != GameplayEffect.DurationPolicy.TURN_BASED:
		return

	# tick_on_turn_start=true means before consuming the turn.
	if active.is_periodic() and effect.tick_on_turn_start and not active.inhibited:
		effects.run_periodic_tick(active)
		if not effects.contains_active(active):
			return
		active.consume_ticks(1)

	active.spec.remaining_turns -= 1

	if not effects.contains_active(active):
		return

	# tick_on_turn_start=false is explicitly the end-of-turn tick.
	if active.is_periodic() and not effect.tick_on_turn_start and not active.inhibited:
		effects.run_periodic_tick(active)
		if not effects.contains_active(active):
			return
		active.consume_ticks(1)

	if active.spec.remaining_turns <= 0:
		effects.expire(active)
#endregion
