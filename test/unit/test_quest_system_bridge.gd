## The QuestSystem bridge, which runs in both directions at once.
##
## That is what makes it the awkward one. A completed quest becomes a gameplay
## event, a gameplay event can be progress on a quest, and a designer who gives
## one quest overlapping tags would have the completion come straight back and
## complete the same quest again, forever. The last test in this file is the one
## that matters most: it builds exactly that configuration on purpose.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const System = preload("res://test/fixtures/fake_quest_system.gd")
const Quest = preload("res://test/fixtures/fake_quest.gd")

const QUEST_ID: int = 7
const OTHER_ID: int = 9
const UNKNOWN_ID: int = 99
const AVAILABLE_TAG: StringName = &"Event.Quest.Available"
const ACCEPTED_TAG: StringName = &"Event.Quest.Accepted"
const COMPLETED_TAG: StringName = &"Event.Quest.Completed"
const OBJECTIVE_TAG: StringName = &"Event.Quest.Objective"
const OBJECTIVE_CHILD: StringName = &"Event.Quest.Objective.WolfSlain"

var fixture: ASCFixture = null
var system: FakeQuestSystem = null
var bridge: QuestSystemGasBridge = null

var forwarded: Array[StringName] = []
var rejected: Array[int] = []


func before_each() -> void:
	fixture = Fixture.create("Adventurer")
	system = System.build()
	bridge = QuestSystemGasBridge.new()
	_enter_the_tree()
	_start_recording()


func _enter_the_tree() -> void:
	add_child_autofree(fixture.owner)
	add_child_autofree(system)
	add_child_autofree(bridge)


## Listen to what the bridge announces, and start each test from silence.
func _start_recording() -> void:
	bridge.quest_event_forwarded.connect(_on_forwarded)
	bridge.binding_rejected.connect(_on_rejected)
	forwarded = []
	rejected = []


func after_each() -> void:
	fixture = null
	system = null
	bridge = null


#region Building
func _on_forwarded(_quest_id: int, event_tag: StringName) -> void:
	forwarded.append(event_tag)


func _on_rejected(quest_id: int) -> void:
	rejected.append(quest_id)


## A binding that speaks at all three moments and listens for progress.
func _binding(quest_id: int) -> QuestGasBinding:
	var binding: QuestGasBinding = QuestGasBinding.new()
	binding.quest_id = quest_id
	binding.available_event_tag = AVAILABLE_TAG
	binding.accepted_event_tag = ACCEPTED_TAG
	binding.completed_event_tag = COMPLETED_TAG
	binding.objective_event_tag = OBJECTIVE_TAG
	return binding


func _bind_with(entries: Array[QuestGasBinding]) -> bool:
	bridge.bindings = entries
	return bridge.bind(system, fixture.asc)


func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	return event
#endregion


#region Binding
func test_binding_needs_a_manager_and_an_asc() -> void:
	bridge.bindings = [_binding(QUEST_ID)]
	assert_false(bridge.bind(null, fixture.asc), "no manager")
	assert_false(bridge.bind(system, null), "nobody to speak for")


func test_binding_to_a_node_that_is_not_a_manager_is_refused() -> void:
	var stranger: Node = Node.new()
	add_child_autofree(stranger)
	bridge.bindings = [_binding(QUEST_ID)]
	assert_false(bridge.bind(stranger, fixture.asc), "it announces none of the three")


func test_two_bindings_for_one_quest_are_refused() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID), _binding(QUEST_ID)]
	assert_false(_bind_with(entries), "which of the two would a lookup mean?")
	assert_eq(rejected, [QUEST_ID] as Array[int], "and it said which quest was ambiguous")


func test_a_binding_without_a_quest_id_is_refused() -> void:
	var entries: Array[QuestGasBinding] = [QuestGasBinding.new()]
	assert_false(_bind_with(entries), "a binding for no quest binds nothing")


## Auto-completion is the only thing that needs the manager's two methods, so
## only a configuration that uses it demands them.
func test_only_auto_completing_bindings_demand_the_manager_methods() -> void:
	var plain: Node = Node.new()
	plain.add_user_signal(String(QuestSystemGasBridge.AVAILABLE_SIGNAL))
	plain.add_user_signal(String(QuestSystemGasBridge.ACCEPTED_SIGNAL))
	plain.add_user_signal(String(QuestSystemGasBridge.COMPLETED_SIGNAL))
	add_child_autofree(plain)

	bridge.bindings = [_binding(QUEST_ID)]
	assert_true(bridge.bind(plain, fixture.asc), "signals alone are enough without it")

	var demanding: QuestGasBinding = _binding(QUEST_ID)
	demanding.auto_complete_on_objective_event = true
	bridge.bindings = [demanding]
	assert_false(bridge.bind(plain, fixture.asc), "but not once something must complete quests")
#endregion


#region Quests reaching the ability system
func test_each_of_the_three_moments_sends_its_own_event() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))
	var quest: FakeQuest = Quest.build(QUEST_ID)

	system.offer(quest)
	system.accept(quest)
	system.finish(quest)

	assert_eq(
		forwarded,
		[AVAILABLE_TAG, ACCEPTED_TAG, COMPLETED_TAG] as Array[StringName],
		"three announcements, three events, in order"
	)


func test_an_empty_tag_says_nothing_at_that_moment() -> void:
	var quiet: QuestGasBinding = _binding(QUEST_ID)
	quiet.available_event_tag = &""
	var entries: Array[QuestGasBinding] = [quiet]
	assert_true(_bind_with(entries))

	system.offer(Quest.build(QUEST_ID))

	assert_eq(forwarded.size(), 0, "silence is a configuration, not an omission")


func test_a_quest_nothing_binds_is_ignored() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))

	system.offer(Quest.build(UNKNOWN_ID))

	assert_eq(forwarded.size(), 0, "no binding, nothing to say")


## The quest object does not travel; its id does, so a listener can tell which
## quest without being handed a reference to it.
func test_the_event_carries_the_quest_id_and_not_the_quest() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))
	watch_signals(fixture.asc)

	system.accept(Quest.build(QUEST_ID))

	assert_signal_emitted(fixture.asc, "gameplay_event_received", "the ASC heard it")
	assert_eq(forwarded, [ACCEPTED_TAG] as Array[StringName], "under the bound tag")
#endregion


#region Gameplay reaching the quests
func test_an_objective_event_updates_a_quest_the_bridge_has_seen() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))
	var quest: FakeQuest = Quest.build(QUEST_ID)
	system.accept(quest)

	fixture.asc.send_gameplay_event(_event(OBJECTIVE_TAG))

	assert_eq(system.updated, [quest] as Array[FakeQuest], "the quest it was handed was advanced")


## The hierarchy is the engine's, asked of its owner rather than reimplemented.
func test_a_more_specific_objective_event_still_counts() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))
	var quest: FakeQuest = Quest.build(QUEST_ID)
	system.accept(quest)

	fixture.asc.send_gameplay_event(_event(OBJECTIVE_CHILD))

	assert_eq(system.updated.size(), 1, "a child of the objective tag is progress on it")


## A quest the bridge was never handed is not invented from its id.
func test_an_unseen_quest_is_not_advanced() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))

	fixture.asc.send_gameplay_event(_event(OBJECTIVE_TAG))

	assert_eq(system.updated.size(), 0, "nothing to advance, and nothing made up")


func test_auto_completion_marks_the_objective_and_completes_the_quest() -> void:
	var finishing: QuestGasBinding = _binding(QUEST_ID)
	finishing.auto_complete_on_objective_event = true
	var entries: Array[QuestGasBinding] = [finishing]
	assert_true(_bind_with(entries))
	var quest: FakeQuest = Quest.build(QUEST_ID)
	system.accept(quest)

	fixture.asc.send_gameplay_event(_event(OBJECTIVE_TAG))

	assert_true(quest.objective_completed, "the property it declares was set")
	assert_eq(system.completed, [quest] as Array[FakeQuest], "and the manager was told to finish")
#endregion


#region Not eating itself
## The configuration that would loop: one quest whose completion event is also
## its objective event, auto-completing, on a manager that announces what it
## completes.
##
## Without the guard, completing sends the event, the event is read as progress,
## progress completes the quest, and so on until the stack gives out. A designer
## can reach this arrangement without doing anything obviously wrong, so the
## bridge closes it rather than documenting it.
func test_a_completion_that_looks_like_progress_does_not_loop() -> void:
	var overlapping: QuestGasBinding = _binding(QUEST_ID)
	overlapping.completed_event_tag = OBJECTIVE_TAG
	overlapping.auto_complete_on_objective_event = true
	var entries: Array[QuestGasBinding] = [overlapping]
	assert_true(_bind_with(entries))
	system.announces_completion = true
	var quest: FakeQuest = Quest.build(QUEST_ID)
	system.accept(quest)

	system.finish(quest)

	assert_eq(system.completed.size(), 0, "the outward event did not come back as progress")
	assert_eq(forwarded, [ACCEPTED_TAG, OBJECTIVE_TAG] as Array[StringName], "and it settled")


## Progress arriving from elsewhere still completes, and still settles.
func test_progress_from_outside_completes_once_and_settles() -> void:
	var overlapping: QuestGasBinding = _binding(QUEST_ID)
	overlapping.completed_event_tag = OBJECTIVE_TAG
	overlapping.auto_complete_on_objective_event = true
	var entries: Array[QuestGasBinding] = [overlapping]
	assert_true(_bind_with(entries))
	system.announces_completion = true
	system.accept(Quest.build(QUEST_ID))

	fixture.asc.send_gameplay_event(_event(OBJECTIVE_TAG))

	assert_eq(system.completed.size(), 1, "completed exactly once")
#endregion


#region Letting go
func test_unbinding_disconnects_both_directions() -> void:
	var entries: Array[QuestGasBinding] = [_binding(QUEST_ID)]
	assert_true(_bind_with(entries))
	var quest: FakeQuest = Quest.build(QUEST_ID)
	system.accept(quest)
	forwarded = []

	bridge.unbind()
	system.accept(quest)
	fixture.asc.send_gameplay_event(_event(OBJECTIVE_TAG))

	assert_eq(forwarded.size(), 0, "quests no longer reach the ability system")
	assert_eq(system.updated.size(), 0, "and gameplay no longer reaches the quests")
	assert_null(bridge.target_asc, "and the bridge holds nobody")


func test_an_absent_quest_system_binds_quietly() -> void:
	bridge.bindings = [_binding(OTHER_ID)]
	assert_false(
		bridge.bind_installed(get_tree(), fixture.asc),
		"QuestSystem is not installed here, so there is nothing to bind to"
	)
#endregion
