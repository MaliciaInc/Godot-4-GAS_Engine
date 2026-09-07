## What one case did when it was run, and every way it disagreed.
##
## Every disagreement rather than the first, because a case that is wrong in two
## dimensions reported one at a time is two runs of the whole corpus to find out
## - and the second one is usually a consequence of the first, which is worth
## seeing together.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayParityResult extends RefCounted

var id: StringName = &""
var reference_version: String = ""
var disagreements: Array[String] = []


static func of(case: GameplayParityCase) -> GameplayParityResult:
	var made: GameplayParityResult = GameplayParityResult.new()
	made.id = case.id
	made.reference_version = case.reference_version
	return made


func disagree(what: String) -> void:
	disagreements.append(what)


func agrees() -> bool:
	return disagreements.is_empty()


## One line for the results file, readable without the corpus beside it.
func to_line() -> String:
	if agrees():
		return "- %s: AGREES (%s)" % [id, reference_version]
	return "- %s: DISAGREES (%s) - %s" % [id, reference_version, "; ".join(disagreements)]
