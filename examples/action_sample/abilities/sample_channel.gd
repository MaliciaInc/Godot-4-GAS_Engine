## An ability that is still happening after it starts.
##
## The shape everything with a wind-up, a beam or a stance has: it does not end
## when its activation function returns. It starts a drain on itself, puts a
## looping cue on the character, and stays up until something ends it - the
## player releasing, the mana running out, or the ability being cancelled.
##
## The loop is a persistent cue rather than a burst repeated: a burst played
## every tick is a sound stack, and nothing takes it off the character when the
## channel is interrupted three fights later.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleChannel extends GameplayAbility

const TAG: StringName = &"Ability.Sample.Channel"

## What the character is while it channels, so other abilities can ask.
const CHANNELLING: StringName = &"State.Sample.Channelling"

## The drain this activation started, so ending takes exactly that one off -
## not every drain on the character, which would end somebody else's channel.
var _drain: ActiveGameplayEffect = null


static func build() -> SampleChannel:
	var ability: SampleChannel = SampleChannel.new()
	ability.name = "SampleChannel"
	ability.ability_name = "Channel"
	ability.ability_tags = [TAG]
	# It outlives its own activation function, which is the whole point.
	ability.auto_end_on_activate_return = false
	return ability


## Whether this activation is still up.
func is_channelling() -> bool:
	return is_active and _drain != null


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false
	_drain = owner_asc.apply_gameplay_effect(
		SampleEffects.channel_drain(), owner_asc, get_ability_level()
	)
	if _drain == null:
		return false
	# The loop is not remembered here. Every persistent cue an activation starts
	# is taken off by end_ability(), whichever way it ended - which is what
	# stops an aura outliving the stance that put it there.
	activate_persistent_cue(SampleCues.CHANNEL_LOOP)
	return true


## Listen once, when the grant is wired up.
##
## The end hook is a signal rather than a virtual, so a game hears the same
## thing this does - and connecting here rather than at each activation means
## one connection for however many times this is channelled.
func on_granted() -> void:
	if not ability_ended.is_connected(_on_ended):
		ability_ended.connect(_on_ended)


## Take the drain off, however this ended.
##
## One place, so a normal end, a cancel and the grant being taken away all take
## the same thing with them - which is the bug a channel has when the tidying
## lives at whatever ended it rather than at the ability.
func _on_ended(_was_cancelled: bool) -> void:
	if _drain != null and owner_asc != null:
		owner_asc.remove_active_effect(_drain)
	_drain = null
