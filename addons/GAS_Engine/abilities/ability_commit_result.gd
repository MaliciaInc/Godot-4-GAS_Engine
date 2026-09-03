## What committing an ability charged, what it started, and why it refused.
##
## A commit is a transaction: it takes the whole price - every cooldown and the
## cost - or it takes none of it. The handles are kept so the commit can undo
## what it already applied when a later step fails, and so a caller can see
## exactly what it now owns.
##
## The status is the whole answer. There is no message field: a caller that has
## to read prose to know what happened cannot branch on it, and a status that
## needs prose to be understood is the wrong status.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityCommitResult extends RefCounted


## Why the commit ended the way it did. SUCCESS is the only one that charged
## anything; every other status leaves the owner exactly as it was found.
enum Status {
	SUCCESS,
	OWNER_MISSING,
	ALREADY_COMMITTED,
	INVALID_COST_DEFINITION,
	INVALID_COOLDOWN_DEFINITION,
	INSUFFICIENT_RESOURCES,
	COOLDOWN_APPLICATION_FAILED,
	COST_APPLICATION_FAILED,
	RESOURCES_CHANGED_DURING_COMMIT,
}

var status: AbilityCommitResult.Status = Status.SUCCESS

## The cooldowns this commit started, in the order it applied them. Empty on
## every failure, including one that had already started some: a commit that
## rolled back reports nothing applied, because nothing is.
var applied_cooldowns: Array[ActiveGameplayEffect] = []

## The cost handle, or null when the ability is free or the commit failed.
var applied_cost: ActiveGameplayEffect = null

## The frozen result of resolving `costs` against the owner, whatever the
## outcome. Never null after a commit attempt reaches the resolver: even a
## refusal keeps the resolved cost so a caller can see why.
var resolved_cost: GameplayResolvedCost = null


func is_ok() -> bool:
	return status == Status.SUCCESS
