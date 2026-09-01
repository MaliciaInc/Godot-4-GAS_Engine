## A read-only picture of one attribute, for the runtime debugger.
##
## Pure reader: nothing here recomputes the canonical formula. base/current
## come straight from AttributeData, and contributions are the same
## AttributeModifierContribution objects the aggregator already holds -
## joined against the owning ActiveGameplayEffect here only to add
## effect_handle/effect_definition/stack_factor, which the aggregator itself
## has no reason to carry.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GasAttributeSnapshot extends RefCounted

## One contribution, with the active effect it belongs to resolved in.
class Contribution extends RefCounted:
	var effect_handle: GameplayEffectHandle = null
	var effect_definition: GameplayEffect = null
	var modifier_index: int = -1
	var operation: GameplayEffectModifier.Operation = GameplayEffectModifier.Operation.ADD
	var magnitude: float = 0.0
	var application_order: int = -1
	## 1 when the effect does not factor_in_stack_count, else its stack_count -
	## the multiplier already baked into `magnitude`, named for the reader.
	var stack_factor: int = 1


var attribute_set: AttributeSet = null
var attribute_name: StringName = &""
var base_value: float = 0.0
var current_value: float = 0.0
## An inhibited effect's contributions are already absent from the
## aggregator by the time this reads it - GameplayEffectInhibitionRuntime
## detaches them - so this never needs to filter them out itself.
var contributions: Array[Contribution] = []


## Every attribute on `asc`, in declaration order.
static func capture_all(asc: AbilitySystemComponent) -> Array[GasAttributeSnapshot]:
	var snapshots: Array[GasAttributeSnapshot] = []
	if asc == null:
		return snapshots
	var active: Array[ActiveGameplayEffect] = asc.effects.active_effects()
	for attribute_name: StringName in asc.attributes.all_attribute_names():
		snapshots.append(_capture_one(asc, attribute_name, active))
	return snapshots


static func _capture_one(
	asc: AbilitySystemComponent, attribute_name: StringName, active: Array[ActiveGameplayEffect]
) -> GasAttributeSnapshot:
	var snapshot: GasAttributeSnapshot = GasAttributeSnapshot.new()
	snapshot.attribute_set = asc.attributes.find_set(attribute_name)
	snapshot.attribute_name = attribute_name
	snapshot.base_value = asc.get_attribute_base(attribute_name)
	snapshot.current_value = asc.get_attribute_current(attribute_name)
	for source: AttributeModifierContribution in asc.attributes.contributions_for(attribute_name):
		snapshot.contributions.append(_capture_contribution(source, active))
	return snapshot


static func _capture_contribution(
	source: AttributeModifierContribution, active: Array[ActiveGameplayEffect]
) -> Contribution:
	var contribution: Contribution = Contribution.new()
	contribution.modifier_index = source.modifier_index
	contribution.operation = source.operation
	contribution.magnitude = source.magnitude
	contribution.application_order = source.application_order
	for candidate: ActiveGameplayEffect in active:
		if candidate.application_order != source.application_order:
			continue
		contribution.effect_handle = candidate.handle
		contribution.effect_definition = candidate.get_effect_def()
		var effect: GameplayEffect = candidate.get_effect_def()
		contribution.stack_factor = candidate.stack_count if effect != null and effect.factor_in_stack_count else 1
		break
	return contribution
