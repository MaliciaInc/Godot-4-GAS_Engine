## Seven commands QA types, and the two switches that must not exist in a
## shipped game.
##
## "Give it to me twenty times and tell me what it says" is not a thing anybody
## clicks through. What is proved here is that each command answers, that a
## wrong one says what it could have said instead, and - the part with teeth -
## that ignoring a cost or a cooldown changes what the preflight decides without
## changing anything about the entity: nothing is topped up, no tag is cleared,
## and turning the switch off leaves it exactly where it was going to be.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const HEALTH: StringName = &"health"
const MANA: StringName = &"mana"
const STUNNED: StringName = &"Status.Stunned"
const COOLDOWN_TAG: StringName = &"State.Cooldown.Probe"
const ABILITY_TAG: StringName = &"Ability.Probe"
const ABILITY_NAME: String = "Ability_Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	GasDebugOptions.forget()
	fixture = Fixture.create("Hero")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	GasDebugOptions.forget()
	fixture = null
	asc = null


#region Getting there
func _ran(line: String) -> String:
	return GasDebugCommands.run(line, fixture.owner)


## A grant that pays and starts its cooldown when it commits, which is what an
## ability does and what these switches are about.
func _committing_grant(cost: float = 0.0, authored: float = 0.0) -> GameplayAbilitySpec:
	var ability: ProbeAbility = Probe.build(ABILITY_TAG)
	# Named, because that is what a person types at a console - and because an
	# ability that never sets one is reachable only by its handle, which is the
	# other half of what `gas.list <entity>` prints.
	ability.ability_name = ABILITY_NAME
	if cost > 0.0:
		# A declared cost rather than an authored cost effect: the activation
		# preflight prices `costs`, and this is about what the preflight decides.
		var charge: GameplayAbilityCost = GameplayAbilityCost.new()
		charge.mode = GameplayAbilityCost.Mode.ABSOLUTE
		charge.target_attribute = MANA
		charge.amount = GameplayScalableFloat.new()
		charge.amount.value = cost
		ability.costs = [charge]
	if authored > 0.0:
		# The other way an ability says what it charges: an effect applied at
		# commit rather than a cost the preflight prices.
		var taken: Array[GameplayEffectModifier] = [EffectFactory.add(MANA, -authored)]
		ability.cost_effect = EffectFactory.instant(taken)
	var nothing: Array[GameplayEffectModifier] = []
	ability.cooldown_effect = EffectFactory.granting(
		EffectFactory.duration(nothing, 30.0), [COOLDOWN_TAG] as Array[StringName]
	)

	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, ability)
	var granted: ProbeAbility = spec.per_actor_instance as ProbeAbility
	granted.commits = true
	return spec
#endregion


#region The switches
## The two ignores only exist in a debug build.
##
## A shipped game in which somebody can turn costs off is a shipped game in
## which somebody will.
func test_the_two_ignores_are_debug_build_switches() -> void:
	assert_true(GasDebugOptions.is_debug_only(GasDebugOptions.IGNORE_COSTS))
	assert_true(GasDebugOptions.is_debug_only(GasDebugOptions.IGNORE_COOLDOWNS))
	assert_false(
		GasDebugOptions.is_debug_only(GasDebugOptions.SUPPRESS_CUES),
		"suppression is not a debug switch: a dedicated server means it"
	)
	assert_false(
		GasDebugOptions.is_debug_only(GasDebugOptions.SUPPRESS_ABILITY_GRANTS),
		"nor is refusing grants on a component being torn down"
	)


## A debug switch does nothing in a release build, whatever it was set to.
##
## Asked of a build of that kind rather than of this one: this suite runs in a
## debug build and cannot become a release one, and "does nothing in release" is
## the promise worth checking. The guard is on the reading as well as the
## writing, so a value that arrived some other way still changes nothing.
func test_a_debug_switch_does_nothing_in_a_release_build() -> void:
	for switch: StringName in GasDebugOptions.declared():
		assert_true(
			GasDebugOptions.exists_in(switch, true),
			"%s exists in a debug build" % switch
		)
		assert_eq(
			GasDebugOptions.exists_in(switch, false),
			not GasDebugOptions.is_debug_only(switch),
			"%s exists in a release build only if it is not a debug switch" % switch
		)


##     [what it is called, the switch]
func _switch_cases() -> Array:
	return [
		["ignoring costs", GasDebugOptions.IGNORE_COSTS],
		["ignoring cooldowns", GasDebugOptions.IGNORE_COOLDOWNS],
		["suppressing cues", GasDebugOptions.SUPPRESS_CUES],
		["suppressing grants", GasDebugOptions.SUPPRESS_ABILITY_GRANTS],
	]


func test_every_switch_goes_on_and_off_again(
	case: Array = use_parameters(_switch_cases())
) -> void:
	var described: String = case[0]
	var switch: StringName = case[1]

	assert_false(GasDebugOptions.is_on(switch), "%s starts off" % described)
	GasDebugOptions.set_switch(switch, true)
	assert_true(GasDebugOptions.is_on(switch), "%s goes on" % described)
	GasDebugOptions.set_switch(switch, false)
	assert_false(GasDebugOptions.is_on(switch), "%s goes off again" % described)


## A switch nobody declared is not invented by asking about it.
func test_a_switch_nobody_declared_is_not_a_switch() -> void:
	assert_false(GasDebugOptions.is_on(&"ignore_gravity"), "no such switch")
	assert_eq(GasDebugOptions.set_switch(&"ignore_gravity", true), "", "and none is made")


func test_forgetting_puts_every_switch_back() -> void:
	for switch: StringName in GasDebugOptions.declared():
		GasDebugOptions.set_switch(switch, true)

	GasDebugOptions.forget()

	for switch: StringName in GasDebugOptions.declared():
		assert_false(GasDebugOptions.is_on(switch), "%s is off again" % switch)
#endregion


#region Costs
## An ability nobody can afford activates while costs are ignored.
func test_ignoring_costs_lets_an_ability_nobody_can_afford_activate() -> void:
	var spec: GameplayAbilitySpec = _committing_grant(1000.0)

	assert_false(
		asc.can_activate_ability_handle(spec.handle),
		"there is nowhere near enough mana"
	)

	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COSTS, true)
	assert_true(asc.can_activate_ability_handle(spec.handle), "and now it may")


## Nothing is topped up, and nothing is charged.
##
## The rule with teeth. A debug switch that added mana would leave a save file
## somebody debugged in, and the moment it went off the entity would be richer
## than the game intended.
func test_ignoring_costs_neither_adds_resources_nor_takes_them() -> void:
	var spec: GameplayAbilitySpec = _committing_grant(10.0)
	var before: float = asc.get_attribute_current(MANA)

	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COSTS, true)
	asc.try_activate_ability_handle(spec.handle)

	assert_almost_eq(
		asc.get_attribute_current(MANA), before, 0.0001,
		"the ability went off and the mana is exactly where it was"
	)

	GasDebugOptions.forget()
	assert_almost_eq(
		asc.get_attribute_current(MANA), before, 0.0001,
		"and turning the switch off did not change it either"
	)


## An authored cost effect is not taken either.
##
## Two ways to declare what an ability charges - `costs`, which the preflight
## prices, and `cost_effect`, which is applied at commit. A switch that silenced
## only the first would let an ability activate for free and then charge for it
## anyway, which is worse than not having the switch.
func test_ignoring_costs_does_not_take_an_authored_cost_effect() -> void:
	var free_one: GameplayAbilitySpec = _committing_grant(0.0, 10.0)
	var before: float = asc.get_attribute_current(MANA)

	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COSTS, true)
	asc.try_activate_ability_handle(free_one.handle)

	assert_almost_eq(
		asc.get_attribute_current(MANA), before, 0.0001,
		"the effect the ability charges through was not applied either"
	)

	# Costs back on, cooldowns off: the first activation started this ability's
	# cooldown and it is the same tag on the second grant, which would refuse
	# for a reason that has nothing to do with what is being checked here.
	GasDebugOptions.forget()
	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COOLDOWNS, true)
	var paying: GameplayAbilitySpec = _committing_grant(0.0, 10.0)
	asc.try_activate_ability_handle(paying.handle)
	assert_almost_eq(
		asc.get_attribute_current(MANA), before - 10.0, 0.0001,
		"and is applied with the switch off"
	)


## With the switch off, the same ability pays.
##
## The other half: a switch that made no difference would pass the test above
## by doing nothing at all.
func test_an_ability_pays_its_cost_with_the_switch_off() -> void:
	var spec: GameplayAbilitySpec = _committing_grant(10.0)
	var before: float = asc.get_attribute_current(MANA)

	asc.try_activate_ability_handle(spec.handle)

	assert_almost_eq(
		asc.get_attribute_current(MANA), before - 10.0, 0.0001, "it was charged"
	)
#endregion


#region Cooldowns
## An ability on cooldown activates again while cooldowns are ignored, and the
## cooldown is never started in the first place.
func test_ignoring_cooldowns_lets_an_ability_go_again() -> void:
	var spec: GameplayAbilitySpec = _committing_grant()

	asc.try_activate_ability_handle(spec.handle)
	assert_true(asc.has_tag(COOLDOWN_TAG), "the cooldown is running")
	assert_false(asc.can_activate_ability_handle(spec.handle), "so it may not go again")

	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COOLDOWNS, true)
	assert_true(asc.can_activate_ability_handle(spec.handle), "and now it may")


## No tag is cleared, so the wait is exactly as long as it was going to be.
func test_ignoring_cooldowns_clears_nothing_that_is_already_running() -> void:
	var spec: GameplayAbilitySpec = _committing_grant()
	asc.try_activate_ability_handle(spec.handle)

	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COOLDOWNS, true)

	assert_true(
		asc.has_tag(COOLDOWN_TAG),
		"the cooldown that was already running is still running"
	)
	GasDebugOptions.forget()
	assert_false(
		asc.can_activate_ability_handle(spec.handle),
		"and the moment the switch goes off it is waiting again"
	)


## Nothing new is started, so a UI is not drawing a wait nobody is having.
func test_ignoring_cooldowns_starts_no_new_cooldown() -> void:
	var spec: GameplayAbilitySpec = _committing_grant()
	GasDebugOptions.set_switch(GasDebugOptions.IGNORE_COOLDOWNS, true)

	asc.try_activate_ability_handle(spec.handle)

	assert_false(
		asc.has_tag(COOLDOWN_TAG),
		"nothing is counting down beside an ability that is firing freely"
	)
#endregion


#region Suppression, centralised
## What a component declares for itself and what the process declares are both
## true, and either is enough.
func test_the_process_wide_suppression_is_asked_beside_the_component_s_own() -> void:
	var granted: GameplayAbilityHandle = asc.give_ability(_a_scene())
	assert_true(granted != null and granted.is_valid(), "a grant works to begin with")

	GasDebugOptions.set_switch(GasDebugOptions.SUPPRESS_ABILITY_GRANTS, true)
	var refused: GameplayAbilityHandle = asc.give_ability(_a_scene())

	assert_false(
		refused != null and refused.is_valid(),
		"and is refused once the process says grants are off, "
		+ "without the component having been told anything"
	)


func _a_scene() -> PackedScene:
	var ability: ProbeAbility = Probe.build(ABILITY_TAG)
	var scene: PackedScene = PackedScene.new()
	scene.pack(ability)
	ability.free()
	return scene
#endregion


#region The commands
## Every command answers something, and a line that is not one says what is.
func test_an_unknown_command_says_what_the_commands_are() -> void:
	var said: String = _ran("gas.explode Hero")

	assert_true(said.contains("no such command"), "it says so")
	for known: String in GasDebugCommands.names():
		assert_true(said.contains(known), "and offers %s" % known)


## A switch command takes on or off, and says so when it is given neither.
func test_a_switch_command_wants_on_or_off() -> void:
	assert_true(_ran("gas.ignore_costs maybe").contains("takes on or off"))
	assert_false(GasDebugOptions.is_on(GasDebugOptions.IGNORE_COSTS), "and changed nothing")

	assert_true(_ran("gas.ignore_costs on").contains("on"), "while on works")
	assert_true(GasDebugOptions.is_on(GasDebugOptions.IGNORE_COSTS), "and takes effect")

	_ran("gas.ignore_cooldowns on")
	assert_true(GasDebugOptions.is_on(GasDebugOptions.IGNORE_COOLDOWNS), "so does the other")


## `gas.list` names every entity, and `gas.list <entity>` names its grants.
##
## The handle beside every grant, because an ability that never set a name has
## only a handle to be called by - and `gas.activate` takes either.
func test_list_names_the_entities_and_then_their_grants() -> void:
	assert_true(_ran("gas.list").contains("Hero"), "the one this suite built")
	assert_true(
		_ran("gas.list Hero").contains("granted abilities"),
		"which has none yet, and says so rather than answering empty"
	)

	var spec: GameplayAbilitySpec = _committing_grant()
	var listed: String = _ran("gas.list Hero")
	assert_true(listed.contains(ABILITY_NAME), "the grant is listed: %s" % listed)
	assert_true(listed.contains("#%d" % spec.handle.id), "with the handle to call it by")

	assert_true(
		_ran("gas.list Nobody").contains("nothing called"),
		"and asking about nobody says so"
	)


## An ability is reachable by its handle when nobody gave it a name.
func test_an_unnamed_ability_is_reachable_by_its_handle() -> void:
	var ability: ProbeAbility = Probe.build(ABILITY_TAG)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, ability)

	assert_true(
		_ran("gas.list Hero").contains(GasDebugCommands.UNNAMED),
		"it is listed as having no name"
	)
	assert_true(
		_ran("gas.activate Hero %d" % spec.handle.id).contains("activated"),
		"and goes off when called by its handle"
	)


## The pages the overlay draws are the pages the console prints.
func test_the_console_shows_what_the_overlay_would_draw() -> void:
	asc.tags.add(STUNNED)

	assert_true(_ran("gas.attributes Hero").contains(String(HEALTH)), "attributes")
	assert_true(_ran("gas.tags Hero").contains(String(STUNNED)), "tags")

	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(HEALTH, 5.0)]
	EffectFactory.apply(asc, EffectFactory.infinite(buff))
	assert_true(
		_ran("gas.effects Hero").contains(GasDebugPageEffects.IN_FORCE), "effects"
	)


## Asking about nobody says who there is instead.
##
## A console that answered nothing would leave somebody wondering whether the
## entity is missing or the command is wrong.
func test_a_command_about_nobody_says_who_there_is() -> void:
	var said: String = _ran("gas.attributes Nobody")

	assert_true(said.contains("nothing called 'Nobody'"), "it says so")
	assert_true(said.contains("Hero"), "and says who there is instead")


func test_a_command_that_needs_an_entity_says_so() -> void:
	assert_true(_ran("gas.attributes").contains("needs the name of an entity"))
	assert_true(_ran("gas.activate Hero").contains("needs an entity and an ability"))


## An entity with nothing on it says that, rather than answering blank.
func test_an_entity_with_nothing_to_show_says_so() -> void:
	assert_true(_ran("gas.tags Hero").contains("has no"), "no tags on it")


## `gas.activate` activates, and says what a refusal was.
func test_activate_starts_an_ability_and_reports_a_refusal_with_its_tag() -> void:
	var spec: GameplayAbilitySpec = _committing_grant()

	assert_true(
		_ran("gas.activate Hero %s" % ABILITY_NAME).contains("activated"),
		"the first one goes"
	)
	assert_true(asc.has_tag(COOLDOWN_TAG), "and starts its cooldown")

	var refused: String = _ran("gas.activate Hero %s" % ABILITY_NAME)
	assert_true(refused.contains("refused"), "the second is refused")
	assert_true(
		refused.contains(String(AbilityFailureTags.of(AbilityRuntime.ActivationError.ON_COOLDOWN))),
		"naming the failure tag a game's own UI reacts to: %s" % refused
	)
	assert_gt(spec.handle.id, 0, "and it is the grant this test made")


func test_activating_an_ability_nobody_has_says_so() -> void:
	assert_true(
		_ran("gas.activate Hero Fireball").contains("no ability called 'Fireball'")
	)
#endregion
