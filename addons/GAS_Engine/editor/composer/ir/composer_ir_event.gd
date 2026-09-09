## One thing that happens in a function body, as the IR sees it.
##
## Either a statement this tool understands - a call, a branch, a return - or a
## region it does not, kept whole and kept exactly. The second is the reason
## this type exists: the reader used to answer "one line I cannot draw" by
## refusing the entire file, so a person with a `for` loop in their ability had
## no Composer at all, for a loop the tool only needed to leave alone.
##
## An opaque event still has a place in the order of the body, still has its
## lines, and still gets drawn - as a card that says what it is and does not
## pretend to be editable. What it never has is a rewrite: the writer puts its
## lines back byte for byte.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerIREvent extends RefCounted

## Whether the tool understands this, or only knows where it starts and ends.
enum Shape { STATEMENT, OPAQUE }

var shape: ComposerIREvent.Shape = Shape.STATEMENT

## Where it is in the file: the first line through the last, comments and
## continuation lines included.
var span: ComposerSpan = ComposerSpan.new()

## Where the statement itself begins, which is after any comment or blank line
## it picked up. The same line as `span.first_line` when it picked up none.
var statement_line: int = ComposerSpan.NO_LINE

## The statement as one line, wrapping removed. For an opaque event this is its
## first line only - what it is, rather than everything it contains.
var text: String = ""

## What the subset made of it. Meaningless for an opaque event, which is
## precisely the case where the subset had nothing to say.
var kind: ComposerSubset.Kind = ComposerSubset.Kind.NOTHING

## Why this cannot be drawn as itself, in the words a person needs. Empty for a
## statement.
var reason: String = ""

## The statement this came from, for a caller that needs its verdict. Null on an
## opaque event, which had no verdict worth keeping.
var statement: ComposerStatements.Statement = null


func is_opaque() -> bool:
	return shape == Shape.OPAQUE


## Whether a card is drawn for this at all.
##
## A comment and a blank line are carried by whatever comes after them rather
## than drawn, which is how a person reads them. An opaque region is always
## drawn: leaving it invisible is how somebody deletes one by editing around a
## gap they cannot see.
func is_drawn() -> bool:
	if is_opaque():
		return true
	return statement != null and statement.verdict.is_drawn()
