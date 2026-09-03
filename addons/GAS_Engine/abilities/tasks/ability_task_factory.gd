## Factories for Task 18's task library: validate the owner, create, register
## on the owner's task runtime, return the task - the same four-step contract
## `GameplayAbility._own()` already applies to the F2 factories.
##
## A static namespace rather than more `GameplayAbility` instance methods:
## that file is already at the project's own LOC ceiling, and a dozen more
## one-line wrappers there would only distinguish these tasks from the F2
## ones by which file happens to hold them. Called as
## `AbilityTaskFactory.wait_tag_added(self, tag)` from inside an ability.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskFactory extends RefCounted


static func _own(ability: GameplayAbility, task: GameplayAbilityTask) -> GameplayAbilityTask:
	if task == null or ability == null or ability.owner_asc == null:
		return null
	return ability.owner_asc.register_ability_task(task)


#region Attributes
static func wait_attribute_change(
	ability: GameplayAbility, attribute: StringName, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitAttributeChange:
	return _own(
		ability, AbilityTaskWaitAttributeChange.create(ability, attribute, target_asc)
	) as AbilityTaskWaitAttributeChange


static func wait_attribute_threshold(
	ability: GameplayAbility,
	attribute: StringName,
	threshold: float,
	comparison: AbilityTaskWaitAttributeThreshold.Comparison,
	trigger_immediately_if_already_true: bool = false
) -> AbilityTaskWaitAttributeThreshold:
	return _own(
		ability,
		AbilityTaskWaitAttributeThreshold.create(
			ability, attribute, threshold, comparison, trigger_immediately_if_already_true
		)
	) as AbilityTaskWaitAttributeThreshold
#endregion


#region Tags
static func wait_tag_added(
	ability: GameplayAbility, tag: StringName, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitTagAdded:
	return _own(ability, AbilityTaskWaitTagAdded.create(ability, tag, target_asc)) as AbilityTaskWaitTagAdded


static func wait_tag_removed(
	ability: GameplayAbility, tag: StringName, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitTagRemoved:
	return _own(
		ability, AbilityTaskWaitTagRemoved.create(ability, tag, target_asc)
	) as AbilityTaskWaitTagRemoved


static func wait_tag_query(
	ability: GameplayAbility,
	query: GameplayTagQuery,
	desired: bool = true,
	target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitTagQuery:
	return _own(
		ability, AbilityTaskWaitTagQuery.create(ability, query, desired, target_asc)
	) as AbilityTaskWaitTagQuery
#endregion


#region Gameplay effects
static func wait_gameplay_effect_applied(
	ability: GameplayAbility,
	query: GameplayEffectQuery,
	target_asc: AbilitySystemComponent = null,
	include_periodic: bool = false,
	trigger_once: bool = true
) -> AbilityTaskWaitGameplayEffectApplied:
	return _own(
		ability,
		AbilityTaskWaitGameplayEffectApplied.create(ability, query, target_asc, include_periodic, trigger_once)
	) as AbilityTaskWaitGameplayEffectApplied


static func wait_gameplay_effect_removed(
	ability: GameplayAbility, handle: GameplayEffectHandle, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectRemoved:
	return _own(
		ability, AbilityTaskWaitGameplayEffectRemoved.create(ability, handle, target_asc)
	) as AbilityTaskWaitGameplayEffectRemoved


static func wait_gameplay_effect_removed_matching(
	ability: GameplayAbility, query: GameplayEffectQuery, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectRemoved:
	return _own(
		ability, AbilityTaskWaitGameplayEffectRemoved.create_matching(ability, query, target_asc)
	) as AbilityTaskWaitGameplayEffectRemoved


static func wait_gameplay_effect_stack_change(
	ability: GameplayAbility, handle: GameplayEffectHandle, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitGameplayEffectStackChange:
	return _own(
		ability, AbilityTaskWaitGameplayEffectStackChange.create(ability, handle, target_asc)
	) as AbilityTaskWaitGameplayEffectStackChange
#endregion


#region Abilities
static func wait_ability_activated(
	ability: GameplayAbility, handle: GameplayAbilityHandle, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityActivated:
	return _own(
		ability, AbilityTaskWaitAbilityActivated.create(ability, handle, target_asc)
	) as AbilityTaskWaitAbilityActivated


static func wait_ability_activated_matching(
	ability: GameplayAbility, query: GameplayTagQuery, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityActivated:
	return _own(
		ability, AbilityTaskWaitAbilityActivated.create_matching(ability, query, target_asc)
	) as AbilityTaskWaitAbilityActivated


static func wait_ability_ended(
	ability: GameplayAbility, handle: GameplayAbilityHandle, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityEnded:
	return _own(
		ability, AbilityTaskWaitAbilityEnded.create(ability, handle, target_asc)
	) as AbilityTaskWaitAbilityEnded


static func wait_ability_ended_matching(
	ability: GameplayAbility, query: GameplayTagQuery, target_asc: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityEnded:
	return _own(
		ability, AbilityTaskWaitAbilityEnded.create_matching(ability, query, target_asc)
	) as AbilityTaskWaitAbilityEnded
#endregion


#region Confirm/cancel, repeat, animation
static func wait_confirm_cancel(
	ability: GameplayAbility, confirm_input_id: int, cancel_input_id: int
) -> AbilityTaskWaitConfirmCancel:
	return _own(
		ability, AbilityTaskWaitConfirmCancel.create(ability, confirm_input_id, cancel_input_id)
	) as AbilityTaskWaitConfirmCancel


static func repeat(
	ability: GameplayAbility, interval_seconds: float, repetitions: int = 0
) -> AbilityTaskRepeat:
	return _own(
		ability, AbilityTaskRepeat.create(ability, interval_seconds, repetitions)
	) as AbilityTaskRepeat


static func play_animation_and_wait(
	ability: GameplayAbility,
	player: AnimationPlayer,
	animation: StringName,
	stop_on_cancel: bool = false
) -> AbilityTaskPlayAnimationAndWait:
	return _own(
		ability, AbilityTaskPlayAnimationAndWait.create(ability, player, animation, stop_on_cancel)
	) as AbilityTaskPlayAnimationAndWait
#endregion
