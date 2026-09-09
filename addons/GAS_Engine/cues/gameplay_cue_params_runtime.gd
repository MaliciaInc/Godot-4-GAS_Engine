## Everything a cue is told, assembled in one place.
##
## Split out of GameplayEffectRuntime the same way the inhibition, stacking and
## chain runtimes were: that file commits transactions, and this answers a
## different question - what does the thing about to play need to know. The two
## were one function until a cue could read a number off the target, and the
## moment it could, filling that in was three decisions rather than six
## assignments.
##
## Reads only. Nothing here writes an attribute, registers a contribution or
## touches an active effect, which is the property that makes it safe to call
## from a removal path where the effect being announced is already gone.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueParamsRuntime extends RefCounted

## Wired alongside everything else in AbilitySystemComponent._wire_runtimes().
var effects: GameplayEffectRuntime = null


## The parameters for one cue of one application.
##
## `binding` is null only for a caller that has a tag and no authoring behind
## it - a prediction rolling a cue back, say - and such a cue gets the effect's
## level, which is what every cue received before a binding could say otherwise.
func params_for(
	cue_tag: StringName,
	spec: GameplayEffectSpec,
	effect_handle: GameplayEffectHandle = null,
	binding: GameplayCueBinding = null
) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = cue_tag
	params.instigator = spec.context.instigator if spec.context != null else null
	params.target = effects.owner_asc.get_effect_target()
	params.context = spec.context
	params.effect_handle = effect_handle
	params.stack_count = spec.stack_count
	var aimed: GameplayAbilityTargetData = (
		spec.context.target_data if spec.context != null else null
	)
	params.target_hit = aimed.first_hit_for(params.target) if aimed != null else null

	params.effect_level = spec.level
	params.ability_level = _ability_level_behind(spec)
	params.source_tags = spec.source_tags_snapshot.duplicate()
	params.target_tags = (
		effects.tags.active_tags() if effects.tags != null else ([] as Array[StringName])
	)
	if spec.context != null:
		params.causer = spec.context.causer
		params.source_object = spec.context.source_object
	_read_magnitude(params, spec, binding)
	return params


## What the cue's number is, and the range it is read against.
##
## A binding naming an attribute is asking about the target as it is now - a
## shield that flickers harder the lower it is is about the shield, not about
## whatever effect fired the cue. With no attribute named, the number is the
## effect's level, which is what every cue authored before this received.
func _read_magnitude(
	params: GameplayCueParams, spec: GameplayEffectSpec, binding: GameplayCueBinding
) -> void:
	if binding == null:
		params.set_magnitude(spec.level)
		return
	var reference: GameplayAttributeRef = binding.magnitude_attribute
	if reference == null or not reference.is_valid() or effects.attributes == null:
		params.set_magnitude(spec.level, binding.min_level, binding.max_level)
		return
	var attribute: AttributeData = effects.attributes.find_by_ref(reference)
	var reading: float = attribute.current_value if attribute != null else 0.0
	params.set_magnitude(reading, binding.min_level, binding.max_level)


## What the ability behind this application was activated at, or zero.
##
## Asked of the source rather than of the target: the ability that caused this
## is granted on whoever cast it, and a target holding an ability of the same
## kind would answer with its own level.
func _ability_level_behind(spec: GameplayEffectSpec) -> float:
	if spec.context == null or spec.context.ability_handle == null:
		return 0.0
	if spec.source_asc == null:
		return 0.0
	var granted: GameplayAbilitySpec = spec.source_asc.get_ability_spec(
		spec.context.ability_handle
	)
	return granted.level if granted != null else 0.0
