## Wait until an ability pays for itself.
##
## Activation and commitment are different moments, and the gap between them is
## where a cost is refused. An ability that reacts to another one starting - a
## counter, a shield that goes up when its owner casts - reacts to the wrong
## moment if it waits on activation: the caster may still be about to fail the
## cost, and the reaction has already happened.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitAbilityCommit extends GameplayAbilityTask

var target_asc: AbilitySystemComponent = null

## Which grant to watch, or an invalid handle for "any of them".
var watched: GameplayAbilityHandle = null

## What the commit that woke this said, so a waiter can act on the reason
## rather than only on the fact.
var result: AbilityCommitResult = null
var committed_handle: GameplayAbilityHandle = null


static func create(
	ability: GameplayAbility,
	handle: GameplayAbilityHandle = null,
	target: AbilitySystemComponent = null
) -> AbilityTaskWaitAbilityCommit:
	var task: AbilityTaskWaitAbilityCommit = AbilityTaskWaitAbilityCommit.new()
	task.owner_ability = ability
	task.watched = handle
	task.target_asc = target if target != null else (ability.owner_asc if ability != null else null)
	return task


func _on_start() -> void:
	if target_asc != null:
		target_asc.ability_committed.connect(_on_committed)


func _on_finish() -> void:
	if target_asc != null and target_asc.ability_committed.is_connected(_on_committed):
		target_asc.ability_committed.disconnect(_on_committed)


func _on_committed(handle: GameplayAbilityHandle, committed: AbilityCommitResult) -> void:
	if not _matches(handle):
		return
	committed_handle = handle
	result = committed
	succeed()


## No handle, or an invalid one, is the "any of them" the field above promises.
## Otherwise the two have to name the same grant, which a handle answers with
## `same_as` - the method it actually has.
func _matches(handle: GameplayAbilityHandle) -> bool:
	if watched == null or not watched.is_valid():
		return true
	return handle != null and handle.same_as(watched)
