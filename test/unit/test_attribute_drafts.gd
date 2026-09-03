## What a designer may name a set and an attribute.
##
## These names are not labels: the compiler writes `@export var <name>:
## AttributeData` and `class_name <set>AttributeSet` straight into a generated
## script. A name that is not a legal GDScript identifier produces a file that
## does not parse, and the dashboard reported the generation as done.
##
## The drafts are where a name is authored, so they are where it is refused.
##
## Persistence is exercised against a redirected path. The real one is the
## project's own draft file, and a test suite has no business writing over a
## designer's work to prove it can write.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const GASEngineProjectSettings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")

## The setting the drafts read their path from, named through the constant
## rather than retyped: a literal here would drift the moment it moved.
const SETTING: String = (
	GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_ATTRIBUTES_DRAFT_CONFIG_FILE
)
const REDIRECTED: String = "user://test_attribute_drafts.cfg"

const SET_NAME: String = "Combat"
const ATTRIBUTE: String = "max_health"

var drafts: AttributeSetDrafts = null
var _original_path: Variant = null
## Whether the project declared the setting at all before the redirect.
## Restoring only when a previous value existed leaves the redirect standing
## on a project that declared none - which is this one - so the scratch path
## outlived the suite and reached `project.godot` the next time anything saved.
var _had_original: bool = false


func before_each() -> void:
	_had_original = ProjectSettings.has_setting(SETTING)
	if _had_original:
		_original_path = ProjectSettings.get_setting(SETTING)
	ProjectSettings.set_setting(SETTING, REDIRECTED)
	drafts = AttributeSetDrafts.new()


func after_each() -> void:
	drafts = null
	if _had_original:
		ProjectSettings.set_setting(SETTING, _original_path)
	else:
		# `null` is how ProjectSettings deletes a setting, and "there was none"
		# is the state this has to restore.
		ProjectSettings.set_setting(SETTING, null)
	_had_original = false
	_original_path = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REDIRECTED))


## The names a designer might reasonably type that GDScript cannot accept.
func _illegal_names() -> Array[String]:
	return ["max health", "2nd_wind", "crit-chance", "attack!", " leading", ""] as Array[String]


## Legal characters, illegal names: every one of these passes
## is_valid_identifier and none of them survives `var <name>:`.
func _reserved_names() -> Array[String]:
	return ["class", "func", "signal", "var", "self", "null", "in", "is"] as Array[String]


#region Attribute names
## Two ways for a name to be one the generator could not emit, and one
## refusal. Characters GDScript will not take inside a name, and words it
## will not take as one.
func test_an_attribute_name_the_generator_could_not_emit_is_refused() -> void:
	drafts.create_set(SET_NAME)
	for name: String in _illegal_names() + _reserved_names():
		assert_false(
			drafts.add_attribute(SET_NAME, name, AttributeSetDrafts.Entry.of(1.0)),
			"'" + name + "' cannot be the name in the generated `var <name>:`"
		)
	assert_eq(drafts.attribute_names(SET_NAME).size(), 0, "and none were stored")

	# Renaming into one is the same mistake arriving later.
	drafts.add_attribute(SET_NAME, ATTRIBUTE, AttributeSetDrafts.Entry.of(1.0))
	assert_false(drafts.rename_attribute(SET_NAME, ATTRIBUTE, "class"))


func test_a_name_that_only_looks_reserved_is_accepted() -> void:
	# The counterweight: refusing too much costs a designer a word they could
	# have had. GDScript takes all five of these as member names, which is why
	# the list was verified against the parser rather than written from memory.
	drafts.create_set(SET_NAME)
	for name: String in ["match", "when", "range", "min", "max"] as Array[String]:
		assert_true(
			drafts.add_attribute(SET_NAME, name, AttributeSetDrafts.Entry.of(1.0)),
			"'" + name + "' reads like a keyword and is not one"
		)


func test_a_set_named_for_a_reserved_word_is_still_accepted() -> void:
	# The asymmetry is deliberate: a set is emitted as
	# `class_name <name>AttributeSet`, and the suffix carries even `class`
	# into a legal identifier. Refusing it here would cost a name for nothing.
	assert_true(drafts.create_set("class"), "the suffix makes it legal")


func test_a_legal_attribute_name_is_accepted() -> void:
	drafts.create_set(SET_NAME)
	assert_true(drafts.add_attribute(SET_NAME, ATTRIBUTE, AttributeSetDrafts.Entry.of(100.0)))
	assert_true(drafts.has_attribute(SET_NAME, ATTRIBUTE))


func test_renaming_an_attribute_to_an_illegal_name_is_refused() -> void:
	drafts.create_set(SET_NAME)
	drafts.add_attribute(SET_NAME, ATTRIBUTE, AttributeSetDrafts.Entry.of(100.0))

	assert_false(drafts.rename_attribute(SET_NAME, ATTRIBUTE, "max health"))
	assert_true(drafts.has_attribute(SET_NAME, ATTRIBUTE), "the original is untouched")
#endregion


#region Set names
## A set name becomes part of a class name, so it has to be an identifier too.
func test_a_set_name_that_is_not_an_identifier_is_refused() -> void:
	for name: String in _illegal_names():
		assert_false(
			drafts.create_set(name),
			"'" + name + "' would be written into `class_name " + name + "AttributeSet`"
		)
	assert_eq(drafts.set_names().size(), 0)


func test_renaming_a_set_to_an_illegal_name_is_refused() -> void:
	drafts.create_set(SET_NAME)
	assert_false(drafts.rename_set(SET_NAME, "My Set"))
	assert_true(drafts.has_set(SET_NAME), "the original is untouched")
#endregion


#region Persistence
## Every mutation saves, and the save has to actually land: the whole reason
## these methods persist for the caller is that a forgotten write loses a
## designer's work without saying so. A write that fails and is not reported is
## the same loss.
func test_a_mutation_reaches_disk_and_reads_back() -> void:
	assert_true(drafts.create_set(SET_NAME))
	assert_true(drafts.add_attribute(SET_NAME, ATTRIBUTE, AttributeSetDrafts.Entry.of(42.0)))

	assert_true(FileAccess.file_exists(REDIRECTED), "the draft file is really there")

	var reloaded: AttributeSetDrafts = AttributeSetDrafts.new()
	reloaded.load_from_disk()
	assert_true(reloaded.has_set(SET_NAME), "the set survived the round trip")
	assert_almost_eq(reloaded.entry(SET_NAME, ATTRIBUTE).value, 42.0, 0.0001)
#endregion
