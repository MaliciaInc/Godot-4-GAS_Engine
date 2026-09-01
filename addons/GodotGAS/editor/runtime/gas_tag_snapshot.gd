## A read-only picture of one active tag, for the runtime debugger.
##
## Hierarchy is derived from the dotted name at display time, not stored
## here - GameplayTagRuntime has no tree of its own, only refcounts.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GasTagSnapshot extends RefCounted

var tag: StringName = &""
var count: int = 0

## Active effects whose granted_tags name this exact tag - never inferred,
## only what the runtime itself can point to. Empty does not mean "nothing
## granted it": an ability's activation-owned tag has no ActiveGameplayEffect
## behind it at all, and this never invents one.
var granting_effect_handles: Array[GameplayEffectHandle] = []

## True while some currently-active ability instance holds this tag as one
## of its own activation_owned_tags.
var is_activation_owned: bool = false


static func capture_all(asc: AbilitySystemComponent) -> Array[GasTagSnapshot]:
	var snapshots: Array[GasTagSnapshot] = []
	if asc == null:
		return snapshots
	var active_effects: Array[ActiveGameplayEffect] = asc.effects.active_effects()
	var owned_tags: Array[StringName] = _activation_owned_tags(asc)
	for tag: StringName in asc.tags.active_tags():
		var snapshot: GasTagSnapshot = GasTagSnapshot.new()
		snapshot.tag = tag
		snapshot.count = asc.tags.count(tag)
		snapshot.is_activation_owned = owned_tags.has(tag)
		for active: ActiveGameplayEffect in active_effects:
			if active.granted_tags.has(tag):
				snapshot.granting_effect_handles.append(active.handle)
		snapshots.append(snapshot)
	return snapshots


## Every activation_owned_tags entry belonging to a spec with something
## running right now - the same condition
## AbilityTagSemanticsRuntime.set_activation_owned_tags() itself grants under.
static func _activation_owned_tags(asc: AbilitySystemComponent) -> Array[StringName]:
	var owned: Array[StringName] = []
	for spec: GameplayAbilitySpec in asc.ability_runtime.specs():
		if spec.definition == null or spec.active_count <= 0:
			continue
		for tag: StringName in spec.definition.activation_owned_tags:
			if not owned.has(tag):
				owned.append(tag)
	return owned
