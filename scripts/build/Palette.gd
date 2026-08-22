class_name Palette
extends RefCounted
## Paleta de materiales del juego. Las recetas son las mismas que usa
## MapGenerator.gd para la nave: los sets del menú tienen que estar hechos del
## MISMO hormigón, el MISMO ladrillo y los MISMOS neones que el mapa, o el
## menú y la partida parecen dos juegos distintos.
##
## Se instancia una vez por set (`Palette.create()`) y se descarta con él: son
## StandardMaterial3D compartidos entre todas las mallas del set, así que un
## set de 400 cajas usa ~30 materiales, no 400.

## Devuelve { nombre_corto: StandardMaterial3D }.
static func create() -> Dictionary:
	var p := {}

	# --- superficies de obra ---
	p["concrete_floor"] = BuildKit.matte(Color(0.08, 0.075, 0.07), 0.95)
	p["concrete_wall"] = BuildKit.matte(Color(0.15, 0.135, 0.12), 0.9)
	p["brick"] = BuildKit.matte(Color(0.19, 0.085, 0.06), 0.92)
	p["tile_floor"] = BuildKit.matte(Color(0.09, 0.15, 0.13), 0.45)
	p["tile_wall"] = BuildKit.matte(Color(0.12, 0.22, 0.19), 0.4)
	p["wood_floor"] = BuildKit.matte(Color(0.14, 0.09, 0.05), 0.85)
	p["aged_wood"] = BuildKit.matte(Color(0.22, 0.12, 0.06), 0.85)
	p["paint_worn"] = BuildKit.matte(Color(0.28, 0.30, 0.31), 0.8)
	p["rubble"] = BuildKit.matte(Color(0.30, 0.28, 0.26), 0.98)

	# --- metales ---
	p["rust_metal"] = BuildKit.matte(Color(0.32, 0.16, 0.08), 0.55, 0.8)
	p["dark_steel"] = BuildKit.matte(Color(0.20, 0.21, 0.23), 0.35, 0.9)
	p["grate"] = BuildKit.matte(Color(0.13, 0.14, 0.15), 0.5, 0.85)
	p["pipe_industrial"] = BuildKit.matte(Color(0.60, 0.40, 0.08), 0.4, 0.7)
	p["hazard_mark"] = BuildKit.matte(Color(0.55, 0.45, 0.08), 0.65, 0.4)
	p["mirror"] = BuildKit.matte(Color(0.85, 0.85, 0.9), 0.05, 1.0)

	# --- blandos ---
	p["fabric_red"] = BuildKit.matte(Color(0.22, 0.05, 0.07), 0.95)
	p["leather_brown"] = BuildKit.matte(Color(0.14, 0.07, 0.04), 0.7)
	p["rubber_black"] = BuildKit.matte(Color(0.05, 0.05, 0.055), 0.95)
	p["mattress"] = BuildKit.matte(Color(0.42, 0.38, 0.30), 0.95)
	p["shrinkwrap"] = BuildKit.matte(Color(0.55, 0.58, 0.60), 0.3)

	# --- recortes ---
	p["silhouette"] = BuildKit.unshaded(Color(0.015, 0.012, 0.02))
	p["void"] = BuildKit.unshaded(Color(0.006, 0.005, 0.008))

	# --- neones y luz emitida ---
	p["neon_magenta"] = BuildKit.emissive(Color(1.0, 0.15, 0.55), Color(1.0, 0.1, 0.55), 2.6)
	p["neon_cyan"] = BuildKit.emissive(Color(0.15, 0.85, 0.95), Color(0.1, 0.8, 0.95), 2.4)
	p["neon_violet"] = BuildKit.emissive(Color(0.6, 0.2, 1.0), Color(0.55, 0.15, 1.0), 2.2)
	p["neon_red_dim"] = BuildKit.emissive(Color(0.7, 0.08, 0.06), Color(0.9, 0.1, 0.08), 1.1)
	p["led_warm"] = BuildKit.emissive(Color(1.0, 0.7, 0.3), Color(1.0, 0.65, 0.25), 1.8)
	p["moon_glass"] = BuildKit.emissive(Color(0.5, 0.58, 0.7), Color(0.55, 0.65, 0.85), 0.8)
	p["fire_orange"] = BuildKit.emissive(Color(1.0, 0.3, 0.05), Color(1.0, 0.35, 0.08), 3.5)
	p["crt_phosphor"] = BuildKit.emissive(Color(0.1, 0.45, 0.2), Color(0.15, 0.75, 0.3), 1.4)
	p["exit_green"] = BuildKit.emissive(Color(0.15, 0.8, 0.3), Color(0.1, 0.9, 0.3), 1.8)
	p["bulb_pale"] = BuildKit.emissive(Color(0.9, 0.88, 0.92), Color(0.92, 0.9, 0.95), 2.2)
	p["laser_green"] = BuildKit.emissive(Color(0.2, 1.0, 0.3), Color(0.15, 1.0, 0.25), 3.0)

	# --- exclusivos del menú -------------------------------------------------
	# El exterior no existe en el mapa (la nave es un cascarón sellado), así que
	# el asfalto mojado, la vereda y el vidrio de los monitores son nuevos.
	p["asphalt_wet"] = BuildKit.matte(Color(0.035, 0.033, 0.04), 0.18, 0.15)
	p["sidewalk"] = BuildKit.matte(Color(0.11, 0.105, 0.10), 0.88)
	p["puddle"] = BuildKit.matte(Color(0.05, 0.06, 0.08), 0.04, 0.6)
	p["monitor_bezel"] = BuildKit.matte(Color(0.055, 0.055, 0.06), 0.75)
	p["screen_off"] = BuildKit.matte(Color(0.02, 0.025, 0.024), 0.25)
	p["night_sky"] = BuildKit.unshaded(Color(0.028, 0.026, 0.045))
	p["haze"] = BuildKit.glow_alpha(Color(0.55, 0.25, 0.75), 0.55, 0.055)
	p["light_shaft"] = BuildKit.glow_alpha(Color(1.0, 0.35, 0.75), 1.1, 0.11)

	_apply_surfaces(p)
	return p


## Texturas procedurales sobre la paleta, con las MISMAS recetas que usa el
## mapa (ver MapGenerator._apply_surfaces).
##
## Está acá por la regla de arriba: si el mapa tiene ladrillo texturado y el
## menú ladrillo de color plano, el menú y la partida parecen dos juegos
## distintos -- que es justamente lo que esta clase existe para evitar.
static func _apply_surfaces(p: Dictionary) -> void:
	var brick := ProcTextures.brick()
	var concrete := ProcTextures.concrete()
	var planks := ProcTextures.planks()
	var tiles := ProcTextures.tiles()
	var plate := ProcTextures.plate()
	var rust := ProcTextures.rust()
	var grate := ProcTextures.grate()
	var grunge := ProcTextures.grunge()

	ProcTextures.apply(p["brick"], brick, 2.4, 1.5, 0.6, Color(0.62, 0.6, 0.6))
	ProcTextures.apply(p["concrete_wall"], concrete, 3.2, 0.9, 0.5, Color(0.22, 0.205, 0.19))
	ProcTextures.apply(p["concrete_floor"], grunge, 3.4, 0.55, 0.5, Color(0.155, 0.146, 0.138))
	ProcTextures.apply(p["tile_floor"], tiles, 2.0, 1.1, 0.7, Color(0.66, 0.68, 0.66))
	ProcTextures.apply(p["tile_wall"], tiles, 1.6, 1.1, 0.7, Color(0.78, 0.82, 0.80))
	ProcTextures.apply(p["wood_floor"], planks, 2.6, 1.0, 0.55, Color(1.25, 1.18, 1.08))
	ProcTextures.apply(p["aged_wood"], planks, 1.4, 0.9, 0.5, Color(1.35, 1.28, 1.18))
	ProcTextures.apply(p["rust_metal"], rust, 1.8, 1.2, 0.7, Color(0.75, 0.72, 0.70))
	ProcTextures.apply(p["pipe_industrial"], rust, 1.2, 0.8, 0.5, Color(1.05, 0.95, 0.55))
	ProcTextures.apply(p["grate"], grate, 1.2, 1.4, 0.4, Color(0.85, 0.87, 0.90))
	ProcTextures.apply(p["dark_steel"], plate, 1.6, 0.7, 0.45, Color(0.85, 0.87, 0.92))
	ProcTextures.apply(p["hazard_mark"], plate, 1.0, 0.6, 0.4, Color(1.10, 0.95, 0.28))
	# La vereda del menú no existe en el mapa, pero es hormigón igual.
	ProcTextures.apply(p["sidewalk"], concrete, 2.6, 0.8, 0.5, Color(0.18, 0.172, 0.164))

	for key in ["rubble", "paint_worn", "leather_brown", "fabric_red", "mattress", "rubber_black"]:
		ProcTextures.apply(p[key], grunge, 2.2, 0.4, 0.5)


## Fósforo de monitor en un color arbitrario. Cada monitor del muro de cámaras
## necesita el suyo porque los pulsamos por separado (parpadeo desfasado); con
## un material compartido titilarían los nueve al unísono y se leería como un
## error de render, no como una sala de cámaras.
static func screen(tint: Color, energy: float) -> StandardMaterial3D:
	return BuildKit.emissive(tint * 0.35, tint, energy)
