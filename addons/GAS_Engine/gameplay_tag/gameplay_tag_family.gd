## What a gameplay tag's family is: the tag itself, and everything above it.
##
## Split out of GameplayTagRuntime because two very different things need it and
## only one of them can afford to live next to the other. The cue manager is an
## autoload, and Godot parses autoloads before the global class cache exists, so
## every file an autoload can reach must preload what it names rather than name
## it. That is a constraint worth putting on ten lines and not worth putting on
## the whole reference-counted tag store.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagFamily extends RefCounted

## Tags are hierarchical and the separator is part of the rule rather than
## decoration: `Damage.Fire` is under `Damage`, and `Damage` is not a match for
## `DamageOverTime` however much of it the two share.
const SEPARATOR: String = "."


## A tag and every ancestor above it, nearest first.
##
## `A.B.C` answers `[A.B.C, A.B, A]`, which is the order anything walking up a
## family wants: a cue looking for the most specific binding, a listener asking
## whether anything it cares about is held. An empty tag has no family at all,
## which is not the same as being its own root.
static func ancestors_of(tag: StringName) -> Array[StringName]:
	var chain: Array[StringName] = []
	if tag == &"":
		return chain
	chain.append(tag)
	var text: String = String(tag)
	var cut: int = text.rfind(SEPARATOR)
	while cut > 0:
		text = text.substr(0, cut)
		chain.append(StringName(text))
		cut = text.rfind(SEPARATOR)
	return chain
