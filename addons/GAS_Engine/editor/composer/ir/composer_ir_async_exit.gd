## A point where the function stops and comes back later.
##
## `await` is the one statement that is not one moment. Everything before it
## happens now; everything after it happens whenever the thing being waited on
## says so, which may be a frame later, a second later, or never. An ability
## that waits on a signal nobody emits does not fail - it stays open, holding
## whatever it took, and that is the shape of bug this exists to make visible.
##
## Kept apart from an ordinary statement in the IR because the two questions a
## person asks about a body - what does it do, and where can it stop - have
## different answers, and only one of them is readable off the order of the
## cards.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerIRAsyncExit extends RefCounted

const AWAIT_MARK: String = "await "

## Where the suspension is written.
var span: ComposerSpan = ComposerSpan.new()

## The statement it is part of, as one line.
var text: String = ""

## What is being waited on: the part after `await`, with anything assigned to it
## taken off the front. `var hit: Node = await wait_for_hit()` waits on
## `wait_for_hit()`, and the local is what it does with the answer.
var awaited: String = ""


## Whether this statement suspends.
static func suspends(text: String) -> bool:
	return text.contains(AWAIT_MARK)


## What the statement waits on, or empty when it waits on nothing.
static func awaited_in(text: String) -> String:
	var at: int = text.find(AWAIT_MARK)
	if at < 0:
		return ""
	return text.substr(at + AWAIT_MARK.length()).strip_edges()
