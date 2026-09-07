## Creates the smallest valid ability the Composer can open immediately.
##
## Creation lives outside the view and outside the runtime. The behaviour
## authority is a normal GDScript, the same source file every other ability
## uses - and beside it a scene, because a script is not something an ASC can
## be given.
##
## `give_ability()` takes a PackedScene and nothing else: an ability is a Node
## with authored state on it, and a project that had only the script had to
## build that scene by hand before it could run what it had just written. Two
## files, one of them generated from the other, and no second way to say what
## an ability is.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerAbilityTemplate extends RefCounted

const SCRIPT_SUFFIX: String = ".gd"
const SCENE_SUFFIX: String = ".tscn"

## The two roots Godot can resolve a path under. Anything else - a relative
## path, an absolute one off the filesystem - is a path this cannot create
## into, and refusing it here is how a caller finds that out before a half
## written pair exists.
const RESOURCE_PREFIX: String = "res://"
const USER_PREFIX: String = "user://"

const SOURCE: String = """@tool
extends GameplayAbility


func _activate_ability() -> bool:
	return true
"""

const INVALID_PATH: String = "Ability path must be a res:// GDScript path."
const ALREADY_EXISTS: String = "Creating an ability here writes both %s and %s, and %s already exists."
const CANNOT_WRITE: String = "Could not create ability at %s."
const CANNOT_BUILD_SCENE: String = "Could not build a scene for %s."


## The scene that belongs to a script, which is the script's own path with the
## other suffix. Public because the create dialog says what it is about to write
## before it writes any of it, and it must not work that out for itself.
static func scene_path_for(script_path: String) -> String:
	return script_path.trim_suffix(SCRIPT_SUFFIX) + SCENE_SUFFIX


## Create the script and the scene beside it, or say why neither was created.
##
## Neither, deliberately. An existing file on either side stops the whole thing:
## writing the script over a scene somebody had already built would leave a pair
## that disagrees, and there is no version of that a person would have asked
## for. The refusal names both outputs, so the answer to "what would this have
## done" does not require guessing at the second one.
static func create(path: String) -> String:
	if not _is_creatable(path):
		return INVALID_PATH

	var scene_path: String = scene_path_for(path)
	var occupied: String = _first_existing(path, scene_path)
	if not occupied.is_empty():
		return ALREADY_EXISTS % [path, scene_path, occupied]

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return CANNOT_WRITE % path
	file.store_string(SOURCE)
	file.close()

	var refusal: String = _write_scene(path, scene_path)
	if not refusal.is_empty():
		# The script alone is the half-made pair this refuses to leave behind.
		DirAccess.remove_absolute(path)
		return refusal

	ComposerLibrary.forget()
	return ""


static func _is_creatable(path: String) -> bool:
	var rooted: bool = path.begins_with(RESOURCE_PREFIX) or path.begins_with(USER_PREFIX)
	return rooted and path.ends_with(SCRIPT_SUFFIX)


static func _first_existing(script_path: String, scene_path: String) -> String:
	if FileAccess.file_exists(script_path):
		return script_path
	if FileAccess.file_exists(scene_path):
		return scene_path
	return ""


## Pack an instance of the script just written into a scene whose root is it.
##
## Instantiated from the script rather than assembled as a Node with a script
## bolted on: the root has to BE the ability for `give_ability()` to accept it,
## and the only thing that knows what the script is worth is the script.
static func _write_scene(script_path: String, scene_path: String) -> String:
	var script: GDScript = load(script_path) as GDScript
	if script == null:
		return CANNOT_BUILD_SCENE % scene_path

	var root: Node = script.new()
	if root == null:
		return CANNOT_BUILD_SCENE % scene_path
	root.name = script_path.get_file().trim_suffix(SCRIPT_SUFFIX)

	var scene: PackedScene = PackedScene.new()
	var packed: Error = scene.pack(root)
	root.free()
	if packed != OK:
		return CANNOT_BUILD_SCENE % scene_path
	if ResourceSaver.save(scene, scene_path) != OK:
		return CANNOT_BUILD_SCENE % scene_path
	return ""
