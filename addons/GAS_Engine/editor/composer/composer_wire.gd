## Wires and the beads that attach them.
##
## Drawn in three passes and no other order:
##
##     wires    behind the cards, so a cable passes under one
##     cards
##     beads    in front, so a dot sits ON the edge it attaches to
##
## Two passes cannot do it. Wires first buries every bead under its card - the
## panel paints over it and only the half sticking out shows, which reads as a
## glow that came loose from its dot. Wires last drags the cables across the
## cards.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerWire extends RefCounted

const SEGMENTS: int = 40
const GLOW_WIDTH: float = 6.0
const LINE_WIDTH: float = 1.5
const MIN_REACH: float = 70.0


## The curve between two points, as a glow and a line laid over it.
##
## Two Line2Ds rather than one wide gradient: a wide translucent line overlaps
## itself at every joint of a curve and the overlaps read as bright spots.
static func draw_into(parent: Node, from: Vector2, to: Vector2) -> void:
	var points: PackedVector2Array = _curve(from, to)

	var glow: Line2D = Line2D.new()
	glow.points = points
	glow.width = GLOW_WIDTH
	glow.default_color = ComposerTheme.WIRE_GLOW
	glow.antialiased = true
	parent.add_child(glow)

	var line: Line2D = Line2D.new()
	line.points = points
	line.width = LINE_WIDTH
	line.default_color = ComposerTheme.WIRE
	line.antialiased = true
	parent.add_child(line)


## A bead where a wire meets a card: halo, disc, white core.
##
## It is the smallest thing on screen and the one that reads as expensive. It
## says the wire is attached to something rather than pointing at it.
static func bead_into(parent: Node, at: Vector2) -> void:
	var halo: TextureRect = ComposerTheme.glow_rect(
		ComposerTheme.glow(ComposerTheme.ACCENT, 0.6)
	)
	halo.position = at - Vector2(ComposerTheme.PORT_HALO, ComposerTheme.PORT_HALO) * 0.5
	halo.size = Vector2(ComposerTheme.PORT_HALO, ComposerTheme.PORT_HALO)
	parent.add_child(halo)

	_disc_into(parent, at, ComposerTheme.PORT_DISC, ComposerTheme.BEAD_DISC)
	_disc_into(parent, at, ComposerTheme.PORT_CORE, ComposerTheme.BEAD_CORE)


## A port with nothing attached. It still exists, and drawing only the wired
## ones makes a card look like it takes nothing.
static func ring_into(parent: Node, at: Vector2) -> void:
	var ring: Panel = Panel.new()
	ring.position = at - Vector2(ComposerTheme.PORT_RING, ComposerTheme.PORT_RING) * 0.5
	ring.size = Vector2(ComposerTheme.PORT_RING, ComposerTheme.PORT_RING)
	ring.add_theme_stylebox_override(GASEditorTheme.PANEL_STYLEBOX, ComposerTheme.ring())
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ring)


static func _disc_into(parent: Node, at: Vector2, radius: float, fill: Color) -> void:
	var disc: Panel = Panel.new()
	disc.position = at - Vector2(radius, radius)
	disc.size = Vector2(radius * 2.0, radius * 2.0)
	disc.add_theme_stylebox_override(GASEditorTheme.PANEL_STYLEBOX, ComposerTheme.disc(fill, radius))
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(disc)


## A bezier that leaves and arrives horizontally.
##
## Flow is left to right, so the handles reach sideways: a curve that left
## vertically would read as a branch even where the code has none. The reach has
## a floor so two cards stacked almost in line still get a curve rather than a
## kink.
static func _curve(from: Vector2, to: Vector2) -> PackedVector2Array:
	var reach: float = maxf(absf(to.x - from.x) * 0.55, MIN_REACH)
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in SEGMENTS + 1:
		var t: float = float(index) / float(SEGMENTS)
		points.append(
			from.bezier_interpolate(
				from + Vector2(reach, 0.0), to - Vector2(reach, 0.0), to, t
			)
		)
	return points
