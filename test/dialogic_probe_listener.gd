## An ability that wakes on a dialogue's event and does nothing else.
##
## The Dialogic bridge is not allowed to activate anything: it sends an event,
## and an ability listening for it decides. This is the listener, so the probe
## can tell "the event arrived" apart from "the event woke somebody".
##
## @meta_license: MIT
extends GameplayAbility

## The family the dialogue's event belongs to. Listening on the parent is the
## point: a more specific event has to wake a general listener.
const FAMILY: StringName = &"Event.Dialogue"


## Built here and not in _ready(): the definition is frozen when the ability is
## granted, which is before _ready() runs.
func _init() -> void:
	activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	gameplay_event_triggers = [
		GameplayAbilityEventTrigger.for_tag(FAMILY)
	] as Array[GameplayAbilityEventTrigger]


func _activate_ability() -> bool:
	end_ability()
	return true
