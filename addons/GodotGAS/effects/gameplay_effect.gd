## The core data asset that defines a buff, debuff, or instant change in the game.
##
## Game Designers create instances of this Resource to build out the game's skills.
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayEffect extends Resource

## Defines the lifecycle behavior of the effect.
enum DurationPolicy { 
	INSTANT, # Applies math immediately and vanishes. Cannot grant tags. (e.g., Fireball Damage)
	DURATION, # Applies math/tags for X seconds, then undoes them. (e.g., 5-second Poison)
	INFINITE, # Applies math/tags permanently until explicitly removed. (e.g., Equipped Ring) 
	TURN_BASED # Applies math/tags for X turns, handled discretely by an external Turn Manager.
}

## Defines the stacking behaviour for the effect.
enum StackingPolicy { 
	FREE,             # Can have infinite overlapping instances of this effect.
	REFRESH_DURATION  # If applied again, resets the timer of the existing instance instead of adding a new one.
}

@export_category("Effect Rules")
## How this effect behaves if it is applied while already active on the target.
## FREE = multiple unique stacks, REFRESH_DURATION will refresh existing
## NOTE: Does not override or decide 'if' a effect stacks
@export var stacking_policy: StackingPolicy = StackingPolicy.FREE
## How long this effect persists on the target.
@export var policy: DurationPolicy = DurationPolicy.INSTANT
## The lifespan of the effect in seconds. Only used if policy is DURATION.
@export_range(0.0, 9999.0, 0.1, "or_greater") var duration: float = 0.0: 
	set(value): 
		duration = maxf(0.0, value)
## Periodic modifiers are permanent and do NOT reverse when the effect ends.
## Note: For Turn-Based effects, set this to 1.0 to tell the system it is a DoT, not a Buff.
@export_range(0.0, 999.0, 0.1, "or_greater") var period: float = 0.0

@export_category("Turn Based Settings")
## How many turns this effect lasts (only used if policy is TURN_BASED).
@export_range(1, 999) var duration_turns: int = 1
## If true, periodic effects (period > 0) trigger their math and cues when the turn advances.
@export var tick_on_turn_start: bool = true

@export_category("Cue Management")
## Cues that play exactly once when the effect is first applied to a target.
@export var application_cue_tags: Array[StringName] = []
## Cues that play every time a periodic tick occurs.
@export var periodic_cue_tags: Array[StringName] = []

@export_category("Attribute Modifiers")
## Custom mathematical scripts that run complex logic (e.g., Damage = Attack - Defense).
@export var executions: Array[GameplayExecutionCalculation] = []
## A list of simple mathematical changes this effect applies to the target's AttributeSets.
@export var modifiers: Array[GameplayEffectModifier] = []

@export_category("Event Management")
## Tags broadcasted directly to the target's ASC as Gameplay Events upon application (or periodic tick).
## Ideal for waking up reactive passive abilities (e.g., 'Event.Damage.Taken').
@export var event_tags: Array[StringName] = []

@export_category("Components")
## Orthogonal, reusable pieces of this effect's behaviour: asset tags, target
## tags, application tag requirements, chance to apply, a custom can-apply
## requirement, UI data. Each component is immutable authored data; none of
## it may hold per-application state. See GameplayEffectComponent.
@export var components: Array[GameplayEffectComponent] = []


## Every asset tag declared by this effect's GameplayEffectAssetTagsComponent
## entries. Descriptive metadata, never granted to a target.
func get_asset_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	for component: GameplayEffectComponent in components:
		var asset_component: GameplayEffectAssetTagsComponent = component as GameplayEffectAssetTagsComponent
		if asset_component != null:
			tags.append_array(asset_component.asset_tags)
	return tags


## Every tag this effect grants to its target, declared by its
## GameplayEffectTargetTagsComponent entries.
func get_granted_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	for component: GameplayEffectComponent in components:
		var target_component: GameplayEffectTargetTagsComponent = component as GameplayEffectTargetTagsComponent
		if target_component != null:
			tags.append_array(target_component.granted_tags)
	return tags


## The query this effect's GameplayEffectRemoveOtherEffectsComponent purges
## by, or null if it has none. At most one is expected; the first found wins.
func get_remove_other_effects_query() -> GameplayEffectQuery:
	for component: GameplayEffectComponent in components:
		var remover: GameplayEffectRemoveOtherEffectsComponent = (
			component as GameplayEffectRemoveOtherEffectsComponent
		)
		if remover != null:
			return remover.query
	return null


## Whether applying this can be noticed by anything except the attributes it
## moves and the tags it grants.
##
## An execution, a purge, a cue or an event is an observable side effect that
## undoing the application cannot take back. Anything that has to stay reversible
## asks this first: a commit that may be refused partway through, and equipment
## that may fail before it has finished being granted.
func is_silent() -> bool:
	if not (
		is_zero_approx(period)
		and executions.is_empty()
		and application_cue_tags.is_empty()
		and periodic_cue_tags.is_empty()
		and event_tags.is_empty()
	):
		return false
	return not _has_observable_component()


## AssetTags, TargetTags (their refcount is reversible), and UIData never
## make an application observable beyond the attributes it moves and the
## tags it grants - the same ground is_silent() already covers. Anything that
## can refuse, roll, purge, or otherwise decide during application can.
func _has_observable_component() -> bool:
	for component: GameplayEffectComponent in components:
		if (
			component is GameplayEffectTargetTagRequirementsComponent
			or component is GameplayEffectChanceToApplyComponent
			or component is GameplayEffectCustomCanApplyComponent
			or component is GameplayEffectRemoveOtherEffectsComponent
		):
			return true
	return false
