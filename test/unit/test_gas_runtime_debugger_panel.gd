## The runtime debugger's tab in the editor's Debugger dock.
##
## The plugin that makes the tab cannot be built outside the editor, so the tab
## is driven the way the plugin drives it: handed what a running game sends,
## through a log, and asked what it shows. The messages are built by the game's
## own half, `GasDebugChannel.snapshot_of()`, so a key spelled differently at the
## two ends fails here rather than drawing an empty tab.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const BURNING: StringName = &"Status.Burning"
const SOMEONE_ELSE: int = 42

var fixture: ASCFixture = null
var reported: GasRuntimeDebuggerLog = null
var panel: GasRuntimeDebuggerPanel = null


func before_each() -> void:
	fixture = Fixture.create("Watched")
	add_child_autofree(fixture.owner)
	fixture.asc.set_process(false)
	reported = GasRuntimeDebuggerLog.new()
	panel = GasRuntimeDebuggerPanel.new(reported)
	add_child_autofree(panel)


func after_each() -> void:
	fixture = null
	reported = null
	panel = null


#region Getting there
## What the game sends about one component, taken the way the plugin takes it.
func _game_sends_snapshot_of(component: AbilitySystemComponent) -> void:
	var understood: bool = reported.take(
		GasDebugMessage.SNAPSHOT, [GasDebugChannel.snapshot_of(component)]
	)
	assert_true(understood, "the snapshot was understood")


func _game_sends_trace(subject: String, asc_id: int) -> void:
	reported.take(GasDebugMessage.TRACE, [{
		GasDebugMessage.KIND: int(GasDebugMessage.Kind.TAG_COUNT_CHANGED),
		GasDebugMessage.ASC_ID: asc_id,
		GasDebugMessage.SUBJECT: subject,
		GasDebugMessage.DETAIL: "",
	}])


func _rows_drawn() -> int:
	var root: TreeItem = panel.table().get_root()
	return root.get_child_count() if root != null else 0


func _tags_page() -> int:
	for index: int in panel.pages().size():
		if panel.pages()[index] is GasDebugPageTags:
			return index
	return -1
#endregion


#region What the tab shows
## Before the game says anything, nobody is listed and nothing is drawn.
func test_a_tab_nobody_has_reported_to_lists_nobody() -> void:
	panel.refresh()

	assert_eq(panel.entity_names().size(), 0, "no entity is listed")
	assert_eq(panel.selected(), 0, "none is chosen")
	assert_eq(_rows_drawn(), 0, "and the table has no rows")


## An entity the game reported is listed by the name it goes by, and drawn.
func test_a_reported_entity_is_listed_and_its_attributes_drawn() -> void:
	_game_sends_snapshot_of(fixture.asc)

	panel.refresh()

	assert_eq(panel.entity_names(), PackedStringArray(["Watched"]), "listed by its name")
	assert_eq(panel.selected(), fixture.asc.get_instance_id(), "and chosen, being the only one")
	var expected: int = GasDebugPageAttributes.new().rows(reported.snapshot(panel.selected())).size()
	assert_gt(expected, 0, "the fixture has attributes to show")
	assert_eq(_rows_drawn(), expected, "one row for each")


## The tab draws the latest thing the game said about an entity, not the first.
func test_the_tab_draws_what_the_latest_snapshot_says() -> void:
	_game_sends_snapshot_of(fixture.asc)
	assert_true(panel.show_page(_tags_page()), "the tags page is there")
	assert_eq(_rows_drawn(), 0, "nothing is held yet")

	fixture.asc.add_tag(BURNING)
	_game_sends_snapshot_of(fixture.asc)
	panel.refresh()

	assert_gt(_rows_drawn(), 0, "the tag the next snapshot carried is drawn")


## Choosing another entity draws that one, and an unreported one cannot be chosen.
func test_choosing_another_entity_draws_that_one() -> void:
	var other: ASCFixture = Fixture.create("Other")
	add_child_autofree(other.owner)
	other.asc.add_tag(BURNING)
	_game_sends_snapshot_of(fixture.asc)
	_game_sends_snapshot_of(other.asc)
	panel.show_page(_tags_page())

	assert_true(panel.select(other.asc.get_instance_id()), "the other entity can be chosen")
	assert_gt(_rows_drawn(), 0, "and its tags are drawn")
	assert_true(panel.select(fixture.asc.get_instance_id()), "and the first again")
	assert_eq(_rows_drawn(), 0, "which holds none")
	assert_false(panel.select(SOMEONE_ELSE), "while one nobody reported cannot be chosen")


## What happened is listed for the chosen entity alone, newest first.
func test_what_happened_is_listed_for_the_chosen_entity_newest_first() -> void:
	_game_sends_snapshot_of(fixture.asc)
	var mine: int = fixture.asc.get_instance_id()
	_game_sends_trace("first", mine)
	_game_sends_trace("elsewhere", SOMEONE_ELSE)
	_game_sends_trace("second", mine)

	panel.refresh()

	var lines: PackedStringArray = panel.event_lines()
	assert_eq(lines.size(), 2, "only what happened to the chosen entity")
	assert_true(lines[0].contains("second"), "newest first")
	assert_true(lines[1].contains("first"), "oldest last")
#endregion
