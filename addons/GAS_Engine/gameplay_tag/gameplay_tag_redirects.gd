## What a tag used to be called, and what it is called now.
##
## Renaming a tag in a project that already ships breaks every asset naming the
## old one, and the assets are Resources somebody authored - hundreds of them,
## on disk, some of them in a build that is already out. A redirect is how the
## rename happens without touching any of them: the old name still resolves, and
## the file that named it is never rewritten unless its author opens and saves
## it themselves.
##
## Never rewritten on load, which is the rule with teeth. A loader that
## "helpfully" updated the asset would be a loader that dirties a hundred files
## the first time somebody opens the project, and puts them in whatever commit
## comes next.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagRedirects extends RefCounted

## How far a chain may go before this stops following it.
##
## A rename of a rename of a rename is ordinary over a project's life; sixty-four
## of them is somebody's mistake, and following it forever is how an editor
## hangs on a file rather than saying what is wrong with it.
const MAX_DEPTH: int = 64

const CYCLE: String = (
	"GAS_Engine: the tag redirect for '%s' leads back to itself; the chain is "
	+ "not followed and the tag is left as it was."
)
const TOO_DEEP: String = (
	"GAS_Engine: the tag redirect chain from '%s' is longer than %d; it is not "
	+ "followed and the tag is left as it was."
)
const RENAMED: String = "GAS_Engine: the tag '%s' has been renamed to '%s'."

## Which old tags have already been mentioned.
##
## Once per old tag per run: a redirect that is hit on every frame of a
## channelled ability would otherwise print a line per frame, and a warning
## nobody can read is a warning nobody reads.
static var _said: Dictionary[StringName, bool] = {}

## What the project declares, read once.
##
## Every tag entering or leaving a runtime is resolved, so this is asked on the
## hottest path in the engine and a file read per tag would be unaffordable.
## Dropped by `forget()`, which the registry calls whenever it writes the file -
## so a redirect added in the editor is in force from the moment it is saved.
static var _declared: Dictionary[StringName, StringName] = {}
static var _read: bool = false


## Forget what has been said, so the next resolve mentions it again.
##
## For a test, and for an editor reloading a project: the point of saying it
## once is that somebody sees it once per run, not once ever.
static func forget() -> void:
	_said.clear()
	_declared.clear()
	_read = false


## What this tag is called now, following the chain as far as it goes.
##
## The tag itself when nothing redirects it, which is every tag in a project
## that has never renamed one - so this is safe to ask about anything.
##
## A cycle or a chain past the limit answers with the tag as it arrived, and
## says so. Answering with a half-followed chain would be answering with a name
## that was never anybody's tag.
static func resolve(
	tag: StringName, redirects: Dictionary[StringName, StringName] = declared()
) -> StringName:
	# The common case, and the one on the hot path: nothing renames this tag, in
	# a project that has never renamed one. Answered before anything is
	# allocated, because a Dictionary per tag per query is a cost every project
	# would pay for a feature almost none of them use.
	if not redirects.has(tag):
		return tag

	var seen: Dictionary[StringName, bool] = {}
	var current: StringName = tag
	var depth: int = 0

	while redirects.has(current):
		if seen.has(current):
			_say(tag, CYCLE % String(tag))
			return tag
		seen[current] = true
		depth += 1
		if depth > MAX_DEPTH:
			_say(tag, TOO_DEEP % [String(tag), MAX_DEPTH])
			return tag
		current = redirects[current]

	if current != tag:
		_say(tag, RENAMED % [String(tag), String(current)])
	return current


## Whether this old tag has already been mentioned in this run.
##
## What "once per run" means, asked rather than inferred: a caller wanting to
## report a rename in its own words needs to know whether the author has
## already been told, and reading it off the console is not an answer.
static func mentioned(tag: StringName) -> bool:
	return _said.has(tag)


## Every rename the project declares, read out of the file that holds them.
static func declared() -> Dictionary[StringName, StringName]:
	if not _read:
		_declared = GameplayTagGenerator.redirects_in_file()
		_read = true
	return _declared


## Say something about one old tag, once.
static func _say(tag: StringName, message: String) -> void:
	if _said.has(tag):
		return
	_said[tag] = true
	push_warning(message)
