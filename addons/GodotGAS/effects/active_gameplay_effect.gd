## One effect currently applied to an ASC, and the runtime state it owns.
##
## Upstream stored `applied_deltas` - the flat amount each attribute moved -
## and reversed it on removal. That model cannot be right: with `+20` and `x2`
## both active, removing the `+20` is not expressible as a single delta, so the
## result depended on removal order and could not recover. The effect now stores
## its typed contributions and removal simply drops them, after which the
## aggregator recomposes from scratch. There is no history left to get wrong.
##
## The periodic clock counts elapsed time and completed ticks rather than
## decrementing a countdown. A frame long enough to span three periods owes
## three ticks, and this model pays all three from their theoretical indices
## instead of dropping two and drifting.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name ActiveGameplayEffect extends RefCounted

## Why an active effect stopped being active. Natural (the clock ran out on
## its own) fires on_natural_expiration; every other gameplay-caused removal
## is premature and fires on_premature_removal; both fire on_any_removal.
## ASC_CLEANUP fires neither - see GameplayEffectAdditionalEffectsComponent.
enum RemovalReason {
	NATURAL_EXPIRATION,
	EXPLICIT,
	CLEANSE,
	SOURCE_REMOVED,
	STACK_OVERFLOW,
	ASC_CLEANUP,
	## An invariant violation, not a gameplay branch: GameplayEffectGrant-
	## AbilitiesComponent's post-commit finalization failed after its own
	## prepare already validated everything. Fires no chain, same as
	## ASC_CLEANUP - this is the runtime unwinding its own failure, not
	## something gameplay decided.
	GRANT_FINALIZATION_FAILED,
}

## This application's own spec. Never shared with another target.
var spec: GameplayEffectSpec = null

## The stable public identity a caller keeps instead of this object itself.
## Null for INSTANT - it never persists to be referenced later.
var handle: GameplayEffectHandle = null

## Monotonic order in which this effect was applied to its ASC. Identifies this
## application's contributions inside the aggregator and decides which OVERRIDE
## wins.
var application_order: int = -1

## How many applications this stack represents. Always 1 for
## `stacking_type == NONE`. Kept synchronized with `spec.stack_count` -
## GameplayEffectStackingRuntime is the only writer of either.
var stack_count: int = 1

## The contributions this effect registered. Empty for instant and periodic
## effects, which mutate the base instead.
var contributed_modifiers: Array[AttributeModifierContribution] = []

## The logical receipt of tags this effect grants - kept even while
## inhibited. Whether it is actually applied to the tag runtime right now is
## `state_attached`, owned by GameplayEffectInhibitionRuntime alone.
var granted_tags: Array[StringName] = []

## False while an ongoing-requirement failure has detached this effect's
## contributions/tags without removing it. It stays registered in `_active`,
## keeps its clock, and reattaches unchanged if the requirement is satisfied
## again - see GameplayEffectInhibitionRuntime.
var inhibited: bool = false

## Whether `granted_tags`/`contributed_modifiers` are currently applied to
## the tag runtime/aggregator. False exactly when `inhibited` is true, plus
## the brief window during removal after they have been dropped but before
## the receipt itself is cleared.
var state_attached: bool = true

## Prepared state for each of this application's components, indexed the
## same as spec.effect_def.components - null where a component prepared
## nothing. Empty for INSTANT and periodic effects, which never persist.
var component_states: Array[GameplayEffectComponentState] = []

## Every ability handle GameplayEffectGrantAbilitiesComponent actually
## granted while committing this effect - the receipt removal reads,
## never the authoring Resource, which may have changed since.
var granted_ability_handles: Array[GameplayAbilityHandle] = []

## Seconds left, for a DURATION effect.
var time_remaining: float = 0.0

## Seconds this effect has been active. The periodic clock reads this rather
## than a countdown, so ticks cannot drift.
var elapsed_time: float = 0.0

## How many periodic ticks have been paid since `period_origin_elapsed`.
var completed_ticks: int = 0

## Where the periodic clock currently counts ticks from - normally 0.0
## (paired with `elapsed_time` from application), but reset to `elapsed_time`
## by GameplayEffectInhibitionRuntime on uninhibit under a policy that
## restarts the period. `elapsed_time` itself never resets: it is the total
## duration/turn clock, unaffected by inhibition.
var period_origin_elapsed: float = 0.0

## True once a due tick has been skipped while inhibited, for
## EXECUTE_IMMEDIATELY_ON_UNINHIBIT to know a catch-up tick is owed.
var missed_tick_while_inhibited: bool = false

## Tolerance used when deciding whether a tick is due. See advance_clock.
const TICK_EPSILON_SECONDS: float = 1e-9


#region Initialization
func _init(in_spec: GameplayEffectSpec = null, in_application_order: int = -1) -> void:
	spec = in_spec
	application_order = in_application_order
	if in_spec == null or in_spec.effect_def == null:
		return
	if in_spec.effect_def.policy == GameplayEffect.DurationPolicy.DURATION:
		time_remaining = in_spec.duration
#endregion


#region Periodic clock
func is_periodic() -> bool:
	return spec != null and spec.period > 0.0


## Advance the clock and report how many ticks are now owed.
##
## Owed ticks come from the elapsed time, not from a countdown that gets reset:
## a 0.1 s period stepped by a 0.35 s frame owes three ticks and leaves 0.05 s
## of credit, and a thousand such frames still owe exactly the right total.
func advance_clock(delta: float) -> int:
	if not is_periodic():
		elapsed_time += delta
		return 0
	elapsed_time += delta
	# Nudged by an epsilon before flooring. Accumulated time is a sum of floats:
	# a hundred additions of 0.1 total 9.99999999999998, so a tick due at t=10
	# would be judged not yet owed and arrive a frame late. The epsilon is
	# nine orders of magnitude larger than the accumulated error and nine
	# orders smaller than any period a game would use, so it can only ever
	# decide a boundary case that was meant to be exact.
	#
	# Relative to period_origin_elapsed rather than 0.0, so a period reset
	# (RESET_PERIOD_ON_UNINHIBIT) can restart the count without touching the
	# total elapsed_time clock.
	var since_origin: float = elapsed_time - period_origin_elapsed
	var due: int = floori((since_origin + TICK_EPSILON_SECONDS) / spec.period)
	var owed: int = due - completed_ticks
	return maxi(owed, 0)


func consume_ticks(count: int) -> void:
	completed_ticks += count


## The instant in time the Nth tick (since the current period origin) was
## theoretically due, for a cue or event that wants to say when it happened
## rather than when it was processed.
func tick_time(tick_index: int) -> float:
	return period_origin_elapsed + spec.period * float(tick_index) if is_periodic() else 0.0
#endregion


#region Helpers
func get_effect_def() -> GameplayEffect:
	return spec.effect_def if spec != null else null


func get_instigator() -> Node:
	if spec == null or spec.context == null:
		return null
	return spec.context.instigator


func get_target_nodes() -> Array[Node]:
	return spec.get_target_nodes() if spec != null else []


## Whether this effect contributes to the aggregator at all. A periodic effect
## does not: one effect cannot be both periodic and a persistent
## contributor, because the two would compound every tick.
func has_contributions() -> bool:
	return not contributed_modifiers.is_empty()
#endregion
