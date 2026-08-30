## Lets a dialogue reach into the ability system, and nothing further.
##
## Bound to Dialogic's one public signal and to nothing else: no subsystem, no
## internal class, no editor structure. The certified version is an alpha, so
## the smaller the surface, the fewer ways a point release can break this - one
## signal is the smallest surface that still does the job.
##
## What a dialogue can ask for is deliberately narrow. It sends events, adds
## tags and removes tags; it cannot activate an ability directly. An event goes
## through the ordinary trigger mechanism, so a writer cannot fire a cast that
## the activation gate would have refused.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name DialogicGasBridge extends Node

## A message that claimed to be for this bridge and then turned out malformed.
## Traffic belonging to somebody else on the bus is not reported here.
signal command_rejected(error: DialogicGasCommandParser.Error)

signal command_applied(command: DialogicGasCommand)

## The one Dialogic signal this bridge knows about.
const SIGNAL_NAME: StringName = &"signal_event"

var target_asc: AbilitySystemComponent = null

## Which messages are ours. Several bridges can listen to one dialogue bus, each
## answering for a different ability system.
var bridge_channel: StringName = &""

var _dialogic: Node = null


#region Binding
## Listen to a Dialogic-shaped node. False when anything needed is missing.
##
## The signal is checked for rather than assumed. Connecting to a name a node
## does not have fails at the connect, which is late and easy to miss in a
## project that is merely missing the addon.
func bind(dialogic_node: Node, asc: AbilitySystemComponent, channel: StringName) -> bool:
	if dialogic_node == null or asc == null or String(channel).is_empty():
		return false
	if not dialogic_node.has_signal(SIGNAL_NAME):
		return false

	# Rebinding is legal and must not leave the old connection behind.
	unbind()

	_dialogic = dialogic_node
	target_asc = asc
	bridge_channel = channel
	_dialogic.connect(SIGNAL_NAME, _on_signal_event)
	return true


## The same, against whatever Dialogic is actually running. False when it is not.
func bind_installed(tree: SceneTree, asc: AbilitySystemComponent, channel: StringName) -> bool:
	return bind(GameplayIntegrationAvailability.dialogic_runtime(tree), asc, channel)


## Stop listening. Safe to call on a bridge that never bound, and again after.
func unbind() -> void:
	if _dialogic != null and _dialogic.is_connected(SIGNAL_NAME, _on_signal_event):
		_dialogic.disconnect(SIGNAL_NAME, _on_signal_event)
	_dialogic = null
	target_asc = null
	bridge_channel = &""


## A freed bridge leaves no connection behind pointing at itself.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unbind()
#endregion


#region Receiving
func _on_signal_event(argument: Variant) -> void:
	var parsed: DialogicGasCommandParser.Result = DialogicGasCommandParser.parse(argument)

	# Somebody else's message on a shared bus. Silence is the correct answer:
	# complaining would bury the real complaints under everyone else's traffic.
	if parsed.error == DialogicGasCommandParser.Error.NOT_FOR_BRIDGE:
		return
	if parsed.error != DialogicGasCommandParser.Error.NONE:
		command_rejected.emit(parsed.error)
		return

	var command: DialogicGasCommand = parsed.command
	# Addressed to another bridge on the same bus. Well-formed, just not ours.
	if command.channel != bridge_channel or target_asc == null:
		return

	_apply(command)
	command_applied.emit(command)


func _apply(command: DialogicGasCommand) -> void:
	if command.type == DialogicGasCommand.Type.ADD_TAG:
		target_asc.add_tag(command.tag)
		return
	if command.type == DialogicGasCommand.Type.REMOVE_TAG:
		target_asc.remove_tag(command.tag)
		return

	# An event, never a direct activation: it travels the ordinary trigger path,
	# so a dialogue cannot fire a cast the activation gate would have refused.
	var avatar: Node = target_asc.get_effect_target()
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = command.tag
	event.target = avatar
	event.instigator = avatar
	event.magnitude = command.magnitude
	target_asc.send_gameplay_event(event)
#endregion
