## One effect a GameplayEffectAdditionalEffectsComponent applies, gated by
## whichever queries are configured. Every configured query must match; an
## unset one imposes no condition.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectConditionalEffect extends Resource

@export var effect: GameplayEffect = null

## Matched against the target actually receiving the chained application.
@export var target_query: GameplayTagQuery = null

## Matched against the parent application's own source ASC's tags.
@export var source_query: GameplayTagQuery = null
