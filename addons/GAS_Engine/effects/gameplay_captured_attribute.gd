## One definition's captured state, for exactly one GameplayEffectSpec.
##
## Only a SNAPSHOT capture ever sets `has_snapshot`. A LIVE capture never
## stores a value here at all - `GameplayEffectSpec.resolve_capture` reads
## straight from the ASC for those, and this record exists for it only so
## `register_capture` has something to key against.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayCapturedAttribute extends RefCounted

var definition: GameplayAttributeCaptureDefinition = null
var has_snapshot: bool = false
var snapshot_value: float = 0.0
