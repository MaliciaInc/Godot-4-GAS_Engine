## A mathematical rule detailing how a Gameplay Effect alters an Attribute.
##
## How much it changes it by is a typed GameplayMagnitude, not a bare float
## and an optional Curve - the flat/curve case still exists as
## GameplayScalableMagnitude, but a modifier can also read a captured
## attribute, ask for a caster-supplied value, or run a custom calculation.
##
## @meta_addon: GAS_Engine Version 1 (See plugin version for exact version)
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayEffectModifier extends Resource

## Defines the mathematical operation applied to the attribute.
enum Operation {
	ADD,      # Adds the magnitude (use negative values for damage/subtraction)
	MULTIPLY, # Multiplies the current value (e.g., 1.5 for a 50% increase)
	DIVIDE,   # Divides the current value
	OVERRIDE  # Completely replaces the current value with the magnitude
}

## The exact attribute name in the AttributeSet (e.g. &"health" or &"mana").
@export var attribute_name: StringName = &""

## How the math should be applied.
@export var operation: GameplayEffectModifier.Operation = Operation.ADD

## How much: a GameplayScalableMagnitude for the flat-or-curve case, or one
## of the other GameplayMagnitude kinds for a captured, caster-supplied or
## custom-computed value.
@export var magnitude: GameplayMagnitude = null
