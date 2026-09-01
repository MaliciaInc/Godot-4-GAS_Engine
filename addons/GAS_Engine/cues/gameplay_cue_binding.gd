## One cue an effect declares, and when it plays - replacing the old
## `application_cue_tags`/`periodic_cue_tags` pair of arrays with one
## authoring route rather than two that could disagree.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayCueBinding extends Resource

enum Type {
	## Once, the moment the effect is applied - including every stack
	## reapplication, each of which is its own application.
	EXECUTED_ON_APPLICATION,
	## Once per periodic tick.
	EXECUTED_ON_PERIODIC,
	## Runs GameplayCueNotify's on_active/while_active/on_removed lifecycle
	## for as long as the active effect stays uninhibited - never
	## auto-pooled, never once per stack join.
	PERSISTENT,
}

@export var cue_tag: StringName = &""
@export var type: GameplayCueBinding.Type = Type.EXECUTED_ON_APPLICATION
