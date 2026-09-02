## Space, then type what you want.
##
## The claim being held is that somebody can find a node without knowing which
## of ten categories it was filed under, and without having to spell it the
## pretty way. Somebody who knows the engine types `wait_target`; being made to
## type `Wait Target Data` is the palette asking them to translate.
##
## @meta_license: MIT
extends GutTest

const GAME_SCRIPT: String = "res://test/fixtures/game_composer_nodes.gd"
const STAMINA: StringName = &"Stamina"

var finder: ComposerFinder = null


func before_each() -> void:
	finder = ComposerFinder.new()
	add_child_autofree(finder)


func after_each() -> void:
	ComposerCatalog.forget(ComposerCatalog.key_for(GAME_SCRIPT, &"spend_stamina"))
	finder = null


func _titles(query: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for key: StringName in finder.matches(query):
		found.append(ComposerCatalog.find(key).title)
	return found


#region Finding one
func test_an_empty_query_offers_everything_there_is() -> void:
	assert_eq(
		finder.matches("").size(), ComposerCatalog.all().size(),
		"nothing typed, nothing hidden"
	)


## Typed the way the engine spells it, and the way a person reads it.
##
## Both, because both are what somebody will type, and a palette that only
## answers one of them is one that works for whoever wrote it.
func test_a_call_is_found_by_its_method_and_by_its_title() -> void:
	assert_true(_titles("wait_target").has("Wait Target Data"), "as the engine spells it")
	assert_true(_titles("Wait Target").has("Wait Target Data"), "and as a person says it")
	assert_true(_titles("WAIT TARGET").has("Wait Target Data"), "however it is capitalised")


## A category is a thing people type too: somebody after any of the waiting
## calls types `tasks`.
func test_a_category_finds_everything_filed_under_it() -> void:
	var found: PackedStringArray = _titles("tasks")

	assert_gt(found.size(), 5, "the waiting calls: %s" % [found])
	assert_true(found.has("Wait Delay"), "including this one")


func test_something_that_is_not_there_finds_nothing() -> void:
	assert_eq(finder.matches("zzzz").size(), 0, "and says so rather than guessing")
#endregion


#region Whose call it is
## A call the engine declares and a call a game registered are told apart by
## where they were read from, not by anything either of them declares.
func test_a_row_says_whether_the_call_is_the_engines_or_a_games() -> void:
	assert_eq(
		ComposerCatalog.register("spend_stamina", STAMINA, GAME_SCRIPT, false), "",
		"a game offers one"
	)

	var mine: ComposerCatalog.Entry = ComposerCatalog.find_on(GAME_SCRIPT, &"spend_stamina")
	var theirs: ComposerCatalog.Entry = ComposerCatalog.find_on(
		ComposerCatalog.script_for(ComposerCatalog.ABILITY_CLASS), &"commit_ability"
	)

	assert_eq(ComposerFinder._badge(mine), ComposerFinder.GAME_BADGE, "the game's")
	assert_eq(ComposerFinder._badge(theirs), ComposerFinder.ENGINE_BADGE, "and the engine's")


## What a game registers is findable the moment it is registered.
func test_a_call_a_game_registered_is_found_like_any_other() -> void:
	assert_false(_titles("spend_stamina").has("Spend Stamina"), "not there yet")

	assert_eq(ComposerCatalog.register("spend_stamina", STAMINA, GAME_SCRIPT, false), "")

	assert_true(_titles("spend_stamina").has("Spend Stamina"), "and now it is")
#endregion


#region Getting about in it
func test_it_opens_empty_and_closes_on_escape() -> void:
	finder.begin()
	assert_true(finder.visible, "open")
	assert_false(finder.here().is_empty(), "with something under the cursor")

	finder.dismiss()

	assert_false(finder.visible, "shut")


## The arrows move within what is on screen and stop at its ends, rather than
## running off into a list nobody can see.
func test_the_cursor_stays_inside_what_is_shown() -> void:
	finder.begin()
	var first: StringName = finder.here()

	finder._step(-1)
	assert_eq(finder.here(), first, "it does not go above the first")

	for _step: int in ComposerFinder.SHOWN * 2:
		finder._step(1)
	assert_false(finder.here().is_empty(), "nor past the last")


## Choosing one says which, and shuts.
func test_choosing_says_which_and_closes() -> void:
	finder.begin()
	var wanted: StringName = finder.here()
	var heard: Array[StringName] = []
	finder.chose.connect(func _picked(key: StringName) -> void: heard.append(key))

	finder._take()

	assert_eq(heard, [wanted] as Array[StringName], "the one that was highlighted")
	assert_false(finder.visible, "and it got out of the way")
#endregion
