## A cue that runs for as long as the effect behind it does: an aura, a burning
## character, a channel.
##
## Four sets rather than one, because a loop has four moments and they are
## genuinely different. What plays as it starts, what runs for the whole of it,
## what happens every so often while it runs, and what plays as it stops. A
## single set would make "the flame" and "the puff of smoke when it goes out"
## the same thing.
##
## Never auto-destroys: a persistent cue ends when the effect it belongs to
## ends, and a node that pooled itself on a timer would leave an aura on a
## character whose buff is still running.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueNotifyLooping extends GameplayCueNotifyTemplate

## Once, as it begins.
@export var on_application: GameplayCueEffectSet = null

## For the whole of it. Taken back when the cue ends, along with everything
## else this node spawned.
@export var looping: GameplayCueEffectSet = null

## Every `recurring_interval` seconds while it runs - a drip, a pulse, a tick
## of damage that wants a sound of its own.
@export var recurring: GameplayCueEffectSet = null

## Once, as it stops.
@export var on_removal: GameplayCueEffectSet = null

## How often the recurring set plays. Zero or less means never, which is what
## a loop with no recurring set wants and costs it no frames.
@export_range(0.0, 60.0, 0.05, "or_greater") var recurring_interval: float = 1.0

## Seconds since the recurring set last played.
var _since_recurred: float = 0.0


func _init() -> void:
	# A persistent cue is ended by the manager, never by a timer. Set here
	# rather than left to whoever builds the scene, because a looping cue that
	# pooled itself would be a bug in every project that forgot to untick it.
	auto_destroy = false
	set_process(false)


func on_active(params: GameplayCueParams) -> void:
	play_set(on_application, params)
	play_set(looping, params)
	_since_recurred = 0.0
	set_process(recurring != null and recurring_interval > 0.0)


func while_active(_params: GameplayCueParams) -> void:
	pass


## The recurring set, on its own clock.
##
## Counted rather than scheduled with a timer: a cue taken from the pool part
## way through somebody else's interval would inherit their timer, and the
## counter is reset by on_active where the timer would have to be cancelled.
func _process(delta: float) -> void:
	if current_params == null:
		return
	_since_recurred += delta
	if _since_recurred < recurring_interval:
		return
	_since_recurred = 0.0
	play_set(recurring, current_params)


func on_removed(params: GameplayCueParams) -> void:
	set_process(false)
	# Cleared first, so what this cue put into the world is gone by the time
	# the puff of smoke announcing that appears.
	clear_spawned()
	play_set(on_removal, params)
	# And released, because this node is about to be pooled: a removal effect
	# freed in the same frame it appeared is not an effect. It outlives the
	# cue by the same delay a one-shot cue is given.
	release_spawned(destroy_delay)
