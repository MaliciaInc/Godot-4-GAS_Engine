## Asking about absent integrations, which is the normal case.
##
## This repository ships none of the three addons, and that is deliberate rather
## than a gap: a GAS that required Dialogic to be present would not be optional.
## So the state under test here is absence, and what is being proved is that
## absence is quiet - no error, no warning, no attempt to load a class that does
## not exist.
##
## Nothing here fabricates a fake `addons/dialogic` to exercise the present case.
## A directory planted to satisfy a check would prove that the check can be
## fooled, and the bridges cover the present case with doubles that implement
## only the third party's published contract.
##
## @meta_license: MIT
extends GutTest


#region Absence is quiet
func test_none_of_the_three_addons_is_installed_here() -> void:
	assert_false(GameplayIntegrationAvailability.is_dialogic_installed(), "no Dialogic")
	assert_false(GameplayIntegrationAvailability.is_gloot_installed(), "no GLoot")
	assert_false(GameplayIntegrationAvailability.is_quest_system_installed(), "no QuestSystem")


func test_an_absent_integration_has_no_runtime() -> void:
	assert_null(
		GameplayIntegrationAvailability.dialogic_runtime(get_tree()),
		"an addon that is not installed cannot be running"
	)
	assert_null(
		GameplayIntegrationAvailability.quest_system_runtime(get_tree()),
		"and neither can the other one"
	)


## A caller with no tree gets null rather than a crash.
##
## The tree is null in more places than it looks: a Resource, a tool script
## outside the scene, an object being torn down. Answering there is cheaper than
## asking every caller to check first.
func test_a_missing_tree_is_answered_rather_than_crashed_on() -> void:
	assert_null(GameplayIntegrationAvailability.dialogic_runtime(null), "no tree, no runtime")
	assert_null(GameplayIntegrationAvailability.quest_system_runtime(null), "and the same here")
#endregion


#region What this suite can and cannot see
## The three addons are looked for in three different places.
##
## This is the one kind of mistake this repository can actually catch. With none
## of the three installed, a misspelled path answers false exactly like a correct
## one, and would only surface as silence in a project that did install the
## addon - so a copy-paste that left two constants pointing at the same
## plugin.cfg is worth asking about, and a typo inside one is not askable here.
##
## The present case is covered where it can be: each bridge's own suite, against
## a double implementing only that third party's published contract.
func test_the_three_integrations_are_looked_for_separately() -> void:
	var paths: Array[String] = [
		GameplayIntegrationAvailability.DIALOGIC_PLUGIN_PATH,
		GameplayIntegrationAvailability.GLOOT_PLUGIN_PATH,
		GameplayIntegrationAvailability.QUEST_SYSTEM_PLUGIN_PATH,
	]

	var distinct: Dictionary[String, bool] = {}
	for path: String in paths:
		assert_false(path.is_empty(), "every integration has somewhere to be looked for")
		distinct[path] = true

	assert_eq(distinct.size(), paths.size(), "three addons, three places to look")
#endregion
