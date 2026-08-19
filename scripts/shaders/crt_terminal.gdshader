shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float scanline_count : hint_range(50.0, 600.0) = 180.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.18;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.06;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.65;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.003;
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.025;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ca_offset = (uv - 0.5) * chromatic_aberration;
	float r = texture(screen_texture, uv - ca_offset).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv + ca_offset).b;
	vec3 col = vec3(r, g, b);

	float scanline = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
	col -= scanline * scanline_intensity;

	float noise = random(uv + vec2(TIME * 1.5, TIME * 0.8));
	col += (noise - 0.5) * grain_amount;

	float flicker = sin(TIME * 60.0) * flicker_intensity + (random(vec2(TIME, 0.0)) - 0.5) * flicker_intensity;
	col += flicker;

	vec2 centered = (uv - 0.5) * 1.2;
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col *= clamp(vig, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
