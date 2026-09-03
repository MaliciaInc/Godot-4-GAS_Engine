## Finding a project's abilities without being told where they are.
##
## The Composer used to draw whatever the Script editor had open and refuse
## anything else, which put the work of finding an ability on the person who
## asked to see one. This is what replaced that, and what it has to get right is
## narrow: find the abilities, in both shapes GDScript writes them, and do not
## call everything else one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const REFERENCE_FOLDER: String = "res://addons/GAS_Engine/reference/"

## The six that ship with the engine. Named rather than counted, because a scan
## that found six of something else would pass a count.
const REFERENCE_ABILITIES: Array[String] = [
	"confirmed_blast", "costly_strike", "cued_dash",
	"instant_damage", "sweeping_volley", "timed_buff",
]


func _found() -> PackedStringArray:
	return ComposerLibrary.abilities_in_project()


#region What it finds
## A bare `extends GameplayAbility`, which is how every reference ability and
## most hand-written ones are declared.
func test_it_finds_every_reference_ability() -> void:
	var found: PackedStringArray = _found()

	for name: String in REFERENCE_ABILITIES:
		assert_true(
			found.has(REFERENCE_FOLDER + name + ".gd"), "%s was found: %s" % [name, found]
		)


## `class_name Foo extends GameplayAbility` says it mid-line.
##
## Worth its own test: a reader that only looked at the start of a line would
## miss every named ability, and a game that bases its own on a named class
## would have none of them found at all.
func test_it_finds_an_ability_that_declares_a_class_name() -> void:
	assert_true(
		_found().has("res://test/fixtures/fireball_ability.gd"),
		"the mid-line form is read as well as the bare one"
	)


## An ability that reaches GameplayAbility through another ability.
##
## The shape a real game takes almost at once - one base holding what every
## action shares, a concrete ability per action - and the shape a one-link scan
## silently fails on: the base is found, and every ability built on it is not.
func test_it_follows_a_chain_rather_than_only_the_first_link() -> void:
	assert_true(
		_found().has("res://test/fixtures/derived_ability.gd"),
		"an ability two links from GameplayAbility is still an ability"
	)


## And does not stop at the depth somebody happened to test.
##
## A resolver written for two levels and one written for any level look
## identical until a third exists. A real game reaches three the first time it
## has a base for melee, a base for spells, and an actual spell - so three is
## the shortest chain that can tell the two resolvers apart.
func test_it_does_not_stop_at_the_depth_that_was_tested_first() -> void:
	assert_true(
		_found().has("res://test/fixtures/deeper_ability.gd"),
		"three links is still an ability, and so is any number of them"
	)
#endregion


#region Remembering, and looking again
## The remembered answer is the answer, not an older one.
##
## The list is kept between openings because a project with the integration
## addons installed carries about five hundred scripts that are nobody's
## abilities, and reading all of them on every press is work nobody asked for.
## What a cache must never do is disagree with the thing it caches.
##
## Speed is not asserted here. That this is faster than looking again is the
## reason it exists, but it is not the thing that could go quietly wrong.
func test_what_is_remembered_agrees_with_looking_again() -> void:
	var remembered: PackedStringArray = ComposerLibrary.abilities_in_project()
	var fresh: PackedStringArray = ComposerLibrary.scan()

	assert_eq(remembered, fresh, "the remembered list is the list")


## Forgetting is what the Re-scan option does, and it has to actually look.
func test_forgetting_still_finds_everything() -> void:
	var before: PackedStringArray = ComposerLibrary.abilities_in_project()

	ComposerLibrary.forget()
	var after: PackedStringArray = ComposerLibrary.abilities_in_project()

	assert_eq(after, before, "looking again finds what was there")
	assert_true(after.size() > 0, "and there was something there to find")
#endregion


#region What it leaves alone
## The engine is full of scripts, and all but a handful are not abilities.
func test_it_does_not_call_everything_an_ability() -> void:
	var found: PackedStringArray = _found()

	assert_false(
		found.has("res://addons/GAS_Engine/gas_engine_plugin.gd"),
		"the plugin's own script is not an ability - the case that started this"
	)
	assert_false(
		found.has("res://addons/GAS_Engine/abilities/gameplay_ability.gd"),
		"and neither is the base class itself"
	)
	assert_false(
		found.has("res://addons/GAS_Engine/components/ability_system_component.gd"),
		"nor a component that merely holds them"
	)


## An ability task extends GameplayAbilityTask, which is a name that begins the
## same way and is not the same thing.
func test_a_task_is_not_an_ability() -> void:
	assert_false(
		_found().has("res://addons/GAS_Engine/abilities/tasks/ability_task_wait_delay.gd"),
		"tasks are owned by abilities, not abilities"
	)


## The vendored test dependency is skipped outright.
func test_it_does_not_walk_the_vendored_dependency() -> void:
	for path: String in _found():
		assert_false(path.begins_with("res://addons/gut"), "nothing from gut: %s" % path)
#endregion
