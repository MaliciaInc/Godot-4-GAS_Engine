## The receipt half of RecordingCustomCost.
##
## Separate because that is the shape the engine requires: what a cost hands
## back has to know both how to take the thing and how to put it back, and the
## cost itself is a Resource an author edits.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name RecordingPreparedCost extends GameplayAbilityPreparedCustomCost

var label: StringName = &"cost"
var succeeds: bool = true


func commit() -> bool:
	RecordingCustomCost.said("commit", label)
	return succeeds


func rollback() -> void:
	RecordingCustomCost.said("rollback", label)
