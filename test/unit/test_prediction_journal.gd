## Doing something before you are allowed to, and unwinding it when you were not.
##
## The easy half of prediction is being told no. The hard half is that by the
## time the answer arrives, more has been done on top of the guess: the cooldown
## went on because the cost was paid, the spark played because the cooldown
## started. Taking the cost back and leaving the cooldown is a character that
## cannot cast an ability it never cast.
##
## So the whole file is about order and about what is still owed. Newest first,
## and never what the authority has already agreed to.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const MANA: StringName = &"mana"
const HEALTH: StringName = &"health"
const OWNING_PEER: int = 2
const SOMEBODY_ELSE: int = 3
const A_PATH: String = "res://test_only/predicted_%d.tres"

var made: int = 0
var bench: PredictionBench = null
var journal: GameplayPredictionJournal = null
var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	bench = PredictionBench.stand(self, OWNING_PEER, {MANA: 100.0, HEALTH: 100.0})
	journal = bench.journal
	fixture = bench.fixture
	asc = bench.asc()


func after_each() -> void:
	bench.dispose()
	bench = null
	journal = null
	fixture = null
	asc = null


func _named(effect: GameplayEffect) -> GameplayEffect:
	made += 1
	effect.take_over_path(A_PATH % made)
	return effect


func _no_modifiers() -> Array[GameplayEffectModifier]:
	return [] as Array[GameplayEffectModifier]


#region What a guess is made of
## Two guesses from one machine are never one guess.
func test_every_key_this_machine_mints_is_its_own() -> void:
	var first: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	var second: GameplayPredictionKey = journal.next_key(OWNING_PEER)

	assert_false(first.same_as(second))
	assert_eq(first.peer, OWNING_PEER, "and both say who guessed")
	assert_eq(second.peer, OWNING_PEER)


## A guess made because of another one says so.
func test_a_key_minted_on_top_of_another_stands_on_it() -> void:
	var first: GameplayPredictionKey = journal.next_key(OWNING_PEER)

	var second: GameplayPredictionKey = journal.next_key(OWNING_PEER, first)

	assert_true(second.depends_on(first))
	assert_false(first.depends_on(second))
#endregion


#region Unwinding
## What a refusal does and what an agreement does, which are opposites.
##
## The same guess, spent the same mana, answered two different ways. A refusal
## puts it back; an agreement leaves it spent - once, because the client already
## spent it and applying the authority's answer on top would spend it twice.
##
##     [what happens, whether the authority agreed, what the mana ends at]
func _answers() -> Array:
	return [
		["refused, so it comes back", false, 100.0],
		["agreed, so it stays spent", true, 70.0],
	]


func test_a_guess_is_put_back_when_it_is_refused_and_kept_when_it_is_not() -> void:
	var rows: Array = _answers()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var agreed: bool = row[1]
		var ends_at: float = row[2]

		before_each()
		var key: GameplayPredictionKey = journal.next_key(OWNING_PEER)
		asc.set_attribute_base(MANA, 70.0)
		journal.record(GameplayPredictionOperation.cost(key, MANA, 30.0))

		if agreed:
			assert_eq(journal.accept(key), 1, "%s: the authority answered" % described)
			assert_eq(journal.reject(key, asc), 0, "%s: and it is not a guess now" % described)
		else:
			assert_eq(journal.reject(key, asc), 1, "%s: one thing was owed" % described)

		assert_almost_eq(asc.get_attribute_base(MANA), ends_at, 0.001, described)
		assert_true(journal.is_empty(), "%s: and nothing is owed now" % described)
		checked += 1
	assert_eq(checked, rows.size(), "both answers were given")


## And so does the cooldown that went on because of it.
func test_a_refused_guess_takes_back_everything_that_stood_on_it() -> void:
	var paying: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	asc.set_attribute_base(MANA, 70.0)
	journal.record(GameplayPredictionOperation.cost(paying, MANA, 30.0))

	var cooling: GameplayPredictionKey = journal.next_key(OWNING_PEER, paying)
	var applied: ActiveGameplayEffect = EffectFactory.apply(
		asc, _named(EffectFactory.infinite(_no_modifiers()))
	)
	journal.record(GameplayPredictionOperation.cooldown(cooling, applied.handle))

	assert_eq(journal.reject(paying, asc), 2, "both of them")
	assert_almost_eq(asc.get_attribute_base(MANA), 100.0, 0.001, "the mana is back")
	assert_null(asc.get_active_effect(applied.handle), "and the cooldown is off")


## Newest first, which is the order it has to come off in.
func test_what_was_done_last_is_offered_back_first() -> void:
	var first: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	journal.record(GameplayPredictionOperation.cost(first, MANA, 10.0))
	var second: GameplayPredictionKey = journal.next_key(OWNING_PEER, first)
	journal.record(GameplayPredictionOperation.attribute_delta(second, HEALTH, -5.0))

	var owed: Array[GameplayPredictionOperation] = journal.under(first)

	assert_eq(owed.size(), 2, "both stand on the first guess")
	assert_true(owed[0].key.same_as(second), "and the later one comes off first")
	assert_true(owed[1].key.same_as(first))


## Somebody else's guess is not this one.
func test_rejecting_one_guess_leaves_another_alone() -> void:
	var mine: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	journal.record(GameplayPredictionOperation.cost(mine, MANA, 10.0))
	var separate: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	journal.record(GameplayPredictionOperation.cost(separate, HEALTH, 20.0))
	asc.set_attribute_base(MANA, 90.0)
	asc.set_attribute_base(HEALTH, 80.0)

	journal.reject(mine, asc)

	assert_almost_eq(asc.get_attribute_base(MANA), 100.0, 0.001, "one came back")
	assert_almost_eq(asc.get_attribute_base(HEALTH), 80.0, 0.001, "and the other did not")
	assert_eq(journal.size(), 1, "which is still owed")
#endregion


#region Agreeing
## Accepting does not replay, which is the whole of "no duplicate".
##
## The client already spent the mana. Applying the authority's answer on top of
## it would spend it twice, which is the double charge this layer exists to
## make impossible - and the reason accepting marks and forgets rather than
## running anything again.
func test_accepting_binds_the_guess_rather_than_repeating_it() -> void:
	var key: GameplayPredictionKey = journal.next_key(OWNING_PEER)
	asc.set_attribute_base(MANA, 70.0)
	var spent: GameplayPredictionOperation = GameplayPredictionOperation.cost(key, MANA, 30.0)
	journal.record(spent)

	journal.accept(key)

	assert_true(spent.accepted, "it is the authority's now")
	assert_false(
		spent.reverse(asc),
		"and an operation asked to undo itself afterwards refuses: the state it "
		+ "produced is the state everybody has"
	)
	assert_almost_eq(asc.get_attribute_base(MANA), 70.0, 0.001, "spent once")
	assert_true(journal.is_empty(), "and the journal owes nothing")
#endregion


#region The two machines, end to end
## Two machines, and who the authority thinks owns the character.
##
## Which the client can disagree with, and that disagreement is the ordinary
## way a well-formed request is refused: a character changes hands between
## the asking and the arrival.
func _pair(the_authority_says_owner: int = OWNING_PEER) -> Array[GameplayNetworkRuntime]:
	var server: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	server.role = GameplayNetAuthority.Role.AUTHORITY
	server.peer = 1
	var client: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	client.peer = OWNING_PEER
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)
	server.attach(asc, id, the_authority_says_owner)
	var mirror: ASCFixture = Fixture.create("Mirror")
	add_child_autofree(mirror.owner)
	client.attach(mirror.asc, id, OWNING_PEER)
	return [server, client] as Array[GameplayNetworkRuntime]


func _ability(policy: GameplayAbility.NetExecutionPolicy) -> PackedScene:
	made += 1
	return AbilityFactory.net_ability(
		policy, "res://test_only/predicted_ability_%d.tscn" % made, &"Ability.Predicted"
	)


## The whole flow, once: ask under a key, be refused, and end up where you
## started.
func test_a_refused_request_unwinds_what_the_client_did_on_the_strength_of_it() -> void:
	var pair: Array[GameplayNetworkRuntime] = _pair(SOMEBODY_ELSE)
	var server: GameplayNetworkRuntime = pair[0]
	var client: GameplayNetworkRuntime = pair[1]
	var sent: Array[GameplayNetMessage] = []
	client.message_ready.connect(func(m: GameplayNetMessage) -> void: sent.append(m))
	server.message_ready.connect(func(m: GameplayNetMessage) -> void: sent.append(m))
	var refused_ability: PackedScene = _ability(
		GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED
	)
	server.registry.register_definition(refused_ability)

	var mirror: AbilitySystemComponent = client.registry.asc_for(GameplayNetEntityId.of(1))
	mirror.set_attribute_base(MANA, 100.0)
	client.start(mirror, refused_ability)
	assert_eq(sent.size(), 1, "the client asked")

	var asked: GameplayNetMessage = sent[0]
	mirror.set_attribute_base(MANA, 70.0)
	client.journal.record(
		GameplayPredictionOperation.cost(asked.prediction_key, MANA, 30.0)
	)

	server.receive(asked)
	assert_eq(sent.size(), 2, "and was answered")
	assert_eq(
		sent[1].kind, GameplayNetMessage.Kind.ACTIVATION_REJECT, "with a refusal"
	)

	client.receive(sent[1])
	assert_almost_eq(mirror.get_attribute_base(MANA), 100.0, 0.001, "and put it back")
	assert_true(client.journal.is_empty())
	server.dispose()
	client.dispose()


## And an answer that arrives twice does not unwind anything twice.
func test_a_refusal_arriving_twice_unwinds_once() -> void:
	var pair: Array[GameplayNetworkRuntime] = _pair()
	var server: GameplayNetworkRuntime = pair[0]
	var client: GameplayNetworkRuntime = pair[1]
	var sent: Array[GameplayNetMessage] = []
	server.message_ready.connect(func(m: GameplayNetMessage) -> void: sent.append(m))
	var refused_ability: PackedScene = _ability(
		GameplayAbility.NetExecutionPolicy.SERVER_ONLY
	)
	server.registry.register_definition(refused_ability)
	var mirror: AbilitySystemComponent = client.registry.asc_for(GameplayNetEntityId.of(1))
	mirror.set_attribute_base(MANA, 70.0)

	var key: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
	client.journal.record(GameplayPredictionOperation.cost(key, MANA, 30.0))
	var asking: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, GameplayNetEntityId.of(1)
	)
	asking.definition = GameplayNetDefinitionId.of_resource(refused_ability)
	asking.prediction_key = key
	server.receive(asking)

	var refusal: GameplayNetMessage = sent[0]
	assert_true(client.receive(refusal), "the first refusal unwound it")
	assert_false(client.receive(refusal), "and the repeat is not acted on")
	assert_almost_eq(
		mirror.get_attribute_base(MANA), 100.0, 0.001, "so the mana came back once"
	)
	server.dispose()
	client.dispose()
#endregion
