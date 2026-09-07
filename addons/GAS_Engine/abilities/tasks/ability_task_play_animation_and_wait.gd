## Play one animation, wait for it, and know whose playback it is.
##
## Godot-native, and deliberately not a reimplementation of AnimMontage's
## section and blend machinery. What is copied from a montage is the part an
## ability actually depends on: the playback belongs to one activation, it ends
## exactly once, and it says how it ended - so an ability can tell "the swing
## finished" from "somebody interrupted it" from "I stopped waiting".
##
## The failure this exists for: two abilities on one character reach for the
## same AnimationPlayer, the second one's `play()` replaces the first's, and the
## first's task waits for an `animation_finished` that will never carry its
## name. It waited until the ability ended, holding everything the ability took.
##
## Drives an AnimationPlayer or an AnimationTree through one surface, so an
## ability does not have to know which the game gave it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskPlayAnimationAndWait extends GameplayAbilityTask

## How the wait ended.
##
## COMPLETED - the animation played to its end.
## INTERRUPTED - somebody else took the surface: another ability's task, or
##     anything at all that asked the same node for something else.
## CANCELLED - the ability ended or was cancelled while it was still playing.
## BLEND_OUT - the ability stopped waiting on purpose and left the animation to
##     play itself out. The moment a montage blends out, without the montage.
## FAILED - it never started: no surface on that node, or no such animation.
enum Outcome { COMPLETED, INTERRUPTED, CANCELLED, BLEND_OUT, FAILED }

## The node to animate. An AnimationMixer, so either kind is accepted; the
## field keeps its old name because callers already pass a player to it.
var player: AnimationMixer = null
var animation: StringName = &""

## A shared surface - one an idle/locomotion tree might also drive - is not
## stopped when this task is cancelled unless the caller says it owns it.
var stop_on_cancel: bool = false

## How it ended, readable the moment `finished` fires.
var outcome: AbilityTaskPlayAnimationAndWait.Outcome = Outcome.FAILED

## Which activation this playback belongs to, copied at the start: the ability
## may have been retriggered by the time this ends, and the receipt has to
## describe the activation that made it.
var activation_id: int = 0

var surface: GameplayAnimationSurface = null
var claim: GameplayAnimationOwnership = null

var _decided: bool = false


static func create(
	ability: GameplayAbility,
	animation_player: AnimationMixer,
	animation_name: StringName,
	stop_when_cancelled: bool = false
) -> AbilityTaskPlayAnimationAndWait:
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskPlayAnimationAndWait.new()
	task.owner_ability = ability
	task.player = animation_player
	task.animation = animation_name
	task.stop_on_cancel = stop_when_cancelled
	return task


func _on_start() -> void:
	surface = GameplayAnimationSurface.of(player)
	if surface == null or not surface.can_play(animation):
		_end_with(Outcome.FAILED)
		return
	activation_id = owner_ability.activation_id if owner_ability != null else 0
	claim = GameplayAnimationOwnership.claim(player, owner_ability, animation)
	player.animation_finished.connect(_on_animation_finished)
	player.animation_started.connect(_on_animation_started)
	surface.play(animation)


## The second way the takeover is noticed, and the one that does not need a
## signal: a task whose claim is no longer on the surface has been replaced,
## however that happened - including by the surface itself being freed, which
## is a playback nobody is going to finish either.
func advance_time(_delta: float) -> void:
	if is_finished() or claim == null:
		return
	if not claim.still_holds():
		_end_with(Outcome.INTERRUPTED)


## Stop waiting, and leave the animation to finish itself.
##
## What a montage's blend-out is for: the ability has got what it needed out of
## the animation and moves on while the body finishes the motion. Distinct from
## cancelling, which means the animation should not have been playing at all.
func blend_out() -> void:
	if is_finished():
		return
	_end_with(Outcome.BLEND_OUT)


func _on_finish() -> void:
	if not _decided:
		_decided = true
		outcome = Outcome.CANCELLED
	if claim != null:
		claim.release()
		claim = null
	if is_instance_valid(player):
		if player.animation_finished.is_connected(_on_animation_finished):
			player.animation_finished.disconnect(_on_animation_finished)
		if player.animation_started.is_connected(_on_animation_started):
			player.animation_started.disconnect(_on_animation_started)
	# Only a real cancellation stops the surface. Stopping after a takeover
	# would kill the animation the new owner just started, which is the one
	# thing this task must not do to the ability that replaced it.
	if stop_on_cancel and outcome == Outcome.CANCELLED and surface != null:
		surface.halt()
	surface = null


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation:
		return
	_end_with(Outcome.COMPLETED)


## Anything else starting on this surface is this playback ending.
func _on_animation_started(started_animation: StringName) -> void:
	if started_animation == animation:
		return
	_end_with(Outcome.INTERRUPTED)


## One decision, whichever way it was reached.
##
## `_on_finish` reads `_decided` to tell "the ability ended this" from "this
## ended itself", which is the difference between CANCELLED and every other
## outcome.
func _end_with(result: AbilityTaskPlayAnimationAndWait.Outcome) -> void:
	if _decided or is_finished():
		return
	_decided = true
	outcome = result
	if result == Outcome.COMPLETED or result == Outcome.BLEND_OUT:
		succeed()
		return
	cancel(GameplayAbilityTask.CancelReason.MANUAL)
