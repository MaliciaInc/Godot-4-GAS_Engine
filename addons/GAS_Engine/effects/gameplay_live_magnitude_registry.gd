## Keeps every persistent contribution whose GameplayAttributeBasedMagnitude
## depends on a LIVE capture updated as the attribute it reads moves.
##
## Split out of GameplayEffectRuntime the way AbilityInstancingRuntime is
## split out of AbilityRuntime: one focused collaborator instead of one file
## answering both "what effects are active" and "how a reactive subscription
## works". GameplayEffectRuntime is still the owner - this is created once by
## it and reached only through it.
##
## SNAPSHOT captures never reach this file at all: they resolved once and
## stay that way, so there is nothing here to subscribe to.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayLiveMagnitudeRegistry extends RefCounted

## Bounds an indirect cycle - A's LIVE capture depends on B, B's on A - so a
## cascade of reactive updates cannot hang the frame. A direct self-reference
## (a modifier reading LIVE the exact attribute it writes) is refused before
## it is ever evaluated once; this cap is only for a cycle that spans more
## than one attribute and so cannot be caught by that simpler check.
const MAX_REEVALUATION_PASSES: int = 64

var owner_asc: AbilitySystemComponent = null

## Back-reference to recompose through after updating a contribution's
## magnitude - the same recompose_and_emit every application already uses.
var effects: GameplayEffectRuntime = null

var _bindings: Array[GameplayLiveMagnitudeBinding] = []
var _reevaluation_depth: int = 0


#region Creation and teardown
## Scan one newly-committed (or refreshed) persistent effect for modifiers
## whose magnitude is attribute-based and LIVE, and subscribe to each one's
## observed attribute. Does nothing for a SNAPSHOT magnitude, an effect with
## no such modifiers, or one whose observed ASC cannot be resolved yet.
func create_bindings_for(active: ActiveGameplayEffect) -> void:
	var spec: GameplayEffectSpec = active.spec
	if spec == null or spec.effect_def == null:
		return

	for index: int in spec.effect_def.modifiers.size():
		var modifier: GameplayEffectModifier = spec.effect_def.modifiers[index]
		if modifier == null:
			continue
		var attribute_based: GameplayAttributeBasedMagnitude = modifier.magnitude as GameplayAttributeBasedMagnitude
		if attribute_based == null or attribute_based.capture == null:
			continue
		if attribute_based.capture.policy != GameplayAttributeCaptureDefinition.Policy.LIVE:
			continue

		var observed: AbilitySystemComponent = (
			spec.source_asc
			if attribute_based.capture.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE
			else owner_asc
		)
		if observed == null:
			continue

		_connect(active, index, modifier.attribute_name, attribute_based, observed)


func _connect(
	active: ActiveGameplayEffect,
	modifier_index: int,
	output_attribute: StringName,
	magnitude: GameplayAttributeBasedMagnitude,
	observed: AbilitySystemComponent
) -> void:
	var binding: GameplayLiveMagnitudeBinding = GameplayLiveMagnitudeBinding.new()
	binding.active_effect = active
	binding.modifier_index = modifier_index
	binding.output_attribute = output_attribute
	binding.capture = magnitude.capture
	binding.magnitude = magnitude
	binding.observed_asc = observed

	binding.attribute_changed_handler = func(
		attribute_name: StringName, _old_value: float, _new_value: float, _source_spec: GameplayEffectSpec
	) -> void:
		if attribute_name == binding.capture.attribute_name:
			_reevaluate(binding)
	observed.attribute_changed.connect(binding.attribute_changed_handler)

	# The ASC watched for this capture may go away before the effect reading
	# it does - the source despawning while its buff is still on the target,
	# say. Godot itself severs a freed Object's connections, so nothing would
	# crash; this only keeps the binding from lingering, still believing it
	# has something to watch.
	binding.tree_exiting_handler = func() -> void: _disconnect(binding)
	observed.tree_exiting.connect(binding.tree_exiting_handler)

	_bindings.append(binding)


## Every binding this effect owns, disconnected and dropped - removal,
## cleanup, or a REFRESH_DURATION reapplication about to build fresh ones for
## the same logical instance.
func disconnect_bindings_for(active: ActiveGameplayEffect) -> void:
	for binding: GameplayLiveMagnitudeBinding in _bindings.duplicate():
		if binding.active_effect == active:
			_disconnect(binding)


func _disconnect(binding: GameplayLiveMagnitudeBinding) -> void:
	_bindings.erase(binding)
	if not is_instance_valid(binding.observed_asc):
		return
	if binding.attribute_changed_handler.is_valid():
		if binding.observed_asc.attribute_changed.is_connected(binding.attribute_changed_handler):
			binding.observed_asc.attribute_changed.disconnect(binding.attribute_changed_handler)
	if binding.tree_exiting_handler.is_valid():
		if binding.observed_asc.tree_exiting.is_connected(binding.tree_exiting_handler):
			binding.observed_asc.tree_exiting.disconnect(binding.tree_exiting_handler)
#endregion


#region Reactive update
## Re-resolve one binding's magnitude and, if it still resolves, write it
## into the existing contribution and recompose once. A capture that stops
## resolving - its source gone, say - leaves the contribution at whatever it
## last resolved to, rather than blanking a buff to zero: the binding stays
## subscribed and picks the reading back up the moment it resolves again.
func _reevaluate(binding: GameplayLiveMagnitudeBinding) -> void:
	if _reevaluation_depth >= MAX_REEVALUATION_PASSES:
		if owner_asc != null:
			owner_asc.live_magnitude_cycle_aborted.emit(binding.output_attribute)
		return

	_reevaluation_depth += 1

	var spec: GameplayEffectSpec = binding.active_effect.spec
	var context: GameplayMagnitudeContext = GameplayMagnitudeContext.new()
	context.spec = spec
	context.source_asc = spec.source_asc if spec != null else null
	context.target_asc = owner_asc
	context.level = spec.level if spec != null else 1.0

	var resolved: GameplayMagnitudeResult = binding.magnitude.resolve(context)
	if resolved.is_ok():
		var contribution: AttributeModifierContribution = _find_contribution(binding)
		if contribution != null:
			contribution.magnitude = resolved.value
			if effects != null:
				effects.recompose_and_emit(spec)

	_reevaluation_depth -= 1


func _find_contribution(binding: GameplayLiveMagnitudeBinding) -> AttributeModifierContribution:
	for contribution: AttributeModifierContribution in binding.active_effect.contributed_modifiers:
		if contribution.modifier_index == binding.modifier_index:
			return contribution
	return null
#endregion
