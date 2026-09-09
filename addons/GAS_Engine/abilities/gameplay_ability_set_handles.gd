## The receipt for a granted loadout, and the only way to take one back.
##
## `undo_steps` is the authority, not the three typed arrays beside it. Those
## exist so a caller can ask what was granted; the steps are what retirement
## walks, in the exact reverse of the order things were published.
##
## Grouping by kind - all the effects, then all the abilities - would be the
## inverse of a sequence nobody performed, and it goes wrong the first time a
## set publishes an effect that grants an ability: retiring the abilities first
## retires one the effect is about to retire again, and retiring the effects
## first retires an ability that is not there any more.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilitySetHandles extends RefCounted

## What one published thing was.
enum Kind { ABILITY, EFFECT, ATTRIBUTE_SET }

## Which component this receipt is about. A receipt from one entity cannot
## retire anything on another, which matters because a loadout Resource is
## granted to every character in a game.
var owner_asc: AbilitySystemComponent = null

var ability_handles: Array[GameplayAbilityHandle] = []
var effect_handles: Array[GameplayEffectHandle] = []
var attribute_set_handles: Array[RegisteredAttributeSetHandle] = []

## What was published, in order. Appended immediately after each success, so a
## failure part-way through has an exact inverse to walk.
var undo_steps: Array[Dictionary] = []

var taken_back: bool = false

## The two keys of an undo step. Namespaced, because `kind` and `handle` are
## words other files use for their own unrelated purposes and a key that
## collides with one of those is a rename waiting to break a receipt.
const STEP_KIND: String = "step.kind"
const STEP_HANDLE: String = "step.handle"


## Record one thing that was just published.
func published(kind: GameplayAbilitySetHandles.Kind, handle: Variant) -> void:
	undo_steps.append({STEP_KIND: kind, STEP_HANDLE: handle})
	match kind:
		Kind.ABILITY:
			ability_handles.append(handle)
		Kind.EFFECT:
			effect_handles.append(handle)
		Kind.ATTRIBUTE_SET:
			attribute_set_handles.append(handle)


## Take the whole loadout off, newest first.
##
## Continues through a step whose handle was already retired by something else -
## a game is allowed to remove one ability of a kit - because stopping there
## would leave the rest of the kit on. A second call does nothing and says so.
func take_back() -> bool:
	if taken_back:
		return true
	if owner_asc == null or not is_instance_valid(owner_asc):
		return false

	for index: int in range(undo_steps.size() - 1, -1, -1):
		_undo(undo_steps[index])

	taken_back = true
	return true


func _undo(step: Dictionary) -> void:
	var kind: GameplayAbilitySetHandles.Kind = step[STEP_KIND]
	match kind:
		Kind.ABILITY:
			owner_asc.remove_ability_handle(step[STEP_HANDLE])
		Kind.EFFECT:
			owner_asc.remove_active_effect_by_handle(step[STEP_HANDLE])
		Kind.ATTRIBUTE_SET:
			owner_asc.unregister_attribute_set(step[STEP_HANDLE])
