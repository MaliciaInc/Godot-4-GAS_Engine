## A read-only picture of one active tag, for the runtime debugger.
##
## Hierarchy is derived from the dotted name at display time, not stored
## here - GameplayTagRuntime has no tree of its own, only refcounts.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GasTagSnapshot extends RefCounted

var tag: StringName = &""
var count: int = 0

## Active effects actually granting this exact tag right now - never inferred,
## only what the runtime itself can point to. Empty does not mean "nothing
## granted it": an ability's activation-owned tag has no ActiveGameplayEffect
## behind it at all, and this never invents one.
##
## An inhibited effect is left out. `granted_tags` stays populated while
## inhibited - it is the receipt uninhibiting puts back - so reading it alone
## named an effect that was granting nothing, and a tag one effect held came up
## as granted by two. The count beside the list said one, which is the whole
## point of a debugger reading badly.
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
			if active.state_attached and active.granted_tags.has(tag):
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
