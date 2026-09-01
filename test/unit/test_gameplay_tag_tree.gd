## The tag picker's tree: one branch per segment, however many tags share it.
##
## Every dashboard tab and the inspector property draw the registry through
## this one builder, so a grouping mistake here is the same mistake in four
## places. It had no tests.
##
## The registry is redirected to a scratch resource rather than read from the
## project's own: these tests decide what the hierarchy contains, and reading
## whatever the project happens to ship would make them pass or fail on
## somebody's tag list.
##
## @meta_license: MIT
extends GutTest

const GASEngineProjectSettings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")

const SETTING: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_REGISTRY
const SCRATCH_REGISTRY: String = "user://test_gameplay_tag_tree_registry.tres"

const NO_FILTER: String = ""

var _original_path: Variant = null
var _had_original: bool = false


func before_each() -> void:
	_had_original = ProjectSettings.has_setting(SETTING)
	if _had_original:
		_original_path = ProjectSettings.get_setting(SETTING)


## Restoring "there was none" matters as much as restoring a value: a redirect
## left standing outlives this script and points the whole rest of the suite at
## a scratch file.
func after_each() -> void:
	if _had_original:
		ProjectSettings.set_setting(SETTING, _original_path)
	else:
		ProjectSettings.set_setting(SETTING, null)
	_had_original = false
	_original_path = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_REGISTRY))


func _built(tags: Array[StringName], filter: String = NO_FILTER) -> Tree:
	var registry: GameplayTagRegistry = GameplayTagRegistry.new()
	registry.tags = tags
	assert_eq(ResourceSaver.save(registry, SCRATCH_REGISTRY), OK, "the scratch registry saved")
	ProjectSettings.set_setting(SETTING, SCRATCH_REGISTRY)

	var tree: Tree = Tree.new()
	add_child_autofree(tree)
	var style: GameplayTagTree.Style = GameplayTagTree.Style.new()
	assert_true(
		GameplayTagTree.build(tree, filter, [] as Array[StringName], style),
		"the registry was found"
	)
	return tree


## The tag a row carries, or the empty name when it carries none.
##
## Read through a typed local rather than handed straight to an assertion:
## `get_metadata` answers Variant, and a Variant argument is an unsafe call
## argument, which this project treats as an error rather than a warning.
func _tag_of(item: TreeItem) -> StringName:
	if item == null:
		return &""
	var carried: Variant = item.get_metadata(0)
	if not carried is StringName:
		return &""
	var tag: StringName = carried
	return tag


func _child_texts(item: TreeItem) -> Array[String]:
	var texts: Array[String] = []
	if item == null:
		return texts
	for child: TreeItem in item.get_children():
		texts.append(child.get_text(0))
	return texts


#region Grouping
func test_tags_sharing_a_prefix_share_one_branch() -> void:
	var tree: Tree = _built(
		[&"Status.Stunned", &"Status.Burning", &"Damage.Fire"] as Array[StringName]
	)
	var root: TreeItem = tree.get_root()
	assert_eq(_child_texts(root).size(), 2, "Status and Damage, not one branch per tag")


## A tag may be a parent and a tag at once: `Status` is a legal tag on its own,
## and the grammar has always allowed a single segment.
##
## The branch a later tag has to find was identified by the row's text, and
## decorating a leaf rewrites that text to `Stunned (Status.Stunned)`. So the
## moment `Status` was itself a tag, the row for it no longer answered to
## "Status", and every longer tag under it built a second branch beside the
## first. The registry sorts its tags, and "Status" sorts before
## "Status.Stunned", so this is the order a real project produces.
func test_a_tag_that_is_also_a_parent_gets_one_branch_not_two() -> void:
	var tree: Tree = _built([&"Status", &"Status.Stunned"] as Array[StringName])
	var root: TreeItem = tree.get_root()

	assert_eq(_child_texts(root).size(), 1, "one Status branch")
	var status: TreeItem = root.get_child(0)
	assert_eq(_tag_of(status), &"Status", "which is itself the tag Status")
	assert_eq(_child_texts(status).size(), 1, "and carries Stunned underneath it")


func test_the_deeper_tag_arriving_first_also_gets_one_branch() -> void:
	var tree: Tree = _built([&"Status.Stunned", &"Status"] as Array[StringName])
	assert_eq(_child_texts(tree.get_root()).size(), 1, "order does not decide the shape")


func test_only_a_leaf_carries_the_tag_it_names() -> void:
	var tree: Tree = _built([&"Status.Stunned"] as Array[StringName])
	var status: TreeItem = tree.get_root().get_child(0)
	assert_eq(_tag_of(status), &"", "a grouping node is not a selectable tag")
	assert_eq(_tag_of(status.get_child(0)), &"Status.Stunned", "the leaf is")
#endregion


#region Filtering
func test_a_filter_keeps_only_the_tags_that_contain_it() -> void:
	var tree: Tree = _built(
		[&"Status.Stunned", &"Damage.Fire"] as Array[StringName], "fire"
	)
	var texts: Array[String] = _child_texts(tree.get_root())
	assert_eq(texts.size(), 1, "one branch survived the filter")
	assert_eq(texts[0], "Damage")


func test_a_filter_matching_nothing_leaves_an_empty_tree() -> void:
	var tree: Tree = _built([&"Status.Stunned"] as Array[StringName], "nothing")
	assert_eq(_child_texts(tree.get_root()).size(), 0)
#endregion


#region A registry that is not there
func test_a_missing_registry_is_reported_rather_than_assumed_empty() -> void:
	ProjectSettings.set_setting(SETTING, "user://test_gameplay_tag_tree_absent.tres")
	var tree: Tree = Tree.new()
	add_child_autofree(tree)
	assert_false(
		GameplayTagTree.build(tree, NO_FILTER, [] as Array[StringName], GameplayTagTree.Style.new()),
		"a caller has to be able to tell 'no tags' from 'no registry'"
	)
#endregion
