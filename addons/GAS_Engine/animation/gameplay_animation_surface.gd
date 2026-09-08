## One way to drive a Godot animation, whichever of the two kinds a game uses.
##
## AnimationPlayer and AnimationTree are both AnimationMixer, so the half that
## matters here is already shared: `has_animation()`, `animation_started` and
## `animation_finished` mean the same thing on both. What differs is how a
## playback is asked for - a player is told to play a clip, a tree is told to
## travel to a state - and nothing else in this addon should have to know which
## of the two it is holding.
##
## Not a port of AnimMontage. What is copied is the observable contract - one
## playback, owned by one activation, that ends exactly once and says how it
## ended - and not sections, slots or blend graphs, which Godot already
## expresses in its own way and which this addon has no use for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAnimationSurface extends RefCounted

## Where an AnimationTree keeps the state machine that answers `travel()`.
const PLAYBACK_PARAMETER: StringName = &"parameters/playback"

## The mixer both kinds are, and the state machine only a tree has.
var mixer: AnimationMixer = null
var playback: AnimationNodeStateMachinePlayback = null


## The surface for a node, or null when the node is neither kind.
##
## Null rather than a surface that quietly does nothing: "this node cannot be
## animated" is a decision the caller has to make, and a silent no-op would
## leave an ability waiting for a playback that was never going to start.
static func of(node: Node) -> GameplayAnimationSurface:
	var mixed: AnimationMixer = node as AnimationMixer
	if mixed == null or not is_instance_valid(mixed):
		return null
	var surface: GameplayAnimationSurface = GameplayAnimationSurface.new()
	surface.mixer = mixed
	var tree: AnimationTree = node as AnimationTree
	if tree != null:
		var found: AnimationNodeStateMachinePlayback = tree.get(PLAYBACK_PARAMETER)
		surface.playback = found
	return surface


## Whether this is a tree driven by a state machine rather than a player.
func drives_a_state_machine() -> bool:
	return playback != null


## Whether this surface can be asked for that animation at all.
##
## A player is asked whether it has the clip; a state machine, whether it has
## the state. The two are different questions with the same purpose, and a task
## that asked the wrong one of a tree would refuse every animation it has.
func can_play(animation: StringName) -> bool:
	if not _alive():
		return false
	if playback != null:
		return _machine_has(animation)
	return mixer.has_animation(animation)


## Ask for the playback, and say whether the ask was accepted.
func play(animation: StringName) -> bool:
	if not can_play(animation):
		return false
	if playback != null:
		playback.travel(animation)
		return true
	var player: AnimationPlayer = mixer as AnimationPlayer
	if player == null:
		return false
	player.play(animation)
	return true


## What is playing now - which is how a task notices somebody else took over.
## Where a named marker sits in an animation, in seconds, or -1 for a name
## the animation does not carry.
##
## Markers are what Godot gives an author to name a point in time with, and
## naming a point in time is the whole of what a section is. A name that is not
## there answers -1 rather than zero: starting from the top is a different
## thing from starting where you asked, and a caller has to be able to tell.
func marker_time(animation: StringName, marker: StringName) -> float:
	if not _alive() or marker == &"":
		return -1.0
	var library: Animation = mixer.get_animation(String(animation))
	if library == null or not library.has_marker(marker):
		return -1.0
	return library.get_marker_time(marker)


## How long an animation runs, or zero when there is no such animation.
func length_of(animation: StringName) -> float:
	if not _alive():
		return 0.0
	var library: Animation = mixer.get_animation(String(animation))
	return library.length if library != null else 0.0


func now_playing() -> StringName:
	if not _alive():
		return &""
	if playback != null:
		return playback.get_current_node()
	var player: AnimationPlayer = mixer as AnimationPlayer
	return StringName(player.current_animation) if player != null else &""


func halt() -> void:
	if not _alive():
		return
	if playback != null:
		playback.stop()
		return
	var player: AnimationPlayer = mixer as AnimationPlayer
	if player != null:
		player.stop()


## A surface outlives the node it drives - an ability cancelled by the death of
## the thing it was animating cleans up through here.
func _alive() -> bool:
	return mixer != null and is_instance_valid(mixer)


func _machine_has(state: StringName) -> bool:
	var tree: AnimationTree = mixer as AnimationTree
	if tree == null:
		return false
	var machine: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	return machine != null and machine.has_node(state)
