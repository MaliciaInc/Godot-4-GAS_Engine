## Deciding which file the Composer opens, and saying no when it cannot.
##
## Split out of the editor plugin so the decisions can be tested. What is left in
## the plugin is the handful of calls that move the editor around, which needs a
## running editor to mean anything; everything that can be got wrong is here.
##
## The one distinction worth keeping straight: a file this refuses is a file the
## Composer will not open at all - the wrong kind of script, or nothing there.
## A file whose body uses a construction outside the subset is *not* refused
## here. It opens, read-only, carrying the reason on its Output panel, because a
## person asking to see an ability is better served by seeing it and being told
## what cannot be drawn than by a dialog that says no and shows nothing.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerHost extends RefCounted

## Borrowed rather than restated: the words for a path that holds nothing are
## one thing, and a second spelling of them is a second thing to keep true.
const NOT_THERE: String = ComposerCatalog.NO_SCRIPT

const SCRIPT_SUFFIX: String = ".gd"
const NOTHING_OPEN: String = "open an ability in the script editor first"
const NOT_A_SCRIPT: String = "%s is not a GDScript file"
const NOT_AN_ABILITY: String = "%s does not extend GameplayAbility"


## What came of asking to open a file.
class Opened extends RefCounted:
	var graph: ComposerGraph = null

	## The file as it was read. The screen holds it and builds everything from
	## it, so handing over only the graph would leave the one thing an edit has
	## to change back on disk where nobody is looking at it.
	var source: String = ""

	## Why it was not opened, or empty. The graph is null exactly when this is
	## not - one question, one answer, so a caller cannot check the wrong one.
	var refusal: String = ""

	func is_ok() -> bool:
		return refusal.is_empty()


## Open the ability at `path`.
static func open(path: String) -> Opened:
	var result: Opened = Opened.new()
	if path.is_empty():
		result.refusal = NOTHING_OPEN
		return result
	if not path.ends_with(SCRIPT_SUFFIX):
		result.refusal = NOT_A_SCRIPT % path.get_file()
		return result
	if not FileAccess.file_exists(path):
		result.refusal = NOT_THERE % path
		return result

	var script: GDScript = load(path) as GDScript
	if script == null:
		result.refusal = NOT_A_SCRIPT % path.get_file()
		return result
	if not is_ability(script):
		result.refusal = NOT_AN_ABILITY % path.get_file()
		return result

	# Read from the file rather than from the loaded script: the two differ the
	# moment somebody has typed in the script editor without saving, and drawing
	# the older of the two would show a graph of code that is no longer there.
	result.source = FileAccess.get_file_as_string(path)
	result.graph = ComposerReader.read(result.source, path)
	return result


## Whether `script` is a GameplayAbility, however many steps away.
##
## Walked over the base scripts rather than over `class_name`s. An ability does
## not need a global name - none of the reference abilities has one - and asking
## the class list would refuse every file that did not bother to declare itself.
static func is_ability(script: GDScript) -> bool:
	var base: String = ComposerCatalog.script_for(ComposerCatalog.ABILITY_CLASS)
	var walked: GDScript = script
	while walked != null:
		if walked.resource_path == base:
			return true
		walked = walked.get_base_script()
	return false
