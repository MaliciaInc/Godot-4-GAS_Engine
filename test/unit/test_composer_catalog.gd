## The node catalog: what the Composer offers, and what those calls take.
##
## One test here matters more than the rest, and it is the one that walks the
## curated list and demands every method still exists on the class it claims to
## be on. The catalog is the only hand-written half of this - the signatures are
## read from the engine - so it is the only half that can drift, and a name that
## drifts produces a node printing an argument nobody accepts.
##
## @meta_license: MIT
extends GutTest


#region Held against the engine
## Every offered call exists, on the class it says it does.
##
## Without this the curated list is a declared authority sitting beside the tree
## it describes, which is the failure this project keeps meeting: it stays right
## until someone renames a method, and then it is wrong everywhere at once and
## silent about it.
func test_every_offered_call_still_exists_on_its_class() -> void:
	for row: Array in ComposerCatalog.OFFERED:
		var method: String = row[0]
		var path: String = row[2]
		var script: GDScript = load(path) as GDScript
		assert_not_null(script, "%s is a script" % path)

		var found: bool = false
		for described: Dictionary in script.get_script_method_list():
			var name: String = described["name"]
			if name == method:
				found = true
				break
		assert_true(found, "%s() is still on %s" % [method, path.get_file()])


## The list and what was built from it agree. An entry that failed to build is
## the same silence the test above exists to prevent.
func test_every_offered_call_became_an_entry() -> void:
	assert_eq(
		ComposerCatalog.all().size(), ComposerCatalog.OFFERED.size(),
		"nothing was quietly dropped on the way in"
	)


func test_every_entry_belongs_to_a_group_the_palette_shows() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		assert_true(
			ComposerCatalog.GROUPS.has(entry.group),
			"%s is in a group the palette lists: %s" % [entry.type_id, entry.group]
		)
#endregion


#region Signatures come from the engine
## The parameter names are the engine's own, not a copy of them.
##
## Read from the method, so a renamed parameter reaches the card without anyone
## editing this file - and a parameter that no longer exists cannot linger here
## claiming it does.
func test_parameters_carry_the_names_the_engine_uses() -> void:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(&"apply_gameplay_effect")

	assert_not_null(entry, "the call is offered")
	assert_eq(entry.parameters.size(), 3, "as many fields as the method takes")
	assert_eq(entry.parameters[0].label, "Effect", "spelled the way a person reads it")
	assert_eq(entry.parameters[0].type_name, &"GameplayEffect", "with its written type")
	assert_eq(entry.parameters[2].label, "Effect Level", "and so is the last")


func test_a_call_with_no_arguments_has_no_parameters() -> void:
	assert_eq(
		ComposerCatalog.find(&"commit_ability").parameters.size(), 0, "it takes nothing"
	)


## A built-in type has no class name, so it is reported by its own name rather
## than as an empty string that would read as "untyped" on a card.
func test_a_builtin_parameter_still_reports_a_type() -> void:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(&"add_tag")

	assert_eq(entry.parameters[0].label, "Tag", "named")
	assert_eq(entry.parameters[0].type_name, &"StringName", "and typed")


## The word `await` on a card comes from here, not from guessing at a method's
## name. A call that suspends is a fact about the API, not about its spelling.
func test_the_calls_that_suspend_are_marked_as_such() -> void:
	assert_true(ComposerCatalog.find(&"wait_target_data").awaits, "this one waits")
	assert_false(ComposerCatalog.find(&"add_tag").awaits, "and this one does not")


func test_an_unoffered_call_is_simply_not_found() -> void:
	assert_null(
		ComposerCatalog.find(&"no_such_method"),
		"asking about something outside the catalog is not an error"
	)
#endregion


#region What the reader does with it
## The card shows the engine's parameter name instead of a position.
func test_a_read_statement_takes_its_field_names_from_the_catalog() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tadd_tag(state_burning)\n"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(graph.nodes[0].title, "Add Tag", "named by the catalog")
	assert_eq(graph.nodes[0].fields[0].label, "Tag", "and its argument too")
	assert_eq(graph.nodes[0].fields[0].display, "state_burning", "carrying what was written")


## A call the catalog does not offer still draws. A person may write anything
## the subset admits, and refusing to show it would make the graph a partial
## view of the file - which is the one thing it must never be.
func test_a_call_outside_the_catalog_still_draws_with_positional_fields() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tmy_own_helper(alpha, beta)\n"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(graph.nodes.size(), 1, "it is drawn")
	assert_eq(graph.nodes[0].fields[0].label, "#1", "claiming only the position")
	assert_eq(graph.nodes[0].fields[1].display, "beta", "and carrying the text")
#endregion
