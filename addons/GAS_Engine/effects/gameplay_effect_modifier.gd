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
	ADD,
	## Legacy/Godot-native multiplicative product.
	MULTIPLY,
	## Legacy/Godot-native divisor product.
	DIVIDE,
	OVERRIDE,

	## UE-compatible aggregator operations.
	MULTIPLY_ADDITIVE,
	DIVIDE_ADDITIVE,
	MULTIPLY_COMPOUND,
	ADD_FINAL,
}

## The exact attribute name in the AttributeSet (e.g. &"health" or &"mana").
## Which attribute this changes, said so it cannot mean two of them.
##
## Authoritative where it is set. `attribute_name` below stays for everything
## authored before this and is what a reference falls back to.
@export var attribute: GameplayAttributeRef = null

@export var attribute_name: StringName = &""

## How the math should be applied.
@export var operation: GameplayEffectModifier.Operation = Operation.ADD

## How much: a GameplayScalableMagnitude for the flat-or-curve case, or one
## of the other GameplayMagnitude kinds for a captured, caster-supplied or
## custom-computed value.
@export var magnitude: GameplayMagnitude = null

## Which pass of the aggregate this joins.
##
## Channels are folded in order, each one composing over what the last one
## produced. It is what lets a game say `this multiplies the buffed value,
## not the base` without every effect having to know about every other.
@export_range(0, 9, 1) var evaluation_channel: int = 0

## Tags the source must carry for this modifier to count at all.
##
## Not a condition on the effect: on this one modifier. An effect can hit
## harder against the undead and normally against everything else without
## being authored twice.
@export var source_requirements: GameplayTagQuery = null

## And the tags the target must carry.
@export var target_requirements: GameplayTagQuery = null

