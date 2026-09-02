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
##
## Asked as presence rather than as a count, because a game may offer nodes of
## its own and a count would then be a test of who ran before it.
func test_every_offered_call_became_an_entry() -> void:
	for row: Array in ComposerCatalog.OFFERED:
		var method: String = row[0]
		assert_true(
			ComposerCatalog.all().has(StringName(method)),
			"%s was not quietly dropped on the way in" % method
		)


func test_every_entry_belongs_to_a_group_the_palette_shows() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		assert_true(
			ComposerCatalog.groups().has(entry.group),
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


#region A game's own calls
## Everything below registers against a fixture the engine has never heard of.
## If any of it needed a change inside the addon to pass, the Composer would have
## learned something about a particular game and the framework would be less
## portable than it claims.
const GAME_SCRIPT: String = "res://test/fixtures/game_composer_nodes.gd"
const OTHER_SCRIPT: String = "res://test/fixtures/probe_ability.gd"
const STAMINA: StringName = &"Stamina"


func after_each() -> void:
	ComposerCatalog.forget(&"spend_stamina")
	ComposerCatalog.forget(&"play_flourish")


func _offer_stamina() -> String:
	return ComposerCatalog.register("spend_stamina", STAMINA, GAME_SCRIPT, false)


## The signature is read off the game's script exactly as it is off the engine's.
func test_a_game_can_offer_a_call_of_its_own() -> void:
	assert_eq(_offer_stamina(), "", "admitted")

	var entry: ComposerCatalog.Entry = ComposerCatalog.find(&"spend_stamina")
	assert_not_null(entry, "and it is offered")
	assert_eq(entry.title, "Spend Stamina", "named the way a person says it")
	assert_eq(entry.parameters[0].label, "Amount", "with the game's own parameter name")
	assert_eq(entry.parameters[0].type_name, &"float", "and its written type")
	assert_eq(entry.required, 1, "one required, one carrying a default")


## The claim that there are no privileged nodes, asked as behaviour rather than
## as an assertion about the code. The same file is read, checked and printed
## before and after registering, and the only difference is how much the tool
## knows about it.
func test_a_registered_call_is_read_checked_and_printed_like_any_other() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tvar cost: float = get_ability_level()\n\tspend_stamina(cost)\n"
	)

	var before: ComposerGraph = ComposerReader.read(source, "res://a.gd")
	assert_eq(before.nodes[1].fields[0].label, "#1", "unknown, so only the position")

	assert_eq(_offer_stamina(), "", "admitted")
	var after: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(after.nodes.size(), before.nodes.size(), "the same file, the same nodes")
	assert_eq(after.nodes[1].fields[0].label, "Amount", "now named by the game's script")
	assert_eq(after.nodes[1].fields[0].type_name, &"float", "and typed by it")
	assert_eq(after.diagnostics.size(), 0, "nothing wrong with it")

	after.nodes[1].dirty = true
	var body: PackedStringArray = ComposerWriter.print_body(after)
	assert_eq(body[1], "\tspend_stamina(cost)", "and it prints itself, with no template")


## Registration adds knowledge, never permission. A call nobody registered still
## draws - a graph that hid the lines it had no entry for would be a partial view
## of the file, which is the one thing it must never be.
func test_an_unregistered_call_is_drawn_and_never_called_wrong() -> void:
	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tspend_stamina()\n"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(graph.nodes.size(), 1, "drawn")
	assert_eq(graph.diagnostics.size(), 0, "and not accused of anything")


## Once it is registered, the same short call is a gap the validator can see.
func test_registering_is_what_lets_the_validator_see_a_missing_argument() -> void:
	assert_eq(_offer_stamina(), "", "admitted")
	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tspend_stamina()\n"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(graph.diagnostics.size(), 1, "now it knows what the call needs")
	assert_true(graph.diagnostics[0].message.contains("Amount"), "and says which")


## Reflection cannot tell whether a method suspends, so the game answers.
func test_a_game_says_for_itself_whether_its_call_suspends() -> void:
	assert_eq(ComposerCatalog.register("play_flourish", STAMINA, GAME_SCRIPT, true), "")

	assert_eq(_offer_stamina(), "", "and one that does not")

	assert_true(ComposerCatalog.find(&"play_flourish").awaits, "the game said so")
	assert_false(ComposerCatalog.find(&"spend_stamina").awaits, "and said so here too")
#endregion


#region When a registration is refused
## A pack that registers again after an editor reload is being careful, not
## wrong. Refusing would push every pack towards guarding a call it should be
## free to repeat.
func test_offering_the_same_call_twice_is_not_a_conflict() -> void:
	assert_eq(_offer_stamina(), "", "the first time")
	assert_eq(_offer_stamina(), "", "and the second")
	assert_eq(ComposerCatalog.entries(STAMINA).size(), 1, "offered once")


## Two packs claiming one name is a conflict only a person can settle. Letting
## the last one win would make the palette depend on load order, which is the
## kind of bug that only shows up on someone else's machine.
func test_a_second_script_cannot_take_a_name_already_offered() -> void:
	assert_eq(_offer_stamina(), "", "the first holds it")

	var refused: String = ComposerCatalog.register(
		"spend_stamina", STAMINA, OTHER_SCRIPT, false
	)

	assert_true(refused.contains("already offered"), "refused: %s" % refused)
	assert_true(refused.contains(GAME_SCRIPT), "naming who holds it: %s" % refused)
	assert_eq(ComposerCatalog.find(&"spend_stamina").source, GAME_SCRIPT, "and it kept it")
	assert_push_error(ComposerCatalog.REFUSED % refused)


## Every way a registration can name something that is not there, and the words
## each one gets.
##
## One table rather than one test apiece: they differ only in what was wrong and
## what was said about it, and a missing path collapsed into the same message as
## a file holding the wrong thing would send someone looking for a file that is
## sitting right where they put it.
const BAD_REGISTRATIONS: Array[Array] = [
	["no_such_call", GAME_SCRIPT, "no_such_call", "a method the script does not declare"],
	["spend_stamina", "res://nowhere.gd", "nothing at", "a path with nothing on it"],
	[
		"spend_stamina", "res://test/gut_headless_runner.tscn", "is not a script",
		"a path holding something else",
	],
]


func test_a_registration_that_names_nothing_real_is_refused() -> void:
	for row: Array in BAD_REGISTRATIONS:
		var method: String = row[0]
		var path: String = row[1]
		var expected: String = row[2]
		var described: String = row[3]

		var refused: String = ComposerCatalog.register(method, STAMINA, path, false)

		assert_true(refused.contains(expected), "%s: %s" % [described, refused])
		assert_null(ComposerCatalog.find(StringName(method)), "%s: nothing offered" % described)
		assert_push_error(ComposerCatalog.REFUSED % refused)
#endregion


#region What the palette is told
## A game's category shows up after the engine's own, in the order it was
## offered. Someone opening the palette should meet what they came for in the
## place they left it, not wherever a dictionary happened to put it.
func test_a_game_category_appears_after_the_engine_own() -> void:
	assert_false(ComposerCatalog.groups().has(STAMINA), "not there yet")

	assert_eq(_offer_stamina(), "", "admitted")

	var groups: Array[StringName] = ComposerCatalog.groups()
	assert_eq(groups[groups.size() - 1], STAMINA, "last, after everything the engine ships")
	assert_eq(
		groups.slice(0, ComposerCatalog.GROUPS.size()), ComposerCatalog.GROUPS,
		"and it moved none of them"
	)


## A pack whose addon is switched off has to be able to withdraw, or the palette
## keeps offering a call into a class that is no longer there.
func test_withdrawing_a_call_takes_its_category_with_it() -> void:
	assert_eq(_offer_stamina(), "", "admitted")

	ComposerCatalog.forget(&"spend_stamina")

	assert_null(ComposerCatalog.find(&"spend_stamina"), "gone")
	assert_false(ComposerCatalog.groups().has(STAMINA), "and its category with it")


## The panel is drawn once and lives for as long as the editor does. Without a
## way to tell that the vocabulary moved, a registration that arrives afterwards
## is invisible and reads to the person who wrote it as having done nothing.
func test_the_vocabulary_says_when_it_changed() -> void:
	var quiet: int = ComposerCatalog.revision()
	assert_eq(ComposerCatalog.revision(), quiet, "reading it changes nothing")

	assert_eq(_offer_stamina(), "", "admitted")
	var offered: int = ComposerCatalog.revision()
	assert_ne(offered, quiet, "offering does")

	ComposerCatalog.forget(&"spend_stamina")
	assert_ne(ComposerCatalog.revision(), offered, "and so does withdrawing")


## One door, proved rather than asserted: an entry only carries a source because
## the admission put it there, so the engine's own calls came in the same way a
## game's does. A shortcut for the core would leave this empty.
func test_the_engine_own_calls_came_through_the_same_door() -> void:
	for row: Array in ComposerCatalog.OFFERED:
		var method: String = row[0]
		var path: String = row[2]
		var entry: ComposerCatalog.Entry = ComposerCatalog.find(StringName(method))
		assert_eq(entry.source, path, "%s was admitted, not installed" % method)
#endregion
