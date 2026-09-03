## What one quest means to the ability system, in both directions.
##
## Outward: which gameplay event to send when the quest becomes available, is
## accepted, or is completed. Inward: which event, arriving from anywhere, counts
## as progress on it.
##
## Every tag is optional. An empty one means "say nothing at that moment", which
## is different from saying something nobody listens to - a designer who wants
## only completion to matter leaves the other three blank and gets silence.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name QuestGasBinding extends Resource

## The quest this speaks for. Ids start at one, so zero means unset.
@export var quest_id: int = 0

@export var available_event_tag: StringName = &""
@export var accepted_event_tag: StringName = &""
@export var completed_event_tag: StringName = &""

## An event matching this - hierarchically, like any other listener - is progress
## on the quest.
@export var objective_event_tag: StringName = &""

## Whether that progress finishes the quest outright.
@export var auto_complete_on_objective_event: bool = false


func is_valid() -> bool:
	return quest_id > 0
