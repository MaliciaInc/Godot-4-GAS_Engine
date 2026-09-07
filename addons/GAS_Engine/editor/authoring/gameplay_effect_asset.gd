## Creating a GameplayEffect that lives in a file rather than in a script.
##
## An effect authored in code belongs to whatever built it. Two abilities that
## should apply the same burn each build their own, and the day the burn changes
## one of them is missed - which is not a bug anybody can see, because both
## still work.
##
## So an effect can be an asset: one Resource on disk, referenced by everything
## that applies it, edited in the inspector like every other Resource in the
## project. The tool here creates it and stops. It does not hold a copy of the
## effect's fields, does not offer a second way to spell them, and does not
## write a `.tres` of its own devising: it saves a `GameplayEffect`, and the
## inspector edits that same object afterwards. A creator that mirrored the
## fields would be a second definition of what an effect is, and the two would
## drift the first time one of them gained a field.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectAsset extends RefCounted

const RESOURCE_SUFFIX: String = ".tres"

## What an authored effect has to be able to say.
##
## The phase names these as the minimum an asset must cover, so they are named
## here rather than assumed: a `GameplayEffect` that stopped exposing one of
## them would be an asset the inspector cannot fully author, and `create()`
## refuses rather than writing a file that is quietly less than it claims.
##
## Tags are two of these because an effect says two different things with them -
## what it IS, for a query to match, and what it GRANTS to whoever carries it -
## and both live on components rather than on the effect itself, which is why
## `components` alone is not enough to cover them.
const AUTHORED_FIELDS: Array[StringName] = [
	&"policy",
	&"duration_magnitude",
	&"period_magnitude",
	&"modifiers",
	&"components",
	&"executions",
	&"stacking_type",
	&"cues",
	&"event_tags",
	&"overflow_effects",
]

const INVALID_PATH: String = "Effect path must be a res:// .tres path."
const ALREADY_EXISTS: String = "A file already exists at %s."
const CANNOT_WRITE: String = "Could not create effect at %s."
const CANNOT_AUTHOR: String = "A GameplayEffect here cannot author: %s."


## Create a blank GameplayEffect asset at `path`, or say why it was not created.
##
## Blank on purpose. The smallest valid effect is an INSTANT one with nothing in
## it, the same way the smallest valid ability is one that returns true, and
## anything more would be this tool deciding what the person meant to author.
static func create(path: String) -> String:
	if not AuthoredPath.is_creatable(path, RESOURCE_SUFFIX):
		return INVALID_PATH
	if FileAccess.file_exists(path):
		return ALREADY_EXISTS % path

	var effect: GameplayEffect = GameplayEffect.new()
	var absent: Array[StringName] = missing_fields(effect)
	if not absent.is_empty():
		return CANNOT_AUTHOR % ", ".join(absent)

	if ResourceSaver.save(effect, path) != OK:
		return CANNOT_WRITE % path
	return ""


## Which of the authored fields this effect cannot express, in order.
##
## Empty for a GameplayEffect as it stands, which is the point: the list is a
## claim about the class, checked against the class, so removing an exported
## field somewhere else in the engine fails here rather than silently narrowing
## what an asset can say.
##
## The field list is a parameter with the real one as its default, so this can
## be asked about a name the class genuinely lacks. A checker nobody has watched
## return something is a checker that might answer empty to everything, and this
## one's whole job is to answer empty.
static func missing_fields(
	effect: GameplayEffect, fields: Array[StringName] = AUTHORED_FIELDS
) -> Array[StringName]:
	var declared: Array[StringName] = []
	for property: Dictionary in effect.get_property_list():
		var named: String = property["name"]
		declared.append(StringName(named))

	var absent: Array[StringName] = []
	for field: StringName in fields:
		if not declared.has(field):
			absent.append(field)
	return absent
