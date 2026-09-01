## One priced entry in an ability's cost list: what it charges, and how the
## price is computed.
##
## Three ways to price an entry:
##
##     ABSOLUTE            a fixed amount, optionally scaled by level
##     PERCENT_OF_BASE      a fraction of `reference_attribute`'s durable base
##     PERCENT_OF_CURRENT   a fraction of `reference_attribute`'s derived value
##
## This Resource only describes intent. `GameplayAbilityCostResolver` turns a
## list of these, read against a live ASC, into one frozen amount to charge. It
## does no arithmetic itself and touches no attribute.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayAbilityCost extends Resource

enum Mode {
	ABSOLUTE,
	PERCENT_OF_BASE,
	PERCENT_OF_CURRENT,
}

@export var mode: GameplayAbilityCost.Mode = Mode.ABSOLUTE

## The attribute this entry actually spends.
@export var target_attribute: StringName = &""

## For a percent mode, the attribute the percentage is computed against. Must
## stay empty for ABSOLUTE: nothing is referenced when nothing is a fraction.
@export var reference_attribute: StringName = &""

## ABSOLUTE: the amount itself. Percent modes: the fraction - `0.10` for 10%,
## `1.00` for 100%. Never negative, never over 1.00 for a percent mode.
@export var amount: GameplayScalableFloat = null
