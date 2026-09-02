## A game's own calls, written the way a game would write them.
##
## Nothing in the engine knows this file exists, and nothing in the engine ever
## will. It reaches the Composer through `ComposerCatalog.register()` and through
## no other road, which is the whole of what C9 claims.
##
## The Composer never instantiates any of this. It reads the signatures off the
## script, so what a node needs is a method a person can point at - not a base
## class, not an interface, not a registration of any other kind.
##
## @meta_license: MIT
extends RefCounted

var stamina_spent: float = 0.0
var last_drain: StringName = &""
var flourishes: Array[StringName] = []


## One argument required, one carrying a default - so a test can tell the
## difference between a gap and a choice on a call the engine has never heard of.
func spend_stamina(amount: float, drain_tag: StringName = &"") -> void:
	stamina_spent += amount
	last_drain = drain_tag


## Suspends. Reflection cannot tell, so the game says so when it registers.
func play_flourish(cue: StringName) -> void:
	flourishes.append(cue)
