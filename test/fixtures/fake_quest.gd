## A stand-in for a QuestSystem quest.
##
## An id and a flag, because those are the only two members the bridge is
## allowed to touch. Everything else a real quest carries - objectives, rewards,
## its own state machine - belongs to the addon that owns it.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name FakeQuest extends RefCounted

var id: int = 0

## The one property the bridge writes, and only after checking it exists and is
## a bool. Setting a property that does not exist would create it, which is a
## different thing from marking an objective done.
var objective_completed: bool = false


static func build(quest_id: int) -> FakeQuest:
	var quest: FakeQuest = FakeQuest.new()
	quest.id = quest_id
	return quest
