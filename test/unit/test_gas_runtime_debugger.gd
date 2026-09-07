## Looking at a game that is running, rather than at a scene that is not.
##
## The distinction the whole thing rests on. An ASC selected in a scene being
## edited is a Resource on disk and shows what somebody authored; an ASC in a
## running game has tags on it, effects ticking, and an ability half way
## through. Confusing the two is how a debugger comes to show a person the
## authored level of an ability while they watch it being levelled up.
##
## So what crosses is messages. The game says what it looks like and what just
## happened; the editor keeps what arrived. Both ends are tested here: the
## snapshot the game builds from a real component, and the reading the editor
## does of it - joined, so a key spelled differently at the two ends fails
## rather than producing a debugger that silently shows nothing.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const PluginWiring = preload("res://test/fixtures/plugin_wiring.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const ATTACK: StringName = &"attack"
const BURNING: StringName = &"Status.Burning"
const ABILITY_TAG: StringName = &"Ability.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Watched")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## What the game would send about this component, read back as the editor reads
## it. The two halves joined, which is the point: a key spelled one way in the
## game and another in the editor is a message that arrives and says nothing.
func _round_tripped() -> GasRuntimeSnapshot:
	return GasRuntimeSnapshot.from_message(GasDebugChannel.snapshot_of(asc))


func _traced(kind: GasDebugMessage.Kind, subject: String, detail: String = "") -> GasTraceEvent:
	return GasTraceEvent.from_message({
		GasDebugMessage.KIND: int(kind),
		GasDebugMessage.ASC_ID: 42,
		GasDebugMessage.SUBJECT: subject,
		GasDebugMessage.DETAIL: detail,
	})
#endregion


#region What an entity looks like
## Who it belongs to and who it happens to, which are two answers.
func test_a_snapshot_says_who_it_belongs_to_and_who_it_happens_to() -> void:
	var mount: Node = Node.new()
	mount.name = "Mount"
	add_child_autofree(mount)
	asc.init_ability_actor_info(fixture.owner, mount)

	var said: GasRuntimeSnapshot = _round_tripped()

	assert_eq(said.owner_name, "Watched", "the entity it hangs under")
	assert_eq(said.avatar_name, "Mount", "and the body it acts through")
	assert_eq(said.asc_id, asc.get_instance_id(), "and which component it is")


## Every attribute, at both of its values.
##
## Both, because they answer different questions: what the entity durably is,
## and what it is worth right now with everything active on it. One of them is
## a number a person has to do arithmetic in front of.
func test_a_snapshot_carries_both_values_of_every_attribute() -> void:
	fixture.set_base(ATTACK, 100.0)
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 25.0)]
	EffectFactory.apply(asc, EffectFactory.infinite(buff))

	var found: GasRuntimeSnapshot.Attribute = _round_tripped().attribute("attack")

	assert_not_null(found, "attack is in the snapshot")
	assert_almost_eq(found.base, 100.0, 0.0001, "what it durably is")
	assert_almost_eq(found.current, 125.0, 0.0001, "and what it is worth right now")


## Tags, with both counts, and the parents nothing holds directly.
##
## `Status` is held while `Status.Burning` is on, and a debugger listing only
## what is written on the entity would leave the person working out that the
## family is held at all.
func test_a_snapshot_carries_every_tag_at_both_of_its_counts() -> void:
	asc.add_tag(BURNING)
	asc.add_tag(BURNING)

	var said: GasRuntimeSnapshot = _round_tripped()

	var held: GasRuntimeSnapshot.Tag = null
	var family: GasRuntimeSnapshot.Tag = null
	for tag: GasRuntimeSnapshot.Tag in said.tags:
		if tag.name == String(BURNING):
			held = tag
		elif tag.name == "Status":
			family = tag

	assert_not_null(held, "the tag itself is there")
	assert_eq(held.count, 2, "held twice")
	assert_not_null(family, "and so is the family it belongs to")
	assert_eq(family.count, 0, "which nothing holds directly")
	assert_eq(family.family_count, 2, "and is held twice all the same")


## Grants by handle, because a grant is what a handle names - the instance
## behind it comes and goes with each activation.
func test_a_snapshot_carries_grants_by_handle() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(ABILITY_TAG))

	var found: GasRuntimeSnapshot.Ability = _round_tripped().ability(spec.handle.id)

	assert_not_null(found, "the grant is in the snapshot")
	assert_almost_eq(found.level, 1.0, 0.0001, "at the level it was granted")
	assert_eq(found.active, 0, "with nothing running yet")


## And running effects by handle, with everything about how long they have.
func test_a_snapshot_carries_running_effects_with_their_time_and_stacks() -> void:
	var buff: Array[GameplayEffectModifier] = [EffectFactory.add(ATTACK, 5.0)]
	var active: ActiveGameplayEffect = EffectFactory.apply(
		asc, EffectFactory.duration(buff, 30.0)
	)

	var found: GasRuntimeSnapshot.Effect = _round_tripped().effect(active.handle.id)

	assert_not_null(found, "the effect is in the snapshot")
	assert_eq(found.stacks, 1, "one of it")
	assert_almost_eq(found.seconds_left, 30.0, 0.0001, "with its time on it")


## An entity with nothing on it is a snapshot with nothing in it, not a failure.
func test_an_entity_with_nothing_on_it_snapshots_cleanly() -> void:
	var said: GasRuntimeSnapshot = _round_tripped()

	assert_eq(said.tags.size(), 0, "no tags")
	assert_eq(said.abilities.size(), 0, "no grants")
	assert_eq(said.effects.size(), 0, "no effects")
	assert_gt(said.attributes.size(), 0, "but the attributes it declares are there")
#endregion


#region What just happened
## An event says what kind it was, what it was about, and what else is worth
## knowing.
func test_an_event_carries_what_happened_and_to_what() -> void:
	var event: GasTraceEvent = _traced(
		GasDebugMessage.Kind.EFFECT_REMOVED, "burning", "NATURAL_EXPIRATION"
	)

	assert_eq(event.kind, GasDebugMessage.Kind.EFFECT_REMOVED, "which kind")
	assert_eq(event.subject, "burning", "about what")
	assert_eq(event.described(), "EFFECT_REMOVED burning (NATURAL_EXPIRATION)", "as one line")


## An event with nothing else to say does not pretend there is.
func test_an_event_with_no_detail_says_only_what_it_knows() -> void:
	var event: GasTraceEvent = _traced(GasDebugMessage.Kind.ABILITY_ACTIVATED, "7")

	assert_eq(event.described(), "ABILITY_ACTIVATED 7", "and no empty brackets")


## A message that is not one is dropped rather than shown.
##
## A row for every malformed packet is a debugger showing a person its own bugs,
## which is worse than showing them nothing.
##
##     [what is wrong with it, the message]
func _malformed() -> Array:
	return [
		["nothing in it", {}],
		["no entity", {GasDebugMessage.KIND: 0}],
		["no kind", {GasDebugMessage.ASC_ID: 42}],
		["a kind that does not exist", {GasDebugMessage.KIND: 999, GasDebugMessage.ASC_ID: 42}],
	]


func test_a_message_that_is_not_one_is_dropped() -> void:
	var rows: Array = _malformed()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var said: Dictionary = row[1]

		assert_null(GasTraceEvent.from_message(said), "%s: dropped" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every malformed shape was offered")


## And so is a snapshot that names no entity.
func test_a_snapshot_that_names_no_entity_is_dropped() -> void:
	assert_null(GasRuntimeSnapshot.from_message({}), "nothing to be about")
#endregion


#region What the editor keeps
## The log keeps what arrived and hands it back by entity and by kind.
##
## Asked of the log rather than of the plugin, and not for tidiness: an
## EditorDebuggerPlugin refuses to be instantiated outside the editor - `new()`
## answers with nothing at all - so anything living on it is code no test can
## drive. The plugin is the door; this is what is behind it.
func test_the_log_keeps_what_arrived_and_answers_by_entity() -> void:
	var plugin: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()

	plugin.take(GasDebugMessage.TRACE, [{
		GasDebugMessage.KIND: int(GasDebugMessage.Kind.TAG_COUNT_CHANGED),
		GasDebugMessage.ASC_ID: 1, GasDebugMessage.SUBJECT: "Status.Burning",
	}])
	plugin.take(GasDebugMessage.TRACE, [{
		GasDebugMessage.KIND: int(GasDebugMessage.Kind.EFFECT_APPLIED),
		GasDebugMessage.ASC_ID: 2, GasDebugMessage.SUBJECT: "burn",
	}])

	assert_eq(plugin.events().size(), 2, "both were kept")
	assert_eq(plugin.events_for(1).size(), 1, "one happened to the first entity")
	assert_eq(
		plugin.events_of(GasDebugMessage.Kind.EFFECT_APPLIED).size(), 1,
		"and one of them was an effect landing"
	)


## A snapshot replaces the last one from that entity, and is found by its id.
func test_a_snapshot_replaces_what_that_entity_last_said() -> void:
	var plugin: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()
	var said: Dictionary = GasDebugChannel.snapshot_of(asc)

	plugin.take(GasDebugMessage.SNAPSHOT, [said])
	asc.add_tag(BURNING)
	plugin.take(GasDebugMessage.SNAPSHOT, [GasDebugChannel.snapshot_of(asc)])

	assert_eq(plugin.watched_ids().size(), 1, "one entity, not two")
	# Two rows for one tag: the tag itself, and the family it is held under.
	assert_eq(
		plugin.snapshot(asc.get_instance_id()).tags.size(), 2,
		"and what it says is the newer of the two"
	)


## A message it does not understand is refused rather than swallowed.
func test_a_message_it_does_not_understand_is_refused() -> void:
	var plugin: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()

	assert_false(plugin.take("something:else", [{}]), "not ours")
	assert_false(plugin.take(GasDebugMessage.TRACE, []), "and nothing is not a message")
	assert_eq(plugin.events().size(), 0, "so nothing was kept")


## History has a bound. A busy entity is thousands of events a minute, and an
## editor that kept all of them is an editor that eventually stops.
func test_history_keeps_the_newest_and_lets_the_oldest_go() -> void:
	var plugin: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()

	for index: int in GasRuntimeDebuggerLog.KEPT_EVENTS + 10:
		plugin.take(GasDebugMessage.TRACE, [{
			GasDebugMessage.KIND: int(GasDebugMessage.Kind.ATTRIBUTE_CHANGED),
			GasDebugMessage.ASC_ID: 1, GasDebugMessage.SUBJECT: str(index),
		}])

	assert_eq(plugin.events().size(), GasRuntimeDebuggerLog.KEPT_EVENTS, "bounded")
	assert_eq(plugin.events()[-1].subject, str(GasRuntimeDebuggerLog.KEPT_EVENTS + 9), "newest")


## A new run of the game is a new subject.
func test_forgetting_drops_the_last_run() -> void:
	var plugin: GasRuntimeDebuggerLog = GasRuntimeDebuggerLog.new()
	plugin.take(GasDebugMessage.SNAPSHOT, [GasDebugChannel.snapshot_of(asc)])

	plugin.forget()

	assert_eq(plugin.watched_ids().size(), 0, "no entities")
	assert_eq(plugin.events().size(), 0, "and no history")
#endregion


#region Every kind has something that says it
## Every trace kind is one the engine actually reports.
##
## A kind nothing emits is a filter that finds nothing and a person concluding
## their ability never committed. Asked of the channel's source, because the
## alternative - driving every one of them through a real component - is twelve
## scenarios to assert one fact about a list.
func test_every_trace_kind_has_something_that_reports_it() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://addons/GAS_Engine/debug/gas_debug_channel.gd"
	)
	assert_false(source.is_empty(), "the channel's source was read")

	var checked: int = 0
	for named: String in GasDebugMessage.Kind.keys():
		assert_true(
			source.contains("GasDebugMessage.Kind.%s" % named),
			"%s is reported by something" % named
		)
		checked += 1
	assert_eq(checked, GasDebugMessage.Kind.size(), "every kind was asked about")


## And the component announces the three that had no signal before.
##
## Granted, committed and a cue played were things the runtime did and never
## said, so a debugger could show an ability activating and never show it
## paying for itself - which is the half somebody debugging a cost is after.
func test_the_component_announces_a_grant_a_commit_and_a_cue() -> void:
	var said: Array[String] = []
	asc.ability_granted.connect(func(_handle: GameplayAbilityHandle) -> void:
		said.append("granted")
	)
	asc.ability_committed.connect(
		func(_handle: GameplayAbilityHandle, _result: AbilityCommitResult) -> void:
			said.append("committed")
	)
	asc.cue_executed.connect(func(_tag: StringName) -> void: said.append("cue"))

	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(ABILITY_TAG))
	var probe: ProbeAbility = spec.per_actor_instance as ProbeAbility
	probe.commits = true
	asc.try_activate_ability_handle(spec.handle)
	asc.execute_cue(CueProbe.params_for(&"Cue.Test", fixture.owner))

	assert_eq(said, ["granted", "committed", "cue"] as Array[String], "all three, in order")
#endregion


#region The door itself
## The plugin is registered and taken back, and it routes to the log.
##
## Asserted against source, for the same reason the log exists: an
## EditorDebuggerPlugin refuses to be instantiated outside the editor, so
## nothing headless can watch it register anything. What this catches is the
## registration going missing, which would leave a game talking to nobody.
const WIRED: Array = [
	["the plugin is registered", "add_debugger_plugin(_runtime_debugger)"],
	["and taken back on the way out", "remove_debugger_plugin(_runtime_debugger)"],
]


func test_the_editor_registers_the_debugger_and_takes_it_back() -> void:
	assert_eq(
		PluginWiring.missing(WIRED), [] as Array[String], "every part of it is there"
	)


## And the door hands everything to the log rather than deciding itself.
func test_the_door_decides_nothing_of_its_own() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://addons/GAS_Engine/editor/debugger/gas_runtime_debugger_plugin.gd"
	)

	assert_true(source.contains("log.take(message, data)"), "it asks the log")
	assert_false(
		source.contains("GasRuntimeSnapshot.from_message"),
		"and parses nothing itself, on whatever thread it was called on"
	)
#endregion


#region Nothing is reported when nobody is listening
## A component attaches nothing while no debugger is running, which is every
## exported build - and is this suite, so the whole thing is being asserted
## from the side that matters.
func test_nothing_is_watched_while_nothing_is_listening() -> void:
	assert_false(EngineDebugger.is_active(), "nothing is debugging this run")
	assert_false(asc.debug_channel.watch(asc), "so nothing was attached")


## And stopping a channel that never started is not an error.
func test_stopping_a_channel_that_never_started_is_not_an_error() -> void:
	var channel: GasDebugChannel = GasDebugChannel.new()

	channel.stop()

	assert_true(true, "it came back")
#endregion
