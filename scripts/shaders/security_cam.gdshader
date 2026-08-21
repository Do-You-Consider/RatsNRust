shader_type canvas_item;
// Monitor de cámara de seguridad. Es el crt_terminal llevado un paso más
// lejos: además de scanlines y grano, deforma la imagen como una lente barata
// (barrel), le saca casi todo el color y le mete un roll vertical cada tanto.
//
// Se usa en la sala de espera: el jugador ve a su propio personaje desde
// afuera del boliche COMO SI el Atrapador lo estuviera mirando por la cámara.
// La deformación de lente es lo que más vende la idea -- sin ella parece un
// filtro viejo aplicado al juego, no una cámara mirando una escena.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float barrel : hint_range(0.0, 0.6) = 0.16;
uniform float desaturation : hint_range(0.0, 1.0) = 0.58;
uniform vec3 tint : source_color = vec3(0.78, 0.86, 0.82);
uniform float scanline_count : hint_range(50.0, 600.0) = 190.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.13;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.10;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.62;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0026;
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.02;
// Cada cuánto (segundos) la imagen se desplaza hacia arriba una vez.
uniform float roll_period : hint_range(1.0, 30.0) = 7.0;
uniform float roll_speed : hint_range(0.1, 4.0) = 1.4;
uniform float glitch_amount : hint_range(0.0, 0.1) = 0.012;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// --- lente barata: la imagen se abomba hacia afuera desde el centro ---
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	uv = 0.5 + c * (1.0 + barrel * r2);

	// --- roll vertical: la imagen "salta" hacia arriba de vez en cuando ---
	float roll_phase = fract(TIME / roll_period);
	float rolling = step(1.0 - (1.0 / roll_period) * roll_speed, roll_phase);
	uv.y = fract(uv.y + rolling * (roll_phase - (1.0 - (1.0 / roll_period) * roll_speed)) * roll_period * 0.9);

	// --- desgarros horizontales cortos ---
	float band = floor(uv.y * 48.0);
	float tear = step(0.985, random(vec2(band, floor(TIME * 6.0))));
	uv.x += tear * (random(vec2(band, TIME)) - 0.5) * glitch_amount;

	// Fuera del área válida la cámara no tiene señal: negro, no repetición.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 ca = (uv - 0.5) * chromatic_aberration;
		vec3 col = vec3(
			texture(screen_texture, uv - ca).r,
			texture(screen_texture, uv).g,
			texture(screen_texture, uv + ca).b);

		// --- casi blanco y negro, con el verdoso de un CCTV viejo ---
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(luma), desaturation) * tint;

		float scan = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
		col -= scan * scanline_intensity;

		float noise = random(uv + vec2(TIME * 1.7, TIME * 0.9));
		col += (noise - 0.5) * grain_amount;

		col += sin(TIME * 48.0) * flicker_intensity;

		vec2 vc = (uv - 0.5) * 1.25;
		col *= clamp(1.0 - dot(vc, vc) * vignette_strength, 0.0, 1.0);

		COLOR = vec4(col, 1.0);
	}
}
