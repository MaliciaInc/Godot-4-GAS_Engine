## The GDScript this addon writes into generated files.
##
## Two generators emit GDScript - the attribute-set writer and the tag
## generator - and both were spelling the same annotations. One spelling of
## "what a generated file looks like" means a change to the house style is one
## edit rather than a hunt.
##
## Only fragments both emitters share live here. A fragment used by one of them
## belongs in that emitter, next to the code that decides its shape.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name GDScriptSource extends RefCounted

## Marks a generated script as editor-runnable, which both emitters need
## because both write classes the dashboard instantiates.
const TOOL_ANNOTATION: String = "@tool"

## The licence line every generated file carries, matching this addon's.
const LICENSE_DOC_LINE: String = "## @meta_license: MIT"

const NEWLINE: String = "\n"
