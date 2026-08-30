## Granted abilities, the activation gate and input routing.
##
## The gate answers one question - may this ability run right now - and reports
## why not through a closed enum rather than a message string, so a UI can react
## to "on cooldown" differently from "not enough mana" without parsing English.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityRuntime extends RefCounted

## Why an activation was refused. Closed: a caller switching over this cannot
## silently miss a reason added later.
enum ActivationError {
	NONE,
	ALREADY_ACTIVE,
	ON_COOLDOWN,
	BLOCKED_TAG,
	MISSING_TAG,
	INSUFFICIENT_RESOURCES,
	INTERNAL_ERROR,
}

var owner_asc: AbilitySystemComponent = null
var tags: GameplayTagRuntime = null

## Every task any granted ability is currently waiting on.
var tasks: AbilityTaskRuntime = AbilityTaskRuntime.new()

var _abilities: Array[GameplayAbility] = []
var _held_inputs: Array[int] = []


#region Registry
## Every granted ability, as a copy, for the same reason the effects are.
func abilities() -> Array[GameplayAbility]:
	return _abilities.duplicate()


func grant(ability: GameplayAbility) -> void:
	if ability == null:
		return
	if not ability.is_inside_tree() and owner_asc != null:
		owner_asc.add_child(ability)
	ability.owner_asc = owner_asc
	if not _abilities.has(ability):
		_abilities.append(ability)


func remove(ability: GameplayAbility) -> void:
	if ability == null:
		return
	# A removed ability must not outlive its own activation. Freeing the node
	# mid-cast left `ability_ended` unfired, so anything waiting on it waited
	# forever, and the commit that activation had made was never forgotten.
	if ability.is_active:
		ability.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
	# Asked again even when the ability was not active: a task that outlived a
	# closed activation is exactly the inconsistency removal has to clear.
	tasks.cancel_for_ability(ability, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
	_abilities.erase(ability)
	# Cleared after the abort, not before: the abort still needs the owner it
	# is ending against.
	ability.owner_asc = null
	ability.queue_free()


## Abort every running ability without freeing anything. Used by cleanup, which
## must leave the ASC in a state a second cleanup can safely see.
func abort_all(reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED) -> void:
	for ability: GameplayAbility in _abilities.duplicate():
		if is_instance_valid(ability) and ability.is_active:
			ability.abort_ability(reason)
	# Whatever is still running belonged to an activation that had already
	# closed. Teardown has to leave nothing behind, so those go too.
	tasks.cancel_all(reason)


func clear() -> void:
	_abilities.clear()
	_held_inputs.clear()
#endregion


#region Activation gate
## Whether an ability may activate, and why not when it may not.
##
## Returns the reason rather than a bare bool so the caller emits one signal
## carrying the cause. Upstream emitted from inside each branch, which meant the
## gate could not be asked a question without also announcing the answer.
func activation_error(ability: GameplayAbility) -> ActivationError:
	if ability == null:
		return ActivationError.INTERNAL_ERROR
	if ability.is_active:
		return ActivationError.ALREADY_ACTIVE
	if tags.has_any(ability.activation_blocked_tags):
		return ActivationError.BLOCKED_TAG
	if tags.has_any(ability.get_cooldown_tags()):
		return ActivationError.ON_COOLDOWN
	if not tags.has_all(ability.activation_required_tags):
		return ActivationError.MISSING_TAG
	if owner_asc != null and not ability.costs.is_empty():
		# The same resolver commit_ability() uses, so a preview here and the
		# charge commit_ability() actually takes can never disagree.
		var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
			ability.costs, owner_asc, ability.ability_level
		)
		if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
			return ActivationError.INSUFFICIENT_RESOURCES
		if resolved.status != GameplayResolvedCost.Status.OK:
			return ActivationError.INTERNAL_ERROR
	return ActivationError.NONE


func can_activate(ability: GameplayAbility) -> bool:
	return activation_error(ability) == ActivationError.NONE


## Abort any running ability that carries one of these tags, or that these tags
## would block.
func cancel_with_tags(cancel_tags: Array[StringName]) -> void:
	for ability: GameplayAbility in _abilities:
		if not ability.is_active:
			continue
		for tag: StringName in cancel_tags:
			if ability.ability_tag == tag or ability.activation_blocked_tags.has(tag):
				ability.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
				break
#endregion


#region Input routing
## Bind an ability to an input slot.
##
## `unbind_others` releases any other ability holding that slot, so two
## abilities can never both answer one press.
func bind_to_input(ability: GameplayAbility, input_id: int, unbind_others: bool = true) -> bool:
	if not _abilities.has(ability):
		push_error("GodotGAS: cannot bind an ability that was never granted to this ASC.")
		return false

	if unbind_others:
		for other: GameplayAbility in _abilities:
			if other != ability and other.input_id == input_id:
				other.input_id = -1

	ability.input_id = input_id
	return true


## The slots currently held down, as a copy: a caller clearing this would
## leave the runtime believing nothing is pressed.
func held_inputs() -> Array[int]:
	return _held_inputs.duplicate()


func input_pressed(input_id: int) -> void:
	if not _held_inputs.has(input_id):
		_held_inputs.append(input_id)
	# Formal tasks hear the transition before an active ability's ad hoc hooks.
	# If a task ends the ability the hook below no longer runs, which is the
	# point: one press must not both finish a cast and be re-read by it.
	tasks.input_pressed(input_id)
	# Snapshot: an ability that grants another one on press must not have its
	# new sibling receive the same press.
	for ability: GameplayAbility in _abilities.duplicate():
		if is_instance_valid(ability) and ability.input_id == input_id:
			ability._input_pressed(owner_asc)


func input_released(input_id: int) -> void:
	_held_inputs.erase(input_id)
	tasks.input_released(input_id)
	for ability: GameplayAbility in _abilities.duplicate():
		if is_instance_valid(ability) and ability.input_id == input_id:
			ability._input_released(owner_asc)
#endregion


#region Ability tasks
## Small pass-throughs. The task runtime owns the tasks; this only forwards,
## so one place decides what still running means.
func register_task(task: GameplayAbilityTask) -> GameplayAbilityTask:
	return tasks.register(task)


func cancel_tasks_for_ability(ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason) -> void:
	tasks.cancel_for_ability(ability, reason)


func submit_target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	tasks.target_data(ability, data)


func advance_time(delta: float) -> void:
	tasks.advance_time(delta)
#endregion
