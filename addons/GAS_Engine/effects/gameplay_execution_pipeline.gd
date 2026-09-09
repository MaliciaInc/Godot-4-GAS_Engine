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
		# One context per calculation, dropped when it returns. Shared between
		# two of them it would be a channel one execution could leave a number
		# in for the next, which is the thing scratch space must not become.
		var context: GameplayExecutionContext = _context_for(execution, spec, target_asc)
		var produced: GameplayExecutionOutput = execution.execute_in(context)
		if produced == null:
			continue
		merged.modifiers.append_array(produced.modifiers)
		merged.conditional_effects.append_array(produced.conditional_effects)
		# Silence is unanimous: one execution asking for quiet is enough, since
		# the alternative is the loudest calculation in an effect deciding for
		# every other one.
		merged.trigger_cues = merged.trigger_cues and produced.trigger_cues
		# And so is saying the stack was counted: an effect where one
		# calculation did it by hand cannot have the factor applied to the
		# merged answer without applying it twice to that one's share.
		merged.stack_count_handled_manually = (
			merged.stack_count_handled_manually or produced.stack_count_handled_manually
		)
	return merged


## The context one calculation runs in: what it was told, an empty scratch
## space, and whichever of its scoped adjustments both sides qualify for.
static func _context_for(
	execution: GameplayExecutionCalculation,
	spec: GameplayEffectSpec,
	target_asc: AbilitySystemComponent
) -> GameplayExecutionContext:
	var context: GameplayExecutionContext = GameplayExecutionContext.new()
	context.spec = spec
	context.source_asc = spec.source_asc
	context.target_asc = target_asc
	context.passed_in_tags = spec.passed_in_tags.duplicate()
	for modifier: GameplayExecutionScopedModifier in execution.scoped_modifiers():
		if _scope_qualifies(modifier, spec, target_asc):
			context.scoped.append(modifier)
	return context


## Whether both sides are what this adjustment requires them to be.
##
## The source is read from the spec's snapshot, the target live, for the
## reason an attribute-based magnitude reads them that way: the caster is
## being asked about the moment the effect was made, and the target about the
## moment it is landing.
static func _scope_qualifies(
	modifier: GameplayExecutionScopedModifier,
	spec: GameplayEffectSpec,
	target_asc: AbilitySystemComponent
) -> bool:
	if modifier == null:
		return false
	var wanted_source: GameplayTagQuery = modifier.source_requirements
	if wanted_source != null and not wanted_source.is_empty():
		if not wanted_source.matches_tags(spec.source_tags_snapshot):
			return false
	var wanted_target: GameplayTagQuery = modifier.target_requirements
	if wanted_target != null and not wanted_target.is_empty():
		if target_asc == null or not wanted_target.matches_runtime(target_asc.tags):
			return false
	return true


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
## Scaled by stack count only where the reference scales it.
##
## Under Unreal's contracts an execution's numbers are multiplied by how many
## of the effect are on the target, and a calculation that has already
## counted them says so with `stack_count_handled_manually`. The native
## profile has never scaled an execution and does not start: a calculation
## there reads `stack_count` and decides for itself what two of it means, and
## a factor applied on top would be the stack counted twice.
static func writes_of(
	produced: GameplayExecutionOutput,
	application_order: int,
	stack_count: int = 1,
	unreal: bool = false
) -> Array[AttributeModifierContribution]:
	var factor: int = (
		stack_count
		if unreal and not produced.stack_count_handled_manually
		else 1
	)
	var writes: Array[AttributeModifierContribution] = []
	for index: int in produced.modifiers.size():
		var modifier: GameplayExecutionOutput.Modifier = produced.modifiers[index]
		if modifier == null or modifier.attribute == null:
			continue
		var write: AttributeModifierContribution = AttributeModifierContribution.new()
		write.attribute_name = modifier.attribute.attribute_name
		write.operation = modifier.operation
		write.magnitude = AttributeAggregateMath.stack_scaled(
			modifier.magnitude, factor, modifier.operation, unreal
		)
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
