## What attribute an execution calculation needs, from whom, when it is read,
## and whether it is frozen or re-read live.
##
## Authored on the execution calculation that needs it - a Resource, not a
## Dictionary, so a typo in an attribute name is still a real property with
## autocomplete rather than a string a consumer might misspell differently.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
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

@export var actor: Actor = Actor.SOURCE
@export var attribute_name: StringName = &""
@export var value: Value = Value.CURRENT
@export var policy: Policy = Policy.SNAPSHOT
