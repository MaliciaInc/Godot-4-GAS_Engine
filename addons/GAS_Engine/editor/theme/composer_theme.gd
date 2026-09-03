## Every colour, measure and surface the Composer draws with, declared once.
##
## A design token repeated at the point of use is a design that drifts: the
## third card written gets a slightly different grey, and nobody notices until
## the screen looks subtly wrong for reasons no one can name. Everything visual
## reads from here.
##
## Colours are built from bytes rather than hex strings on purpose. A hex string
## is a literal the tooling has to scan and a human has to trust; `Color8` says
## the same thing in numbers that cannot be mistyped into a valid-but-wrong
## colour.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerTheme extends RefCounted

#region Palette
## The canvas, and the chrome that frames it. The chrome is a shade lighter so
## the graph reads as the thing in front.
const CANVAS: Color = Color(0.043, 0.043, 0.059)
const CHROME: Color = Color(0.055, 0.055, 0.075)

const ROW: Color = Color(0.118, 0.118, 0.149)
const BORDER: Color = Color(0.165, 0.165, 0.204)
const RULE: Color = Color(0.125, 0.125, 0.165)

const TEXT: Color = Color(0.929, 0.929, 0.949)
const TEXT_DIM: Color = Color(0.541, 0.541, 0.600)
const TEXT_FAINT: Color = Color(0.353, 0.353, 0.408)

## The one accent, spent sparingly: the active view, the primary control, the
## light under a card, the bead on a wire. Anything else stays grey.
const ACCENT: Color = Color(0.482, 0.361, 1.0)

const WARNING: Color = Color(0.851, 0.643, 0.255)
const ERROR: Color = Color(0.878, 0.322, 0.322)
const OK: Color = Color(0.239, 0.839, 0.549)

const WIRE: Color = Color(0.820, 0.820, 0.902, 0.72)
const WIRE_GLOW: Color = Color(0.482, 0.361, 1.0, 0.14)
const BEAD_DISC: Color = Color(0.80, 0.78, 1.0, 0.92)
const BEAD_CORE: Color = Color(1.0, 1.0, 1.0, 1.0)
const ACCENT_SOFT: Color = Color(0.482, 0.361, 1.0, 0.9)
const GRID_DOT: Color = Color(1.0, 1.0, 1.0, 0.06)
const GLASS_TINT: Color = Color(0.086, 0.086, 0.110, 0.66)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.5)
const HAIRLINE: Color = Color(1.0, 1.0, 1.0, 0.035)
const TRANSPARENT: Color = Color(0.0, 0.0, 0.0, 0.0)
const RING_EDGE: Color = Color(0.353, 0.353, 0.408, 0.75)
const WIRE_GLOW_ALPHA: float = 0.14
const GLASS_TINT_ALPHA: float = 0.66
const BLOOM_STRENGTH: float = 0.42
const DOT_ALPHA: float = 0.06
#endregion


#region Measures
## One scale. Every gap is a multiple of it, so nothing lands on a number
## someone picked because it looked right that day.
const S1: float = 4.0
const S2: float = 8.0
const S3: float = 12.0
const S4: float = 20.0

const FONT_TITLE: int = 14
const FONT_VALUE: int = 12
const FONT_LABEL: int = 10

## Fixed. Anything that does not fit goes to the Inspector rather than making
## one card wider than its neighbours.
const NODE_WIDTH: float = 232.0
const PAD_X: float = 14.0
const PAD_Y: float = 12.0

const RADIUS_PANEL: int = 13
const RADIUS_ROW: int = 8

## Grid spacing at 1.0 zoom. The dots keep their size at every level and the
## mesh changes pitch instead, so pulling out never turns them into smudges.
const GRID_SPACING: float = 26.0

## How far apart the layout's columns and lanes sit once they become pixels.
## The layout deals in grid coordinates; this is the only place they gain a
## size, so a card's own measured height can still push its lane apart.
const COLUMN_STEP: float = 320.0
const LANE_STEP: float = 210.0

## An ellipse rather than a circle, at this multiple of the card it belongs to.
## A circle around a short wide card spills far above and below it.
## The wash left over the graph while a selection box is being dragged. Faint
## on purpose: it says which cards it covers without hiding them.
const SELECTION_FILL: Color = Color(0.482, 0.361, 1.0, 0.14)

## How thick the outline around a picked card is.
const RING_WIDTH: float = 1.0

const BLOOM_SCALE: float = 1.9

const PORT_CORE: float = 2.6
const PORT_DISC: float = 5.6
const PORT_HALO: float = 30.0
const PORT_RING: float = 9.0
#endregion


#region Surfaces
## The card, the field row, the floating panel - all the same builder, because
## they differ only in fill, radius and whether they cast a shadow.
static func box(
	fill: Color, radius: int, border: Color, shadow: int = 0
) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(1)
	style.shadow_color = SHADOW
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0.0, 7.0)
	style.content_margin_left = PAD_X
	style.content_margin_right = PAD_X
	style.content_margin_top = PAD_Y
	style.content_margin_bottom = PAD_Y + 1.0
	return style


## A value slot inside a card: tighter margins, no shadow, a hairline edge.
static func field_box() -> StyleBoxFlat:
	var style: StyleBoxFlat = box(ROW, RADIUS_ROW, HAIRLINE)
	style.content_margin_top = S2
	style.content_margin_bottom = S2
	style.content_margin_left = S3 - 1.0
	style.content_margin_right = S3 - 1.0
	return style


## A filled circle, for the core of a port bead and the dot on a card's title.
static func disc(fill: Color, radius: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(ceil(radius)))
	return style


## An unconnected port: an outline, not a fill. Drawing only the wired ones
## makes a card look like it takes nothing.
static func ring() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = TRANSPARENT
	style.border_color = RING_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(PORT_RING * 0.5) + 1)
	return style


## The radial gradient behind a card, and the halo under a port bead.
##
## Drawn rather than post-processed: an editor Control has no WorldEnvironment,
## so there is no camera glow to lean on.
static func glow(tint: Color, strength: float) -> GradientTexture2D:
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, strength),
		Color(tint.r, tint.g, tint.b, strength * 0.28),
		Color(tint.r, tint.g, tint.b, 0.0),
	])

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## A TextureRect that honours the size it is given.
##
## `EXPAND_KEEP_SIZE` is the default and its minimum size IS the texture, so the
## control quietly takes the texture's dimensions instead of the ones asked for
## and draws from its corner. The result reads as a glow that came loose from
## the thing it belongs to, and it is not obvious from the code that set a size.
static func glow_rect(texture: GradientTexture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
#endregion


#region Diagnostics
## How a severity looks, as two tables rather than two match statements.
##
## Indexed by the enum, so the order here IS ComposerGraph.Severity's order and
## a severity added without a colour or a mark is a missing entry rather than a
## silent fall-through to whatever the default branch happened to be. A test
## holds the two lengths against the enum.
##
## Two branching functions were the alternative, and they were the same shape
## twice - which is how a card's dot and its Output row end up disagreeing about
## one fact.
## A file this tool cannot draw is not a file with mistakes in it, so it is not
## red - but it is something a person has to know, so it is not grey either. Grey
## is what a count of nodes is drawn in, and a reason that reads as a count is a
## reason nobody reads. Hollow rather than solid, for the same reason: it has to
## be told apart from an error at a glance.
const SEVERITY_COLORS: Array[Color] = [TEXT_FAINT, WARNING, ERROR, WARNING]
const SEVERITY_MARKS: Array[String] = ["•", "▲", "■", "□"]


static func severity_color(severity: ComposerGraph.Severity) -> Color:
	return SEVERITY_COLORS[int(severity)]


## The glyph that opens an Output row. Same table, same order.
static func severity_mark(severity: ComposerGraph.Severity) -> String:
	return SEVERITY_MARKS[int(severity)]
#endregion
