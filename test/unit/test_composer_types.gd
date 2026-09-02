## Which wires may be drawn.
##
## The claim under all of this is that a refused wire is a `.gd` that would not
## compile, so the tests are written against GDScript's own rules rather than
## against a table someone chose: the same type, a subclass reaching a base, an
## int widening into a float. If this ever disagrees with the language, the
## Composer is either refusing legal code or promising illegal code, and both
## are worse than no type system at all.
##
## @meta_license: MIT
extends GutTest

const EXEC_IN: StringName = &"exec_in"
const EXEC_OUT: StringName = &"exec_out"


func _port(
	kind: ComposerNode.PortKind, direction: ComposerNode.PortDirection, type_name: StringName
) -> ComposerNode.Port:
	var made: ComposerNode.Port = ComposerReader.port(EXEC_IN, kind, direction)
	made.type_name = type_name
	return made


func _out(type_name: StringName) -> ComposerNode.Port:
	return _port(ComposerNode.PortKind.DATA, ComposerNode.PortDirection.OUTPUT, type_name)


func _in(type_name: StringName) -> ComposerNode.Port:
	return _port(ComposerNode.PortKind.DATA, ComposerNode.PortDirection.INPUT, type_name)


#region What GDScript allows
func test_the_same_type_fits_itself() -> void:
	assert_true(ComposerTypes.accepts(&"float", &"float"), "float into float")
	assert_true(
		ComposerTypes.accepts(&"GameplayEffect", &"GameplayEffect"), "and an engine type"
	)


## GDScript widens an int into a float and refuses the other direction. So does
## this: a wire that quietly drops the fraction is one nobody meant to draw.
func test_an_int_widens_into_a_float_but_not_the_other_way() -> void:
	assert_true(ComposerTypes.accepts(&"float", &"int"), "int fits a float")
	assert_false(ComposerTypes.accepts(&"int", &"float"), "and a float does not fit an int")


## Read from the project, not written down here. If someone changes a base
## class, this follows without anyone editing the type system.
func test_a_subclass_reaches_its_base() -> void:
	assert_true(
		ComposerTypes.inherits(&"GameplayAbility", &"Node"),
		"an ability is a Node, through however many steps the project declares"
	)
	assert_true(
		ComposerTypes.accepts(&"Node", &"GameplayAbility"), "so it fits a Node slot"
	)
	assert_false(
		ComposerTypes.accepts(&"GameplayAbility", &"Node"),
		"and a Node does not fit an ability slot"
	)


## An untyped slot takes anything, because GDScript lets it. Refusing here would
## be this tool being stricter than the language and calling legal code an error.
func test_an_untyped_slot_takes_anything() -> void:
	assert_true(ComposerTypes.accepts(&"", &"GameplayEffect"), "nothing was asked for")
	assert_true(ComposerTypes.accepts(&"Variant", &"float"), "nor here")
#endregion


#region What it refuses, and how it says so
func test_unrelated_types_do_not_fit() -> void:
	assert_false(ComposerTypes.accepts(&"GameplayEffectHandle", &"float"), "unrelated")
	assert_false(ComposerTypes.accepts(&"Vector3", &"Vector2"), "and near-misses too")


## Naming both ends is the difference between a message someone can act on and
## one that sends them to compare two ports by eye.
func test_a_refusal_names_both_ends() -> void:
	var said: String = ComposerTypes.refusal(&"GameplayEffectHandle", &"float")

	assert_true(said.contains("float"), "what was offered: %s" % said)
	assert_true(said.contains("GameplayEffectHandle"), "and what was wanted: %s" % said)
	assert_eq(ComposerTypes.refusal(&"float", &"int"), "", "and says nothing when it fits")
#endregion


#region Ports
## Nothing else stops a person joining a value to a run of control. Flow is
## horizontal, so both families arrive on the same sides and only this keeps
## them apart.
func test_execution_and_data_do_not_meet() -> void:
	var run: ComposerNode.Port = _port(
		ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT, &""
	)
	assert_false(ComposerTypes.ports_match(run, _in(&"float")), "a run is not a value")


func test_a_wire_leaves_an_output_and_lands_on_an_input() -> void:
	assert_true(
		ComposerTypes.ports_match(_out(&"float"), _in(&"float")), "out to in"
	)
	assert_false(
		ComposerTypes.ports_match(_in(&"float"), _out(&"float")), "never in to out"
	)
	assert_false(
		ComposerTypes.ports_match(_out(&"float"), _out(&"float")), "nor out to out"
	)


## Execution carries no value, so its ports have nothing to compare. Asking the
## type system about them would refuse every control wire in the graph.
func test_execution_ports_join_without_a_type() -> void:
	var from: ComposerNode.Port = _port(
		ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.OUTPUT, &""
	)
	var to: ComposerNode.Port = _port(
		ComposerNode.PortKind.EXECUTION, ComposerNode.PortDirection.INPUT, &""
	)
	assert_true(ComposerTypes.ports_match(from, to), "control flows regardless")


func test_a_missing_port_is_not_a_match() -> void:
	assert_false(ComposerTypes.ports_match(null, _in(&"float")), "nothing to leave from")
	assert_false(ComposerTypes.ports_match(_out(&"float"), null), "nowhere to land")
#endregion


#region Against the catalog
## The types the catalog reads off the engine are the ones this decides about.
## A wire into `apply_gameplay_effect`'s first slot has to accept the very thing
## the method declares, or the Composer and the compiler disagree.
func test_a_catalog_parameter_accepts_what_the_method_declares() -> void:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(&"apply_gameplay_effect")
	var wanted: StringName = entry.parameters[0].type_name

	assert_eq(wanted, &"GameplayEffect", "read from the method")
	assert_true(ComposerTypes.accepts(wanted, wanted), "and it accepts its own type")
	assert_false(ComposerTypes.accepts(wanted, &"float"), "but not a number")


## A local's written type reaches its port, so a real read graph carries types
## the system can actually decide about.
##
## Without this the value port would claim to carry nothing and every wire out
## of it would pass by default - a type system that agrees with everything.
func test_a_local_carries_its_written_type_onto_its_port() -> void:
	var source: String = "\n".join(PackedStringArray([
		"extends GameplayAbility", "", "",
		"func _activate_ability() -> void:",
		"\tvar target: GameplayAbilityTargetData = await wait_target_data()",
	]))
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")
	var value: ComposerNode.Port = graph.nodes[0].find_port(ComposerReader.VALUE_OUT)

	assert_not_null(value, "the local offers a value")
	assert_eq(
		value.type_name, &"GameplayAbilityTargetData", "typed as the file typed it"
	)
	assert_true(
		ComposerTypes.accepts(&"GameplayAbilityTargetData", value.type_name),
		"and it fits a slot asking for one"
	)
#endregion
