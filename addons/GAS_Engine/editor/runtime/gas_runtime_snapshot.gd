## One ASC, read whole - the runtime debugger's single entry point. Captures
## every per-domain snapshot in one call so a panel refresh is one read, not
## six independently-timed ones that could each see a slightly different
## moment.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasRuntimeSnapshot extends RefCounted

var asc: AbilitySystemComponent = null
var attributes: Array[GasAttributeSnapshot] = []
var tags: Array[GasTagSnapshot] = []
var effects: Array[GasEffectSnapshot] = []
var abilities: Array[GasAbilitySnapshot] = []
var tasks: Array[GasTaskSnapshot] = []
var cues: Array[GasCueSnapshot] = []
## Oldest first - GameplayEffectRuntime.refusal_log.recent() already is.
var recent_refusals: Array[GameplayEffectRefusalRecord] = []


static func capture(target_asc: AbilitySystemComponent) -> GasRuntimeSnapshot:
	var snapshot: GasRuntimeSnapshot = GasRuntimeSnapshot.new()
	snapshot.asc = target_asc
	if target_asc == null:
		return snapshot
	snapshot.attributes = GasAttributeSnapshot.capture_all(target_asc)
	snapshot.tags = GasTagSnapshot.capture_all(target_asc)
	snapshot.effects = GasEffectSnapshot.capture_all(target_asc)
	snapshot.abilities = GasAbilitySnapshot.capture_all(target_asc)
	snapshot.tasks = GasTaskSnapshot.capture_all(target_asc)
	snapshot.cues = GasCueSnapshot.capture_all(target_asc)
	snapshot.recent_refusals = target_asc.effects.refusal_log.recent()
	return snapshot
