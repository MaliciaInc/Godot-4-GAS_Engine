## What is bound to what, and which binding answers a request.
##
## Split out of GameplayCueManager, which had grown into two jobs: this one is
## the catalogue - the scenes, the scriptless handlers, the tags that end a
## fallback walk, and the flags each cue declares about itself - and the manager
## is the part that takes an instance, parents it under a target and drives its
## lifecycle. Neither needs the other's fields.
##
## Reads the project's generated registry file and nothing else. It never
## instantiates a cue to play it; the one instance it does build is built to
## read four exported values off and freed on the spot.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueCatalog extends RefCounted

const Settings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")
const CueGenerator = preload("res://addons/GAS_Engine/cues/gameplay_cue_generator.gd")
const CueNotify = preload("res://addons/GAS_Engine/cues/gameplay_cue_notify.gd")
const CueHandler = preload("res://addons/GAS_Engine/cues/gameplay_cue_handler.gd")
const CueFlags = preload("res://addons/GAS_Engine/cues/gameplay_cue_flags.gd")
const TagFamily = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_family.gd")

const MISSING: String = "GAS_Engine: cue %s names a scene that will not load: %s"

## Tags answered by a scene, and tags answered by a script. A tag is in one or
## the other, never both.
var scenes: Dictionary[StringName, PackedScene] = {}
var handlers: Dictionary[StringName, CueHandler] = {}

## Tags that end a fallback walk where they stand.
var overrides: Dictionary[StringName, bool] = {}

## What each cue scene declares about itself, read once.
var flags: Dictionary[StringName, CueFlags] = {}


## Fill the catalogue from the project's generated registry.
##
## False when there is no registry file, which is normal in a project that
## declares no cues and worth a warning only in one that meant to.
func load_from_project() -> bool:
	if not FileAccess.file_exists(Settings.get_generated_cue_script_path()):
		_warn_missing()
		return false

	var bindings: Dictionary[StringName, String] = CueGenerator.bindings_in_file()
	for tag: StringName in bindings:
		var scene: PackedScene = load(bindings[tag]) as PackedScene
		if scene == null:
			push_error(MISSING % [String(tag), bindings[tag]])
			continue
		scenes[tag] = scene

	var handler_paths: Dictionary[StringName, String] = CueGenerator.handlers_in_file()
	for tag: StringName in handler_paths:
		var handler_script: Script = load(handler_paths[tag]) as Script
		if handler_script == null:
			push_error(MISSING % [String(tag), handler_paths[tag]])
			continue
		handlers[tag] = handler_script.new()

	for tag: StringName in CueGenerator.overrides_in_file():
		overrides[tag] = true
	return true


## Which tag actually answers a request.
##
## The cue a game announces is often more specific than the cue it has art for:
## `Cue.Damage.Fire.Critical` is a reasonable thing to say and a silly thing to
## demand a separate scene for. So a request nothing answers falls back up its
## own family - A.B.C, then A.B, then A - and the first binding found is the one
## that plays.
##
## Both kinds of binding are consulted at each level, in one walk. Two walks -
## scenes first, then handlers - would answer a request with an ancestor's scene
## while a handler was bound to the exact tag, so which kind a project chose
## would silently change which tag answered.
##
## A tag under OVERRIDE_PARENT ends that walk where it stands. With a binding of
## its own, that binding is what plays; without one, nothing plays and nothing
## further up is consulted either - which is how a project says "this whole
## branch is silent" without binding every leaf under it to an empty scene.
##
## Answers &"" when nothing does, which every caller already treats as "no cue
## to show for it, and gameplay carries on regardless".
func resolve(requested: StringName) -> StringName:
	for candidate: StringName in TagFamily.ancestors_of(requested):
		if scenes.has(candidate) or handlers.has(candidate):
			return candidate
		if overrides.has(candidate):
			return &""
	return &""


## What a cue scene declares about itself, read once and kept.
##
## A scene's exported values cannot be read without building one of it, and
## these are asked on every persistent activation. The instance is freed the
## moment it has been read: keeping it would keep a Node nobody ever plays,
## parented nowhere, which is an orphan and the run counts those.
func flags_for(tag: StringName) -> CueFlags:
	if flags.has(tag):
		return flags[tag]
	if not scenes.has(tag):
		return null
	var raw: Node = scenes[tag].instantiate()
	var declared: CueNotify = raw as CueNotify
	if declared == null:
		raw.free()
		return null
	var read: CueFlags = CueFlags.new()
	read.unique_per_instigator = declared.unique_per_instigator
	read.unique_per_source_object = declared.unique_per_source_object
	read.allow_multiple_on_active = declared.allow_multiple_on_active
	read.preallocate = declared.preallocate
	declared.free()
	flags[tag] = read
	return read


## A missing registry is normal in a project that declares no cues, and noisy
## in one that meant to. Only the second case warrants a warning.
func _warn_missing() -> void:
	if Engine.is_editor_hint() and not EditorInterface.is_plugin_enabled(Settings.ADDON_NAME):
		return
	push_warning(
		"GAS_Engine: No cue registry found at " + Settings.get_generated_cue_script_path()
	)
