## A read-only picture of one active effect, for the runtime debugger.
##
## A thin reader over ActiveGameplayEffect - every field here already exists
## there; this only flattens spec.duration/remaining_turns/period and adds
## get_instigator() as source, so the debugger's view model does not have to
## reach through .spec itself.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GasEffectSnapshot extends RefCounted

var handle: GameplayEffectHandle = null
var definition: GameplayEffect = null
var source: Node = null
var duration: float = 0.0
var remaining_turns: int = 0
var period: float = 0.0
var inhibited: bool = false
var stack_count: int = 1
var asset_tags: Array[StringName] = []
var granted_tags: Array[StringName] = []
var modifiers: Array[AttributeModifierContribution] = []
var component_states: Array[GameplayEffectComponentState] = []
var persistent_cue_handles: Array[GameplayCueHandle] = []
var granted_ability_handles: Array[GameplayAbilityHandle] = []


static func capture_all(asc: AbilitySystemComponent) -> Array[GasEffectSnapshot]:
	var snapshots: Array[GasEffectSnapshot] = []
	if asc == null:
		return snapshots
	for active: ActiveGameplayEffect in asc.effects.active_effects():
		snapshots.append(_capture_one(active))
	return snapshots


static func _capture_one(active: ActiveGameplayEffect) -> GasEffectSnapshot:
	var snapshot: GasEffectSnapshot = GasEffectSnapshot.new()
	snapshot.handle = active.handle
	snapshot.definition = active.get_effect_def()
	snapshot.source = active.get_instigator()
	snapshot.duration = active.time_remaining
	snapshot.remaining_turns = active.spec.remaining_turns if active.spec != null else 0
	snapshot.period = active.spec.period if active.spec != null else 0.0
	snapshot.inhibited = active.inhibited
	snapshot.stack_count = active.stack_count
	snapshot.asset_tags = active.spec.get_asset_tags() if active.spec != null else []
	snapshot.granted_tags = active.granted_tags.duplicate()
	snapshot.modifiers = active.contributed_modifiers.duplicate()
	snapshot.component_states = active.component_states.duplicate()
	snapshot.persistent_cue_handles = active.persistent_cue_handles.duplicate()
	snapshot.granted_ability_handles = active.granted_ability_handles.duplicate()
	return snapshot
