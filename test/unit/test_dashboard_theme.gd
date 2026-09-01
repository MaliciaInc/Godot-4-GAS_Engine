## The dashboard's shared palette, asked whether it can style anything before it
## knows what colour to use.
##
## `sync_from_editor()` has three ways to decline - no editor, no editor theme,
## and the all-black theme a hot reload passes through - and it was the only
## place the styleboxes were ever created. Every consumer that styled a control
## before the first successful sync therefore handed Godot a null StyleBox,
## which the engine refuses: the override never lands, the control keeps the
## default look, and nothing re-styles it afterwards.
##
## Headless is exactly that unsynced state - `Engine.is_editor_hint()` is false
## here - so these run against the real failure without standing up an editor.
##
## @meta_license: MIT
extends GutTest

const TREE_SELECTED: String = "selected"
const TREE_SELECTED_FOCUS: String = "selected_focus"


func _theme() -> DashboardTheme:
	var theme: DashboardTheme = DashboardTheme.new()
	assert_false(theme.sync_from_editor(), "headless declines to sync; that is the state under test")
	return theme


#region Styling before the first sync
func test_a_tree_styled_before_the_first_sync_is_still_styled() -> void:
	var tree: Tree = Tree.new()
	autofree(tree)

	_theme().style_tree(tree)

	assert_true(tree.has_theme_stylebox_override(TREE_SELECTED), "selection stylebox landed")
	assert_true(tree.has_theme_stylebox_override(TREE_SELECTED_FOCUS), "and the focused one too")


## `TagManagerTab._ready()` calls `configure_tree()` first and syncs second, so
## this is the shipped order, not a hypothetical one.
func test_configure_tree_styles_a_tree_before_the_first_sync() -> void:
	var tree: Tree = Tree.new()
	autofree(tree)

	_theme().configure_tree(tree, ["Name", "Value"] as Array[String], [3, 1] as Array[int])

	assert_eq(tree.columns, 2, "the columns still get laid out")
	assert_true(tree.has_theme_stylebox_override(TREE_SELECTED), "and the styling is not lost")


## `CueRow.build()` reads this one straight into an override of its own.
func test_every_shared_stylebox_exists_before_the_first_sync() -> void:
	var theme: DashboardTheme = _theme()
	assert_not_null(theme.base_panel, "base_panel")
	assert_not_null(theme.dark_panel, "dark_panel")
	assert_not_null(theme.header_panel, "header_panel")
	assert_not_null(theme.selection, "selection")
	assert_not_null(theme.list_item, "list_item")
#endregion


#region The in-place contract the header promises
## The boxes are mutated rather than replaced so a control that already holds
## one repaints on a re-sync. That is what makes handing out an uncoloured box
## safe, so it is pinned here rather than left as a comment.
func test_a_resync_mutates_the_box_a_control_already_holds() -> void:
	var theme: DashboardTheme = _theme()
	var tree: Tree = Tree.new()
	autofree(tree)
	theme.style_tree(tree)

	var held: StyleBoxFlat = tree.get_theme_stylebox(TREE_SELECTED) as StyleBoxFlat
	assert_not_null(held, "the tree hands back what was overridden onto it")

	theme.selection.bg_color = Color.RED
	assert_eq(held.bg_color, Color.RED, "the control sees the new colour without being restyled")
	assert_same(held, theme.selection, "because it is the same object, not a copy")
#endregion
