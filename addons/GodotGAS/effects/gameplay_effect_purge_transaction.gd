## A provisional purge of `remove_effects_with_tags`, reversible until the
## incoming effect's own outcome is known.
##
## `GameplayEffectRuntime.apply()` promises a refusal is total: nothing
## observable happens. Purging before evaluating the incoming effect broke
## that promise, because the purge itself is observable - it drops tags and
## contributions and moves attributes - and an incoming effect that then
## failed left the purge applied anyway. The fix is not to purge after
## evaluating: the incoming is meant to see the state the purge leaves
## behind, not the state before it. So the purge still runs first, but stays
## reversible until the incoming effect's outcome is known.
##
## Owns no permanent registry. Everything needed to restore what it touched
## lives in the snapshot one instance holds for the one `apply()` call that
## created it.
##
## An effect matching more than one purge tag is removed once, in one pass
## over the registry in reverse order - the same order a single purge tag
## alone would have used. This differs from the old per-tag loop only when
## several purge tags and several effects interleave, which nothing in this
## codebase authors or tests; the one-pass shape is simpler and was not worth
## complicating to reproduce an unobserved corner of the old ordering.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectPurgeTransaction extends RefCounted

## What removing one grant of one tag, from one purged effect, found. Captured
## at detach time because the tag registry may have moved again by the time
## commit() or rollback() runs.
class TagRemoval extends RefCounted:
	var tag: StringName = &""
	var change: GameplayTagRuntime.Change = GameplayTagRuntime.Change.NONE
	var count_after: int = 0

var _runtime: GameplayEffectRuntime = null

## The effects removed, and the index each was removed from - so a rollback
## reinserts in the order that reconstructs the original array, not merely one
## that contains the same members.
var _removed: Array[ActiveGameplayEffect] = []
var _removed_at: Array[int] = []

var _tag_removals: Array[TagRemoval] = []
var _attribute_mutations: Array[AttributeMutationResult] = []

## True once commit() or rollback() has run, or immediately for a transaction
## that had nothing to purge. Guards both against running twice.
var _resolved: bool = false


#region Begin
## Detach every active effect granting any of `purge_tags`, silently: no
## signal fires until commit() says the incoming effect actually happened.
static func begin(
	runtime: GameplayEffectRuntime, purge_tags: Array[StringName]
) -> GameplayEffectPurgeTransaction:
	var transaction: GameplayEffectPurgeTransaction = GameplayEffectPurgeTransaction.new()
	transaction._runtime = runtime
	if purge_tags.is_empty():
		transaction._resolved = true
		return transaction

	var live: Array[ActiveGameplayEffect] = runtime.live_active_effects()
	for index: int in range(live.size() - 1, -1, -1):
		var active: ActiveGameplayEffect = live[index]
		if not _grants_any(active, purge_tags):
			continue
		transaction._removed.append(active)
		transaction._removed_at.append(index)
		for tag: StringName in active.granted_tags:
			transaction._tag_removals.append(_remove_one_tag(runtime, tag))
		runtime.attributes.remove_contributions_of(active.application_order)
		runtime.extract_active(active)

	if transaction._removed.is_empty():
		transaction._resolved = true
		return transaction

	# Recomposed now, not merely staged: an evaluation that reads current_value
	# right after this - the whole reason the purge runs before the incoming is
	# evaluated - has to see the post-purge numbers, whether or not this
	# transaction is ultimately kept.
	transaction._attribute_mutations = runtime.attributes.recompose_all()
	return transaction


static func _remove_one_tag(runtime: GameplayEffectRuntime, tag: StringName) -> TagRemoval:
	var removal: TagRemoval = TagRemoval.new()
	removal.tag = tag
	removal.change = runtime.tags.remove(tag)
	removal.count_after = runtime.tags.count(tag)
	return removal


static func _grants_any(active: ActiveGameplayEffect, purge_tags: Array[StringName]) -> bool:
	for tag: StringName in purge_tags:
		if active.granted_tags.has(tag):
			return true
	return false
#endregion


#region Resolve
## The incoming effect succeeded, by refresh or by full application. Announce
## exactly what detaching already decided, once each, in the order it
## happened - the same signals an ordinary `remove()` of each effect would
## have produced.
func commit() -> void:
	if _resolved:
		return
	_resolved = true

	var owner_asc: AbilitySystemComponent = _runtime.owner_asc
	for removal: TagRemoval in _tag_removals:
		if owner_asc != null:
			owner_asc.emit_tag_change(removal.tag, removal.change, removal.count_after)
	for mutation: AttributeMutationResult in _attribute_mutations:
		if mutation.current_changed and owner_asc != null:
			owner_asc.emit_attribute_changed(mutation, null)
	for active: ActiveGameplayEffect in _removed:
		active.granted_tags.clear()
		active.contributed_modifiers.clear()
		if owner_asc != null:
			owner_asc.active_effect_removed.emit(active)


## The incoming effect failed. Put every purged effect back exactly as found -
## the same objects, holding the same tag and contribution lists they were
## never actually cleared of, at the same position - then recompose silently.
## Nothing this transaction did is observable.
func rollback() -> void:
	if _resolved:
		return
	_resolved = true

	for removal: TagRemoval in _tag_removals:
		_runtime.tags.add(removal.tag)
	for i: int in range(_removed.size() - 1, -1, -1):
		var active: ActiveGameplayEffect = _removed[i]
		_runtime.attributes.add_contributions(active.contributed_modifiers)
		_runtime.restore_active(active, _removed_at[i])
	if not _removed.is_empty():
		_runtime.attributes.recompose_all()
#endregion
