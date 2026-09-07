## Running an effect's execution calculations, and aiming what they decided.
##
## An execution used to answer with a dictionary of attribute-to-float, and the
## evaluator turned every entry into "add this much to that". That is one
## sentence, and the interesting calculations need more of them: which of two
## same-named attributes they meant, whether their number multiplies rather than
## adds, what else should happen now that the numbers exist, and whether any of
## it should make a sound.
##
## Kept apart from GameplayEffectEvaluator because the evaluator's job is
## staging - turning decided values into writes nobody has committed yet - and
## this is the part that decides them. Static and stateless, so asking the same
## question twice gives the same answer both times.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayExecutionPipeline extends RefCounted


## Run every execution of one spec and merge what they decided into one answer.
##
## Through `execute_typed()`, whose default adapts a calculation that only knows
## how to return deltas - so an engine with both kinds of calculation in it
## still has exactly one path through here.
static func run(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayExecutionOutput:
	var merged: GameplayExecutionOutput = GameplayExecutionOutput.new()
	for execution: GameplayExecutionCalculation in spec.effect_def.executions:
		if execution == null:
			continue
		var produced: GameplayExecutionOutput = execution.execute_typed(spec, target_asc)
		if produced == null:
			continue
		merged.modifiers.append_array(produced.modifiers)
		merged.conditional_effects.append_array(produced.conditional_effects)
		# Silence is unanimous: one execution asking for quiet is enough, since
		# the alternative is the loudest calculation in an effect deciding for
		# every other one.
		merged.trigger_cues = merged.trigger_cues and produced.trigger_cues
	return merged


## The first write this entity has no attribute for, or null when all of them
## land somewhere.
##
## Two ways to name nothing. A reference carrying a set is asked of that set, so
## an execution meaning the vehicle's `health` is refused where there is no
## vehicle rather than quietly writing the driver's. A bare one is the name it
## always was.
static func first_unresolved(
	produced: GameplayExecutionOutput, attributes: GameplayAttributeRuntime
) -> GameplayAttributeRef:
	for modifier: GameplayExecutionOutput.Modifier in produced.modifiers:
		var reference: GameplayAttributeRef = modifier.attribute
		if reference == null or not reference.is_valid():
			return GameplayAttributeRef.new()
		if reference.set_name != &"":
			if attributes.find_by_ref(reference) == null:
				return reference
		elif not attributes.has(reference.attribute_name):
			return reference
	return null


## What the executions decided, said in the currency the aggregate speaks.
##
## Every write keeps its position, so two writes to one attribute are ordered by
## the sequence the calculation produced them in rather than by their values.
## They all land in channel zero: an execution writes the durable base, and
## channels order passes over a value, which a base is not.
##
## Never scaled by stack count. A standard modifier is scaled for its author
## because a stack of two is twice the buff; a calculation reads `stack_count`
## itself and decides what two of it means, and scaling on top of that would
## apply the stack twice.
static func writes_of(
	produced: GameplayExecutionOutput, application_order: int
) -> Array[AttributeModifierContribution]:
	var writes: Array[AttributeModifierContribution] = []
	for index: int in produced.modifiers.size():
		var modifier: GameplayExecutionOutput.Modifier = produced.modifiers[index]
		if modifier == null or modifier.attribute == null:
			continue
		var write: AttributeModifierContribution = AttributeModifierContribution.new()
		write.attribute_name = modifier.attribute.attribute_name
		write.operation = modifier.operation
		write.magnitude = modifier.magnitude
		write.modifier_index = index
		write.application_order = application_order
		writes.append(write)
	return writes


## Every attribute these writes touch, in the order they were first named.
static func attributes_of(
	writes: Array[AttributeModifierContribution]
) -> Array[StringName]:
	var names: Array[StringName] = []
	for write: AttributeModifierContribution in writes:
		if not names.has(write.attribute_name):
			names.append(write.attribute_name)
	return names


## What one attribute is worth once these writes have had their say.
##
## Folded by the arithmetic every other contribution is folded by, in this
## entity's own profile of it: an execution that multiplies is a multiply under
## whichever algebra the entity composes with, never a third one written here.
## An attribute none of the writes name comes back as its own base, which is
## what the fold of an empty list means.
static func compose(
	attributes: GameplayAttributeRuntime,
	attribute_name: StringName,
	writes: Array[AttributeModifierContribution],
	unreal: bool
) -> AttributeAggregateMath.Composed:
	var base: float = attributes.get_base_value(attribute_name)
	if unreal:
		return AttributeAggregateMath.unreal(base, attribute_name, writes)
	return AttributeAggregateMath.godot_native(base, attribute_name, writes)
