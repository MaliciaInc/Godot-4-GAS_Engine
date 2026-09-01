## What the attribute-set generator actually emits.
##
## The writer's own header says a generator that emits code which does not
## compile "is worse than no generator: it produces a file that looks
## authored", and it was written pure - names and numbers in, text out -
## precisely so that could be asserted rather than inspected by opening the
## generated file. Nothing asserted it.
##
## So these tests compile the emitted source and run it. A string comparison
## would pass against source that GDScript refuses, and it would have to be
## rewritten every time a comment in the template moved; what matters is that
## the file parses, that the hooks it declares really override the ones
## AttributeSet declares, and that the clamps it writes clamp.
##
## @meta_license: MIT
extends GutTest

const Writer = preload("res://addons/GAS_Engine/editor/attribute_set_script_writer.gd")

## Not a name any real project would author, so the generated class cannot
## collide with something the editor already registered.
const SET_NAME: String = "GutProbeCombat"

const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const MIN_HEALTH: StringName = &"min_health"
const MANA: StringName = &"mana"
const MAX_MANA: StringName = &"max_mana"
const STAMINA: StringName = &"stamina"

const TOLERANCE: float = 0.0001


func _attribute(name: StringName, value: float) -> Writer.Attribute:
	return Writer.Attribute.of(String(name), value)


## health has both bounds, mana only an upper one, stamina neither.
func _bounded_set() -> Array[Writer.Attribute]:
	return [
		_attribute(HEALTH, 80.0),
		_attribute(MAX_HEALTH, 100.0),
		_attribute(MIN_HEALTH, 10.0),
		_attribute(MANA, 30.0),
		_attribute(MAX_MANA, 50.0),
		_attribute(STAMINA, 7.0),
	] as Array[Writer.Attribute]


## Compile the emitted source, or fail and answer null so a caller can stop.
##
## Returning null rather than letting the caller dereference a script that
## never compiled: an assertion failure does not end a GUT test function, and
## a null dereference here would stop the whole run at the debugger.
func _compiled(attributes: Array[Writer.Attribute]) -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = Writer.write(SET_NAME, attributes)
	var status: Error = script.reload()
	assert_eq(status, OK, "the generated source compiles")
	return script if status == OK else null


func _instance(attributes: Array[Writer.Attribute]) -> AttributeSet:
	var script: GDScript = _compiled(attributes)
	if script == null:
		return null
	var made: Variant = script.new()
	assert_true(made is AttributeSet, "the generated class is an AttributeSet")
	return made if made is AttributeSet else null


#region The file it names
func test_a_set_name_becomes_a_snake_case_file_name() -> void:
	assert_eq(Writer.file_name_for("GutProbeCombat"), "gut_probe_combat_attribute_set.gd")
	assert_eq(Writer.file_name_for("Combat"), "combat_attribute_set.gd")
#endregion


#region It compiles
func test_the_generated_source_compiles() -> void:
	assert_not_null(_compiled(_bounded_set()))


func test_a_set_with_no_attributes_still_compiles() -> void:
	var empty: Array[Writer.Attribute] = []
	assert_not_null(_compiled(empty), "an empty draft is a legal draft")


## Every name is a bound, so no attribute is bounded by anything - the branch
## where both emitted `match` statements have no case to write at all.
func test_a_set_of_nothing_but_bounds_still_compiles() -> void:
	var bounds_only: Array[Writer.Attribute] = [
		_attribute(MAX_HEALTH, 100.0), _attribute(MIN_HEALTH, 0.0)
	] as Array[Writer.Attribute]
	assert_not_null(_compiled(bounds_only))


## A default that is not a whole number, which `str()` renders differently.
func test_a_fractional_default_survives_into_compilable_source() -> void:
	var fractional: Array[Writer.Attribute] = [
		_attribute(STAMINA, 0.25)
	] as Array[Writer.Attribute]
	var instance: AttributeSet = _instance(fractional)
	if instance == null:
		return
	var stamina: AttributeData = instance.get(String(STAMINA))
	assert_not_null(stamina, "the attribute was declared")
	if stamina != null:
		assert_almost_eq(stamina.base_value, 0.25, TOLERANCE)
#endregion


#region The attributes it declares
func test_every_drafted_attribute_is_declared_with_its_default() -> void:
	var instance: AttributeSet = _instance(_bounded_set())
	if instance == null:
		return
	var declared: Array[StringName] = instance.get_attribute_names()
	for expected: StringName in [HEALTH, MAX_HEALTH, MIN_HEALTH, MANA, MAX_MANA, STAMINA]:
		assert_true(declared.has(expected), "declared " + String(expected))

	var health: AttributeData = instance.get(String(HEALTH))
	assert_almost_eq(health.base_value, 80.0, TOLERANCE, "and carries its drafted default")
	assert_almost_eq(health.current_value, 80.0, TOLERANCE, "on both fields")
#endregion


#region The clamps it writes
## The hooks have to be real overrides. A generated signature that drifted from
## AttributeSet's own would be a method the engine never calls, and every
## assertion here would pass against the inherited pass-through instead.
##
## One test over the whole table rather than one per shape of attribute: each
## reading is a single call to the same emitted `match`, and tests differing
## only in two numbers say the same thing several times. Both hooks are read,
## because only the derived one used to be emitted - which is how a character
## reached base -400 and stayed dead through a full heal.
func test_the_clamps_bound_each_attribute_by_the_siblings_it_has() -> void:
	var instance: AttributeSet = _instance(_bounded_set())
	if instance == null:
		return

	# health has both bounds.
	assert_almost_eq(
		instance.pre_attribute_base_change(HEALTH, 500.0), 100.0, TOLERANCE, "capped at max_health"
	)
	assert_almost_eq(
		instance.pre_attribute_base_change(HEALTH, -400.0), 10.0, TOLERANCE, "floored at min_health"
	)
	assert_almost_eq(
		instance.pre_attribute_base_change(HEALTH, 55.0), 55.0, TOLERANCE, "left alone between them"
	)
	assert_almost_eq(
		instance.pre_attribute_change(HEALTH, 500.0), 100.0, TOLERANCE, "and the derived value the same"
	)
	assert_almost_eq(
		instance.pre_attribute_change(HEALTH, -400.0), 10.0, TOLERANCE, "on both ends"
	)

	# mana has only an upper bound, so the floor is the emitted default.
	assert_almost_eq(
		instance.pre_attribute_base_change(MANA, 500.0), 50.0, TOLERANCE, "max_mana is the ceiling"
	)
	assert_almost_eq(
		instance.pre_attribute_base_change(MANA, -5.0), 0.0, TOLERANCE,
		"no min_mana was drafted, so zero is the floor"
	)

	# stamina has neither, and nothing declares the last name at all.
	assert_almost_eq(
		instance.pre_attribute_base_change(STAMINA, 9999.0), 9999.0, TOLERANCE, "no ceiling"
	)
	assert_almost_eq(
		instance.pre_attribute_base_change(STAMINA, -12.0), -12.0, TOLERANCE,
		"and a stat with no bound may be negative"
	)
	assert_almost_eq(
		instance.pre_attribute_base_change(&"nothing_here", 42.0), 42.0, TOLERANCE,
		"a name the set never declared passes straight through"
	)
#endregion


#region The dependency hook it writes
## One story rather than four tests of one line each: the same instance is
## pushed through every case the emitted `match` can take, in an order where
## each reading depends on the last.
func test_a_bound_moving_trims_only_the_attribute_it_bounds() -> void:
	var instance: AttributeSet = _instance(_bounded_set())
	if instance == null:
		return
	var health: AttributeData = instance.get(String(HEALTH))
	assert_not_null(health, "health was declared")
	if health == null:
		return

	instance.post_attribute_change(null, &"max_stamina", 10.0, 1.0)
	assert_almost_eq(health.base_value, 80.0, TOLERANCE, "a bound nothing declares moves nothing")

	instance.post_attribute_change(null, MAX_HEALTH, 100.0, 250.0)
	assert_almost_eq(health.base_value, 80.0, TOLERANCE, "a higher ceiling is not a heal")

	instance.post_attribute_change(null, MAX_HEALTH, 250.0, 40.0)
	assert_almost_eq(health.base_value, 40.0, TOLERANCE, "a lower ceiling brings the durable value down")
	assert_almost_eq(health.current_value, 40.0, TOLERANCE, "and the derived one with it")

	instance.post_attribute_change(null, MIN_HEALTH, 10.0, 95.0)
	assert_almost_eq(health.base_value, 95.0, TOLERANCE, "a higher floor lifts it back")
	assert_almost_eq(health.current_value, 95.0, TOLERANCE, "on both fields again")
#endregion
