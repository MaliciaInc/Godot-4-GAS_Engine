## One finding from GameplayAssetValidator, over any asset kind it checks.
##
## One closed vocabulary for every asset kind, rather than a bag of strings:
## `code` is what a caller switches on, `message` is only ever built at the
## editor's own reporting boundary, from `code` - never stored as the
## authority itself.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAssetValidationResult extends RefCounted

enum Severity { ERROR, WARNING }

enum Code {
	OK,
	MISSING_REFERENCE,
	CYCLIC_TAG_QUERY,
	EMPTY_TAG_IN_QUERY,
	INVALID_TAG_IN_QUERY,
	INVALID_COMPONENT_DEFINITION,
	MISSING_COST_AMOUNT,
	MISSING_COST_TARGET_ATTRIBUTE,
	MISSING_COST_REFERENCE_ATTRIBUTE,
	MISSING_MAGNITUDE,
	ROOT_NOT_GAMEPLAY_ABILITY,
	SCENE_MISSING,
	## A modifier spelled MULTIPLY or DIVIDE while the resolved profile is
	## UE_5_7, where those names mean the additive arms rather than the
	## compounding ones. It folds correctly; the author is told because the
	## two arms produce different numbers and the name does not say which.
	LEGACY_OPERATION_UNDER_UNREAL_PROFILE,
	## A modifier naming an attribute no attribute set in the project declares.
	## It is a warning rather than an error because the catalogue knows what
	## the project's scripts declare and a game may build an attribute
	## somewhere it cannot see - but a misspelled name is a modifier that does
	## nothing at all, and the first person to notice used to be whoever
	## wondered why the effect had no effect.
	UNDECLARED_ATTRIBUTE,
	## A stacking effect under UE_5_7 that left factor_in_stack_count false.
	## The reference includes the stack count by default and this engine
	## does not, so an effect ported from there scales differently until
	## somebody answers the question on purpose.
	STACKING_WITHOUT_STACK_COUNT_ANSWER,
}

var severity: GameplayAssetValidationResult.Severity = Severity.ERROR
## The Resource/PackedScene this finding is about - never the whole asset
## tree, so a caller can select exactly what failed.
var asset: Object = null
## Dotted path to the offending field, e.g. "modifiers[2].magnitude" -
## advisory for a human, never parsed back into domain logic.
var field: String = ""
var code: GameplayAssetValidationResult.Code = Code.OK


static func error(asset: Object, field: String, code: GameplayAssetValidationResult.Code) -> GameplayAssetValidationResult:
	var result: GameplayAssetValidationResult = GameplayAssetValidationResult.new()
	result.severity = Severity.ERROR
	result.asset = asset
	result.field = field
	result.code = code
	return result


static func warning(asset: Object, field: String, code: GameplayAssetValidationResult.Code) -> GameplayAssetValidationResult:
	var result: GameplayAssetValidationResult = error(asset, field, code)
	result.severity = Severity.WARNING
	return result
