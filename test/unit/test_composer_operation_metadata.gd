## What the palette knows about an operation, and where each part of it came
## from.
##
## The catalog offered every public method of five classes and argued for it:
## leaving one out would answer a question - "is this worth drawing?" - that
## belongs to whoever writes the ability. The argument was right about the
## question and wrong about who had already answered it. `dispose()`,
## `cleanup()` and `emit_tag_change()` are public, and nobody writes those in an
## ability: they are how the runtime talks to itself. Public in GDScript means
## "another part of the engine calls this", which is a different fact from
## "somebody authors this".
##
## So a method says which it is, beside the code. What it takes and hands back
## is still read from the engine, because those are facts about the method and
## restating them is how a catalog names a parameter the API stopped having -
## which is the split this file is here to hold in place.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ASC_PATH: String = "res://addons/GAS_Engine/components/ability_system_component.gd"
const ABILITY_PATH: String = "res://addons/GAS_Engine/abilities/gameplay_ability.gd"


#region Getting there
func _operation(path: String, method: StringName) -> ComposerOperation:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find_on(path, method)
	return entry.operation if entry != null else null


func _doc(lines: Array) -> PackedStringArray:
	var written: PackedStringArray = PackedStringArray()
	for line: String in lines:
		written.append(line)
	return written
#endregion


#region Every operation carries all of it
## The nine things the phase names, on every operation there is.
##
## Asked of all of them rather than of one, because the failure this catches is
## an operation built down one branch of the catalog that forgot a field - and
## one example would be exactly the branch somebody remembered.
func test_every_operation_carries_the_whole_of_its_metadata() -> void:
	var checked: int = 0
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var made: ComposerOperation = entry.operation
		assert_not_null(made, "%s has metadata at all" % entry.key)
		assert_eq(made.id, entry.key, "%s: its id is what it is filed under" % entry.key)
		assert_eq(made.category, entry.group, "%s: and its category" % entry.key)
		assert_false(made.display_name.is_empty(), "%s: it has a name" % entry.key)
		assert_eq(
			made.input_types.size(), entry.parameters.size(),
			"%s: one input type per parameter" % entry.key
		)
		assert_eq(
			made.defaults.size(), entry.parameters.size() - entry.required,
			"%s: one default per optional parameter" % entry.key
		)
		checked += 1
	assert_gt(checked, 50, "the whole catalog was asked")


## A call that hands nothing back names no output, and one that does names it.
func test_what_an_operation_hands_back_is_named_or_absent() -> void:
	var silent: ComposerOperation = _operation(ASC_PATH, &"add_tag")
	var answering: ComposerOperation = _operation(ASC_PATH, &"get_attribute_current")

	assert_eq(silent.output_types.size(), 0, "adding a tag hands nothing back")
	assert_eq(answering.output_types, [&"float"] as Array[StringName], "and this hands a float")


## An output that only exists after the ability has waited is named apart.
##
## What comes out of a task is not available on the line the call was written
## on, and a palette that listed the two together would offer a value nothing
## can reach yet.
func test_an_output_that_only_arrives_after_a_wait_is_named_apart() -> void:
	var waiting: ComposerOperation = _operation(ABILITY_PATH, &"wait_delay")
	var immediate: ComposerOperation = _operation(ASC_PATH, &"add_tag")

	assert_eq(waiting.async_outputs.size(), 1, "the task it hands back")
	assert_eq(waiting.async_outputs, waiting.output_types, "which is what it hands back")
	assert_eq(immediate.async_outputs.size(), 0, "and nothing waits on a tag")
#endregion


#region Where the words come from
## The sentence on the card is the one already written above the method.
##
## Read rather than restated: a second copy of an explanation is the copy that
## drifts, and it drifts without anything noticing because both still read well.
##
## Anchored at both ends to the file itself - the doc line is looked for in the
## source, and the description is required to begin with it - so this cannot
## pass by comparing the reader with itself.
func test_the_description_is_the_method_s_own_first_sentence() -> void:
	var written: String = "## Grant an ability from its scene"
	var made: ComposerOperation = _operation(ASC_PATH, &"give_ability")

	assert_true(
		FileAccess.get_file_as_string(ASC_PATH).contains(written),
		"the sentence is written above the method"
	)
	assert_true(
		made.description.begins_with(written.trim_prefix("## ")),
		"and the card starts with it: %s" % made.description
	)


## A method whose own name reads badly is given one that does not.
func test_a_method_can_say_what_it_should_be_called() -> void:
	var named: ComposerOperation = _operation(ASC_PATH, &"ability_local_input_pressed")
	var unnamed: ComposerOperation = _operation(ASC_PATH, &"add_tag")

	assert_eq(named.display_name, "Input Pressed", "the name it asked for")
	assert_eq(unnamed.display_name, "Add Tag", "and the method's own where it asked for none")


## What a doc comment declares, in the three shapes one can take.
##
## One table because they are the same question asked of three comments, and
## what separates them is the answer: a marker with a category, a marker on its
## own - which is a method saying "offer me, and work the rest out" - and no
## marker at all. The description is asked every time, because the marker being
## taken out of it is the part that goes wrong quietly.
##
##     [what the comment is, its lines, is it an operation, its category,
##      its description]
func _doc_comments() -> Array:
	return [
		[
			"a marker naming a category",
			["## Does a thing.", "## @composer: Tasks"], true, &"Tasks", "Does a thing.",
		],
		["a marker on its own", ["## @composer"], true, &"", ""],
		[
			"no marker at all",
			["## An ordinary comment.", "##", "## Two lines of it."],
			false, &"", "An ordinary comment.",
		],
	]


func test_a_doc_comment_declares_what_it_says_and_nothing_more() -> void:
	var rows: Array = _doc_comments()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var written: Array = row[1]
		var said: PackedStringArray = _doc(written)
		var declares: bool = row[2]
		var category: StringName = row[3]
		var description: String = row[4]

		assert_eq(ComposerOperation.is_declared_in(said), declares, "%s: offered?" % described)
		assert_eq(ComposerOperation.category_in(said), category, "%s: which part" % described)
		assert_eq(
			ComposerOperation.description_in(said), description,
			"%s: what it says, with the marker out of it" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every shape was offered")
#endregion


#region Which methods are offered at all
## The runtime's own plumbing is public and is not on the palette.
##
##     [what it is, the method]
func _plumbing() -> Array:
	return [
		["tearing a component down", "dispose"],
		["resetting one for reuse", "cleanup"],
		["announcing a tag change", "emit_tag_change"],
		["telling an ability who it is on", "init_ability_actor_info"],
	]


func test_the_runtime_s_own_plumbing_is_not_offered() -> void:
	var rows: Array = _plumbing()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var method: String = row[1]

		assert_null(
			ComposerCatalog.find_on(ASC_PATH, StringName(method)),
			"%s is not something anybody authors" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every one was asked about")


## And what somebody does author is.
func test_what_somebody_authors_is_offered() -> void:
	assert_not_null(_operation(ASC_PATH, &"apply_gameplay_effect"), "applying an effect")
	assert_not_null(_operation(ASC_PATH, &"add_tag"), "adding a tag")
	assert_not_null(_operation(ABILITY_PATH, &"commit_ability"), "committing")
	assert_not_null(_operation(ABILITY_PATH, &"wait_target_data"), "waiting for a target")
#endregion


#region Saying what should no longer be reached for
## A deprecated operation is offered and says so.
##
## Offered because an ability already written on it still has to open, and said
## out loud because a palette that quietly kept offering it is a palette
## teaching the old way to whoever reads it next.
func test_a_deprecated_operation_is_offered_and_says_what_to_use_instead() -> void:
	var made: ComposerOperation = _operation(ASC_PATH, &"remove_ability")

	assert_not_null(made, "still offered")
	assert_true(made.is_deprecated(), "and marked")
	assert_true(
		made.deprecated.contains("remove_ability_handle"),
		"naming what to reach for instead: %s" % made.deprecated
	)


## The one beside it is not, so the mark means something.
func test_the_operation_it_points_at_is_not_deprecated() -> void:
	var made: ComposerOperation = _operation(ASC_PATH, &"remove_ability_handle")

	assert_false(made.is_deprecated(), "this is the one to use")
	assert_eq(made.deprecated, "", "so it says nothing about being old")
#endregion


#region Reading a doc comment off a file
## The doc comment above a method is the one immediately above it.
##
## A comment separated from what it describes by a blank line is a comment about
## something else, and attaching it would put another method's sentence on this
## one's card.
func test_a_comment_separated_by_a_blank_line_belongs_to_nothing() -> void:
	var found: Dictionary[StringName, PackedStringArray] = (
		ComposerDeclarations.doc_comments_in(ASC_PATH)
	)

	assert_gt(found.size(), 20, "the file was read")
	assert_true(found.has(&"add_tag"), "and a documented method was found")
	var said: PackedStringArray = found[&"add_tag"]
	assert_gt(said.size(), 0, "with lines above it")
	for line: String in said:
		assert_true(line.begins_with("##"), "every one of which is a doc line: %s" % line)


## A file that is not there is answered with nothing rather than a crash.
func test_a_file_that_is_not_there_is_answered_with_nothing() -> void:
	var found: Dictionary[StringName, PackedStringArray] = (
		ComposerDeclarations.doc_comments_in("res://no/such/file.gd")
	)

	assert_eq(found.size(), 0, "nothing, and nothing thrown")
#endregion
