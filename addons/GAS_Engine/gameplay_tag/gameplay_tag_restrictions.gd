## Which parts of the tag hierarchy belong to somebody else.
##
## A plugin that ships tags under `Lyra.` owns that branch: a project adding
## `Lyra.Ability.Sprint` of its own gets a tag the plugin's next version may
## define differently, and the two definitions are then one name. The
## declaration says who owns the prefix, and adding a tag under it is refused
## with the owner named - so the person typing it learns where to ask rather
## than finding out at the next update.
##
## Only the prefix is owned. `Lyra` owning `Lyra.` says nothing about
## `Lyras.Ability`, which is a different word that happens to start the same
## way - the boundary is a segment, not a character.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagRestrictions extends RefCounted

const SEPARATOR: String = "."
const NOBODY: StringName = &""

## What a refusal says, with the prefix and its owner in it.
const REFUSED: String = "'%s' is owned by %s. Ask them for the tag you need."


## Every restricted prefix the project declares.
static func declared() -> Dictionary[StringName, StringName]:
	return GameplayTagGenerator.restricted_in_file()


## Who owns the branch this tag would sit in, or nobody.
##
## The longest matching prefix wins. A plugin owning `Lyra.` and a team owning
## `Lyra.Ability.` are both true of `Lyra.Ability.Sprint`, and the answer
## somebody needs is the nearer of the two - the one whose owner would actually
## have to define the tag.
static func owner_of(
	tag: StringName, restricted: Dictionary[StringName, StringName] = declared()
) -> StringName:
	var found: StringName = NOBODY
	var longest: int = -1
	for prefix: StringName in restricted:
		if not _is_under(tag, prefix):
			continue
		var length: int = String(prefix).length()
		if length > longest:
			longest = length
			found = restricted[prefix]
	return found


## Whether anybody owns the branch this tag would sit in.
static func is_restricted(
	tag: StringName, restricted: Dictionary[StringName, StringName] = declared()
) -> bool:
	return owner_of(tag, restricted) != NOBODY


## What to tell somebody who tried to add a tag somebody else owns.
static func refusal(prefix_owner: StringName, tag: StringName) -> String:
	return REFUSED % [String(tag), String(prefix_owner)]


## Whether a tag is the prefix itself, or sits inside it.
##
## The prefix is written without its trailing dot - `Lyra`, not `Lyra.` - which
## is how a tag is written, so the two are the same kind of thing and a
## declaration cannot be half a segment.
static func _is_under(tag: StringName, prefix: StringName) -> bool:
	if prefix == NOBODY:
		return false
	if tag == prefix:
		return true
	return String(tag).begins_with(String(prefix) + SEPARATOR)
