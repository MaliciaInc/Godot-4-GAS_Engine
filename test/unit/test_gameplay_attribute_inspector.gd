## Picking an attribute instead of typing one, and the typo that is now visible
## before the game runs.
##
## The friction F6.0.9 measured: a misspelled attribute name was caught by
## nothing, and the first person to notice was whoever wondered why the effect
## did nothing. What is proved here is that the catalogue knows what the project
## declares, that the picker writes a typed reference rather than a bare name,
## and that a name nobody declares is kept and shown rather than quietly
## deleted.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const InspectorPlugin = preload(
	"res://addons/GAS_Engine/attributes/gameplay_attribute_inspector_plugin.gd"
)


func before_each() -> void:
	# The catalogue remembers, and these tests are about what it found: a scan
	# left over from another suite would be a different answer than this one is
	# asking about.
	GameplayAttributeCatalog.forget()


func after_each() -> void:
	GameplayAttributeCatalog.forget()


#region What the project declares
## The catalogue finds the sets this project actually has, and the attributes
## on them.
##
## Asked of a set the suite already owns rather than a fixture written for this,
## because what is being checked is that the scan reaches a real set - one that
## something else in the project is already using.
func test_the_catalogue_finds_the_attributes_the_project_declares() -> void:
	var shown: Array[String] = []
	for entry: GameplayAttributeCatalog.Entry in GameplayAttributeCatalog.entries():
		shown.append(entry.shown())

	assert_true(
		shown.has("test_attribute_set.health"),
		"the suite's own set, and one of the attributes on it"
	)
	assert_true(
		shown.has("policy_attribute_set.damage"),
		"and another set entirely, so it is not finding only the first"
	)


## Two sets that both declare `health` are two entries, which is the whole
## reason the reference carries a set name.
func test_two_sets_declaring_one_name_are_two_entries() -> void:
	var healths: int = 0
	for entry: GameplayAttributeCatalog.Entry in GameplayAttributeCatalog.entries():
		if entry.attribute_name == &"health":
			healths += 1

	assert_gt(healths, 1, "more than one set declares health")


## What an entry stands for is a typed reference, and a fresh one each time.
##
## Shared, every effect in a project would point at one object, and editing the
## set name on one modifier would change it on all of them.
func test_an_entry_hands_out_a_fresh_typed_reference() -> void:
	var entry: GameplayAttributeCatalog.Entry = GameplayAttributeCatalog.entries()[0]

	var first: GameplayAttributeRef = entry.as_reference()
	var second: GameplayAttributeRef = entry.as_reference()

	assert_ne(first, second, "two references, not one shared")
	assert_eq(first.attribute_name, entry.attribute_name, "naming the same attribute")
	assert_eq(first.set_name, entry.set_name, "in the same set")
#endregion


#region The typo
## A misspelled attribute is detectable before the game runs.
##
## The friction itself. `is_valid()` only asks whether the field was filled in,
## which a typo passes; the catalogue asks whether anything declares it, which
## is the question somebody actually has.
func test_a_misspelled_attribute_is_caught_before_runtime() -> void:
	var typo: GameplayAttributeRef = GameplayAttributeRef.new()
	typo.attribute_name = &"helth"

	assert_true(typo.is_valid(), "the field is filled in, which is all that asks")
	assert_false(
		GameplayAttributeCatalog.knows(typo), "and nothing in the project declares it"
	)

	var correct: GameplayAttributeRef = GameplayAttributeRef.new()
	correct.attribute_name = &"health"
	assert_true(GameplayAttributeCatalog.knows(correct), "unlike the one spelled right")


## A reference naming a set is checked against that set, not against any set.
##
## Which is what naming one is for: `vehicle.health` and `player.health` are
## two attributes, and a check that accepted either for both would be no check.
func test_a_reference_that_names_a_set_is_checked_against_that_set() -> void:
	var elsewhere: GameplayAttributeRef = GameplayAttributeRef.new()
	elsewhere.set_name = &"no_such_set"
	elsewhere.attribute_name = &"health"

	assert_false(
		GameplayAttributeCatalog.knows(elsewhere),
		"the attribute exists, but not in the set this names"
	)
#endregion


#region What the picker shows
## A value nobody declares is shown as wrong, and an unfilled one is not.
##
## The rule lives on the catalogue rather than on the EditorProperty, because
## Godot refuses to instantiate one of those outside the editor - a rule there
## would be a rule nothing can check. What the widget does with the answer is
## colour it red and keep it: an editor that cleared a name it could not find
## would lose work every time a set is renamed, and the author would not know
## until the effect stopped doing anything.
##
##     [what it is called, the attribute named, whether it reads as wrong]
func _shown_cases() -> Array:
	return [
		["a name nobody declares", &"helth", true],
		["a name somebody does", &"health", false],
		["nothing chosen yet", &"", false],
	]


func test_a_value_the_project_does_not_declare_reads_as_wrong(
	case: Array = use_parameters(_shown_cases())
) -> void:
	var described: String = case[0]
	var named: StringName = case[1]
	var wrong: bool = case[2]

	var reference: GameplayAttributeRef = GameplayAttributeRef.new()
	reference.attribute_name = named

	assert_eq(GameplayAttributeCatalog.is_unknown(reference), wrong, described)


## The plugin offers the picker for a typed reference and for nothing else.
##
## By the property's type rather than by its name, so a reference on a cue
## binding gets the picker without anybody having to add its name to a list.
##
##     [what it is called, the type, the hint, whether the picker is offered]
func _handled_cases() -> Array:
	return [
		["a typed attribute reference", TYPE_OBJECT, "GameplayAttributeRef", true],
		["some other Resource", TYPE_OBJECT, "Curve", false],
		["a bare name", TYPE_STRING_NAME, "", false],
	]


func test_the_picker_is_offered_for_a_reference_and_nothing_else(
	case: Array = use_parameters(_handled_cases())
) -> void:
	var described: String = case[0]
	var type: Variant.Type = case[1]
	var hint: String = case[2]
	var offered: bool = case[3]

	var answered: bool = InspectorPlugin.is_an_attribute_reference(type, hint)
	assert_eq(answered, offered, described)
#endregion
