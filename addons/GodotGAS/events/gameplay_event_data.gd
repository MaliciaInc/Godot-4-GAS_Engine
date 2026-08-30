## The typed payload every gameplay event carries.
##
## Upstream passed a `Dictionary` here, which meant each listener decided for
## itself what keys existed and what they held. A listener that guessed wrong
## failed silently, because a missing key reads as null rather than as an error.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
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
