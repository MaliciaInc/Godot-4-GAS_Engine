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

## Identity two applications are matched by to become one stack instead of
## two independent active effects.
enum StackingType {
	NONE,                 # Every application is its own independent active effect.
	AGGREGATE_BY_SOURCE,  # Same effect_def AND same source ASC join one stack.
	AGGREGATE_BY_TARGET,  # Same effect_def on this target joins one stack, any source.
}

## Whether a successful reapplication restarts a stacked effect's DURATION clock.
enum StackDurationRefreshPolicy { NEVER, ON_SUCCESSFUL_APPLICATION }

## Whether a successful reapplication restarts a stacked effect's periodic clock.
enum StackPeriodResetPolicy { NEVER, ON_SUCCESSFUL_APPLICATION }

## What happens to a stack when its clock runs out.
enum StackExpirationPolicy {
	CLEAR_ENTIRE_STACK,                       # The whole stack, all counts, is removed.
	REMOVE_SINGLE_STACK_AND_REFRESH_DURATION, # stack_count -= 1; if >0, duration restarts.
	REFRESH_DURATION,                         # count is kept; duration restarts.
}

## What a periodic effect's clock does with ticks it owed while inhibited.
enum PeriodInhibitionPolicy {
	SKIP_MISSED_TICKS, # Missed ticks are simply gone; the clock never catches up.
	EXECUTE_IMMEDIATELY_ON_UNINHIBIT, # One tick fires the moment uninhibited, if any were missed.
	RESET_PERIOD_ON_UNINHIBIT, # No catch-up tick; the period starts counting fresh from uninhibit.
}

@export_category("Effect Rules")
## How long this effect persists on the target.
@export var policy: DurationPolicy = DurationPolicy.INSTANT
## The lifespan of the effect in seconds. Only used if policy is DURATION.
@export_range(0.0, 9999.0, 0.1, "or_greater") var duration: float = 0.0: 
	set(value): 
		duration = maxf(0.0, value)
## Periodic modifiers are permanent and do NOT reverse when the effect ends.
## Note: For Turn-Based effects, set this to 1.0 to tell the system it is a DoT, not a Buff.
@export_range(0.0, 999.0, 0.1, "or_greater") var period: float = 0.0
## What ticks owed while this effect is inhibited do to the periodic clock.
@export var period_inhibition_policy: PeriodInhibitionPolicy = PeriodInhibitionPolicy.SKIP_MISSED_TICKS

@export_category("Turn Based Settings")
## How many turns this effect lasts (only used if policy is TURN_BASED).
@export_range(1, 999) var duration_turns: int = 1
## If true, periodic effects (period > 0) trigger their math and cues when the turn advances.
@export var tick_on_turn_start: bool = true

@export_category("Stacking")
## Identity two applications must share to join one stack. NONE means every
## application is its own independent active effect - the whole category
## below does not apply.
@export var stacking_type: StackingType = StackingType.NONE
## <= 0 is unlimited. Reaching this count is not itself a failure - see
## deny_overflow_application.
@export var stack_limit_count: int = 0
## False: each standard modifier contributes its single-stack magnitude.
## True: `resolved_magnitude * stack_count`, recomputed from the authored
## magnitude whenever the count changes - never an incremental delta.
@export var factor_in_stack_count: bool = false
## If true, an application that would exceed stack_limit_count is refused
## outright instead of being accepted as a non-growing refresh.
@export var deny_overflow_application: bool = false
## If true, the entire stack is removed once an overflow is decided,
## independently of deny_overflow_application.
@export var clear_stack_on_overflow: bool = false
## Applied to the same target, with derived source/context, whenever an
## application overflows this stack's limit.
@export var overflow_effects: Array[GameplayEffect] = []
## Whether a successful reapplication restarts the DURATION clock.
@export var stack_duration_refresh_policy: StackDurationRefreshPolicy = StackDurationRefreshPolicy.NEVER
## Whether a successful reapplication restarts the periodic clock.
@export var stack_period_reset_policy: StackPeriodResetPolicy = StackPeriodResetPolicy.NEVER
## What happens to the stack when its clock runs out.
@export var stack_expiration_policy: StackExpirationPolicy = StackExpirationPolicy.CLEAR_ENTIRE_STACK

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


## This effect's GameplayEffectAdditionalEffectsComponent, or null if it has
## none. At most one is expected; the first found wins.
func get_additional_effects_component() -> GameplayEffectAdditionalEffectsComponent:
	for component: GameplayEffectComponent in components:
		var additional: GameplayEffectAdditionalEffectsComponent = component as GameplayEffectAdditionalEffectsComponent
		if additional != null:
			return additional
	return null


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


## The query this effect's GameplayEffectImmunityComponent blocks incoming
## applications with, or null if it has none. At most one is expected; the
## first found wins.
func get_immunity_query() -> GameplayEffectQuery:
	for component: GameplayEffectComponent in components:
		var immunity: GameplayEffectImmunityComponent = component as GameplayEffectImmunityComponent
		if immunity != null:
			return immunity.incoming_effect_query
	return null


## The query this effect's GameplayEffectTargetTagRequirementsComponent stays
## uninhibited by, or null if it has none/never inhibits. At most one is
## expected; the first found wins.
func get_ongoing_query() -> GameplayTagQuery:
	var requirements: GameplayEffectTargetTagRequirementsComponent = _target_tag_requirements()
	return requirements.ongoing_query if requirements != null else null


## The query this effect's GameplayEffectTargetTagRequirementsComponent
## removes itself by, or null if it has none.
func get_removal_query() -> GameplayTagQuery:
	var requirements: GameplayEffectTargetTagRequirementsComponent = _target_tag_requirements()
	return requirements.removal_query if requirements != null else null


func _target_tag_requirements() -> GameplayEffectTargetTagRequirementsComponent:
	for component: GameplayEffectComponent in components:
		var requirements: GameplayEffectTargetTagRequirementsComponent = (
			component as GameplayEffectTargetTagRequirementsComponent
		)
		if requirements != null:
			return requirements
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
	if stacking_type != StackingType.NONE and not overflow_effects.is_empty():
		return true
	for component: GameplayEffectComponent in components:
		if (
			component is GameplayEffectTargetTagRequirementsComponent
			or component is GameplayEffectChanceToApplyComponent
			or component is GameplayEffectCustomCanApplyComponent
			or component is GameplayEffectRemoveOtherEffectsComponent
			or component is GameplayEffectAdditionalEffectsComponent
		):
			return true
	return false
