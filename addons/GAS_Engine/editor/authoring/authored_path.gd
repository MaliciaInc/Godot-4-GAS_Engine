## What a path this addon can create a file at looks like.
##
## Two creators ask the same question - the ability template about a `.gd`, the
## effect asset about a `.tres` - and it is one question: can Godot resolve
## this, and is it the kind of file being made. Asked in two places it is two
## answers waiting to disagree, and the one that drifts is the one that lets a
## file be written somewhere nothing can load it back from.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AuthoredPath extends RefCounted

## The two roots Godot resolves. Anything else - a relative path, an absolute
## one off the filesystem, a URL - is a path nothing in a project can load.
const RESOURCE_PREFIX: String = "res://"
const USER_PREFIX: String = "user://"


static func is_creatable(path: String, suffix: String) -> bool:
	var rooted: bool = path.begins_with(RESOURCE_PREFIX) or path.begins_with(USER_PREFIX)
	return rooted and path.ends_with(suffix)
