## Which file the Composer agrees to open.
##
## The editor plugin around this is a handful of calls that move the editor
## about, and none of them mean anything without an editor to move. The
## decisions are here, where they can be asked directly.
##
## The distinction these tests exist to hold is between two things that both
## look like "no": a file the Composer will not open, and a file it opens and
## cannot fully draw. The first is a wrong turn - the wrong kind of script, or
## nothing there. The second is an ability, opened, read-only, with the reason on
## its Output panel. Collapsing them would mean a person who asked to see their
## ability got a dialog saying no and nothing on screen.
##
## @meta_license: MIT
extends GutTest

const REFERENCE: String = "res://addons/GAS_Engine/reference/instant_damage.gd"
const NOT_AN_ABILITY: String = "res://test/fixtures/game_composer_nodes.gd"
const NOT_A_SCRIPT: String = "res://test/gut_headless_runner.tscn"
const MISSING: String = "res://nowhere.gd"


#region What it opens
func test_a_reference_ability_opens() -> void:
	var opened: ComposerHost.Opened = ComposerHost.open(REFERENCE)

	assert_true(opened.is_ok(), "opened: %s" % opened.refusal)
	assert_not_null(opened.graph, "and there is a graph to draw")
	assert_gt(opened.graph.nodes.size(), 0, "with something in it")
	assert_eq(opened.graph.source_path, REFERENCE, "that knows where it came from")


## An ability with no `class_name` is still an ability.
##
## None of the reference abilities declares one, and asking the global class
## list would have refused every one of them. The base chain is read instead.
func test_an_ability_without_a_global_name_is_still_recognised() -> void:
	var script: GDScript = load(REFERENCE) as GDScript

	assert_true(script.get_global_name().is_empty(), "it never declared a name")
	assert_true(ComposerHost.is_ability(script), "and it is an ability all the same")


## A file the subset cannot fully draw is opened, not refused.
##
## This is the case worth being careful about. The engine's own fixtures use
## constructions outside the subset, and a person opening one should see the
## ability and be told what cannot be drawn - not be turned away at the door
## with nothing on screen.
func test_an_ability_outside_the_subset_opens_read_only_rather_than_being_refused() -> void:
	var opened: ComposerHost.Opened = ComposerHost.open(
		"res://test/fixtures/fireball_ability.gd"
	)

	assert_true(opened.is_ok(), "it opened: %s" % opened.refusal)
	assert_false(opened.graph.is_editable(), "read-only")
	assert_false(
		opened.graph.blocked_reason().is_empty(), "and it says what it cannot draw"
	)
#endregion


#region What it turns away, and in what words
## Every wrong turn, and the words each one gets.
##
## One table rather than one test apiece: they differ only in what was wrong and
## what was said about it, and a refusal that does not name the file leaves a
## person guessing which of their scripts the menu was complaining about.
const REFUSALS: Array[Array] = [
	["", "script editor", "nothing open at all"],
	[NOT_A_SCRIPT, "not a GDScript", "a file that is not a script"],
	[MISSING, "nothing at", "a path with nothing on it"],
	[NOT_AN_ABILITY, "GameplayAbility", "a script that is not an ability"],
]


func test_a_file_the_composer_cannot_open_is_refused_in_its_own_words() -> void:
	for row: Array in REFUSALS:
		var path: String = row[0]
		var expected: String = row[1]
		var described: String = row[2]

		var opened: ComposerHost.Opened = ComposerHost.open(path)

		assert_false(opened.is_ok(), "%s is refused" % described)
		assert_true(
			opened.refusal.contains(expected), "%s: %s" % [described, opened.refusal]
		)
		assert_null(opened.graph, "%s: and nothing was drawn" % described)
#endregion


#region Against the file, not the loaded copy
## What is drawn is what the file says right now.
##
## A loaded script is whatever Godot last compiled, and the two part company the
## moment somebody types in the script editor without saving. Drawing the loaded
## one would show a graph of code that is no longer there - the exact failure
## this whole tool exists to avoid.
func test_the_graph_is_read_from_the_file_on_disk() -> void:
	var source: String = FileAccess.get_file_as_string(REFERENCE)
	var opened: ComposerHost.Opened = ComposerHost.open(REFERENCE)

	var printed: ComposerWriter.Result = ComposerWriter.apply(opened.graph, source)

	assert_true(printed.is_ok(), "the graph writes back: %s" % printed.refusal)
	assert_eq(printed.text, source, "byte for byte what is on disk")
#endregion
