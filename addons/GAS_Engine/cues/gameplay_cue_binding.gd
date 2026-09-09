## One cue an effect declares, and when it plays - replacing the old
## `application_cue_tags`/`periodic_cue_tags` pair of arrays with one
## authoring route rather than two that could disagree.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
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

## Whether other machines hear about this cue at all.
##
## Two different questions that used to be one. A cue can be suppressed - a
## dedicated server plays nothing - and still have to be told to everybody, and
## a cue can be played here and be nobody else's business: the crunch under your
## own footsteps is not something to spend a packet on.
##
## LOCAL_ONLY plays here if nothing is suppressing it and never reaches the
## wire. REPLICATED may be silent on the machine that decided it, and still
## goes out.
enum Replication {
	REPLICATED,
	LOCAL_ONLY,
}

@export var replication: GameplayCueBinding.Replication = Replication.REPLICATED

@export var cue_tag: StringName = &""
@export var type: GameplayCueBinding.Type = Type.EXECUTED_ON_APPLICATION

## The attribute this cue reads itself off, when the number it wants is a
## reading rather than the effect's own magnitude.
##
## "A shield that flickers harder the lower it is" is about the target's
## shield, not about the effect that happened to fire the cue - and before
## this the only number a cue could have was the second one. Read from the
## target at the moment the cue is made, because a value captured earlier is
## the value something else already changed.
@export var magnitude_attribute: GameplayAttributeRef = null

## The range the reading is normalised against, so a cue can be authored once
## and scale itself without knowing what the numbers of this game are.
##
## `normalized_magnitude` is where the reading lands between them, clamped.
## The defaults describe a value that is already 0..1, which is what a cue
## reading a percentage wants and costs nothing to leave alone.
@export var min_level: float = 0.0
@export var max_level: float = 1.0
