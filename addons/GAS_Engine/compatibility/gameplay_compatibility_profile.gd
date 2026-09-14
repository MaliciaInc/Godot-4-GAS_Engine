## Versioned behavior profile for contracts that intentionally differ between
## GAS_Engine's original Godot-native semantics and the channel-folded
## alternative.
##
## The profile is data. Runtimes ask it; no runtime invents its own definition
## of "compatible".
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCompatibilityProfile extends Resource

enum Mode {
	GODOT_NATIVE,
	CHANNEL_FOLDED,
}

@export var mode: GameplayCompatibilityProfile.Mode = Mode.GODOT_NATIVE

func is_channel_folded() -> bool:
	return mode == Mode.CHANNEL_FOLDED
