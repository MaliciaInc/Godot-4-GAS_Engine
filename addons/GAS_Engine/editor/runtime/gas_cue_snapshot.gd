## A read-only picture of one running persistent cue, for the runtime
## debugger.
##
## GameplayCueManager keeps no public registry of its own active persistent
## cues - ActiveGameplayEffect.persistent_cue_handles already is that
## registry, zipped by index against its effect's own
## get_persistent_cue_bindings() the same way
## GameplayEffectInhibitionRuntime._deactivate_persistent_cues() resolves a
## handle's cue_tag for removal. This reuses that exact join rather than
## asking the manager for a second one.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GasCueSnapshot extends RefCounted

var persistent_handle: GameplayCueHandle = null
var tag: StringName = &""
var target: Node = null
var owning_effect_handle: GameplayEffectHandle = null
## GameplayCueManager.get_pooled_count(tag) - the pool this cue's tag draws
## from, not a count of this one instance.
var pooled_count: int = 0


static func capture_all(asc: AbilitySystemComponent) -> Array[GasCueSnapshot]:
	var snapshots: Array[GasCueSnapshot] = []
	if asc == null:
		return snapshots
	var target: Node = asc.get_effect_target()
	# get_node_or_null, never the bare autoload identifier - the same guard
	# AbilitySystemComponent's own _cue_manager() uses, for an asc that may
	# be outside the tree by the time a debugger snapshot reads it.
	var manager: Node = asc.get_node_or_null(GameplayCueManager.AUTOLOAD_NODE_PATH) if asc.is_inside_tree() else null
	for active: ActiveGameplayEffect in asc.effects.active_effects():
		var effect: GameplayEffect = active.get_effect_def()
		if effect == null or active.persistent_cue_handles.is_empty():
			continue
		var bindings: Array[GameplayCueBinding] = effect.get_persistent_cue_bindings()
		for index: int in active.persistent_cue_handles.size():
			if index >= bindings.size():
				break
			snapshots.append(_capture_one(active, bindings[index], index, target, manager))
	return snapshots


static func _capture_one(
	active: ActiveGameplayEffect, binding: GameplayCueBinding, index: int, target: Node, manager: Node
) -> GasCueSnapshot:
	var snapshot: GasCueSnapshot = GasCueSnapshot.new()
	snapshot.persistent_handle = active.persistent_cue_handles[index]
	snapshot.tag = binding.cue_tag
	snapshot.target = target
	snapshot.owning_effect_handle = active.handle
	@warning_ignore_start("unsafe_method_access")
	snapshot.pooled_count = manager.get_pooled_count(binding.cue_tag) if manager != null else 0
	@warning_ignore_restore("unsafe_method_access")
	return snapshot
