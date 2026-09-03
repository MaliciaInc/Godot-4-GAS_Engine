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
