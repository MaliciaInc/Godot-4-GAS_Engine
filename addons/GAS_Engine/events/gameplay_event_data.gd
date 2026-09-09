## The typed payload every gameplay event carries.
##
## Upstream passed a `Dictionary` here, which meant each listener decided for
## itself what keys existed and what they held. A listener that guessed wrong
## failed silently, because a missing key reads as null rather than as an error.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEventData extends RefCounted

## The hierarchical tag this event was broadcast under, e.g. Event.Damage.Taken.
var event_tag: StringName = &""

## Who caused the event. May be null for an event with no actor.
var instigator: Node = null

## Who the event is about.
var target: Node = null

## The single scalar an event carries. Events that need more than one number
## carry a context instead; this field is not a place to pack two meanings.
var magnitude: float = 0.0

## The originating effect context, when the event came from an effect.
var context: GameplayEffectContext = null

## Two slots for whatever an ability needs to hand its listeners that is not
## one of the fields above - a weapon, a card, a definition.
##
## Objects rather than a typed field because the engine cannot know what a
## game means by them, and two rather than one because the reference has two
## and a game porting from it should not have to pack a pair into a context.
## Neither crosses a network: GameplayEventWire carries what the registry can
## name and omits the rest.
var optional_object: Object = null
var optional_object2: Object = null

## What the instigator and the target had on them when this was dispatched.
##
## Snapshots, not views. A listener woken three frames later is about the
## moment the event happened, and reading the world at that point would answer
## a different question - one the sender never asked. An absence stays an
## empty array rather than becoming a tag that matches nothing, because those
## are different answers to a query.
var instigator_tags: Array[StringName] = []
var target_tags: Array[StringName] = []

## What the event was aimed at, when it came from something aimed.
var target_data: GameplayAbilityTargetData = null
