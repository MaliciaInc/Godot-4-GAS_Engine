## Saying which entity, which definition and which run, on two machines at once.
##
## The whole subject of this file is one refusal: an ObjectID must never cross
## the network. It is a slot in one process's object table - different on every
## machine, handed out again the moment something is freed - so a message
## carrying one arrives meaning nothing, or meaning somebody else. Everything
## here is the alternative to that, and the last test in the file is the
## refusal itself, asked of the source.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const NETWORKING: String = "res://addons/GAS_Engine/networking"

const A_PATH: String = "res://abilities/fireball.tscn"
const ANOTHER_PATH: String = "res://abilities/frostbolt.tscn"


#region Entities
func test_an_entity_id_is_the_number_it_was_assigned() -> void:
	var assigned: GameplayNetEntityId = GameplayNetEntityId.of(7)

	assert_true(assigned.is_valid())
	assert_eq(assigned.to_wire(), 7, "and that is what travels")
	assert_true(assigned.same_as(GameplayNetEntityId.from_wire(7)), "there and back")


## Nobody is not entity zero.
func test_an_unassigned_entity_id_names_nobody() -> void:
	var nobody: GameplayNetEntityId = GameplayNetEntityId.new()

	assert_false(nobody.is_valid())
	assert_false(nobody.same_as(GameplayNetEntityId.new()), "two nobodies are not each other")


## Compared by what it says, not by which object is holding it: an id off the
## wire is a new object every time, and identity would answer false to every
## question worth asking.
func test_two_ids_for_one_entity_are_the_same_id() -> void:
	assert_true(GameplayNetEntityId.of(3).same_as(GameplayNetEntityId.of(3)))
	assert_false(GameplayNetEntityId.of(3).same_as(GameplayNetEntityId.of(4)))
#endregion


#region Definitions
## Derived, not assigned: both machines already have the same file.
func test_a_definition_id_is_the_same_on_both_machines() -> void:
	var here: GameplayNetDefinitionId = GameplayNetDefinitionId.of_path(A_PATH)
	var there: GameplayNetDefinitionId = GameplayNetDefinitionId.of_path(A_PATH)

	assert_true(here.same_as(there), "one file, one id")
	assert_false(
		here.same_as(GameplayNetDefinitionId.of_path(ANOTHER_PATH)), "and a different file is not"
	)


## A resource that was never saved cannot be named to another machine, so it
## does not get an id that would let it be sent as if it could.
func test_a_definition_with_nowhere_to_live_has_no_id() -> void:
	assert_false(GameplayNetDefinitionId.of_path("").is_valid())
	assert_false(GameplayNetDefinitionId.of_resource(GameplayEffect.new()).is_valid())
	assert_false(GameplayNetDefinitionId.of_resource(null).is_valid())
#endregion


#region Runs of an ability
## Which entity and which of its runs, because a sequence alone collides across
## characters the moment two of them cast at once.
func test_an_activation_id_is_an_entity_and_one_of_its_runs() -> void:
	var mine: GameplayNetActivationId = GameplayNetActivationId.of(GameplayNetEntityId.of(1), 4)

	assert_true(mine.is_valid())
	assert_true(
		mine.same_as(GameplayNetActivationId.of(GameplayNetEntityId.of(1), 4)), "the same run"
	)
	assert_false(
		mine.same_as(GameplayNetActivationId.of(GameplayNetEntityId.of(2), 4)),
		"another character's fourth cast is not this one"
	)
	assert_false(
		mine.same_as(GameplayNetActivationId.of(GameplayNetEntityId.of(1), 5)),
		"and neither is this character's fifth"
	)


func test_half_an_activation_id_names_nothing() -> void:
	assert_false(
		GameplayNetActivationId.of(GameplayNetEntityId.new(), 4).is_valid(), "nobody's fourth cast"
	)
	assert_false(
		GameplayNetActivationId.of(GameplayNetEntityId.of(1), 0).is_valid(),
		"and a character with no cast is the character, not a cast"
	)


func test_an_activation_id_survives_the_wire() -> void:
	var sent: GameplayNetActivationId = GameplayNetActivationId.of(GameplayNetEntityId.of(9), 2)

	var arrived: GameplayNetActivationId = GameplayNetActivationId.from_wire(sent.to_wire())

	assert_true(arrived.same_as(sent))
	assert_false(GameplayNetActivationId.from_wire(PackedInt64Array([1])).is_valid(), "half of it is not one")
#endregion


#region Guesses, and what was built on them
## A key done because of another one remembers what it stood on.
func test_a_derived_key_depends_on_the_one_it_was_built_on() -> void:
	var first: GameplayPredictionKey = GameplayPredictionKey.of(2, 1)
	var second: GameplayPredictionKey = first.deriving(2)
	var third: GameplayPredictionKey = second.deriving(3)

	assert_true(third.depends_on(first), "however far down")
	assert_true(third.depends_on(second))
	assert_false(first.depends_on(third), "and not the other way round")
	assert_false(first.depends_on(second))


## The order a rejection is reversed in: the newest guess comes off before the
## one it was made on top of.
func test_a_chain_reads_from_the_newest_guess_down() -> void:
	var first: GameplayPredictionKey = GameplayPredictionKey.of(2, 1)
	var third: GameplayPredictionKey = first.deriving(2).deriving(3)

	var standing: Array[GameplayPredictionKey] = third.chain()

	assert_eq(standing.size(), 3, "all three of them")
	assert_eq(standing[0].value, 3, "newest first")
	assert_eq(standing[2].value, 1, "and what everything stood on last")


## Two clients count from one independently, so a server hearing key 7 from
## each of them is hearing about two different guesses.
func test_the_same_number_from_two_peers_is_two_guesses() -> void:
	assert_false(GameplayPredictionKey.of(2, 7).same_as(GameplayPredictionKey.of(3, 7)))
	assert_true(GameplayPredictionKey.of(2, 7).same_as(GameplayPredictionKey.of(2, 7)))


func test_a_key_that_was_never_counted_is_not_a_guess() -> void:
	assert_false(GameplayPredictionKey.new().is_valid())
	assert_false(GameplayPredictionKey.new().depends_on(null), "and depends on nothing")
#endregion


#region The envelope
func test_a_message_is_about_somebody() -> void:
	var about: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_DELTA, GameplayNetEntityId.of(5)
	)

	assert_true(about.is_addressed())
	assert_false(
		GameplayNetMessage.of(GameplayNetMessage.Kind.STATE_DELTA, null).is_addressed(),
		"a message about nobody cannot be acted on, and must not be guessed at"
	)


## Checked at the boundary, so no reader finds the missing half in the middle
## of acting on it.
##
##     [what it is, the kind, definition, run, state, whether that is enough]
func _completeness() -> Array:
	return [
		["a grant with its definition", GameplayNetMessage.Kind.GRANT, true, false, false, true],
		["a grant with nothing to grant", GameplayNetMessage.Kind.GRANT, false, false, false, false],
		["a request with its definition", GameplayNetMessage.Kind.ACTIVATION_REQUEST, true, false, false, true],
		["a confirm with the run it confirms", GameplayNetMessage.Kind.ACTIVATION_CONFIRM, false, true, false, true],
		["a confirm with no run", GameplayNetMessage.Kind.ACTIVATION_CONFIRM, false, false, false, false],
		["a reject with the run it refuses", GameplayNetMessage.Kind.ACTIVATION_REJECT, false, true, false, true],
		["a delta with a reading in it", GameplayNetMessage.Kind.STATE_DELTA, false, false, true, true],
		["a delta with nothing to read", GameplayNetMessage.Kind.STATE_DELTA, false, false, false, false],
		["a cue, which names only whose", GameplayNetMessage.Kind.CUE, false, false, false, true],
	]


func test_a_message_carries_what_its_kind_requires() -> void:
	var rows: Array = _completeness()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var kind: GameplayNetMessage.Kind = row[1]
		var with_definition: bool = row[2]
		var with_activation: bool = row[3]
		var with_state: bool = row[4]
		var enough: bool = row[5]

		var message: GameplayNetMessage = GameplayNetMessage.of(kind, GameplayNetEntityId.of(1))
		if with_definition:
			message.definition = GameplayNetDefinitionId.of_path(A_PATH)
		if with_activation:
			message.activation = GameplayNetActivationId.of(GameplayNetEntityId.of(1), 1)
		if with_state:
			message.state = GameplayNetState.delta()

		assert_eq(message.is_complete(), enough, described)
		checked += 1
	assert_eq(checked, rows.size(), "every kind was offered")


func test_a_message_says_whether_it_is_part_of_a_guess() -> void:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, GameplayNetEntityId.of(1)
	)
	assert_false(message.is_predicted(), "the server says things on its own account")

	message.prediction_key = GameplayPredictionKey.of(2, 1)
	assert_true(message.is_predicted())
#endregion


#region Where an ability is allowed to run
## Two claims, and only two, because only two of them have behaviour yet.
##
## What LOCAL_PREDICTED means as opposed to SERVER_INITIATED is a question for
## whoever reads the policy, and nothing reads it until the authority rules do.
## Asserting here that four enum values are four different numbers would be a
## test of the vocabulary rather than of anything the engine does.
##
## What is real now is the default and the freeze.
func test_an_ability_that_has_never_heard_of_a_network_runs_locally() -> void:
	var written_before_any_of_this: GameplayAbility = autofree(Probe.build(&"Ability.Old"))

	assert_eq(
		written_before_any_of_this.net_execution_policy,
		GameplayAbility.NetExecutionPolicy.LOCAL_ONLY,
		"the default is what every ability written before this field already did"
	)


## Frozen at grant time, like every other policy.
##
## What a grant may do is decided when it is granted. An ability scene edited
## while a match is running is a definition two machines would disagree about,
## and the disagreement would be about who is allowed to ask for what.
func test_what_a_grant_may_do_is_decided_when_it_is_granted() -> void:
	var fixture: ASCFixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	var authored: ProbeAbility = Probe.build(&"Ability.Authored")
	authored.net_execution_policy = GameplayAbility.NetExecutionPolicy.SERVER_ONLY

	var spec: GameplayAbilitySpec = AbilityFactory.give(fixture.asc, authored)
	spec.per_actor_instance.net_execution_policy = (
		GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED
	)

	assert_eq(
		spec.definition.net_execution_policy,
		GameplayAbility.NetExecutionPolicy.SERVER_ONLY,
		"the grant says what it said when it was made"
	)
#endregion


#region The rule the folder exists for
## An ObjectID never crosses the network, asserted against the source rather
## than against a comment saying so.
##
## The failure it guards is not a crash. `get_instance_id()` answers a number on
## both machines, and a message built out of one arrives looking perfectly
## valid - naming whatever object happens to occupy that slot on the receiver,
## or nothing at all once the original has been freed and the slot reused.
func test_nothing_in_the_networking_folder_reaches_for_an_object_id() -> void:
	var offenders: Array[String] = []
	for path: String in _networking_sources():
		if _code_of(path).contains("get_instance_id("):
			offenders.append(path)

	assert_gt(_networking_sources().size(), 0, "there were files to look at")
	assert_eq(offenders, [] as Array[String], "an ObjectID is a slot, not a name")


## A local handle is mapped onto a net id, never converted into one.
##
## Mapping is what the registry does and what the phase asks for: a table with
## a handle on one side and a counted number on the other. Converting is what
## the ids themselves must never do - a handle turned into an id would be a
## local number sent as a shared one, which is the ObjectID failure again with
## a type in front of it. So this is asked of the things that travel, and only
## of those: five classes, named rather than globbed, because the folder also
## holds the tables and the journal, whose whole job is to hold local things.
func _what_travels() -> Array[String]:
	return [
		NETWORKING + "/gameplay_net_entity_id.gd",
		NETWORKING + "/gameplay_net_definition_id.gd",
		NETWORKING + "/gameplay_net_activation_id.gd",
		NETWORKING + "/gameplay_prediction_key.gd",
		NETWORKING + "/gameplay_net_message.gd",
	]


func test_nothing_that_travels_is_built_out_of_a_local_handle() -> void:
	var offenders: Array[String] = []
	for path: String in _what_travels():
		assert_true(FileAccess.file_exists(path), "%s is there to look at" % path)
		var code: String = _code_of(path)
		if code.contains("GameplayAbilityHandle") or code.contains("GameplayEffectHandle"):
			offenders.append(path)

	assert_eq(offenders, [] as Array[String], "mapping is the registry's job, and it is a table")


## The file with its prose taken out.
##
## Each rule above is explained in the doc comments of the very files it
## governs - that is where a rule belongs - so a scan that read comments would
## find the rule stated and report it as the violation.
func _code_of(path: String) -> String:
	var code: Array[String] = []
	for line: String in FileAccess.get_file_as_string(path).split("
"):
		if not line.strip_edges().begins_with("#"):
			code.append(line)
	return "
".join(code)


func _networking_sources() -> Array[String]:
	var found: Array[String] = []
	var directory: DirAccess = DirAccess.open(NETWORKING)
	if directory == null:
		return found
	for name: String in directory.get_files():
		if name.ends_with(".gd"):
			found.append(NETWORKING + "/" + name)
	return found
#endregion
