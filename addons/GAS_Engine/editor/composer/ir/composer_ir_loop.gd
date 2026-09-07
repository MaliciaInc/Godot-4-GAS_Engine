## A `for` or a `while`, and where it ends.
##
## A loop has no single place on a canvas - that much has always been true, and
## it is why the Composer does not draw one. What was wrong was the conclusion:
## the whole file was turned away, so an ability with one loop in it could not
## be opened at all, and the nine statements around the loop were unreachable
## for the sake of the one.
##
## Knowing where a loop ENDS is what changes that. The body is everything
## indented under the header, so the loop is one region with a first line and a
## last line - and the statements after it are ordinary statements again. The
## tool leaves the region alone and gets on with the rest.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerIRLoop extends RefCounted

enum Sort { FOR, WHILE }

const FOR_MARK: String = "for "
const WHILE_MARK: String = "while "

var sort: ComposerIRLoop.Sort = Sort.FOR

## The header line, stripped: `for target: Node in targets:`.
var header: String = ""

## The header and everything under it.
var span: ComposerSpan = ComposerSpan.new()

## How far in the header sits, so the body is what is further in than this.
var indent: int = 0


## Which loop this line opens, or null when it opens none.
##
## Asked of a line the subset has already classified as a loop, so this decides
## which of the two it is rather than whether it is one at all.
static func sort_of(text: String) -> Variant:
	var stripped: String = text.strip_edges()
	if stripped.begins_with(FOR_MARK):
		return Sort.FOR
	if stripped.begins_with(WHILE_MARK):
		return Sort.WHILE
	return null


## Whether a line opens a loop.
static func opens_one(text: String) -> bool:
	return sort_of(text) != null


## The words for a card, and for the reason a person is told it is not editable.
func described() -> String:
	return "a %s loop" % ("for" if sort == Sort.FOR else "while")
