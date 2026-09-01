## A passive that actually stays active, unlike ProbeAbility's default
## _activate_ability() (returns true immediately, non-channelled) - a
## passive that ends the instant it starts loses its activation-owned tags
## in the same frame it gained them, which proves nothing about the
## activation-owned-tags contract. Awaits its own signal, never emitted; ASC
## teardown/remove_ability() aborts it, the same as every channelling probe
## elsewhere in this suite.
##
## A real top-level ability script, not a test-file inner class - see
## FireballAbility for why that matters for anything PackedScene.pack() has
## to duplicate.
##
## @meta_license: MIT
class_name StaysActiveAbility extends GameplayAbility

signal channel_gate


func _activate_ability() -> bool:
	await channel_gate
	return true
