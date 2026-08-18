shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.07;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = texture(screen_texture, uv);

	float noise = random(uv + vec2(TIME * 0.7, TIME * 1.3));
	col.rgb += (noise - 0.5) * grain_amount;

	vec2 centered = uv - 0.5;
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col.rgb *= clamp(vig, 0.0, 1.0);

	COLOR = col;
}
