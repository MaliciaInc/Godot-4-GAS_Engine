## The Dialogic bridge: what a dialogue may ask of the ability system.
##
## Two things are being proved here at once. That a well-formed instruction
## reaches the ASC, which is the easy half; and that everything else on a shared
## bus is left alone, which is the half that decides whether this addon is
## usable in a project that already uses Dialogic for its own messages.
##
## The double implements only Dialogic's one published signal. If it ever needs
## a second member for these tests to pass, the bridge has reached past the
## surface it promised to depend on.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Fake = preload("res://test/fixtures/fake_dialogic.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const CHANNEL: StringName = &"Player"
const OTHER_CHANNEL: StringName = &"Companion"
const EVENT_TAG: StringName = &"Event.Dialogue.Accepted"
const EVENT_PARENT: StringName = &"Event.Dialogue"
const STATE_TAG: StringName = &"State.Sworn"
const PROBE_TAG: StringName = &"Ability.Probe"
const INTEGRATIONS_DIR: String = "res://addons/GAS_Engine/integrations"

var fixture: ASCFixture = null
var dialogic: FakeDialogic = null
var bridge: DialogicGasBridge = null

## What the bridge announced, recorded through typed handlers rather than by
## reaching into it.
var applied: Array[DialogicGasCommand] = []
var rejected: Array[DialogicGasCommandParser.Error] = []


func before_each() -> void:
	fixture = Fixture.create("Speaker")
	dialogic = Fake.build()
	bridge = DialogicGasBridge.new()
	_enter_the_tree()
	_start_recording()


func _enter_the_tree() -> void:
	add_child_autofree(fixture.owner)
	add_child_autofree(dialogic)
	add_child_autofree(bridge)


## Listen to what the bridge announces, and start each test from silence.
func _start_recording() -> void:
	bridge.command_applied.connect(_on_applied)
	bridge.command_rejected.connect(_on_rejected)
	applied = []
	rejected = []


func after_each() -> void:
	fixture = null
	dialogic = null
	bridge = null


#region Helpers
func _on_applied(command: DialogicGasCommand) -> void:
	applied.append(command)


func _on_rejected(error: DialogicGasCommandParser.Error) -> void:
	rejected.append(error)


func _bound() -> bool:
	return bridge.bind(dialogic, fixture.asc, CHANNEL)


func test_dialogic_freed_before_the_bridge_does_not_take_the_teardown_with_it() -> void:
	# The ordinary teardown order: a scene frees the node the bridge watches,
	# and the bridge beside it goes a moment later. A freed Node is not null,
	# so the old `!= null` guard was true and is_connected() reached a dead
	# instance, taking the shutdown with it.
	var doomed: FakeDialogic = Fake.build()
	add_child(doomed)
	assert_true(bridge.bind(doomed, fixture.asc, CHANNEL), "bound to it")

	doomed.free()
	bridge.unbind()

	assert_null(bridge.target_asc, "the bridge let go instead of crashing")
	# Not also asked to refuse binding to the dead node: GDScript's typed-argument
	# check rejects a freed object before bind() runs, which halts the run under
	# the debugger rather than returning false. That check is the guard there.

## A well-formed message, before any one field is spoiled.
func _message() -> Dictionary:
	var message: Dictionary = {}
	message[DialogicGasCommandParser.BRIDGE_KEY] = DialogicGasCommandParser.BRIDGE_NAME
	message[DialogicGasCommandParser.CHANNEL_KEY] = String(CHANNEL)
	message[DialogicGasCommandParser.COMMAND_KEY] = "send_event"
	message[DialogicGasCommandParser.TAG_KEY] = String(EVENT_TAG)
	return message


## The same message, aimed at the tag commands instead.
func _tag_message(command: String) -> Dictionary:
	var message: Dictionary = _message()
	message[DialogicGasCommandParser.COMMAND_KEY] = command
	message[DialogicGasCommandParser.TAG_KEY] = String(STATE_TAG)
	return message
#endregion


#region Binding
func test_binding_needs_a_node_an_asc_and_a_channel() -> void:
	assert_false(bridge.bind(null, fixture.asc, CHANNEL), "no node to listen to")
	assert_false(bridge.bind(dialogic, null, CHANNEL), "nobody to speak for")
	assert_false(bridge.bind(dialogic, fixture.asc, &""), "no way to tell its messages apart")


## A node that is not Dialogic-shaped is refused before anything is connected.
func test_binding_to_a_node_without_the_signal_is_refused() -> void:
	var stranger: Node = Node.new()
	add_child_autofree(stranger)
	assert_false(bridge.bind(stranger, fixture.asc, CHANNEL), "it has no signal_event")


func test_binding_to_a_dialogic_shaped_node_succeeds() -> void:
	assert_true(_bound(), "the double carries the one signal the bridge needs")
	assert_eq(bridge.target_asc, fixture.asc, "and it knows who it speaks for")


## Dialogic is not installed here, so binding to whatever is running finds none.
func test_binding_to_an_absent_installation_is_refused_quietly() -> void:
	assert_false(
		bridge.bind_installed(get_tree(), fixture.asc, CHANNEL),
		"no Dialogic is running, so there is nothing to bind to"
	)


func test_unbinding_is_safe_before_after_and_twice() -> void:
	bridge.unbind()
	assert_true(_bound(), "binding after an idle unbind still works")
	bridge.unbind()
	bridge.unbind()
	assert_null(bridge.target_asc, "and it forgot who it spoke for")


func test_rebinding_does_not_leave_the_old_connection_behind() -> void:
	assert_true(_bound(), "bound once")
	assert_true(_bound(), "and again")

	dialogic.say(_message())
	assert_eq(applied.size(), 1, "one message, one application")
#endregion


#region Other people's traffic
## The bus is shared. Anything not addressed to this bridge is not its business,
## and saying so out loud would bury the real complaints under the rest.
func test_a_message_that_is_not_a_dictionary_is_ignored_without_complaint() -> void:
	assert_true(_bound())
	dialogic.say("some timeline said something")

	assert_eq(applied.size(), 0, "nothing was applied")
	assert_eq(rejected.size(), 0, "and nothing was reported as wrong")


## The bridge answers to the product's current name and to the one it carried
## before the rename. A timeline is authored content in somebody else's project:
## renaming what they type is a change this addon absorbs, and quietly ceasing
## to recognise what they already wrote is not.
func test_the_bridge_answers_to_its_current_name_and_the_one_it_used_to_have() -> void:
	assert_true(_bound())
	assert_ne(
		DialogicGasCommandParser.BRIDGE_NAME,
		DialogicGasCommandParser.LEGACY_BRIDGE_NAME,
		"the rename really happened"
	)

	dialogic.say(_message())
	assert_eq(applied.size(), 1, "addressed by the current name")

	var legacy: Dictionary = _message()
	legacy[DialogicGasCommandParser.BRIDGE_KEY] = DialogicGasCommandParser.LEGACY_BRIDGE_NAME
	dialogic.say(legacy)
	assert_eq(applied.size(), 2, "and by the one it used to have")
	assert_eq(rejected.size(), 0, "neither is a complaint")


func test_a_dictionary_for_another_bridge_is_ignored_without_complaint() -> void:
	assert_true(_bound())
	var theirs: Dictionary = {}
	theirs[DialogicGasCommandParser.BRIDGE_KEY] = "SomebodyElse"
	dialogic.say(theirs)

	assert_eq(applied.size(), 0, "nothing was applied")
	assert_eq(rejected.size(), 0, "and nothing was reported as wrong")


## Well-formed, correct bridge, different channel: silence rather than refusal.
func test_a_message_for_another_channel_is_ignored_without_complaint() -> void:
	assert_true(_bound())
	var message: Dictionary = _message()
	message[DialogicGasCommandParser.CHANNEL_KEY] = String(OTHER_CHANNEL)
	dialogic.say(message)

	assert_eq(applied.size(), 0, "not ours to apply")
	assert_eq(rejected.size(), 0, "and not ours to complain about either")
#endregion


#region Malformed messages that did claim to be ours
func test_a_message_without_a_channel_is_refused() -> void:
	assert_true(_bound())
	var message: Dictionary = _message()
	message.erase(DialogicGasCommandParser.CHANNEL_KEY)
	dialogic.say(message)

	assert_eq(rejected, [DialogicGasCommandParser.Error.MISSING_CHANNEL] as Array, "said so")


func test_a_message_naming_an_unknown_command_is_refused() -> void:
	assert_true(_bound())
	var message: Dictionary = _message()
	message[DialogicGasCommandParser.COMMAND_KEY] = "detonate"
	dialogic.say(message)

	assert_eq(rejected, [DialogicGasCommandParser.Error.UNKNOWN_COMMAND] as Array, "said so")


## The tag is validated, not repaired: a sender that named `event.dialogue` did
## not name `Event.Dialogue`, and correcting it would hide that.
func test_a_message_carrying_an_invalid_tag_is_refused() -> void:
	assert_true(_bound())
	var message: Dictionary = _message()
	message[DialogicGasCommandParser.TAG_KEY] = "event.dialogue.accepted"
	dialogic.say(message)

	assert_eq(rejected, [DialogicGasCommandParser.Error.INVALID_TAG] as Array, "said so")


func test_a_message_carrying_a_non_numeric_magnitude_is_refused() -> void:
	assert_true(_bound())
	var message: Dictionary = _message()
	message[DialogicGasCommandParser.MAGNITUDE_KEY] = "a lot"
	dialogic.say(message)

	assert_eq(rejected, [DialogicGasCommandParser.Error.INVALID_MAGNITUDE] as Array, "said so")
#endregion


#region What a dialogue can do
func test_a_send_event_reaches_the_ability_system() -> void:
	assert_true(_bound())
	watch_signals(fixture.asc)
	dialogic.say(_message())

	assert_eq(applied.size(), 1, "the command was applied")
	assert_signal_emitted(fixture.asc, "gameplay_event_received", "and the ASC heard the event")


## An event reaches an ability through the ordinary trigger path, hierarchy and
## all - the bridge never activates anything directly.
func test_an_event_from_a_dialogue_can_wake_a_listening_ability() -> void:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [GameplayAbilityEventTrigger.for_tag(EVENT_PARENT)]
	var spec: GameplayAbilitySpec = AbilityFactory.give(fixture.asc, probe)
	var ability: ProbeAbility = spec.per_actor_instance as ProbeAbility
	assert_true(_bound())

	dialogic.say(_message())

	assert_eq(ability.activations, 1, "the more specific event woke the general listener")


## Two timeline events, so two messages. Dialogic freezes what it emits, and
## a test that edited one message and sent it twice was describing
## something no timeline can do.
func test_a_dialogue_can_add_and_remove_a_tag() -> void:
	assert_true(_bound())
	dialogic.say(_tag_message("add_tag"))
	assert_true(fixture.asc.has_tag(STATE_TAG), "the tag was granted")

	dialogic.say(_tag_message("remove_tag"))
	assert_false(fixture.asc.has_tag(STATE_TAG), "and taken away again")
#endregion


#region Letting go
func test_nothing_arrives_after_unbinding() -> void:
	assert_true(_bound())
	bridge.unbind()

	dialogic.say(_message())

	assert_eq(applied.size(), 0, "the bridge stopped listening")
	assert_eq(dialogic.signal_event.get_connections().size(), 0, "and let the connection go")


## A freed bridge leaves no connection pointing at itself.
func test_a_freed_bridge_disconnects_itself() -> void:
	var temporary: DialogicGasBridge = DialogicGasBridge.new()
	assert_true(temporary.bind(dialogic, fixture.asc, CHANNEL), "bound")
	assert_eq(dialogic.signal_event.get_connections().size(), 1, "one listener")

	temporary.free()

	assert_eq(dialogic.signal_event.get_connections().size(), 0, "and none after it went")
#endregion


#region One grammar, one owner
## The bridge validates tags with the registry's expression, not a copy of it.
##
## A second copy is how two parts of a project end up disagreeing about what a
## tag is, and the disagreement shows up as a message that was silently refused.
func test_the_integrations_carry_no_second_copy_of_the_tag_grammar() -> void:
	var offenders: Array[String] = []
	for path: String in _integration_scripts(INTEGRATIONS_DIR):
		if FileAccess.get_file_as_string(path).contains(GameplayTagRegistry.TAG_PATTERN):
			offenders.append(path)

	assert_eq(offenders, [] as Array[String], "the grammar is spelled in exactly one place")


func _integration_scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	for entry: String in DirAccess.get_files_at(directory):
		if entry.ends_with(".gd"):
			found.append(directory + "/" + entry)
	for child: String in DirAccess.get_directories_at(directory):
		found.append_array(_integration_scripts(directory + "/" + child))
	return found
#endregion
