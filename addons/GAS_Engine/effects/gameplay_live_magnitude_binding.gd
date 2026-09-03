## One persistent modifier's subscription to the attribute its LIVE capture
## reads. Owns no registry of its own - `GameplayEffectRuntime` keeps the
## list, connects and disconnects every binding, and is the only thing that
## ever reacts to one firing.
##
## Only SNAPSHOT-free: a SNAPSHOT capture never creates one of these, because
## nothing about it can change after it was taken.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayLiveMagnitudeBinding extends RefCounted

## The still-active effect this binding keeps updated.
var active_effect: ActiveGameplayEffect = null

## Which of that effect's modifiers - and so which existing contribution -
## this binding re-resolves.
var modifier_index: int = -1

## The attribute the contribution itself writes to. Kept explicit rather than
## re-read from the modifier each time, so a binding remains meaningful even
## if something about the definition were to change underneath it.
var output_attribute: StringName = &""

## What is captured: whose attribute, BASE or CURRENT.
var capture: GameplayAttributeCaptureDefinition = null

## The magnitude this binding re-resolves through - the same
## GameplayMagnitude.resolve() the initial evaluation used.
var magnitude: GameplayAttributeBasedMagnitude = null

## The ASC this binding listens to: `capture`'s SOURCE or TARGET, resolved
## once when the binding was created.
var observed_asc: AbilitySystemComponent = null

## The Callable connected to `observed_asc.attribute_changed`, kept so it can
## be disconnected later without reconstructing an equivalent one - two
## separately-created Callables wrapping the same lambda body are not `==`.
var attribute_changed_handler: Callable = Callable()

## The Callables connected to `observed_asc.tree_exiting`/`tree_entered`.
## Leaving a tree suspends the subscription above and entering one resumes
## it, so an actor that is merely moved keeps feeding what reads it.
var tree_exiting_handler: Callable = Callable()
var tree_entered_handler: Callable = Callable()
