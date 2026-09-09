## One place that says which kinds of ability block, cancel and require which.
##
## A growing ruleset finds out the hard way that the fourteenth ability is the
## one that forgot the rule the other thirteen have. A row says it once, and the
## fourteenth is covered by being what it is.
##
## The rule with teeth is that rows only ever add. A central table that could
## quietly make an ability activatable when its own declaration refused would be
## a rule nobody reading the ability could account for.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const MELEE: StringName = &"Ability.Melee"
const STUNNED: StringName = &"Status.Stunned"
const READY: StringName = &"Status.Ready"
const DODGE: StringName = &"Ability.Dodge"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Fighter")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = tags
	var made: GameplayTagQuery = GameplayTagQuery.new()
	made.root = expression
	return made


func _table(configure: Callable) -> void:
	var row: GameplayAbilityTagRelationship = GameplayAbilityTagRelationship.new()
	row.ability_query = _query([MELEE] as Array[StringName])
	configure.call(row)
	var table: GameplayAbilityTagRelationships = GameplayAbilityTagRelationships.new()
	table.relationships = [row] as Array[GameplayAbilityTagRelationship]
	asc.ability_tag_relationships = table


## A granted ability of one kind that stays active until the test lets it go.
##
## Channelled rather than ProbeAbility with `channels` set, because that field
## is not exported and does not survive the grant's pack-then-instantiate trip.
func _channelled(tag: StringName) -> GameplayAbilitySpec:
	var ability: ChannelingAbility = ChannelingAbility.new()
	ability.name = String(tag).replace(".", "_")
	ability.ability_tags = [tag]
	return AbilityFactory.give(asc, ability)


func _melee() -> GameplayAbilitySpec:
	return AbilityFactory.give(asc, Probe.build(MELEE))
#endregion


## A row adds a restriction, and lifting what the row is about lifts it again.
##
## Both directions in one test because they are one rule with two spellings: a
## requirement the owner must satisfy, and a condition the owner must not be in.
## Written separately they were the same test with two words changed.
##
##     [what the row says, how to satisfy it, what refusing looks like]
func _relationship_cases() -> Array:
	return [
		[
			"a requirement",
			true,
			GameplayAbilityActivationResult.Status.MISSING_REQUIRED_TAGS,
		],
		[
			"a blocker",
			false,
			GameplayAbilityActivationResult.Status.BLOCKED_BY_TAGS,
		],
	]


func test_a_relationship_row_adds_a_restriction_and_only_a_restriction(
	case: Array = use_parameters(_relationship_cases())
) -> void:
	var described: String = case[0]
	var requiring: bool = case[1]
	var expected: GameplayAbilityActivationResult.Status = case[2]

	var spec: GameplayAbilitySpec = _melee()
	assert_true(
		asc.try_activate_ability_handle(spec.handle).is_ok(), "allowed with no table at all"
	)

	var gate: StringName = READY if requiring else STUNNED
	_table(func(row: GameplayAbilityTagRelationship) -> void:
		if requiring:
			row.requires_query = _query([gate] as Array[StringName])
		else:
			row.blocked_by_query = _query([gate] as Array[StringName])
	)

	if not requiring:
		asc.add_tag(gate)

	var refused: GameplayAbilityActivationResult = asc.try_activate_ability_handle(spec.handle)
	assert_false(refused.is_ok(), "%s: the table refused it" % described)
	assert_eq(refused.status, expected, "%s: and said which kind of refusal" % described)

	if requiring:
		asc.add_tag(gate)
	else:
		asc.remove_tag(gate)

	assert_true(
		asc.try_activate_ability_handle(spec.handle).is_ok(),
		"%s: and allowed once the condition changed" % described
	)


## The rule that keeps a central table readable: it can only ever say no.
func test_tag_relationships_never_override_an_ability_refusal() -> void:
	var probe: ProbeAbility = Probe.build(MELEE)
	probe.activation_blocked_query = _query([STUNNED] as Array[StringName])
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)

	# A table that says nothing at all about this ability's blocker.
	_table(func(row: GameplayAbilityTagRelationship) -> void:
		row.requires_query = _query([] as Array[StringName])
	)
	asc.add_tag(STUNNED)

	assert_false(
		asc.try_activate_ability_handle(spec.handle).is_ok(),
		"the ability refused itself, and nothing here can undo that"
	)


func test_a_row_about_something_else_says_nothing() -> void:
	var spec: GameplayAbilitySpec = _melee()
	var row: GameplayAbilityTagRelationship = GameplayAbilityTagRelationship.new()
	row.ability_query = _query([&"Ability.Ranged"] as Array[StringName])
	row.blocked_by_query = _query([STUNNED] as Array[StringName])
	var table: GameplayAbilityTagRelationships = GameplayAbilityTagRelationships.new()
	table.relationships = [row] as Array[GameplayAbilityTagRelationship]
	asc.ability_tag_relationships = table

	asc.add_tag(STUNNED)

	assert_true(
		asc.try_activate_ability_handle(spec.handle).is_ok(),
		"a rule about ranged attacks is not a rule about this one"
	)


## The two arms of a row that nobody wrote on either ability involved.
##
## One test rather than two because it is one rule read from both sides: what
## a running melee forbids is exactly what beginning a melee takes away. Split
## in half, each side passes while the table is only half wired to the
## runtime - which is how it first shipped.
func test_tag_relationships_can_block_and_cancel() -> void:
	var melee: GameplayAbilitySpec = _channelled(MELEE)
	var dodge: GameplayAbilitySpec = _channelled(DODGE)
	_table(func(row: GameplayAbilityTagRelationship) -> void:
		row.blocks_query = _query([DODGE] as Array[StringName])
		row.cancels_query = _query([DODGE] as Array[StringName])
	)

	assert_true(
		asc.try_activate_ability_handle(dodge.handle).is_ok(), "a dodge on its own runs"
	)
	assert_true(
		asc.try_activate_ability_handle(melee.handle).is_ok(), "and a melee may begin"
	)
	assert_false(
		dodge.per_actor_instance.is_active,
		"beginning the melee took the dodge away, though neither ability says so"
	)

	var refused: GameplayAbilityActivationResult = asc.try_activate_ability_handle(
		dodge.handle
	)
	assert_false(refused.is_ok(), "and while the melee runs, no dodge starts")
	assert_eq(
		refused.status,
		GameplayAbilityActivationResult.Status.BLOCKED_BY_ACTIVE_ABILITY,
		"blocked by what is running, which is what the row is about"
	)

	(melee.per_actor_instance as ChannelingAbility).channel_gate.emit()


#region Every refusal has a name
## A reason with no tag would be a refusal a UI cannot describe, so the mapping
## is total by construction and this is what keeps it that way.
func test_every_activation_error_has_a_stable_failure_tag() -> void:
	var seen: Array[StringName] = []
	# Over the mapping's own keys: the enum's values() answers Variant, and this
	# project compiles an untyped argument to a typed parameter as an error. The
	# count is asserted against the enum so a reason added without a tag still
	# fails here rather than passing over a shorter list.
	assert_eq(
		AbilityFailureTags.DEFAULTS.size(),
		AbilityRuntime.ActivationError.size(),
		"every reason the engine can give has a name"
	)
	for error: int in AbilityFailureTags.DEFAULTS:
		var tag: StringName = AbilityFailureTags.DEFAULTS[error]
		assert_ne(tag, &"", "reason %d has a tag" % error)
		assert_false(seen.has(tag), "and it is not shared with another reason: %s" % tag)
		seen.append(tag)


func test_a_refusal_is_announced_with_its_tag() -> void:
	var spec: GameplayAbilitySpec = _melee()
	_table(func(row: GameplayAbilityTagRelationship) -> void:
		row.blocked_by_query = _query([STUNNED] as Array[StringName])
	)
	asc.add_tag(STUNNED)
	watch_signals(asc)

	asc.try_activate_ability_handle(spec.handle)

	assert_signal_emitted(asc, "ability_activation_failed_with_tag", "the tagged signal fired")
	var said: Array = get_signal_parameters(asc, "ability_activation_failed_with_tag", 0)
	var reported: StringName = said[2]
	assert_eq(
		reported,
		AbilityFailureTags.DEFAULTS[AbilityRuntime.ActivationError.BLOCKED_TAG],
		"with the tag for that reason"
	)
#endregion
