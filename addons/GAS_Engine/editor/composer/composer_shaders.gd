## The two shaders the Composer draws with, and the materials that carry them.
##
## Both were built and verified running inside the Godot editor rather than
## reasoned about. The notes below are what that cost to find out.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerShaders extends RefCounted

const PARAM_CANVAS: StringName = &"canvas_color"
const PARAM_DOT: StringName = &"dot_color"
const PARAM_SPACING: StringName = &"spacing"
const PARAM_TINT: StringName = &"tint"
const PARAM_BLUR: StringName = &"blur"
const PARAM_RADIUS: StringName = &"radius"
const PARAM_RECT: StringName = &"rect_size"

## The canvas mesh.
##
## Read from FRAGCOORD rather than UV so the dots stay square and evenly spaced
## whatever size the control is. The spacing is a parameter because zoom changes
## the pitch of the mesh instead of scaling it - scaling fattens the dots until
## they are smudges.
const DOT_GRID: String = """
shader_type canvas_item;
uniform vec4 canvas_color : source_color;
uniform vec4 dot_color : source_color;
uniform float spacing = 26.0;
uniform float radius = 1.05;
void fragment() {
	vec2 cell = mod(FRAGCOORD.xy, spacing) - spacing * 0.5;
	float d = 1.0 - smoothstep(radius - 0.7, radius + 0.7, length(cell));
	COLOR = mix(canvas_color, dot_color, d * dot_color.a);
}
"""

## The card.
##
## Samples what is already on screen and blurs it, so a card takes the colour of
## the glow it stands on. A solid fill sits on its own light without taking any
## of it and reads as a sticker laid over the canvas.
##
## No BackBufferCopy anywhere near this. Godot 4 requests the back buffer on its
## own when it sees `hint_screen_texture`; adding the node by hand BREAKS the
## sampling, and the panel comes out a flat rectangle. That failure looks exactly
## like the technique not working.
##
## The corners are rounded here rather than by a StyleBox, because a ColorRect
## is square and the shader is what decides which of its pixels exist.
const GLASS: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color;
uniform float blur = 3.4;
uniform float radius = 13.0;
uniform vec2 rect_size = vec2(232.0, 118.0);

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 local = (UV - 0.5) * rect_size;
	float d = rounded_box(local, rect_size * 0.5, radius);
	float inside = 1.0 - smoothstep(-1.0, 1.0, d);
	if (inside <= 0.001) { discard; }

	vec4 acc = vec4(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			vec2 o = vec2(float(x), float(y));
			float w = 1.0 - length(o) / 5.0;
			if (w <= 0.0) { continue; }
			acc += texture(screen_tex, SCREEN_UV + o * SCREEN_PIXEL_SIZE * blur) * w;
			total += w;
		}
	}
	vec3 back = (acc / total).rgb;
	float edge = smoothstep(-2.0, -0.4, d);
	COLOR = vec4(mix(mix(back, tint.rgb, tint.a), vec3(1.0), edge * 0.06), inside);
}
"""


static func _compiled(source: String) -> Shader:
	var shader: Shader = Shader.new()
	shader.code = source
	return shader


## The canvas mesh, at a pitch that follows the zoom.
static func grid_material(zoom: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _compiled(DOT_GRID)
	material.set_shader_parameter(PARAM_CANVAS, ComposerTheme.CANVAS)
	material.set_shader_parameter(PARAM_DOT, ComposerTheme.GRID_DOT)
	material.set_shader_parameter(PARAM_SPACING, ComposerTheme.GRID_SPACING * zoom)
	return material


## A card. `size` is set again by `resize_glass()` once the card has measured
## itself, because a card is cut to its content rather than guessed at.
static func glass_material(size: Vector2) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _compiled(GLASS)
	material.set_shader_parameter(PARAM_TINT, ComposerTheme.GLASS_TINT)
	material.set_shader_parameter(PARAM_BLUR, 3.4)
	material.set_shader_parameter(PARAM_RADIUS, float(ComposerTheme.RADIUS_PANEL))
	material.set_shader_parameter(PARAM_RECT, size)
	return material


## The shader rounds its own corners, so it has to be told the rectangle it is
## rounding. Resizing the control alone leaves the corners cut for the old size.
static func resize_glass(material: ShaderMaterial, size: Vector2) -> void:
	if material == null:
		return
	material.set_shader_parameter(PARAM_RECT, size)
