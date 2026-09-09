## A game-specific cost whose mutation is still part of the engine's atomic
## ability commit.
##
## Ammunition in a magazine, a charge on an item, a stack on a tag: things this
## engine has no opinion about and cannot price, but which a commit still has to
## be able to take back if a later step fails.
##
## Two questions, deliberately separate. `check` is asked without taking
## anything, so a button can grey itself out; `prepare` works out exactly what
## would be taken and hands back the object that knows how to undo it. The
## engine never asks a cost to simply pay, because a cost that paid without
## handing back a receipt is the one state the commit contract cannot survive.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityCustomCost extends Resource


## Whether this could be paid right now, without taking anything.
func check(
	_asc: AbilitySystemComponent,
	_spec: GameplayAbilitySpec,
	_level: float
) -> GameplayAbilityCustomCostCheck:
	return GameplayAbilityCustomCostCheck.allowed()


## Work out what would be taken, and hand back the thing that can take it and
## put it back. Null means this cost cannot be prepared, which refuses the
## commit before anything has been touched.
func prepare(
	_asc: AbilitySystemComponent,
	_spec: GameplayAbilitySpec,
	_level: float
) -> GameplayAbilityPreparedCustomCost:
	return null


## What a client may predict about this cost, if anything.
##
## NONE by default and deliberately: the journal can only undo what it knows how
## to undo, and an inventory is not that. A game whose custom cost happens to be
## an attribute delta may say so in a later phase; this one does not invent
## remote rollback of things the engine cannot see.
func prediction_kind() -> GameplayPredictionOperation.Kind:
	return GameplayPredictionOperation.Kind.NONE
