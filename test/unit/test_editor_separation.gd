## The Composer never reaches a running game.
##
## Not a promise about export filters, which belong to whoever ships the game -
## a fact about this addon: nothing outside the editor folder names anything
## inside it, so there is no path by which a running game loads any of it.
##
## Its own file rather than a region of the Composer's gates, because it is not
## about the Composer: every class under `editor/` is in scope, and the ones
## added since - the authoring tools among them - are exactly the classes a
## check living beside the Composer would have been quietly narrowed away from.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## What an identifier may be made of, so a name is matched where it ends.
const IDENTIFIER_CHARS: String = (
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
)

const EDITOR_ROOT: String = "res://addons/GAS_Engine/editor/"
const ADDON_ROOT: String = "res://addons/GAS_Engine/"


func test_nothing_in_the_runtime_names_anything_in_the_editor() -> void:
	var editor_classes: Array[String] = []
	for described: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = described["class"]
		var where: String = described["path"]
		if where.begins_with(EDITOR_ROOT):
			editor_classes.append(declared)
	assert_gt(editor_classes.size(), 10, "there is an editor to keep out")

	for described: Dictionary in ProjectSettings.get_global_class_list():
		var where: String = described["path"]
		if not where.begins_with(ADDON_ROOT) or where.begins_with(EDITOR_ROOT):
			continue
		var source: String = FileAccess.get_file_as_string(where)
		for declared: String in editor_classes:
			assert_false(
				_uses(source, declared),
				"%s does not reach %s" % [where.get_file(), declared]
			)


## Named as code rather than mentioned in a comment, and named whole.
##
## `contains()` on its own reads GameplayEffectAssetTagsComponent - a runtime
## class - as a use of GameplayEffectAsset, an editor one it merely starts with.
## That is this check reporting a violation nobody committed, and it would have
## kept doing it for every editor name that happens to prefix a runtime name. An
## identifier ends where a character that cannot be part of one begins.
static func _uses(source: String, declared: String) -> bool:
	for line: String in source.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		if _names_whole(line, declared):
			return true
	return false


static func _names_whole(line: String, declared: String) -> bool:
	var at: int = line.find(declared)
	while at >= 0:
		var ends_at: int = at + declared.length()
		var before: String = line.substr(at - 1, 1) if at > 0 else ""
		var after: String = line.substr(ends_at, 1) if ends_at < line.length() else ""
		if not _is_identifier_char(before) and not _is_identifier_char(after):
			return true
		at = line.find(declared, at + 1)
	return false


static func _is_identifier_char(character: String) -> bool:
	return not character.is_empty() and IDENTIFIER_CHARS.contains(character)


## The check above, checked.
##
## Its whole value is the answer "no", and a matcher that answered "yes" to a
## longer name was doing that for two runtime classes at once - so the case that
## caught it is a row here, beside the two it must still catch.
##
##     [what the line is, the line, whether it names the class]
func _separation_lines() -> Array:
	return [
		["a declared type", "var made: GameplayEffectAsset = null", true],
		["a static call", "\tGameplayEffectAsset.create(path)", true],
		["a longer name that starts the same", "var t: GameplayEffectAssetTagsComponent", false],
		["a longer name that ends the same", "var t: MyGameplayEffectAsset = null", false],
		["a comment", "# GameplayEffectAsset is an editor class", false],
	]


func test_the_separation_check_reads_a_name_whole() -> void:
	var rows: Array = _separation_lines()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var line: String = row[1]
		var names_it: bool = row[2]

		assert_eq(_uses(line, "GameplayEffectAsset"), names_it, described)
		checked += 1
	assert_eq(checked, rows.size(), "every shape was offered")
