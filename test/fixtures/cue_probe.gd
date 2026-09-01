## A recording cue, installed into the real GameplayCueManager.
##
## Two suites drive cues through the real manager rather than constructing one
## by hand, and both need the same three steps: pack a recording
## GameplayCueNotify into a PackedScene, put it into the manager's own maps
## under a tag, and take it back out afterwards. Written out twice that is one
## fact in two places, and the second copy is the one that stops matching the
## day those maps change shape.
##
## The project's shipped cue registry is empty on purpose, so injecting the
## scene directly is what a populated registry would have produced through
## `_load_registry()` - the manager itself is never stubbed.
##
## No `class_name`: the two suites reach this through `preload`, the way they
## already reach the cue manager. A global name resolves only once Godot has
## built its class cache, and this project has to parse on a checkout that has
## never had one.
##
## @meta_license: MIT
extends RefCounted

const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")


## A cue overriding the F2.5 lifecycle directly, none of it falling through to
## the F2 virtual, recording what it was asked to do instead of drawing.
class RecordingPersistentCue extends GameplayCueNotify:
	var events: Array[StringName] = []
	var executed_count: int = 0
	var play_cue_count: int = 0

	func executed(_params: GameplayCueParams) -> void:
		executed_count += 1

	func play_cue(_params: GameplayCueParams) -> void:
		play_cue_count += 1

	func on_active(_params: GameplayCueParams) -> void:
		events.append(&"on_active")

	func while_active(_params: GameplayCueParams) -> void:
		events.append(&"while_active")

	func on_removed(_params: GameplayCueParams) -> void:
		events.append(&"on_removed")


## Register a recording cue scene under `tag`, with an empty bucket beside it.
##
## `PackedScene.pack()` neither consumes nor frees the template, so the template
## is freed here - one orphan per call otherwise, and GUT counts them.
static func install(manager: CueManagerScript, tag: StringName) -> void:
	var template: RecordingPersistentCue = RecordingPersistentCue.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(template)
	template.free()
	manager._cue_scenes[tag] = scene
	manager._pool[tag] = GameplayCuePoolBucket.new()


## Take the tag back out of the manager the suite shares with every other test.
static func uninstall(manager: CueManagerScript, tag: StringName) -> void:
	manager._cue_scenes.erase(tag)
	manager._pool.erase(tag)


## The parameter object a cue playback needs, aimed at one node.
static func params_for(tag: StringName, node: Node, magnitude: float = 3.0) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = node
	params.target = node
	params.magnitude = magnitude
	return params
