## Every ability in this project, found rather than asked for.
##
## The Composer used to draw whatever the Script editor happened to have open,
## and said so when that was not an ability. That is friction charged to the
## person for the tool's convenience: somebody who chose Ability Composer asked
## for their abilities, not for instructions about opening one first.
##
## Found by reading rather than by loading. `load()` on every script in a
## project compiles every script in a project, which is a visible pause on a
## real game for a question that a first line answers. So each file is read as
## text, its `extends` is resolved through the project's own class list, and a
## chain that reaches GameplayAbility makes it a candidate.
##
## A candidate, not a verdict. `ComposerHost.open()` is still what decides, and
## it decides on the loaded script; a false positive here costs one refusal with
## a reason on it, which is a cheaper mistake than a scan that misses somebody's
## ability and leaves them unable to reach it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerLibrary extends RefCounted


## What the last look found, and whether one has happened.
##
## A project with Dialogic, GLoot and QuestSystem installed carries about five
## hundred scripts that are not anybody's abilities, and looking through all of
## them again on every press is work nobody asked for. The answer is remembered
## instead, and thrown away whenever the editor says the filesystem moved.
static var _remembered: PackedStringArray = PackedStringArray()
static var _looked: bool = false


## Look again next time. Cheap, and correct to call whenever anything might have
## changed: the cost of forgetting too often is one scan, and the cost of
## forgetting too rarely is somebody's new ability being invisible.
static func forget() -> void:
	_looked = false
	_remembered = PackedStringArray()


## Start listening for somebody's word that files moved, exactly once.
##
## The editor's filesystem outlives the plugin, and `forget` is static, so a
## plugin that connects on enable and never lets go has connected twice by its
## second enable. Godot refuses that with an error rather than ignoring it - and
## disable-then-enable is not an unusual thing to do, it is the documented way
## to reload a plugin after its files change on disk.
static func listen_to(source: Object, moved: StringName) -> void:
	if not source.is_connected(moved, forget):
		source.connect(moved, forget)


## And stop. Safe to call when it was never listening, because an exit path that
## has to be sure it ran first is an exit path that eventually does not.
static func stop_listening_to(source: Object, moved: StringName) -> void:
	if source.is_connected(moved, forget):
		source.disconnect(moved, forget)


## Every file whose base chain reaches GameplayAbility, sorted so the list a
## person sees does not reshuffle itself between two openings.
static func abilities_in_project() -> PackedStringArray:
	if not _looked:
		_remembered = scan()
		_looked = true
	return _remembered


## The look itself, without the remembering. Separate so a caller that has to
## know the answer is current can ask for one, and so the two can be compared.
##
## The walking and the base-chain resolving are GDScriptClassScan's, because
## the attribute picker asks the same question about a different base and two
## copies of it would be two answers.
static func scan() -> PackedStringArray:
	return GDScriptClassScan.scripts_extending(ComposerCatalog.ABILITY_CLASS)
