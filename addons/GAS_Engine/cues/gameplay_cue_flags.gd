## What one cue scene declares about itself, read once and kept.
##
## A scene's exported values cannot be read without building one of it, and
## these four are asked on every persistent activation. Keeping the instance
## instead would keep a Node nobody ever plays, parented nowhere - which is an
## orphan, and the run counts those.
##
## Data and nothing else. Whoever built it does the reading: a static
## constructor here would have to name the notify type and this record's own
## type, and this file sits inside the GameplayCueManager autoload's parse-time
## closure, where a global name does not resolve.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueFlags extends RefCounted

var unique_per_instigator: bool = false
var unique_per_source_object: bool = false
var allow_multiple_on_active: bool = true
var preallocate: int = 0
