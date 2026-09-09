## One tab of the runtime overlay: a snapshot turned into lines of text.
##
## The transformation is the whole page. Drawing it is a Tree with some columns,
## which every page shares and none of them decides; what differs is which part
## of the entity a page is about and how it is worded.
##
## Nothing here touches a Canvas, a Control or a Theme, so a page can be asked
## what it would show without a screen - which is how these are tested, and the
## reason the deciding does not live in the overlay.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugPage extends RefCounted

## What a page says instead of a table when there is nothing to say.
const NOTHING: String = "nothing yet"


## One line of a page.
class Row extends RefCounted:
	var cells: PackedStringArray = PackedStringArray()

	## Whether this row is the one somebody is looking for: an inhibited
	## effect, an ability that just refused, a tag held only through its
	## children. Drawn differently rather than sorted to the top, because the
	## order a page lists things in is the order the runtime holds them and
	## re-ordering would hide which of two effects landed first.
	var notable: bool = false

	func said() -> String:
		return " | ".join(cells)


## What the tab is called.
func title() -> String:
	return ""


## The word this page is called by at a console.
##
## Its own title, because a page and the command that prints it are the same
## thing said to two audiences, and two spellings of one word is how a command
## comes to print a page nobody meant.
func command() -> String:
	return title().to_lower()


## The column headings, which also say how many cells a row has.
func columns() -> PackedStringArray:
	return PackedStringArray()


## The lines this page would draw for that snapshot.
func rows(_snapshot: GasRuntimeSnapshot) -> Array[Row]:
	return []


## One line, from its cells.
static func row_of(cells: Array[String], notable: bool = false) -> Row:
	var row: Row = Row.new()
	# Built rather than assigned: a PackedStringArray takes its contents at
	# construction and has no `assign`, which is the sort of thing that only
	# fails once the whole file has stopped compiling.
	row.cells = PackedStringArray(cells)
	row.notable = notable
	return row


## A number as somebody reads it rather than as a float prints.
##
## Two decimals, and no decimals at all when there are none: `20` rather than
## `20.00`, because an overlay full of trailing zeroes is an overlay whose
## interesting digits are harder to find.
static func number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return String.num(value, 0)
	return String.num(value, 2)


## A duration, or a dash when nothing is counting down.
##
## A dash rather than `0.00`, which reads as "about to expire" - the opposite of
## what an infinite effect is doing.
static func seconds(value: float) -> String:
	if value <= 0.0:
		return "-"
	return number(value) + "s"


## A whole number, or a dash at zero, for the same reason.
static func turns(value: int) -> String:
	if value <= 0:
		return "-"
	return str(value)
