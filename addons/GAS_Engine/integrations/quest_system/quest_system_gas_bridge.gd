## Carries quests into the ability system and progress back out.
##
## Both directions at once is what makes this the awkward one. A completed quest
## becomes a gameplay event; a gameplay event can be progress on a quest; and a
## designer who gives one quest overlapping tags would have the completion event
## come straight back and complete the same quest again, forever. A depth held
## across the outward call closes that door without asking anyone to configure
## their way around it - a depth rather than a flag, because a listener can
## announce a second quest from inside the first announcement.
##
## Quests are held only as they are seen. The addon's public lookup by id
## exposes operations this bridge has no business performing, so instead it
## remembers the quests the three signals actually handed it. A quest it never
## saw is one it will not act on - which is the honest answer, not a limitation
## worth working around.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name QuestSystemGasBridge extends Node

signal binding_rejected(quest_id: int)
signal quest_event_forwarded(quest_id: int, event_tag: StringName)

const AVAILABLE_SIGNAL: StringName = &"new_available_quest"
const ACCEPTED_SIGNAL: StringName = &"quest_accepted"
const COMPLETED_SIGNAL: StringName = &"quest_completed"
const UPDATE_METHOD: StringName = &"update_quest"
const COMPLETE_METHOD: StringName = &"complete_quest"
const QUEST_ID_PROPERTY: StringName = &"id"
const OBJECTIVE_COMPLETED_PROPERTY: StringName = &"objective_completed"


## Which of a quest's three announcements is being handled.
enum Moment {
	AVAILABLE,
	ACCEPTED,
	COMPLETED,
}

@export var bindings: Array[QuestGasBinding] = []

var target_asc: AbilitySystemComponent = null

var _quest_system: Node = null

## Quests this bridge has actually been handed, by id. Never invented.
var _observed: Dictionary[int, Object] = {}

## How many quest announcements are being turned into gameplay events right now.
##
## A depth, not a flag. A listener on the outward event can announce a second
## quest, and that nested forward used to lower the flag on its way out while
## the outer one was still being dispatched - so every listener after it saw
## the door standing open, and the outer completion event walked back in as
## progress on the very quest that produced it.
##
## Raising and lowering bracket one synchronous call with nothing between them
## that can return early, so the pair always balances.
var _forwarding_depth: int = 0


#region Binding
func bind(quest_system_node: Node, asc: AbilitySystemComponent) -> bool:
	if quest_system_node == null or asc == null:
		return false
	if not _bindings_are_valid():
		return false

	if not quest_system_node.has_signal(AVAILABLE_SIGNAL):
		return false
	if not quest_system_node.has_signal(ACCEPTED_SIGNAL):
		return false
	if not quest_system_node.has_signal(COMPLETED_SIGNAL):
		return false

	# Only demanded when something here would actually call them. A project that
	# never auto-completes should not need a manager that can.
	if _any_binding_auto_completes():
		if not quest_system_node.has_method(UPDATE_METHOD):
			return false
		if not quest_system_node.has_method(COMPLETE_METHOD):
			return false

	unbind()

	_quest_system = quest_system_node
	target_asc = asc
	_quest_system.connect(AVAILABLE_SIGNAL, _on_available)
	_quest_system.connect(ACCEPTED_SIGNAL, _on_accepted)
	_quest_system.connect(COMPLETED_SIGNAL, _on_completed)
	target_asc.gameplay_event_received.connect(_on_gameplay_event)
	return true


func bind_installed(tree: SceneTree, asc: AbilitySystemComponent) -> bool:
	return bind(GameplayIntegrationAvailability.quest_system_runtime(tree), asc)


## Let go of both directions, and of every quest this bridge was holding.
func unbind() -> void:
	_drop(AVAILABLE_SIGNAL, _on_available)
	_drop(ACCEPTED_SIGNAL, _on_accepted)
	_drop(COMPLETED_SIGNAL, _on_completed)
	if target_asc != null and target_asc.gameplay_event_received.is_connected(_on_gameplay_event):
		target_asc.gameplay_event_received.disconnect(_on_gameplay_event)

	_quest_system = null
	target_asc = null
	_observed.clear()


func _drop(signal_name: StringName, handler: Callable) -> void:
	if _quest_system != null and _quest_system.is_connected(signal_name, handler):
		_quest_system.disconnect(signal_name, handler)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unbind()


## Two bindings for one quest make every lookup ambiguous, so the whole
## configuration is refused rather than silently answering with the first.
func _bindings_are_valid() -> bool:
	var seen: Array[int] = []
	for binding: QuestGasBinding in bindings:
		if binding == null:
			binding_rejected.emit(0)
			return false
		if not binding.is_valid():
			binding_rejected.emit(binding.quest_id)
			return false
		if seen.has(binding.quest_id):
			binding_rejected.emit(binding.quest_id)
			return false
		seen.append(binding.quest_id)
	return true


func _any_binding_auto_completes() -> bool:
	for binding: QuestGasBinding in bindings:
		if binding != null and binding.auto_complete_on_objective_event:
			return true
	return false
#endregion


#region Quests reaching the ability system
func _on_available(quest: Object) -> void:
	_forward(quest, Moment.AVAILABLE)


func _on_accepted(quest: Object) -> void:
	_forward(quest, Moment.ACCEPTED)


func _on_completed(quest: Object) -> void:
	_forward(quest, Moment.COMPLETED)


func _forward(quest: Object, moment: QuestSystemGasBridge.Moment) -> void:
	var quest_id: int = _quest_id_of(quest)
	if quest_id <= 0:
		return

	# Remembered here and nowhere else, so the cache only ever holds quests this
	# bridge was genuinely handed.
	_observed[quest_id] = quest

	var binding: QuestGasBinding = _binding_for(quest_id)
	if binding == null:
		return
	var tag: StringName = _tag_for(binding, moment)
	if String(tag).is_empty():
		return

	# The quest object itself does not travel. Its id does, as the magnitude,
	# so a listener can tell which quest without holding a reference to it.
	var avatar: Node = target_asc.get_effect_target()
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	event.target = avatar
	event.instigator = avatar
	event.magnitude = float(quest_id)

	# Held around this call only. A completion turned into an event must not
	# arrive back at the objective listener and complete the same quest again,
	# and it must stay held while a nested announcement finishes inside it.
	_forwarding_depth += 1
	target_asc.send_gameplay_event(event)
	_forwarding_depth -= 1

	quest_event_forwarded.emit(quest_id, tag)


func _tag_for(binding: QuestGasBinding, moment: QuestSystemGasBridge.Moment) -> StringName:
	if moment == Moment.AVAILABLE:
		return binding.available_event_tag
	if moment == Moment.ACCEPTED:
		return binding.accepted_event_tag
	return binding.completed_event_tag


func _quest_id_of(quest: Object) -> int:
	if quest == null:
		return 0
	var raw: Variant = quest.get(QUEST_ID_PROPERTY)
	if raw is int:
		var quest_id: int = raw
		return quest_id
	return 0


func _binding_for(quest_id: int) -> QuestGasBinding:
	for binding: QuestGasBinding in bindings:
		if binding != null and binding.quest_id == quest_id:
			return binding
	return null
#endregion


#region Gameplay reaching the quests
func _on_gameplay_event(event: GameplayEventData) -> void:
	# The door against re-entry: this is an event still being sent outward.
	if _forwarding_depth > 0 or event == null or _quest_system == null:
		return

	for binding: QuestGasBinding in bindings:
		if binding == null or String(binding.objective_event_tag).is_empty():
			continue
		# The same hierarchy every other listener uses, asked of its owner.
		if GameplayEventRuntime.matches(event.event_tag, binding.objective_event_tag):
			_advance(binding)


func _advance(binding: QuestGasBinding) -> void:
	if not _observed.has(binding.quest_id):
		return
	var quest: Object = _observed[binding.quest_id]
	if quest == null:
		return

	if _quest_system.has_method(UPDATE_METHOD):
		_quest_system.call(UPDATE_METHOD, quest)

	if not binding.auto_complete_on_objective_event:
		return

	# Only a property the quest actually declares, and only when it is a bool.
	# Setting one that does not exist would add it, which is a different thing
	# from marking an objective done.
	if typeof(quest.get(OBJECTIVE_COMPLETED_PROPERTY)) == TYPE_BOOL:
		quest.set(OBJECTIVE_COMPLETED_PROPERTY, true)
	if _quest_system.has_method(COMPLETE_METHOD):
		_quest_system.call(COMPLETE_METHOD, quest)
#endregion
