## One finding from GameplayAssetValidator, over any asset kind it checks.
##
## One closed vocabulary for every asset kind, rather than a bag of strings:
## `code` is what a caller switches on, `message` is only ever built at the
## editor's own reporting boundary, from `code` - never stored as the
## authority itself.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
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
}

var severity: Severity = Severity.ERROR
## The Resource/PackedScene this finding is about - never the whole asset
## tree, so a caller can select exactly what failed.
var asset: Object = null
## Dotted path to the offending field, e.g. "modifiers[2].magnitude" -
## advisory for a human, never parsed back into domain logic.
var field: String = ""
var code: Code = Code.OK


static func error(asset: Object, field: String, code: Code) -> GameplayAssetValidationResult:
	var result: GameplayAssetValidationResult = GameplayAssetValidationResult.new()
	result.severity = Severity.ERROR
	result.asset = asset
	result.field = field
	result.code = code
	return result


static func warning(asset: Object, field: String, code: Code) -> GameplayAssetValidationResult:
	var result: GameplayAssetValidationResult = error(asset, field, code)
	result.severity = Severity.WARNING
	return result
