## A cue that happens once and is over: an impact, a footstep, a spark.
##
## One effect set, played the moment the cue executes, and then the node pools
## itself on the delay it was given. Nothing here is authored in a script: a
## burst is a Resource of sounds and particles bound to a tag, which is the
## whole point of it existing rather than every project writing this class.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueNotifyBurst extends GameplayCueNotifyTemplate

## What plays. Null is a cue that does nothing, which is a legitimate thing to
## bind while art is missing: gameplay stays correct with nothing to show.
@export var burst: GameplayCueEffectSet = null


func executed(params: GameplayCueParams) -> void:
	play_set(burst, params)
