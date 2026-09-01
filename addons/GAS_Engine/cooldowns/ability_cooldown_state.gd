## What a UI needs to draw an ability's cooldown, and nothing more.
##
## A snapshot, not a handle. It holds no ASC and no active effects on purpose:
## a widget that kept one would keep the entity alive past its own death, and a
## value read once would silently keep changing underneath the frame that drew
## it. Ask again next frame instead.
##
## Seconds and turns are separate fields because they are separate units. A
## turn-based cooldown has no seconds and a real-time one has no turns, and
## flattening them into one number would make "3" ambiguous.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityCooldownState extends RefCounted

## Whether the ability is on cooldown at all. True when any of its cooldown tags
## is present, or any clock still has time on it.
var active: bool = false

## An INFINITE cooldown is on until something removes it. There is no bar to
## draw for that, so it is reported as its own fact rather than as a huge number.
var infinite: bool = false

## The longest wait left in seconds, across every cooldown tag this ability has.
var seconds_remaining: float = 0.0

## The longest wait left in turns, on the same basis.
var turns_remaining: int = 0

## The tags that were consulted, in the order they were declared, once each.
var tags: Array[StringName] = []
