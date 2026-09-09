## One step of a targeting preset: it is handed what the step before it found,
## and hands on what it made of that.
##
## The shape is deliberately the same for selecting, filtering and sorting,
## because a preset is a list and a list of things with different shapes is not
## a list. A step that selects ignores its input; one that filters keeps some of
## it; one that sorts keeps all of it in another order.
##
## Deterministic by contract. No step may consult a clock or a random number:
## a preset run twice on the same world has to answer the same way, or a client
## and a server running the same preset would disagree about what was aimed at,
## which is the one thing this whole layer exists to make checkable.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetingTask extends Resource


## What this step makes of what it was handed.
##
## The default hands it straight on, which is what a step that is authored but
## not configured does - and is why an empty preset answers with an empty aim
## rather than with an error.
func execute(
	input: GameplayAbilityTargetData, _source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	return input
