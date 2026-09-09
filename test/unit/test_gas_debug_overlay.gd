## The debugger the game draws itself, and the four pages it draws.
##
## The editor's debugger needs the editor. It is not there in the build somebody
## exported to look at on a console, on a phone, or on the machine of whoever
## reported the bug - which is where the bugs worth this are. This is the same
## information, drawn by the running game, and everything it decides is asked
## here without a screen.
##
## Every page is a transformation from one snapshot to lines of text, so what is
## checked is what a person would read: that an inhibited effect says so, that
## an ability on cooldown says how long, that a tag held only through its
## children is not reported as held.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const STUNNED: StringName = &"Status.Stunned"
const ABILITY_TAG: StringName = &"Ability.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Watched")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _taken(history: GasAttributeHistory = null) -> GasRuntimeSnapshot:
	return GasRuntimeSnapshot.of(asc, history)


## The one row whose first cell is `named`, or null.
func _row_for(page: GasDebugPage, snapshot: GasRuntimeSnapshot, named: String) -> GasDebugPage.Row:
	for row: GasDebugPage.Row in page.rows(snapshot):
		if not row.cells.is_empty() and row.cells[0] == named:
			return row
	return null
#endregion


#region The bounded history
## The history keeps the last hundred and twenty-eight and no more.
##
## An unbounded log of every attribute change in a running game is a memory leak
## with a nice name on it: a periodic effect ticking twice a second fills a
## hundred thousand entries in an afternoon, and nobody scrolls back that far.
func test_the_history_keeps_the_last_hundred_and_twenty_eight() -> void:
	var history: GasAttributeHistory = GasAttributeHistory.new()
	assert_eq(history.limit, 128, "the default the phase names")

	for step: int in 200:
		history.record(HEALTH, float(step), float(step + 1))

	assert_eq(history.size(), 128, "no more than the limit is kept")
	assert_eq(history.recorded(), 200, "and it knows how many it saw")
	assert_almost_eq(
		history.recent()[0].to_value, 200.0, 0.0001, "the newest is at the front"
	)
	assert_almost_eq(
		history.recent()[127].to_value, 73.0, 0.0001,
		"and the oldest kept is the hundred and twenty-eighth back, not the first"
	)


## A limit of none keeps none, which is a thing somebody can mean.
func test_a_history_told_to_keep_nothing_keeps_nothing() -> void:
	var history: GasAttributeHistory = GasAttributeHistory.new()
	history.limit = 0

	history.record(HEALTH, 100.0, 90.0)

	assert_eq(history.size(), 0, "kept none")
	assert_eq(history.recorded(), 1, "and still counted it")


## What the component announces is what the history records.
##
## Recorded rather than instrumented: the component already says every change,
## and announcing it a second time at each site would be a second description
## that disagrees the first time one of them is updated.
func test_the_history_records_what_the_component_announces() -> void:
	var history: GasAttributeHistory = GasAttributeHistory.new()
	assert_true(history.watch(asc), "attached to the component")

	var hit: Array[GameplayEffectModifier] = [EffectFactory.add(HEALTH, -25.0)]
	EffectFactory.apply(asc, EffectFactory.instant(hit))

	var changes: Array[GasAttributeHistory.Change] = history.recent_for(HEALTH)
	assert_eq(changes.size(), 1, "one change, from one effect")
	assert_almost_eq(changes[0].delta(), -25.0, 0.0001, "of the amount the effect said")

	history.stop()
	EffectFactory.apply(asc, EffectFactory.instant(hit))
	assert_eq(
		history.recent_for(HEALTH).size(), 1, "and nothing is recorded after it stops"
	)
#endregion


#region What a snapshot carries that the wire did not
## An effect that is applied and not in force says so.
##
## The state somebody stares at longest: the stun they can see in the list that
## is not stunning anybody.
func test_a_snapshot_says_which_effects_are_applied_but_not_in_force() -> void:
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 5.0)]
	var active: ActiveGameplayEffect = EffectFactory.apply(
		asc, EffectFactory.duration(buff, 30.0)
	)
	active.inhibited = true

	var found: GasRuntimeSnapshot.Effect = _taken().effect(active.handle.id)

	assert_not_null(found, "the effect is in the snapshot")
	assert_true(found.inhibited, "and it says it is not in force")


## A grant carries why it is not going off.
func test_a_snapshot_carries_a_grant_s_cooldown_and_last_result() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(ABILITY_TAG))

	var found: GasRuntimeSnapshot.Ability = _taken().ability(spec.handle.id)

	assert_not_null(found, "the grant is in the snapshot")
	assert_false(found.on_cooldown, "nothing is stopping it")
	assert_eq(found.last_result, "", "and it has never been tried")

	asc.try_activate_ability_handle(spec.handle)
	var tried: GasRuntimeSnapshot.Ability = _taken().ability(spec.handle.id)
	assert_ne(tried.last_result, "", "after a try, it says what happened")


## An entity with nothing on it is a snapshot with nothing in it, not a failure.
func test_an_entity_with_nothing_on_it_snapshots_cleanly() -> void:
	var taken: GasRuntimeSnapshot = _taken()

	assert_eq(taken.tags.size(), 0, "no tags")
	assert_eq(taken.effects.size(), 0, "no effects")
	assert_gt(taken.attributes.size(), 0, "but the attributes it declares are there")


## Nothing at all is a snapshot that says nothing, rather than a crash.
##
## A debugger is the last thing that should fall over on the state it was
## opened to look at.
func test_a_snapshot_of_nothing_says_nothing() -> void:
	var taken: GasRuntimeSnapshot = GasRuntimeSnapshot.of(null)

	assert_eq(taken.asc_id, 0, "nothing to be about")
	assert_eq(taken.attributes.size(), 0, "and nothing to say")
#endregion


#region The attributes page
## Base and current side by side, and what last moved it.
##
## "Why is health 75" is never answered by the number 75, and by the time
## somebody opens an overlay the change they care about has already happened.
func test_the_attributes_page_shows_both_numbers_and_the_last_change() -> void:
	var history: GasAttributeHistory = GasAttributeHistory.new()
	history.watch(asc)
	var hit: Array[GameplayEffectModifier] = [EffectFactory.add(HEALTH, -25.0)]
	EffectFactory.apply(asc, EffectFactory.instant(hit))

	var page: GasDebugPageAttributes = GasDebugPageAttributes.new()
	var row: GasDebugPage.Row = _row_for(page, _taken(history), String(HEALTH))

	assert_not_null(row, "health has a row")
	assert_eq(row.cells[3], "-25", "saying what last moved it, signed")
	history.stop()


## A modified attribute is the notable one: it is what something did to this
## character, and it stops being true when the effect ends.
func test_the_attributes_page_marks_the_ones_something_is_changing() -> void:
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 5.0)]
	EffectFactory.apply(asc, EffectFactory.infinite(buff))

	var page: GasDebugPageAttributes = GasDebugPageAttributes.new()
	var taken: GasRuntimeSnapshot = _taken()

	var buffed: GasDebugPage.Row = _row_for(page, taken, String(ATTACK))
	var untouched: GasDebugPage.Row = _row_for(page, taken, String(HEALTH))

	assert_not_null(buffed, "attack has a row")
	assert_true(buffed.notable, "and it is not what it was authored as")
	assert_ne(buffed.cells[1], buffed.cells[2], "which is base and current disagreeing")
	assert_not_null(untouched, "health has one too")
	assert_false(untouched.notable, "and nothing is doing anything to it")


## An attribute nothing has touched says so rather than showing a zero.
func test_an_attribute_nothing_has_touched_shows_no_change() -> void:
	var page: GasDebugPageAttributes = GasDebugPageAttributes.new()
	var row: GasDebugPage.Row = _row_for(page, _taken(), String(HEALTH))

	assert_not_null(row, "health has a row")
	assert_eq(row.cells[3], "-", "and nothing has moved it")
#endregion


#region The effects page
## An inhibited effect reads differently from one that is working.
func test_the_effects_page_says_which_effect_is_not_in_force() -> void:
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 5.0)]
	var active: ActiveGameplayEffect = EffectFactory.apply(
		asc, EffectFactory.duration(buff, 30.0)
	)

	var page: GasDebugPageEffects = GasDebugPageEffects.new()
	var working: GasDebugPage.Row = page.rows(_taken())[0]
	assert_eq(working.cells[4], GasDebugPageEffects.IN_FORCE, "it is working")
	assert_false(working.notable, "so it is not what somebody is hunting")

	active.inhibited = true
	var stopped: GasDebugPage.Row = page.rows(_taken())[0]
	assert_eq(stopped.cells[4], GasDebugPageEffects.INHIBITED, "and now it is not")
	assert_true(stopped.notable, "which is exactly what somebody is hunting")


## An infinite effect shows a dash rather than a zero.
##
## `0.00` reads as "about to expire", which is the opposite of what an infinite
## effect is doing.
func test_an_effect_with_no_clock_shows_a_dash_rather_than_zero() -> void:
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 5.0)]
	EffectFactory.apply(asc, EffectFactory.infinite(buff))

	var row: GasDebugPage.Row = GasDebugPageEffects.new().rows(_taken())[0]

	assert_eq(row.cells[2], "-", "no seconds are counting down")
	assert_eq(row.cells[3], "-", "and no turns either")
#endregion


#region The abilities page
## A granted ability that has never been tried says so, and is not marked.
func test_the_abilities_page_shows_a_grant_that_is_simply_ready() -> void:
	AbilityFactory.give(asc, Probe.build(ABILITY_TAG))

	var row: GasDebugPage.Row = GasDebugPageAbilities.new().rows(_taken())[0]

	assert_eq(row.cells[2], GasDebugPageAbilities.READY, "nothing is running")
	assert_eq(row.cells[3], GasDebugPageAbilities.READY, "nothing is on cooldown")
	assert_eq(row.cells[4], GasDebugPageAbilities.NEVER_TRIED, "and it has never been tried")
	assert_false(row.notable, "so there is nothing to look at")


## A running ability says how many of it are running.
##
## Channelled, because an ability that returns from _activate_ability is closed
## the moment it does: "running" is a state you have to actually be in for a
## page to be able to report it, and one that ended is a page reporting nothing.
func test_the_abilities_page_says_how_many_activations_are_running() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(ABILITY_TAG))
	# Set on the granted instance rather than on the template: `channels` is not
	# exported, so it does not survive the pack-then-instantiate round trip a
	# grant performs, and the template is freed by the factory.
	var channelled: ProbeAbility = spec.per_actor_instance as ProbeAbility
	channelled.channels = true
	asc.try_activate_ability_handle(spec.handle)

	var page: GasDebugPageAbilities = GasDebugPageAbilities.new()
	var running: GasDebugPage.Row = page.rows(_taken())[0]
	assert_true(
		running.cells[2].contains(GasDebugPageAbilities.RUNNING),
		"it says it is running: %s" % running.cells[2]
	)

	channelled.channel_gate.emit()
	var finished: GasDebugPage.Row = page.rows(_taken())[0]
	assert_eq(
		finished.cells[2], GasDebugPageAbilities.READY,
		"and says so no longer once it has ended"
	)
#endregion


#region The tags page
## A tag held only through its children is not reported as held.
##
## `State` reading nothing while `State.Stunned` reads two is a person working
## out the hierarchy by hand, and a page that showed one number would make them
## do it.
func test_the_tags_page_tells_a_family_apart_from_a_tag_that_is_held() -> void:
	asc.tags.add(STUNNED)

	var page: GasDebugPageTags = GasDebugPageTags.new()
	var taken: GasRuntimeSnapshot = _taken()

	var held: GasDebugPage.Row = _row_for(page, taken, String(STUNNED))
	var family: GasDebugPage.Row = _row_for(page, taken, "Status")

	assert_not_null(held, "the tag itself has a row")
	assert_eq(held.cells[3], GasDebugPageTags.HELD, "something holds it")
	assert_false(held.notable, "which is ordinary")

	assert_not_null(family, "and so does the family it belongs to")
	assert_eq(family.cells[1], "0", "which nothing holds directly")
	assert_eq(family.cells[2], "1", "and is held once all the same")
	assert_eq(family.cells[3], GasDebugPageTags.THROUGH_CHILDREN, "saying how")
#endregion


#region Every page
## No page needs a screen to say what it would draw.
##
## The whole reason the deciding does not live in the overlay: a rule written
## inside a Control is a rule nothing headless can check, and headless is where
## this suite runs.
func _pages() -> Array:
	return [
		["attributes", GasDebugPageAttributes.new()],
		["effects", GasDebugPageEffects.new()],
		["abilities", GasDebugPageAbilities.new()],
		["tags", GasDebugPageTags.new()],
	]


func test_every_page_says_what_it_would_draw_without_a_screen(
	case: Array = use_parameters(_pages())
) -> void:
	var described: String = case[0]
	var page: GasDebugPage = case[1]

	assert_false(page.title().is_empty(), "%s has a name" % described)
	assert_gt(page.columns().size(), 0, "%s has columns" % described)
	for row: GasDebugPage.Row in page.rows(_taken()):
		assert_eq(
			row.cells.size(), page.columns().size(),
			"%s draws a cell per column" % described
		)


## Every page survives being asked about nothing.
func test_every_page_survives_a_snapshot_of_nothing(
	case: Array = use_parameters(_pages())
) -> void:
	var described: String = case[0]
	var page: GasDebugPage = case[1]

	assert_eq(page.rows(null).size(), 0, "%s draws nothing for nothing" % described)
	assert_eq(
		page.rows(GasRuntimeSnapshot.new()).size(), 0,
		"%s draws nothing for an empty snapshot" % described
	)
#endregion


#region The overlay itself
## The overlay runs in a game, with no editor anywhere.
##
## Instantiated from its scene the way a game would, in a headless tree - which
## is as far from the editor as this suite can get.
func _overlay() -> GasDebugOverlay:
	var scene: PackedScene = load(GasDebugOverlay.SCENE)
	assert_not_null(scene, "the overlay scene is where it says it is")
	var made: GasDebugOverlay = scene.instantiate()
	add_child_autofree(made)
	return made


func test_the_overlay_watches_an_entity_and_draws_its_pages() -> void:
	var overlay: GasDebugOverlay = _overlay()
	asc.tags.add(STUNNED)

	assert_eq(overlay.pages().size(), 4, "the four pages the phase names")
	assert_true(overlay.watch(asc), "it attached to the component")
	assert_same(overlay.watched(), asc, "and says which one")

	var taken: GasRuntimeSnapshot = overlay.snapshot()
	assert_eq(taken.asc_id, asc.get_instance_id(), "its snapshot is of that entity")
	assert_gt(taken.tags.size(), 0, "and carries what is on it")


## Each page can be brought to the front, and a page that is not there is not.
func test_the_overlay_shows_one_page_at_a_time() -> void:
	var overlay: GasDebugOverlay = _overlay()
	overlay.watch(asc)

	for index: int in overlay.pages().size():
		assert_true(overlay.show_page(index), "page %d can be shown" % index)
		assert_eq(overlay.showing(), index, "and is the one showing")

	assert_false(overlay.show_page(overlay.pages().size()), "there is no page after the last")
	assert_false(overlay.show_page(-1), "nor before the first")
	assert_eq(
		overlay.showing(), overlay.pages().size() - 1,
		"and asking for one that is not there changed nothing"
	)


## Watching an entity starts remembering what happens to it.
func test_the_overlay_remembers_what_happens_while_it_watches() -> void:
	var overlay: GasDebugOverlay = _overlay()
	overlay.watch(asc)

	var hit: Array[GameplayEffectModifier] = [EffectFactory.add(HEALTH, -10.0)]
	EffectFactory.apply(asc, EffectFactory.instant(hit))

	assert_eq(overlay.history().recent_for(HEALTH).size(), 1, "the change was kept")
	assert_eq(overlay.snapshot().changes.size(), 1, "and reaches the pages through the snapshot")

	overlay.stop()
	assert_null(overlay.watched(), "and it lets go when told")
	assert_eq(overlay.history().size(), 0, "forgetting what it was keeping")


## Watching nothing is refused rather than half-done.
func test_the_overlay_refuses_to_watch_nothing() -> void:
	var overlay: GasDebugOverlay = _overlay()

	assert_false(overlay.watch(null), "there is nothing to watch")
	assert_null(overlay.watched(), "so nothing is being watched")
#endregion
