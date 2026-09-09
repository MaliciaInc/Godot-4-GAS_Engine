## One thing wrong with an ability, said so somebody can go straight to it.
##
## A message on its own is a message that sends a person hunting. This carries
## the file, the line, the column and the card, so every way of looking at the
## ability - the canvas, the script editor, an external tool reading a build
## log - can be taken to the same place from the same finding.
##
## And a `code`. The prose changes as the wording improves and should; a code is
## how somebody says "this one again" across two versions, filters a build for
## the kind of mistake they are hunting, or writes a rule about it. A finding
## identified only by its sentence is one nobody can talk about twice.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCompileDiagnostic extends RefCounted

## Which kinds of mistake this engine reports, as stable names.
##
## Named rather than numbered: a number is a thing to look up, and the lookup
## table is the copy that stops being true. These are what a build log carries
## and what a filter is written against, so they change only when the kind of
## mistake changes.
const MISSING_ARGUMENT: StringName = &"gas.missing_argument"
const WRONG_TYPE: StringName = &"gas.wrong_type"
const UNREAD_VALUE: StringName = &"gas.unread_value"
const KEPT_REGION: StringName = &"gas.kept_region"
const NOT_DRAWABLE: StringName = &"gas.not_drawable"
const UNCLASSIFIED: StringName = &"gas.unclassified"

## How loudly this speaks, in the vocabulary the Composer already uses.
##
## Shared rather than restated. Two scales of severity is two places to decide
## what an error is, and the first time they disagreed a card would be red while
## its row in the Output was not.
var severity: ComposerGraph.Severity = ComposerGraph.Severity.NOTE

## Which kind of mistake this is, from the list above.
var code: StringName = UNCLASSIFIED

## What it says, in the words a person reads.
var message: String = ""

## Where it is, at every scale somebody might want to go to it by.
var source_path: String = ""
var line: int = 0
var column: int = 0

## Which card on the canvas, when it is about one. Empty for a finding about
## the file rather than about anything in it.
var node_id: StringName = &""


## Whether this stops the ability being run.
##
## A warning does not. A region the tool kept is a warning: the ability works,
## and what it is being told is which part of itself the Composer will not
## touch. An error does - a call short of a required argument does not compile,
## and running it is not something to offer.
func stops_a_run() -> bool:
	return (
		severity == ComposerGraph.Severity.ERROR
		or severity == ComposerGraph.Severity.NOT_REPRESENTABLE
	)


## `file.gd:61:1`, the shape every editor lets you click.
func at() -> String:
	if line <= 0:
		return source_path.get_file()
	if column <= 0:
		return "%s:%d" % [source_path.get_file(), line]
	return "%s:%d:%d" % [source_path.get_file(), line, column]
