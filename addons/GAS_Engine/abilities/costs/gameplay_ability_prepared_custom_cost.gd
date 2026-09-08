## A custom cost that has been worked out and not yet taken.
##
## The unit the whole transaction is built on. A cost that could only be told
## "pay" would leave the engine with nothing to undo it by, so what a cost hands
## back is an object that already knows both - what it is about to take, and how
## to put it back.
##
## There is deliberately no `pay()` that returns a bool and nothing else. A path
## like that is exactly the state this class exists to make unreachable: paid,
## and nobody holding the receipt.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityPreparedCustomCost extends RefCounted

## Set by the engine once commit() answered true, so a rollback knows which of
## several prepared costs actually took anything.
var committed: bool = false


## Take it. False means nothing was taken - a commit that half-took something
## and answered false has broken the contract this object exists to keep.
func commit() -> bool:
	return false


## Put back exactly what commit() took. Called only on a prepared cost whose
## commit() answered true, and never twice.
func rollback() -> void:
	pass
