## What attribute an execution calculation needs, from whom, when it is read,
## and whether it is frozen or re-read live.
##
## Authored on the execution calculation that needs it - a Resource, not a
## Dictionary, so a typo in an attribute name is still a real property with
## autocomplete rather than a string a consumer might misspell differently.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeCaptureDefinition extends Resource

## Whose attribute this reads: the instigator of the effect, or whoever it is
## being applied to.
enum Actor {
	SOURCE,
	TARGET,
}

## Which of an attribute's two numbers this reads.
enum Value {
	BASE,
	CURRENT,
}

## When the value is fixed. SNAPSHOT freezes it once, at the time this
## definition's actor/value pair says to. LIVE never stores an authority of
## its own - every read resolves fresh from the ASC at the moment it is asked.
enum Policy {
	SNAPSHOT,
	LIVE,
}

@export var actor: GameplayAttributeCaptureDefinition.Actor = Actor.SOURCE
## Which attribute is captured, said so it cannot mean two of them.
@export var attribute: GameplayAttributeRef = null

## The bare name, read only when `attribute` names nothing.
@export var attribute_name: StringName = &""
@export var value: GameplayAttributeCaptureDefinition.Value = Value.CURRENT
@export var policy: GameplayAttributeCaptureDefinition.Policy = Policy.SNAPSHOT


## The attribute this reads, whichever way it was authored.
func resolved_attribute_name() -> StringName:
	return GameplayAttributeRef.name_of(attribute, attribute_name)


## The same, as a reference: the shape a read is answered by, so a capture that
## names its set reads that set's attribute and not the first one declaring it.
func attribute_ref() -> GameplayAttributeRef:
	return GameplayAttributeRef.resolved(attribute, attribute_name)
