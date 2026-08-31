## A declarative filter over an ASC's active effects: every field configured
## is AND'd together, and an empty query matches everything.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectQuery extends Resource

enum InhibitionFilter {
	ANY,
	ACTIVE_ONLY,
	INHIBITED_ONLY,
}

@export var effect_definition: GameplayEffect = null
@export var asset_tags: GameplayTagQuery = null
@export var granted_tags: GameplayTagQuery = null
@export var source_tags: GameplayTagQuery = null
@export var target_tags: GameplayTagQuery = null
@export var modified_attribute: StringName = &""
@export var inhibition: InhibitionFilter = InhibitionFilter.ANY

## Filters by who caused the application. Runtime-only: never authored on
## the Resource, set by whoever builds the query at the call site.
var source: Node = null


func is_empty() -> bool:
	return (
		effect_definition == null
		and (asset_tags == null or asset_tags.is_empty())
		and (granted_tags == null or granted_tags.is_empty())
		and (source_tags == null or source_tags.is_empty())
		and (target_tags == null or target_tags.is_empty())
		and modified_attribute == &""
		and inhibition == InhibitionFilter.ANY
		and source == null
	)


## `target_asc` is the ASC `active` actually lives on - needed because an
## ActiveGameplayEffect has no back-reference to its own owner, and
## target_tags must read that owner's tags live, not a snapshot.
func matches(active: ActiveGameplayEffect, target_asc: AbilitySystemComponent) -> bool:
	if active == null or active.spec == null or active.get_effect_def() == null:
		return false
	if effect_definition != null and active.get_effect_def() != effect_definition:
		return false
	if source != null and active.get_instigator() != source:
		return false
	if inhibition == InhibitionFilter.INHIBITED_ONLY:
		# Inhibition does not exist yet (Task 11): nothing is ever inhibited.
		return false
	if asset_tags != null and not asset_tags.matches_tags(active.spec.get_asset_tags()):
		return false
	if granted_tags != null and not granted_tags.matches_tags(active.granted_tags):
		return false
	if source_tags != null and not source_tags.matches_tags(active.spec.source_tags_snapshot):
		return false
	if target_tags != null and target_asc != null and not target_tags.matches_runtime(target_asc.tags):
		return false
	if modified_attribute != &"" and not _modifies_attribute(active.get_effect_def(), modified_attribute):
		return false
	return true


## True if `attribute_name` is written by a standard modifier or is declared
## as an execution's output. Advisory metadata only - an execution with no
## declared outputs is never run just to find out what it might change.
static func _modifies_attribute(effect: GameplayEffect, attribute_name: StringName) -> bool:
	for modifier: GameplayEffectModifier in effect.modifiers:
		if modifier != null and modifier.attribute_name == attribute_name:
			return true
	for execution: GameplayExecutionCalculation in effect.executions:
		if execution != null and execution.declared_output_attributes().has(attribute_name):
			return true
	return false
