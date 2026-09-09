## The two cues this sample plays, and how a game that builds them rather than
## listing them says so.
##
## A burst for a hit that is over the moment it lands, and a loop for a channel
## that is not. Neither is a script somebody wrote: both are the templates the
## addon ships, carrying a `GameplayCueEffectSet` - the sounds, particles and
## decals a designer fills in - which is what F6.2.6 made possible.
##
## Bound in code because this sample lives inside the engine's own repository
## and must not rewrite the repository's cue registry to run. A project of your
## own lists these in the registry the `gas_engine/resources/cues/registry_file`
## setting points at, and `bind_cue` is what loading that file calls.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleCues extends RefCounted

## The manager's own script, so what this file calls on it is typed.
##
## Preloaded rather than named: an autoload has no global class name, and a
## duck-typed call would be an unsafe one - which this project's warnings
## refuse, and rightly: a typo in a method name would be a cue that silently
## never binds.
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

## What lands when a strike connects.
const STRIKE_IMPACT: StringName = &"Cue.Sample.Strike.Impact"

## What is on the character for as long as the channel is up.
const CHANNEL_LOOP: StringName = &"Cue.Sample.Channel.Loop"

## What lands where a slam does.
const SLAM_IMPACT: StringName = &"Cue.Sample.Slam.Impact"

## The tag a strike's cooldown grants. Here rather than beside the effect
## because it is a name two things have to agree on.
const STRIKE_COOLDOWN: StringName = &"State.Cooldown.Sample.Strike"

## How often the loop says something while it runs.
const LOOP_INTERVAL: float = 1.0


## The running cue manager, found from anywhere in the tree.
##
## Through the manager's own constant rather than a path typed again here: a
## second spelling of it is a sample that binds its cues into nobody and plays
## nothing, which looks exactly like a sample whose cues are wrong. Null-checked
## rather than named as a global, because a project that has not enabled the
## addon's autoload should get "no cues" instead of an error.
static func manager_from(node: Node) -> CueManagerScript:
	if node == null or not is_instance_valid(node) or node.get_tree() == null:
		return null
	return node.get_node_or_null(CueManagerScript.AUTOLOAD_NODE_PATH) as CueManagerScript


## Bind every cue this sample plays into the running manager.
##
## Answers how many were bound, so a caller can tell "bound" from "the manager
## was not there" - which look the same the first time a cue does not play.
static func bind_into(manager: CueManagerScript) -> int:
	if manager == null:
		return 0
	var bound: int = 0
	bound += 1 if manager.bind_cue(STRIKE_IMPACT, burst()) else 0
	bound += 1 if manager.bind_cue(SLAM_IMPACT, burst()) else 0
	bound += 1 if manager.bind_cue(CHANNEL_LOOP, loop()) else 0
	return bound


## Take them back out again, for a game unloading the sample.
static func unbind_from(manager: CueManagerScript) -> void:
	if manager == null:
		return
	for tag: StringName in [STRIKE_IMPACT, SLAM_IMPACT, CHANNEL_LOOP]:
		manager.unbind_cue(tag)


## Whether one of this sample's cues is playing on somebody right now.
##
## Asked through here rather than of the manager directly, so the sample has one
## place that knows where the manager is and what it is - and a project with no
## autoload gets "no" instead of a crash.
static func is_playing(from: Node, on: Node, tag: StringName) -> bool:
	var manager: CueManagerScript = manager_from(from)
	return manager != null and manager.is_cue_active(on, tag)


## A one-shot cue: it happens, and then it is over.
##
## The effect set is empty of assets here because a sample that shipped a sound
## would be shipping a sound. What matters is that it is data on a template
## rather than a subclass somebody wrote: a designer fills in the arrays.
static func burst() -> PackedScene:
	var notify: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	notify.burst = GameplayCueEffectSet.new()
	return _packed(notify)


## A cue with a life: it starts, it says something every second while it runs,
## and it stops when whatever started it stops.
static func loop() -> PackedScene:
	var notify: GameplayCueNotifyLooping = GameplayCueNotifyLooping.new()
	notify.on_application = GameplayCueEffectSet.new()
	notify.looping = GameplayCueEffectSet.new()
	notify.recurring = GameplayCueEffectSet.new()
	notify.on_removal = GameplayCueEffectSet.new()
	notify.recurring_interval = LOOP_INTERVAL
	return _packed(notify)


## Pack a template and free it.
##
## `pack()` copies rather than consumes, so the template left alive is an
## orphan - one per call, which a suite counts and reports.
static func _packed(notify: Node) -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	var packed: Error = scene.pack(notify)
	notify.free()
	return scene if packed == OK else null
