shader_type canvas_item;
// Shader de GAMEPLAY (distinto del CRT del menú a propósito). Usa dithering
// ordenado (matriz Bayer 4x4), la técnica real que usaban PS1/PS2 para
// simular más colores de los que su hardware podía mostrar. Se nota como
// una textura/banding sutil en superficies planas, no como "ruido de TV" ni
// como el look de terminal del menú -- la idea es que se sienta low-poly /
// baja resolución de color sin llamar la atención sobre el efecto en sí.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.1;
uniform float color_levels : hint_range(4.0, 32.0) = 20.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.3;

const float bayer4x4[16] = float[16](
	0.0,  8.0,  2.0, 10.0,
	12.0, 4.0, 14.0,  6.0,
	3.0, 11.0,  1.0,  9.0,
	15.0, 7.0, 13.0,  5.0
);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = texture(screen_texture, uv);

	ivec2 p = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = (bayer4x4[p.x + p.y * 4] / 16.0) - 0.5;

	col.rgb += threshold * dither_strength / color_levels;
	col.rgb = floor(col.rgb * color_levels + 0.5) / color_levels;

	// Viñeta muy leve -- solo para que los bordes de pantalla no se sientan
	// tan "planos", sin oscurecer visibilidad de juego.
	vec2 centered = uv - 0.5;
	float vig = 1.0 - dot(centered, centered) * vignette_strength;
	col.rgb *= clamp(vig, 0.0, 1.0);

	COLOR = col;
}
