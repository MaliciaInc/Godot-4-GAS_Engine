## An effect being edited: what is open, what may be done to it, and saving it
## back to where it came from.
##
## The editing half of the Gameplay Effect editor, with no Control in it at all.
## Split the way the Composer is split, and for the same reason: what an edit
## means is a question with a right answer, and a question with a right answer
## should be answerable without standing up a window. The screen is a projection
## of this.
##
## There is no shadow model. The thing being edited is the `GameplayEffect`
## Resource itself, edits are made on it, and saving is `ResourceSaver` writing
## that Resource back to its own path. A JSON or Dictionary intermediate would
## be a second description of an effect, and the two would disagree the first
## time somebody added a field to one of them.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GameplayEffectDocument extends RefCounted

## The effect being edited, and where it came from. Null until something is
## opened; the path is empty for an effect that lives only in memory, which is
## a legal thing to edit and an illegal thing to save.
var effect: GameplayEffect = null
var path: String = ""

## Which contracts to validate against, when the project has said.
##
## Some of what the engine refuses it refuses only under Unreal's contracts -
## a stacking effect that never answered whether the count scales it is legal
## on the native profile and a warning on the other. An editor that guessed
## would be warning about the wrong things half the time.
var profile: GameplayCompatibilityProfile = null

## Emitted whenever an edit changed the effect, so a screen can redraw without
## every edit method having to know a screen exists.
signal changed


#region Opening and saving
## Open an effect from disk.
##
## False when there is nothing at that path or what is there is not an effect.
## Nothing is opened in that case: an editor showing the last thing it opened
## while claiming to show a new one is worse than an editor showing nothing.
func open(from_path: String) -> bool:
	# Asked before loading rather than after: `load` on a path with nothing
	# at it pushes an engine error, and an editor whose open dialog can be
	# cancelled into a missing file would print one every time.
	if not ResourceLoader.exists(from_path):
		return false
	var loaded: GameplayEffect = load(from_path) as GameplayEffect
	if loaded == null:
		return false
	effect = loaded
	path = from_path
	changed.emit()
	return true


## Edit an effect that is already in hand, remembering where it came from.
##
## For the inspector, which hands over the Resource rather than a path. The path
## comes off the Resource itself when it has one, so saving still writes back to
## where it lives.
func adopt(open_effect: GameplayEffect) -> bool:
	if open_effect == null:
		return false
	effect = open_effect
	path = open_effect.resource_path
	changed.emit()
	return true


## Write it back where it came from.
##
## False for an effect with no path: that is an effect nobody chose a home for,
## and choosing one is a decision this document is not entitled to make.
func save() -> bool:
	if effect == null or path.is_empty():
		return false
	return ResourceSaver.save(effect, path) == OK


func is_open() -> bool:
	return effect != null
#endregion


#region Timing
## @composer
func set_policy(policy: GameplayEffect.DurationPolicy) -> void:
	if effect == null or effect.policy == policy:
		return
	effect.policy = policy
	changed.emit()


## How long it lasts, and how often it ticks.
##
## Clamped at zero rather than refused: a negative duration is a typo, and an
## editor that refused the keystroke would be an editor somebody cannot type a
## minus sign into on the way to a valid number.
## @composer
func set_duration(seconds: float) -> void:
	if effect == null:
		return
	effect.duration = maxf(seconds, 0.0)
	changed.emit()


## @composer
func set_period(seconds: float) -> void:
	if effect == null:
		return
	effect.period = maxf(seconds, 0.0)
	changed.emit()
#endregion


#region Modifiers
## Add one modifier row, ready to be filled in.
##
## Complete rather than empty: the whole chain - the modifier, its magnitude and
## the scalable float the magnitude reads - is what a person had to build four
## Resources for, and a row that arrived half-built would leave them building
## the other half.
## @composer
func add_modifier() -> GameplayEffectModifier:
	if effect == null:
		return null
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute = GameplayAttributeRef.new()
	var amount: GameplayScalableFloat = GameplayScalableFloat.new()
	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = amount
	modifier.magnitude = magnitude
	effect.modifiers.append(modifier)
	changed.emit()
	return modifier


## @composer
func remove_modifier(index: int) -> bool:
	if effect == null or index < 0 or index >= effect.modifiers.size():
		return false
	effect.modifiers.remove_at(index)
	changed.emit()
	return true


## Which attribute one modifier changes, said so it cannot mean two of them.
## @composer
func set_modifier_attribute(index: int, reference: GameplayAttributeRef) -> bool:
	var modifier: GameplayEffectModifier = modifier_at(index)
	if modifier == null or reference == null:
		return false
	modifier.attribute = reference
	# The legacy name is kept in step rather than left stale: everything
	# authored before typed references reads it, and two names for one
	# attribute that disagree is worse than either of them alone.
	modifier.attribute_name = reference.attribute_name
	changed.emit()
	return true


## @composer
func set_modifier_operation(
	index: int, operation: GameplayEffectModifier.Operation
) -> bool:
	var modifier: GameplayEffectModifier = modifier_at(index)
	if modifier == null:
		return false
	modifier.operation = operation
	changed.emit()
	return true


## What one modifier is worth, at level one.
##
## Written onto the scalable float the row was built with rather than replacing
## the magnitude, so a curve somebody authored on it survives being retyped.
## @composer
func set_modifier_amount(index: int, amount: float) -> bool:
	var scalable: GameplayScalableMagnitude = magnitude_at(index)
	if scalable == null or scalable.value == null:
		return false
	scalable.value.value = amount
	changed.emit()
	return true


## @composer
func set_modifier_channel(index: int, channel: int) -> bool:
	var modifier: GameplayEffectModifier = modifier_at(index)
	if modifier == null:
		return false
	modifier.evaluation_channel = clampi(channel, 0, AttributeAggregateMath.CHANNELS - 1)
	changed.emit()
	return true


func modifier_at(index: int) -> GameplayEffectModifier:
	if effect == null or index < 0 or index >= effect.modifiers.size():
		return null
	return effect.modifiers[index]


## The scalable magnitude of one row, when it has one this editor authored.
func magnitude_at(index: int) -> GameplayScalableMagnitude:
	var modifier: GameplayEffectModifier = modifier_at(index)
	if modifier == null:
		return null
	return modifier.magnitude as GameplayScalableMagnitude
#endregion


#region Components
## Add one component, unless the effect already has one the runtime would not
## read a second of.
##
## Asked of the component rather than of a list kept here, so the editor and
## the runtime cannot disagree about which kind it is.
## @composer
func add_component(component: GameplayEffectComponent) -> bool:
	if effect == null or component == null:
		return false
	if not component.allows_duplicates() and holds_kind_of(component) != null:
		return false
	effect.components.append(component)
	changed.emit()
	return true


## @composer
func remove_component(index: int) -> bool:
	if effect == null or index < 0 or index >= effect.components.size():
		return false
	effect.components.remove_at(index)
	changed.emit()
	return true


## The component already on this effect that is the same kind as `like`, or
## null. Compared by script, because that is what "the same kind" means for a
## Resource.
func holds_kind_of(like: GameplayEffectComponent) -> GameplayEffectComponent:
	if effect == null or like == null:
		return null
	var wanted: Script = like.get_script()
	for held: GameplayEffectComponent in effect.components:
		if held != null and held.get_script() == wanted:
			return held
	return null
#endregion


#region Stacking and cues
## @composer
func set_stacking(
	stacking: GameplayEffect.StackingType, limit: int = 0
) -> void:
	if effect == null:
		return
	effect.stacking_type = stacking
	effect.stack_limit_count = maxi(limit, 0)
	changed.emit()


## Bind a cue tag to one of the three moments an effect can play one.
## @composer
func add_cue(tag: StringName, type: GameplayCueBinding.Type) -> GameplayCueBinding:
	if effect == null:
		return null
	var binding: GameplayCueBinding = GameplayCueBinding.new()
	binding.cue_tag = tag
	binding.type = type
	effect.cues.append(binding)
	changed.emit()
	return binding


## @composer
func remove_cue(index: int) -> bool:
	if effect == null or index < 0 or index >= effect.cues.size():
		return false
	effect.cues.remove_at(index)
	changed.emit()
	return true
#endregion


#region What is wrong with it
## Everything the asset validator can say about what is open.
##
## The same validator the rest of the addon uses rather than a second opinion
## written for the editor: an editor that thought an effect was fine while the
## engine refused it would be worse than no editor.
func validation() -> Array[GameplayAssetValidationResult]:
	if effect == null:
		return [] as Array[GameplayAssetValidationResult]
	var found: Array[GameplayAssetValidationResult] = (
		GameplayAssetValidator.validate_effect(effect, profile)
	)
	return found
#endregion
