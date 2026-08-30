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

## This application's own spec. Never shared with another target.
var spec: GameplayEffectSpec = null

## Monotonic order in which this effect was applied to its ASC. Identifies this
## application's contributions inside the aggregator and decides which OVERRIDE
## wins.
var application_order: int = -1

## The contributions this effect registered. Empty for instant and periodic
## effects, which mutate the base instead.
var contributed_modifiers: Array[AttributeModifierContribution] = []

## Tags this effect granted, so removal drops exactly what it added.
var granted_tags: Array[StringName] = []

## Seconds left, for a DURATION effect.
var time_remaining: float = 0.0

## Seconds this effect has been active. The periodic clock reads this rather
## than a countdown, so ticks cannot drift.
var elapsed_time: float = 0.0

## How many periodic ticks have already been paid.
var completed_ticks: int = 0

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
	var due: int = floori((elapsed_time + TICK_EPSILON_SECONDS) / spec.period)
	var owed: int = due - completed_ticks
	return maxi(owed, 0)


func consume_ticks(count: int) -> void:
	completed_ticks += count


## The instant in time the Nth tick was theoretically due, for a cue or event
## that wants to say when it happened rather than when it was processed.
func tick_time(tick_index: int) -> float:
	return spec.period * float(tick_index) if is_periodic() else 0.0
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
## does not: section 3.6 forbids one effect being both periodic and a persistent
## contributor, because the two would compound every tick.
func has_contributions() -> bool:
	return not contributed_modifiers.is_empty()
#endregion
