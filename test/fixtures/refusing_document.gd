## A document that reads, prints and refuses.
##
## Everything the controller asks it before writing answers truthfully - it is
## open, it may be written to, its graph is the real one read from the source -
## and then every commit is turned down. That is the shape of the one failure
## the controller cannot produce on its own: the reread that says the text would
## leave a file the Composer can no longer draw.
##
## The point is what the controller does next. A caller that hears "yes" from a
## document that said no has just told somebody their wire was made, and the
## canvas will redraw itself around a change that never happened.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends ComposerDocument


func commit(_next: String) -> ComposerGraph.Diagnostic:
	return ComposerWriter.refuse(ComposerDocument.BROKE_IT)
