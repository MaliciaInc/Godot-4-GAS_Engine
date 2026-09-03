## The frozen outcome of resolving an ability's cost list against a live ASC.
##
## `absolute_effect` is the single INSTANT, silent effect the commit will
## charge - one negative ADD modifier per target attribute, already aggregated
## and already evaluated. Built once by the resolver; nothing downstream
## recomputes a percentage from it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayResolvedCost extends RefCounted

enum Status {
	OK,
	INVALID_DEFINITION,
	TARGET_ATTRIBUTE_NOT_FOUND,
	REFERENCE_ATTRIBUTE_NOT_FOUND,
	NON_FINITE_VALUE,
	PERCENT_OUT_OF_RANGE,
	INSUFFICIENT_RESOURCES,
}

var status: GameplayResolvedCost.Status = Status.OK

## One entry per declared cost, in declaration order. Populated on OK and on
## INSUFFICIENT_RESOURCES; empty on every structural failure, because a
## structural failure means at least one entry could not be built at all.
var entries: Array[GameplayResolvedCostEntry] = []

## The engine-built charge, or null when there was nothing to charge: an empty
## cost list, or every entry resolving to zero for its attribute.
var absolute_effect: GameplayEffect = null


func is_ok() -> bool:
	return status == Status.OK
