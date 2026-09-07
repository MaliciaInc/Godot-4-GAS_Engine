## What an execution calculation produced, said in full.
##
## A dictionary of attribute-to-float could only say one thing: add this much to
## that. It could not say *how* - every delta was an addition - and it could not
## say which of two attributes called `health` it meant, on an entity carrying
## two sets that declare one. It also could not say anything that was not a
## number: that this hit should also apply a burn, or that it landed but should
## be silent because a hundred of them are landing this frame.
##
## So a calculation says all of it. A calculation that only ever added numbers
## keeps working unchanged: the legacy dictionary is adapted into this shape,
## with every entry an addition, which is what it always meant.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayExecutionOutput extends RefCounted

## One thing a calculation decided to do to one attribute.
class Modifier extends RefCounted:
	var attribute: GameplayAttributeRef = null
	var operation: GameplayEffectModifier.Operation = GameplayEffectModifier.Operation.ADD
	var magnitude: float = 0.0

var modifiers: Array[Modifier] = []

## Effects this execution decided to apply as well, once its own writes land.
##
## For a hit that also sets the target alight, where whether it does depends on
## what the calculation worked out - which is exactly what an authored
## conditional cannot express, because it runs before the numbers exist.
var conditional_effects: Array[GameplayEffect] = []

## Whether the containing effect's cues play for this application.
##
## True is what an effect has always done. False is for the case a game hits
## every frame - a hundred of them landing at once should be a hundred numbers
## and one sound.
var trigger_cues: bool = true


## One addition, which is what every entry of the old dictionary meant.
static func adding(attribute_name: StringName, magnitude: float) -> Modifier:
	var made: Modifier = Modifier.new()
	made.attribute = GameplayAttributeRef.new()
	made.attribute.attribute_name = attribute_name
	made.magnitude = magnitude
	return made


## The old return value, said in the new shape.
##
## The adapter that keeps every calculation written before this working: a
## dictionary of deltas is a list of additions, and always was.
static func from_deltas(deltas: Dictionary[StringName, float]) -> GameplayExecutionOutput:
	var made: GameplayExecutionOutput = GameplayExecutionOutput.new()
	for attribute_name: StringName in deltas:
		made.modifiers.append(adding(attribute_name, deltas[attribute_name]))
	return made
