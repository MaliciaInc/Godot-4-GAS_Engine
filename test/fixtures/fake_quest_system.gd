## A stand-in for the QuestSystem manager, carrying only its published contract.
##
## Three signals and two methods. It can also be told to announce a completion
## from inside `complete_quest`, the way a real manager does - which is exactly
## the shape that would loop forever if the bridge did not guard against
## re-entry, and so is worth being able to reproduce here.
##
## @meta_license: MIT
class_name FakeQuestSystem extends Node

signal new_available_quest(quest: Object)
signal quest_accepted(quest: Object)
signal quest_completed(quest: Object)

var updated: Array[FakeQuest] = []
var completed: Array[FakeQuest] = []

## Set true to have `complete_quest` announce what it just completed.
var announces_completion: bool = false


static func build() -> FakeQuestSystem:
	var system: FakeQuestSystem = FakeQuestSystem.new()
	system.name = "QuestSystem"
	return system


#region What the bridge calls
func update_quest(quest: FakeQuest) -> void:
	updated.append(quest)


func complete_quest(quest: FakeQuest) -> void:
	completed.append(quest)
	if announces_completion:
		quest_completed.emit(quest)
#endregion


#region What the game does
func offer(quest: FakeQuest) -> void:
	new_available_quest.emit(quest)


func accept(quest: FakeQuest) -> void:
	quest_accepted.emit(quest)


func finish(quest: FakeQuest) -> void:
	quest_completed.emit(quest)
#endregion
