## What a commit found out before it wrote anything.
##
## Committing is a transaction, and the half that decides has to be separable
## from the half that pays: a caller that wants to know whether an ability is
## affordable right now must be able to ask without charging for it, and the
## commit itself has to ask again immediately before the first write, because
## anything it did in between - starting a cooldown, and every signal that
## raised - could have moved the resources it was about to take.
##
## Carrying the resolved cost and the cooldowns is what makes the second ask
## cheap: they were already worked out, and re-resolving them would be a second
## opinion about what the ability costs.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityCommitPreflight extends RefCounted

enum Status {
	OK,
	ON_COOLDOWN,
	INSUFFICIENT_RESOURCES,
	INVALID_COST,
	INVALID_COOLDOWN,
}

var status: AbilityCommitPreflight.Status = Status.OK
var resolved_cost: GameplayResolvedCost = null
var cooldowns: Array[GameplayEffect] = []


func is_ok() -> bool:
	return status == Status.OK


## The commit status this preflight refuses with.
##
## Written here rather than at each call site: two places mapping the same five
## answers is two mappings to keep in step, and nothing reports it when they
## stop matching.
func as_commit_status() -> AbilityCommitResult.Status:
	match status:
		Status.ON_COOLDOWN:
			return AbilityCommitResult.Status.ON_COOLDOWN
		Status.INSUFFICIENT_RESOURCES:
			return AbilityCommitResult.Status.INSUFFICIENT_RESOURCES
		Status.INVALID_COST:
			return AbilityCommitResult.Status.INVALID_COST_DEFINITION
		Status.INVALID_COOLDOWN:
			return AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION
	return AbilityCommitResult.Status.SUCCESS
