## A stateless cue endpoint that needs no scene instance.
##
## Most cues are a scene: particles, a sound, something with a position. Some
## are not - a screen shake request, a line in a combat log, a counter on a HUD -
## and for those a PackedScene is a Node to instantiate, parent, pool and
## eventually free for something that never drew anything.
##
## Stateless is the contract, not an observation. One handler answers for every
## entity that plays its tag, and everything about a particular playback arrives
## in the params. A handler that kept a field would be one playback's state read
## by the next one's, which is exactly the bug pooling a scene avoids by giving
## each playback its own instance.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueHandler extends RefCounted

## Types by preload rather than by name: this file is inside the
## GameplayCueManager autoload's parse-time closure, and Godot parses autoloads
## before it has scanned the project for class_name declarations.
const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")

## A one-shot cue happened.
func on_execute(_params: CueParams) -> void:
	pass


## A persistent cue started.
func on_active(_params: CueParams) -> void:
	pass


## And is still running. Called once per frame while it is, so a handler that
## only cares about starting and stopping leaves this alone.
func while_active(_params: CueParams) -> void:
	pass


## A persistent cue ended - because the effect behind it was removed, was
## inhibited, or because the component was torn down.
func on_removed(_params: CueParams) -> void:
	pass
