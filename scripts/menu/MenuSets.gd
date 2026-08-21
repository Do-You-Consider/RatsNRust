class_name MenuSets
extends RefCounted
## Escenografía del menú. Cuatro sets independientes construidos por código
## con las mismas primitivas y la misma paleta que la nave del juego.
##
## POR QUÉ NO REUSAMOS MapGenerator: genera 66x66 m con las nueve zonas
## completas y cientos de nodos con colisión. El menú necesita cuatro rincones
## que la cámara mira desde UN solo ángulo, sin física. Construir el mapa
## entero para mostrar un balcón costaría un segundo largo de carga y ~20x más
## nodos de los que se ven.
##
## Y por qué el EXTERIOR es nuevo de cero: la nave del juego es un cascarón
## sellado -- el portón está tapiado y no hay calle. Nunca existió un afuera.
##
## Cada builder devuelve un Node3D listo para colgar del árbol, con su propio
## WorldEnvironment y con las posiciones de cámara y de actores guardadas en
## metadatos:
##   root.get_meta("shots")  -> { nombre: {xf: Transform3D, fov: float} }
##   root.get_meta("actor")  -> Transform3D del personaje principal
##   root.get_meta("slots")  -> Array[Transform3D] (un puesto por jugador)
##   root.get_meta("path")   -> Array[Vector3] recorrido a pie de la transición

## Altura del piso de la pista vista desde el balcón. Una sola planta: con la
## caída de tres pisos que tiene la nave del juego, para ver la pista hay que
## picar tanto la cámara que la baranda cruza el cuadro en diagonal y el
## público queda a 20 m, del tamaño de una hormiga.
const ATRIUM_DROP := -4.2


static func _shot(pos: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {
		"xf": Transform3D(Basis(), pos).looking_at(target, Vector3.UP),
		"fov": fov,
	}


static func _new_set(set_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = set_name
	return root


static func _env(root: Node3D, bg: Color, ambient: Color, ambient_energy: float,
		fog: Color, fog_density: float, glow: float) -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.fog_enabled = fog_density > 0.0
	e.fog_light_color = fog
	e.fog_light_energy = 1.0
	e.fog_density = fog_density
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = glow > 0.0
	e.glow_intensity = glow
	e.glow_bloom = 0.1

	var we := WorldEnvironment.new()
	we.name = "SetEnvironment"
	we.environment = e
	root.add_child(we)


static func _animator(root: Node3D) -> SetAnimator:
	var a := SetAnimator.new()
	a.name = "Animator"
	root.add_child(a)
	return a


# =============================================================================
# 1. BALCÓN -- pantalla de título. El Atrapador apoyado en la baranda de un
#    nivel alto, mirando la pista de abajo. La puerta por la que se va a la
#    sala de cámaras está a la IZQUIERDA del encuadre.
# =============================================================================

static func build_balcony() -> Node3D:
	var root := _new_set("SetBalcony")
	var pal := Palette.create()
	var anim := _animator(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260820

	_env(root, Color(0.012, 0.008, 0.018), Color(0.30, 0.10, 0.36), 0.30,
		Color(0.24, 0.06, 0.30), 0.022, 0.55)

	_balcony_structure(root, pal, rng)
	_balcony_atrium(root, pal, anim, rng)

	root.set_meta("shots", {
		# Encuadre de título: el Atrapador entra por la derecha del cuadro y la
		# pista ocupa el resto. Cámara alta y apenas picada.
		# Casi sin paneo: el Atrapador visto desde atrás por el hombro y la pista
		# de frente. Encuadres con mucho giro hacían leer la baranda como una
		# diagonal y el cuadro parecía una cámara torcida.
		"main": _shot(Vector3(2.30, 2.05, 2.95), Vector3(1.40, 0.15, -6.60), 64.0),
		# Al arrancar la caminata la cámara se abre para que se vea la puerta.
		"door": _shot(Vector3(1.20, 1.85, 3.30), Vector3(-5.10, 1.30, 1.20), 66.0),
		# Último tramo: entramos con él.
		"through": _shot(Vector3(-2.10, 1.80, 2.90), Vector3(-6.70, 1.35, 1.40), 68.0),
	})
	root.set_meta("actor", Transform3D(Basis(), Vector3(0.55, 0.0, -0.45)))
	root.set_meta("path", [
		Vector3(0.55, 0.0, -0.45),
		Vector3(-1.60, 0.0, 0.65),
		Vector3(-4.30, 0.0, 1.35),
		Vector3(-5.95, 0.0, 1.40),
	])
	root.set_meta("door", Vector3(-6.55, 0.0, 1.40))
	return root


static func _balcony_structure(root: Node3D, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	# Losa del balcón. El borde delantero (z = -1.15) es donde va la baranda;
	# más allá está el vacío del atrio.
	BuildKit.box(root, Vector3(0, -0.12, 2.0), Vector3(13.6, 0.24, 6.4), pal["concrete_floor"])
	BuildKit.box(root, Vector3(0, -0.30, -1.05), Vector3(13.6, 0.30, 0.5), pal["rust_metal"])

	# --- muro izquierdo con el vano de la puerta ---
	var wall_x := -6.65
	BuildKit.box(root, Vector3(wall_x, 2.1, -0.25), Vector3(0.3, 4.2, 1.8), pal["concrete_wall"])
	BuildKit.box(root, Vector3(wall_x, 2.1, 3.60), Vector3(0.3, 4.2, 3.0), pal["concrete_wall"])
	BuildKit.box(root, Vector3(wall_x, 3.25, 1.40), Vector3(0.3, 1.9, 1.4), pal["concrete_wall"])
	# Marco y hoja. La hoja cuelga de un pivote en la jamba: MenuFlow la abre
	# rotando el pivote, no la hoja (rotar la hoja la haría girar sobre su
	# centro, como una puerta giratoria).
	BuildKit.box(root, Vector3(wall_x - 0.02, 1.15, 0.68), Vector3(0.34, 2.36, 0.12), pal["rust_metal"])
	BuildKit.box(root, Vector3(wall_x - 0.02, 1.15, 2.12), Vector3(0.34, 2.36, 0.12), pal["rust_metal"])
	BuildKit.box(root, Vector3(wall_x - 0.02, 2.33, 1.40), Vector3(0.34, 0.12, 1.56), pal["rust_metal"])

	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(wall_x, 0.0, 0.74)
	root.add_child(hinge)
	BuildKit.box(hinge, Vector3(0.02, 1.12, 0.63), Vector3(0.09, 2.24, 1.26), pal["dark_steel"])
	BuildKit.box(hinge, Vector3(-0.05, 1.05, 1.15), Vector3(0.06, 0.06, 0.22), pal["rust_metal"])
	# Rendija de luz verde de la sala de cámaras filtrándose por el marco:
	# es lo que hace que la puerta se lea como "hay algo del otro lado".
	BuildKit.box(root, Vector3(wall_x - 0.18, 1.15, 1.40), Vector3(0.02, 2.2, 1.3), pal["crt_phosphor"])
	BuildKit.omni(root, Vector3(wall_x + 0.5, 1.6, 1.40), Color(0.2, 0.85, 0.4), 0.5, 3.4)

	# --- muro del fondo y techo ---
	BuildKit.box(root, Vector3(0, 2.1, 5.25), Vector3(13.6, 4.2, 0.3), pal["brick"])
	BuildKit.box(root, Vector3(6.65, 2.1, 3.2), Vector3(0.3, 4.2, 4.4), pal["brick"])
	BuildKit.box(root, Vector3(0, 4.32, 2.0), Vector3(13.6, 0.24, 6.6), pal["concrete_wall"])

	# Caños y cables cruzando el techo
	for i in 3:
		var z := 0.4 + i * 1.7
		BuildKit.cylinder(root, Vector3(0, 4.05, z), 0.09, 13.0, pal["pipe_industrial"], false,
			Vector3(0, 0, PI * 0.5))
	BuildKit.beam(root, Vector3(-6.2, 3.95, 4.9), Vector3(6.2, 3.72, 4.6), 0.025, pal["dark_steel"])

	# --- baranda del borde (dos largueros + parantes), igual que en el mapa ---
	for rail_h in [0.58, 1.06]:
		BuildKit.box(root, Vector3(0, rail_h, -1.15), Vector3(13.4, 0.07, 0.07), pal["rust_metal"])
	for p in 9:
		var t: float = lerpf(-6.4, 6.4, float(p) / 8.0)
		BuildKit.box(root, Vector3(t, 0.53, -1.15), Vector3(0.07, 1.06, 0.07), pal["rust_metal"])
	# Rodapié: sin esto se ve el vacío por debajo del pasamanos y el piso
	# parece flotar.
	BuildKit.box(root, Vector3(0, 0.13, -1.18), Vector3(13.4, 0.26, 0.05), pal["grate"])

	# --- relleno del balcón: no puede ser una losa pelada ---
	for i in 4:
		var x := -5.6 + i * 3.4 + rng.randf_range(-0.4, 0.4)
		var s := rng.randf_range(0.7, 1.05)
		BuildKit.box(root, Vector3(x, s * 0.5, 4.5), Vector3(s, s, s), pal["aged_wood"], false,
			Vector3(0, rng.randf_range(-0.5, 0.5), 0))
	BuildKit.cylinder(root, Vector3(4.9, 0.45, 4.6), 0.36, 0.9, pal["rust_metal"])
	BuildKit.cylinder(root, Vector3(5.7, 0.45, 4.2), 0.36, 0.9, pal["rust_metal"])
	BuildKit.box(root, Vector3(-3.2, 0.6, 4.8), Vector3(1.2, 1.2, 0.14), pal["aged_wood"], false,
		Vector3(0, 0.2, 0.28))
	# Vasos y latas tiradas contra el rodapié
	for i in 7:
		var x2 := rng.randf_range(-6.0, 6.0)
		BuildKit.cylinder(root, Vector3(x2, 0.06, -0.85 + rng.randf_range(-0.15, 0.15)),
			0.045, 0.12, pal["shrinkwrap"], false,
			Vector3(PI * 0.5, rng.randf_range(0, PI), 0))

	# Luz de servicio del balcón: cálida, tenue y por detrás del personaje, para
	# que quede recortado contra el resplandor de la pista.
	BuildKit.omni(root, Vector3(1.8, 3.6, 3.6), Color(1.0, 0.62, 0.28), 1.5, 8.5)
	# Rebote de la pista sobre el piso del balcon: sin esto la mitad inferior
	# del cuadro de titulo era un rectangulo negro muerto.
	BuildKit.omni(root, Vector3(-1.2, 0.35, -0.90), Color(0.95, 0.25, 0.70), 1.8, 9.0)
	BuildKit.omni(root, Vector3(3.6, 0.30, -0.90), Color(0.25, 0.65, 0.95), 1.1, 7.0)
	BuildKit.omni(root, Vector3(-4.6, 3.4, 3.9), Color(0.95, 0.45, 0.20), 0.9, 6.5)
	BuildKit.box(root, Vector3(1.8, 4.12, 3.6), Vector3(0.5, 0.12, 0.5), pal["led_warm"])


## El vacío del atrio: pista de baile 9 metros más abajo, con público, cabina
## de DJ, cabezales barriendo y humo. Es el fondo de la pantalla de título.
static func _balcony_atrium(root: Node3D, pal: Dictionary, anim: SetAnimator,
		rng: RandomNumberGenerator) -> void:
	var floor_y := ATRIUM_DROP
	var cx := 1.6
	var cz := -9.0

	# Muros del pozo y piso base
	BuildKit.box(root, Vector3(cx, floor_y - 0.2, cz), Vector3(30.0, 0.4, 30.0), pal["concrete_floor"])
	BuildKit.box(root, Vector3(cx, floor_y * 0.5, cz - 15.2), Vector3(30.0, 22.0, 0.4), pal["brick"])
	BuildKit.box(root, Vector3(cx - 15.2, floor_y * 0.5, cz), Vector3(0.4, 22.0, 30.0), pal["brick"])
	BuildKit.box(root, Vector3(cx + 15.2, floor_y * 0.5, cz), Vector3(0.4, 22.0, 30.0), pal["brick"])

	# --- piso LED: 4 materiales compartidos en cadena de 4 tiempos ---
	var chase: Array[StandardMaterial3D] = [
		Palette.screen(Color(1.0, 0.12, 0.55), 1.6),
		Palette.screen(Color(0.15, 0.85, 0.95), 1.6),
		Palette.screen(Color(0.60, 0.20, 1.00), 1.6),
		Palette.screen(Color(1.0, 0.45, 0.10), 1.6),
	]
	for i in chase.size():
		anim.pulse(chase[i], 0.9, 5.2, 3.4, i * PI * 0.5)
	var tile := 2.3
	for gx in 9:
		for gz in 9:
			var px := cx + (gx - 4) * tile
			var pz := cz + (gz - 4) * tile
			BuildKit.box(root, Vector3(px, floor_y + 0.02, pz), Vector3(tile * 0.94, 0.06, tile * 0.94),
				chase[(gx + gz) % 4])

	# --- público ---
	# 44 recortes negros que saltan desfasados. Contra el piso LED se leen como
	# una multitud a contraluz; modelarlos sería tirar polígonos a la basura.
	for i in 58:
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(1.4, 9.6)
		var px := cx + cos(ang) * rad
		var pz := cz + sin(ang) * rad
		var h := rng.randf_range(1.55, 1.85)

		var person := Node3D.new()
		person.position = Vector3(px, floor_y, pz)
		person.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(person)
		BuildKit.box(person, Vector3(0, h * 0.34, 0), Vector3(0.34, h * 0.68, 0.22), pal["silhouette"])
		BuildKit.box(person, Vector3(0, h * 0.78, 0), Vector3(0.42, h * 0.28, 0.26), pal["silhouette"])
		BuildKit.sphere(person, Vector3(0, h * 0.98, 0), 0.115, pal["silhouette"])
		# Brazos arriba en la mitad de la gente
		if rng.randf() < 0.45:
			for sx in [-1.0, 1.0]:
				BuildKit.box(person, Vector3(sx * 0.26, h * 1.0, 0), Vector3(0.09, 0.5, 0.09),
					pal["silhouette"], false, Vector3(0, 0, sx * 0.35))

		anim.bob(person, rng.randf_range(0.11, 0.24), rng.randf_range(4.4, 6.2), rng.randf_range(0.0, TAU))
		anim.sway(person, rng.randf_range(6.0, 16.0), rng.randf_range(1.2, 2.4), rng.randf_range(0.0, TAU))

	# --- cabina de DJ al fondo ---
	var dj := Vector3(cx, floor_y, cz - 11.0)
	BuildKit.box(root, dj + Vector3(0, 0.55, 0), Vector3(7.0, 1.1, 2.4), pal["dark_steel"])
	BuildKit.box(root, dj + Vector3(0, 1.16, -0.2), Vector3(3.2, 0.12, 1.2), pal["grate"])
	BuildKit.box(root, dj + Vector3(0, 1.45, 0.9), Vector3(4.6, 0.5, 0.12), pal["neon_magenta"])
	for sx in [-4.6, 4.6]:
		for sy in 3:
			BuildKit.box(root, dj + Vector3(sx, 0.9 + sy * 1.7, 0.2), Vector3(1.6, 1.6, 1.4),
				pal["rubber_black"])
			BuildKit.cylinder(root, dj + Vector3(sx, 0.9 + sy * 1.7, -0.52), 0.52, 0.1,
				pal["dark_steel"], false, Vector3(PI * 0.5, 0, 0))
	# El DJ
	var dj_fig := Node3D.new()
	dj_fig.position = dj + Vector3(0, 1.1, 0.55)
	root.add_child(dj_fig)
	BuildKit.box(dj_fig, Vector3(0, 0.42, 0), Vector3(0.5, 0.84, 0.28), pal["silhouette"])
	BuildKit.sphere(dj_fig, Vector3(0, 0.98, 0), 0.14, pal["silhouette"])
	anim.bob(dj_fig, 0.09, 5.0, 0.0)

	# Pantalla gigante detrás del DJ
	var wall_screen := Palette.screen(Color(0.55, 0.15, 0.95), 1.2)
	anim.pulse(wall_screen, 0.5, 2.2, 1.9, 0.7)
	BuildKit.box(root, dj + Vector3(0, 5.2, -1.6), Vector3(9.0, 5.0, 0.2), wall_screen)

	# --- cabezales barriendo la pista ---
	var head_colors := [Color(1.0, 0.12, 0.55), Color(0.15, 0.85, 0.95), Color(0.6, 0.2, 1.0)]
	for i in 6:
		var hx := cx + (i - 2.5) * 3.4
		var pivot := Node3D.new()
		pivot.position = Vector3(hx, floor_y + 8.6, cz - 3.0 + (i % 2) * 5.0)
		root.add_child(pivot)
		var col: Color = head_colors[i % head_colors.size()]
		var shaft := BuildKit.glow_alpha(col, 1.3, 0.10)
		BuildKit.cylinder(pivot, Vector3(0, -4.4, 0), 0.12, 8.8, shaft)
		BuildKit.cylinder(pivot, Vector3(0, -8.7, 0), 0.95, 0.3, shaft)
		var l := BuildKit.spot(pivot, Vector3.ZERO, Vector3(0, -6.0, 0), col, 3.2, 14.0, 22.0)
		anim.sweep(pivot, Vector3(0, 0, 1), 0.0, 26.0, 0.55 + i * 0.07, i * 1.1)
		anim.blink(l, 1.4, 3.6, 2.2 + i * 0.3, i * 0.9)

	# --- láseres verdes cruzando en el aire ---
	for i in 5:
		var fan := Node3D.new()
		fan.position = Vector3(cx - 7.0 + i * 3.5, floor_y + 7.4, cz + 6.0)
		root.add_child(fan)
		BuildKit.beam(fan, Vector3.ZERO, Vector3(rng.randf_range(-6, 6), -5.5, -13.0), 0.018,
			pal["laser_green"])
		anim.sweep(fan, Vector3(0, 1, 0), 0.0, 12.0, 0.9 + i * 0.13, i * 0.8)

	# --- humo: planos translúcidos que dan volumen a los haces ---
	for i in 4:
		BuildKit.quad(root, Vector3(cx, floor_y + 2.0 + i * 2.2, cz + 4.0 - i * 3.0),
			Vector2(28.0, 7.0), pal["haze"])

	# Rebote de luz de la pista hacia arriba: es lo que ilumina al Atrapador
	# desde abajo y lo recorta contra el balcón.
	var up1 := BuildKit.omni(root, Vector3(cx, floor_y + 3.0, cz + 3.0), Color(0.90, 0.20, 0.78), 5.5, 26.0)
	var up2 := BuildKit.omni(root, Vector3(cx - 5.0, floor_y + 2.4, cz - 4.0), Color(0.18, 0.72, 0.95), 4.5, 24.0)
	var up3 := BuildKit.omni(root, Vector3(cx + 5.0, floor_y + 2.4, cz - 1.0), Color(0.62, 0.22, 1.0), 3.6, 22.0)
	anim.blink(up1, 3.0, 6.5, 1.7, 0.0)
	anim.blink(up2, 2.2, 5.0, 2.3, 1.4)
	anim.blink(up3, 1.8, 4.2, 1.9, 2.7)


# =============================================================================
# 2. SALA DE CÁMARAS -- pantalla de crear/unirse. Muro de monitores, consola,
#    y el Atrapador mirando las cámaras del boliche.
# =============================================================================

static func build_control_room() -> Node3D:
	var root := _new_set("SetControlRoom")
	var pal := Palette.create()
	var anim := _animator(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 771144

	_env(root, Color(0.010, 0.012, 0.011), Color(0.16, 0.26, 0.22), 0.30,
		Color(0.10, 0.16, 0.14), 0.030, 0.42)

	var h := 3.5
	# --- caja de la sala ---
	BuildKit.box(root, Vector3(0, -0.12, 0), Vector3(14.4, 0.24, 9.6), pal["concrete_floor"])
	BuildKit.box(root, Vector3(0, h + 0.12, 0), Vector3(14.4, 0.24, 9.6), pal["concrete_wall"])
	# Zócalo de azulejo verde institucional + hormigón arriba (el mismo corte
	# que tienen los baños del mapa).
	for wall in [
		{"pos": Vector3(0, 0, -4.8), "size": Vector3(14.4, 0, 0.3)},
		{"pos": Vector3(0, 0, 4.8), "size": Vector3(14.4, 0, 0.3)},
	]:
		BuildKit.box(root, wall.pos + Vector3(0, 0.75, 0), Vector3(wall.size.x, 1.5, wall.size.z), pal["tile_wall"])
		BuildKit.box(root, wall.pos + Vector3(0, 2.5, 0), Vector3(wall.size.x, 2.0, wall.size.z), pal["concrete_wall"])
	for sx in [-7.2, 7.2]:
		BuildKit.box(root, Vector3(sx, 0.75, 0), Vector3(0.3, 1.5, 9.6), pal["tile_wall"])
		BuildKit.box(root, Vector3(sx, 2.5, 0), Vector3(0.3, 2.0, 9.6), pal["concrete_wall"])

	_control_monitor_wall(root, pal, anim, rng)
	_control_console(root, pal, anim, rng)
	_control_dressing(root, pal, anim, rng)

	root.set_meta("shots", {
		# Encuadre principal: monitores a la izquierda, Atrapador a la derecha.
		"main": _shot(Vector3(2.35, 1.72, 1.10), Vector3(-0.35, 2.05, -4.40), 60.0),
		# Justo después de cruzar la puerta, todavía pegados a ella.
		"entry": _shot(Vector3(5.20, 1.70, 3.40), Vector3(-0.60, 2.00, -4.10), 72.0),
	})
	root.set_meta("actor", Transform3D(Basis(), Vector3(2.45, 0.0, -3.10)).rotated_local(Vector3.UP, 1.05))
	return root


static func _control_monitor_wall(root: Node3D, pal: Dictionary, anim: SetAnimator,
		rng: RandomNumberGenerator) -> void:
	var wall_z := -4.6
	var cols := 4
	var rows := 3
	var mw := 1.16
	var mh := 0.88
	var ox := -1.9
	var oy := 1.55

	# Bastidor de chapa donde están montados
	BuildKit.box(root, Vector3(ox, oy + mh, wall_z + 0.12), Vector3(cols * mw + 0.5, rows * mh + 0.6, 0.14),
		pal["dark_steel"])

	for r in rows:
		for c in cols:
			var px: float = ox + (c - (cols - 1) * 0.5) * mw
			var py: float = oy + r * mh
			var pz := wall_z + 0.40
			# Carcasa + bisel. OJO con el orden en Z: la camara mira desde +Z,
			# asi que la pantalla va DELANTE del bisel (z mayor). Al reves la
			# tapaba la propia carcasa y el muro entero salia negro.
			BuildKit.box(root, Vector3(px, py, pz + 0.10), Vector3(mw - 0.06, mh - 0.06, 0.30),
				pal["monitor_bezel"])
			# Cada pantalla con su propio material: el parpadeo desfasado es lo
			# que hace que se lea como nueve cámaras y no como un solo panel.
			var tintv := 0.55 + rng.randf() * 0.35
			var scr := Palette.screen(Color(0.25 * tintv, 0.85 * tintv, 0.45 * tintv), 1.1)
			BuildKit.box(root, Vector3(px, py, pz + 0.27), Vector3(mw - 0.26, mh - 0.26, 0.03), scr)
			anim.pulse(scr, 1.3, 2.9, rng.randf_range(2.2, 7.5), rng.randf_range(0.0, TAU))

			# "Contenido" de la cámara: dos o tres barras oscuras que sugieren
			# una silueta y un piso. A esta resolución cada monitor mide ~30 px:
			# feeds reales serían nueve renders del mundo para nada.
			var inner := Node3D.new()
			inner.position = Vector3(px, py, pz + 0.30)
			root.add_child(inner)
			BuildKit.box(inner, Vector3(0, -mh * 0.24, 0), Vector3(mw - 0.30, 0.05, 0.01), pal["silhouette"])
			var fx := rng.randf_range(-0.25, 0.25)
			BuildKit.box(inner, Vector3(fx, -mh * 0.05, 0), Vector3(0.09, 0.26, 0.01), pal["silhouette"])
			BuildKit.sphere(inner, Vector3(fx, mh * 0.13, 0), 0.035, pal["silhouette"])
			anim.sway(inner, 3.0, rng.randf_range(0.5, 1.4), rng.randf_range(0.0, TAU))
			# Barrido de scanline: una franja clara bajando muy despacio.
			var band := BuildKit.box(root, Vector3(px, py, pz + 0.31),
				Vector3(mw - 0.28, 0.05, 0.01), Palette.screen(Color(0.6, 1.0, 0.7), 0.9)) as Node3D
			anim.bob(band, mh - 0.30, rng.randf_range(0.6, 1.1), rng.randf_range(0.0, TAU))

			# Etiqueta de la cámara: una rayita naranja bajo cada monitor
			BuildKit.box(root, Vector3(px - mw * 0.28, py - mh * 0.46, pz + 0.28),
				Vector3(0.22, 0.03, 0.02), pal["led_warm"])

	# Resplandor verde del muro sobre la sala. Es la única luz fuerte del set.
	BuildKit.omni(root, Vector3(ox, oy + 1.0, wall_z + 1.6), Color(0.25, 0.95, 0.45), 3.6, 11.0)
	BuildKit.omni(root, Vector3(ox + 2.2, oy - 0.4, wall_z + 2.6), Color(0.2, 0.8, 0.5), 1.1, 7.0)

	# Cartel "CAMARAS" sobre el bastidor
	BuildKit.box(root, Vector3(ox, oy + 3.05, wall_z + 0.46), Vector3(2.4, 0.30, 0.08), pal["hazard_mark"])


static func _control_console(root: Node3D, pal: Dictionary, anim: SetAnimator,
		rng: RandomNumberGenerator) -> void:
	var z := -3.35
	# Mesada + frente de rack
	BuildKit.box(root, Vector3(-1.9, 0.82, z), Vector3(8.2, 0.10, 1.30), pal["dark_steel"])
	BuildKit.box(root, Vector3(-1.9, 0.40, z + 0.55), Vector3(8.2, 0.80, 0.14), pal["paint_worn"])
	for i in 5:
		BuildKit.box(root, Vector3(-5.4 + i * 1.75, 0.40, z - 0.55), Vector3(0.12, 0.80, 0.12), pal["dark_steel"])

	# Monitores chicos de mesa
	for i in 3:
		var px := -4.4 + i * 2.1
		BuildKit.box(root, Vector3(px, 1.12, z - 0.2), Vector3(0.72, 0.52, 0.22), pal["monitor_bezel"], false,
			Vector3(-0.18, 0, 0))
		var scr := Palette.screen(Color(0.3, 0.9, 0.5), 1.0)
		BuildKit.box(root, Vector3(px, 1.13, z - 0.32), Vector3(0.58, 0.38, 0.02), scr, false,
			Vector3(-0.18, 0, 0))
		anim.pulse(scr, 0.5, 1.4, rng.randf_range(3.0, 6.0), rng.randf_range(0.0, TAU))

	# Teclados y botoneras
	for i in 3:
		BuildKit.box(root, Vector3(-4.4 + i * 2.1, 0.89, z + 0.42), Vector3(0.62, 0.05, 0.24),
			pal["rubber_black"], false, Vector3(0.10, 0, 0))
	for i in 14:
		BuildKit.box(root, Vector3(-5.6 + i * 0.52, 0.89, z - 0.48), Vector3(0.06, 0.05, 0.06),
			pal["neon_red_dim"] if i % 3 == 0 else pal["led_warm"])

	# Silla vacía girada: alguien estuvo acá recién
	BuildKit.cylinder(root, Vector3(-3.2, 0.24, z + 1.5), 0.30, 0.08, pal["dark_steel"])
	BuildKit.cylinder(root, Vector3(-3.2, 0.28, z + 1.5), 0.05, 0.50, pal["dark_steel"])
	BuildKit.box(root, Vector3(-3.2, 0.54, z + 1.5), Vector3(0.52, 0.08, 0.48), pal["rubber_black"])
	BuildKit.box(root, Vector3(-3.2, 0.86, z + 1.72), Vector3(0.50, 0.60, 0.08), pal["rubber_black"], false,
		Vector3(-0.22, 0.7, 0))


static func _control_dressing(root: Node3D, pal: Dictionary, anim: SetAnimator,
		rng: RandomNumberGenerator) -> void:
	# --- puerta por la que entramos (derecha del fondo) ---
	BuildKit.box(root, Vector3(6.0, 1.15, -4.55), Vector3(1.36, 2.36, 0.16), pal["rust_metal"])
	BuildKit.box(root, Vector3(6.0, 1.12, -4.44), Vector3(1.16, 2.24, 0.08), pal["dark_steel"])
	BuildKit.box(root, Vector3(6.42, 1.05, -4.38), Vector3(0.20, 0.06, 0.06), pal["rust_metal"])
	# --- segunda puerta al fondo izquierdo, cerrada con barra ---
	BuildKit.box(root, Vector3(-6.1, 1.15, 4.55), Vector3(1.36, 2.36, 0.16), pal["rust_metal"])
	BuildKit.box(root, Vector3(-6.1, 1.12, 4.44), Vector3(1.16, 2.24, 0.08), pal["dark_steel"])
	BuildKit.box(root, Vector3(-6.1, 1.30, 4.36), Vector3(1.40, 0.10, 0.06), pal["hazard_mark"], false,
		Vector3(0, 0, 0.12))
	BuildKit.box(root, Vector3(-6.1, 2.55, 4.40), Vector3(0.9, 0.26, 0.08), pal["exit_green"])
	BuildKit.omni(root, Vector3(-6.1, 2.4, 4.0), Color(0.15, 0.9, 0.35), 0.6, 4.0)

	# --- caños y tubo fluorescente en el techo ---
	for i in 3:
		BuildKit.cylinder(root, Vector3(0, 3.24, -2.6 + i * 2.6), 0.10, 14.0, pal["pipe_industrial"], false,
			Vector3(0, 0, PI * 0.5))
	# El tubo va CORRIDO al fondo: encima de la camara reventaba el borde
	# superior del cuadro y dejaba los monitores en penumbra por contraste.
	BuildKit.box(root, Vector3(0.6, 3.30, -2.2), Vector3(2.4, 0.10, 0.22),
		BuildKit.emissive(Color(0.55, 0.58, 0.62), Color(0.75, 0.82, 0.9), 0.55))
	var tube := BuildKit.omni(root, Vector3(0.6, 3.10, -2.2), Color(0.75, 0.85, 0.95), 0.9, 8.0)
	# Tubo que hace mal contacto: parpadeo rápido e irregular.
	anim.blink(tube, 0.9, 1.8, 11.0, 0.0)

	# --- rack de equipos, archivadores, clutter ---
	BuildKit.box(root, Vector3(-6.4, 1.0, -2.0), Vector3(1.2, 2.0, 0.7), pal["dark_steel"])
	for i in 8:
		BuildKit.box(root, Vector3(-5.83, 0.35 + i * 0.22, -2.0), Vector3(0.06, 0.06, 0.06),
			pal["neon_red_dim"] if i % 4 == 0 else pal["crt_phosphor"])
	BuildKit.box(root, Vector3(6.3, 0.85, 1.2), Vector3(1.0, 1.7, 0.6), pal["paint_worn"])
	BuildKit.box(root, Vector3(6.3, 1.75, 1.2), Vector3(0.9, 0.10, 0.55), pal["rubble"])
	for i in 5:
		var s := rng.randf_range(0.3, 0.6)
		BuildKit.box(root, Vector3(rng.randf_range(-6.5, 6.5), s * 0.5, rng.randf_range(2.0, 4.2)),
			Vector3(s, s, s * 0.8), pal["aged_wood"], false, Vector3(0, rng.randf_range(0, PI), 0))
	# Mancha de humedad y pintura saltada en la pared del fondo
	BuildKit.box(root, Vector3(-3.4, 2.7, 4.62), Vector3(2.6, 1.4, 0.03), pal["rubble"])


# =============================================================================
# 3. EXTERIOR -- sala de espera. Los jugadores esperan en el callejón, frente a
#    la entrada. La cámara es un CCTV montado alto: el Atrapador los está
#    mirando desde la sala de cámaras.
#
#    Todo esto es geometría nueva: la nave del juego nunca tuvo un afuera.
# =============================================================================

static func build_exterior() -> Node3D:
	var root := _new_set("SetExterior")
	var pal := Palette.create()
	var anim := _animator(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150

	_env(root, Color(0.020, 0.019, 0.032), Color(0.18, 0.19, 0.32), 0.52,
		Color(0.13, 0.12, 0.22), 0.016, 0.60)

	_exterior_street(root, pal, rng)
	_exterior_facade(root, pal, anim)
	_exterior_props(root, pal, anim, rng)

	root.set_meta("shots", {
		# CCTV en lo alto de la pared derecha, picado y gran angular.
		"cam": _shot(Vector3(2.20, 2.90, -9.00), Vector3(-0.30, 1.20, -15.80), 56.0),
		# Al arrancar la partida la cámara baja y se mete detrás del grupo.
		"launch": _shot(Vector3(1.40, 2.20, -11.00), Vector3(0.00, 1.40, -22.00), 62.0),
	})
	root.set_meta("slots", _exterior_slots())
	root.set_meta("door", Vector3(0.0, 0.0, -22.6))
	return root


## Ocho puestos frente a la entrada, en dos filas sueltas. Van ordenados de
## adentro hacia afuera: el jugador 1 (el host) queda más cerca de la puerta.
static func _exterior_slots() -> Array:
	var out: Array = []
	# La fila arranca a ~7 m de la camara. Mas lejos (que es donde estaba) cada
	# jugador medía 30 px de alto y no se distinguia de un poste.
	# El abanico se cierra hacia adelante: los puestos de atrás están más cerca
	# de la cámara, así que separarlos tanto como los del fondo los mandaba
	# fuera de cuadro (el jugador 8 caía justo sobre el borde derecho).
	var spots: Array[Vector3] = [
		Vector3(-0.9, 0, -16.1), Vector3(1.4, 0, -15.7),
		Vector3(-2.6, 0, -14.9), Vector3(2.5, 0, -14.7),
		Vector3(-1.5, 0, -13.5), Vector3(0.8, 0, -13.2),
		Vector3(-3.0, 0, -12.7), Vector3(2.9, 0, -12.9),
	]
	for i in spots.size():
		var xf := Transform3D(Basis(), spots[i])
		# Todos miran a la puerta, con una desviación distinta cada uno para
		# que no parezcan formados.
		var to_door := (Vector3(0, 0, -22.6) - spots[i]).normalized()
		var yaw := atan2(-to_door.x, -to_door.z) + (0.22 if i % 2 == 0 else -0.16)
		out.append(xf.rotated_local(Vector3.UP, yaw))
	return out


static func _exterior_street(root: Node3D, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	# Asfalto mojado. El roughness bajísimo del material es lo que hace que los
	# neones de la entrada se estiren sobre el piso.
	BuildKit.box(root, Vector3(0, -0.10, -8.0), Vector3(19.0, 0.20, 34.0), pal["asphalt_wet"])
	# Veredas contra las dos paredes
	for sx in [-7.6, 7.6]:
		BuildKit.box(root, Vector3(sx, 0.07, -8.0), Vector3(2.2, 0.34, 34.0), pal["sidewalk"])
		BuildKit.box(root, Vector3(sx + (0.95 if sx < 0 else -0.95), 0.09, -8.0),
			Vector3(0.3, 0.38, 34.0), pal["concrete_wall"])

	# Paredes del callejón
	for sx2 in [-9.0, 9.0]:
		BuildKit.box(root, Vector3(sx2, 5.0, -8.0), Vector3(0.6, 10.0, 34.0), pal["brick"])
		BuildKit.box(root, Vector3(sx2 + (0.32 if sx2 < 0 else -0.32), 1.1, -8.0),
			Vector3(0.08, 2.2, 34.0), pal["concrete_wall"])

	# Charcos: planos horizontales casi espejo
	for i in 9:
		var px := rng.randf_range(-6.0, 6.0)
		var pz := rng.randf_range(-21.0, 4.0)
		BuildKit.quad(root, Vector3(px, 0.012, pz), Vector2(rng.randf_range(1.4, 3.6), rng.randf_range(1.0, 2.6)),
			pal["puddle"], Vector3(-PI * 0.5, rng.randf_range(0, PI), 0))

	# Boca del callejón hacia la calle: resplandor frío que da profundidad y
	# evita que el fondo sea un agujero negro.
	BuildKit.box(root, Vector3(0, 5.0, 9.0), Vector3(18.0, 10.0, 0.3), pal["night_sky"])
	BuildKit.box(root, Vector3(0, 2.2, 8.6), Vector3(9.0, 4.4, 0.1), BuildKit.glow_alpha(
		Color(0.35, 0.45, 0.75), 0.5, 0.22))
	BuildKit.omni(root, Vector3(0, 3.2, 6.0), Color(0.35, 0.45, 0.8), 1.4, 16.0)

	# Farol de la calle a mitad del callejón
	BuildKit.cylinder(root, Vector3(-7.0, 2.4, -6.0), 0.09, 4.8, pal["dark_steel"])
	BuildKit.beam(root, Vector3(-7.0, 4.7, -6.0), Vector3(-5.4, 4.9, -6.0), 0.07, pal["dark_steel"])
	BuildKit.box(root, Vector3(-5.3, 4.82, -6.0), Vector3(0.5, 0.16, 0.34), pal["bulb_pale"])
	BuildKit.spot(root, Vector3(-5.3, 4.7, -6.0), Vector3(-3.6, 0.0, -6.0),
		Color(0.95, 0.82, 0.6), 2.6, 12.0, 46.0, true)


static func _exterior_facade(root: Node3D, pal: Dictionary, anim: SetAnimator) -> void:
	var fz := -23.0
	# Frente de ladrillo del boliche
	BuildKit.box(root, Vector3(0, 5.5, fz - 0.4), Vector3(19.0, 11.0, 0.8), pal["brick"])
	BuildKit.box(root, Vector3(0, 0.9, fz + 0.05), Vector3(19.0, 1.8, 0.2), pal["concrete_wall"])

	# --- vano de la entrada: un rectángulo de luz, que es lo que la hace leer
	# como "adentro pasa algo" desde 20 metros ---
	BuildKit.box(root, Vector3(0, 1.65, fz + 0.10), Vector3(3.6, 3.30, 0.10),
		BuildKit.glow_alpha(Color(1.0, 0.18, 0.62), 1.6, 0.85))
	for sx in [-2.0, 2.0]:
		BuildKit.box(root, Vector3(sx, 1.75, fz + 0.22), Vector3(0.36, 3.60, 0.36), pal["dark_steel"])
		BuildKit.box(root, Vector3(sx, 1.75, fz + 0.40), Vector3(0.12, 3.20, 0.12), pal["neon_cyan"])
	BuildKit.box(root, Vector3(0, 3.50, fz + 0.30), Vector3(4.4, 0.30, 0.5), pal["dark_steel"])

	# Marquesina
	BuildKit.box(root, Vector3(0, 4.30, fz + 1.30), Vector3(6.4, 0.22, 2.6), pal["rust_metal"])
	for sx2 in [-2.9, 2.9]:
		BuildKit.beam(root, Vector3(sx2, 4.19, fz + 2.5), Vector3(sx2, 5.9, fz + 0.3), 0.04, pal["dark_steel"])

	# Escalón de entrada
	BuildKit.box(root, Vector3(0, 0.09, fz + 0.85), Vector3(4.6, 0.18, 1.2), pal["concrete_wall"])

	# --- cartel de neón: barras que respiran en dos colores ---
	var sign_mag := Palette.screen(Color(1.0, 0.14, 0.56), 2.4)
	var sign_cya := Palette.screen(Color(0.16, 0.86, 0.96), 2.2)
	anim.pulse(sign_mag, 1.6, 3.0, 1.1, 0.0)
	anim.pulse(sign_cya, 1.2, 2.6, 1.7, 1.9)
	BuildKit.box(root, Vector3(0, 6.30, fz + 0.20), Vector3(8.6, 1.5, 0.24), pal["dark_steel"])
	for i in 7:
		BuildKit.box(root, Vector3(-3.6 + i * 1.2, 6.55, fz + 0.36), Vector3(0.85, 0.16, 0.10), sign_mag)
	for i in 5:
		BuildKit.box(root, Vector3(-2.4 + i * 1.2, 6.05, fz + 0.36), Vector3(0.85, 0.16, 0.10), sign_cya)
	# Un tubo muerto en la punta: el cartel entero sano se ve demasiado nuevo.
	BuildKit.box(root, Vector3(4.2, 6.55, fz + 0.36), Vector3(0.85, 0.16, 0.10), pal["screen_off"])

	var glow1 := BuildKit.omni(root, Vector3(0, 2.2, fz + 1.6), Color(1.0, 0.20, 0.62), 4.0, 16.0)
	var glow2 := BuildKit.omni(root, Vector3(0, 6.2, fz + 1.4), Color(0.9, 0.30, 0.85), 2.6, 14.0)
	anim.blink(glow1, 2.6, 4.4, 1.1, 0.0)
	anim.blink(glow2, 1.6, 3.0, 1.7, 1.9)

	# Grafiti a los costados de la puerta
	BuildKit.box(root, Vector3(-4.4, 1.9, fz + 0.12), Vector3(2.2, 0.10, 0.04), pal["neon_violet"], false,
		Vector3(0, 0, 0.35))
	BuildKit.box(root, Vector3(4.6, 2.3, fz + 0.12), Vector3(1.8, 0.10, 0.04), pal["neon_cyan"], false,
		Vector3(0, 0, -0.28))

	# Portero: silueta quieta al costado de la puerta. Es lo único que hace que
	# la fila de jugadores se lea como una FILA y no como gente perdida.
	var bouncer := Node3D.new()
	bouncer.position = Vector3(2.85, 0.0, fz + 1.35)
	bouncer.rotation.y = 0.5
	root.add_child(bouncer)
	BuildKit.box(bouncer, Vector3(0, 0.45, 0), Vector3(0.52, 0.90, 0.30), pal["silhouette"])
	BuildKit.box(bouncer, Vector3(0, 1.16, 0), Vector3(0.78, 0.56, 0.36), pal["silhouette"])
	BuildKit.sphere(bouncer, Vector3(0, 1.58, 0), 0.16, pal["silhouette"])
	anim.sway(bouncer, 4.0, 0.5, 0.0)


static func _exterior_props(root: Node3D, pal: Dictionary, anim: SetAnimator,
		rng: RandomNumberGenerator) -> void:
	# Vallado de fila hacia la puerta
	for side in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for i in 5:
			var post := Vector3(side * 2.6, 0.0, -20.6 + i * 1.7)
			BuildKit.cylinder(root, post + Vector3(0, 0.5, 0), 0.06, 1.0, pal["dark_steel"])
			BuildKit.cylinder(root, post + Vector3(0, 0.02, 0), 0.22, 0.06, pal["dark_steel"])
			if i > 0:
				BuildKit.beam(root, prev + Vector3(0, 0.92, 0), post + Vector3(0, 0.92, 0), 0.02,
					pal["fabric_red"])
			prev = post

	# Contenedor de basura y bolsas
	BuildKit.box(root, Vector3(-5.6, 0.62, -12.4), Vector3(2.4, 1.24, 1.30), pal["rust_metal"], false,
		Vector3(0, 0.12, 0))
	BuildKit.box(root, Vector3(-5.6, 1.28, -12.4), Vector3(2.44, 0.10, 1.34), pal["dark_steel"], false,
		Vector3(0, 0.12, -0.14))
	for i in 6:
		BuildKit.sphere(root, Vector3(-5.0 + rng.randf_range(-1.2, 1.2), 0.28,
			-11.2 + rng.randf_range(-0.9, 0.9)), rng.randf_range(0.22, 0.34), pal["rubber_black"])

	# Pallets y cajones apoyados en la pared
	BuildKit.box(root, Vector3(6.6, 0.6, -14.5), Vector3(1.15, 1.2, 0.12), pal["aged_wood"], false,
		Vector3(0, 0.4, 0.22))
	for i in 3:
		BuildKit.box(root, Vector3(6.5, 0.3 + i * 0.55, -16.6), Vector3(1.0, 0.52, 0.8), pal["aged_wood"], false,
			Vector3(0, rng.randf_range(-0.2, 0.2), 0))

	# Escalera de incendios en la pared izquierda
	for i in 3:
		var y := 3.0 + i * 2.4
		BuildKit.box(root, Vector3(-7.4, y, -17.0), Vector3(2.4, 0.10, 1.6), pal["grate"])
		for rail_h in [0.5, 0.95]:
			BuildKit.box(root, Vector3(-6.3, y + rail_h, -17.0), Vector3(0.05, 0.05, 1.6), pal["rust_metal"])
		BuildKit.beam(root, Vector3(-6.3, y, -16.3), Vector3(-6.3, y + 2.4, -17.7), 0.05, pal["rust_metal"])

	# Equipos de aire y caños
	for i in 2:
		BuildKit.box(root, Vector3(8.1, 3.4 + i * 3.0, -13.0 - i * 4.0), Vector3(1.2, 1.1, 1.2),
			pal["dark_steel"])
		BuildKit.cylinder(root, Vector3(7.45, 3.4 + i * 3.0, -13.0 - i * 4.0), 0.42, 0.14,
			pal["grate"], false, Vector3(0, 0, PI * 0.5))
	BuildKit.cylinder(root, Vector3(8.4, 4.5, -8.0), 0.14, 22.0, pal["pipe_industrial"], false,
		Vector3(PI * 0.5, 0, 0))

	# Vapor de una rejilla: un plano translúcido subiendo despacio
	var steam := BuildKit.quad(root, Vector3(-3.2, 1.4, -9.5), Vector2(2.6, 3.2),
		BuildKit.glow_alpha(Color(0.6, 0.65, 0.8), 0.3, 0.09))
	anim.bob(steam, 0.5, 0.5, 0.0)
	BuildKit.box(root, Vector3(-3.2, 0.02, -9.5), Vector3(1.4, 0.04, 1.4), pal["grate"])

	# Papeles y escombros sueltos
	for i in 16:
		var s := rng.randf_range(0.10, 0.28)
		BuildKit.box(root, Vector3(rng.randf_range(-7.0, 7.0), s * 0.3, rng.randf_range(-21.0, 5.0)),
			Vector3(s, s * 0.12, s * 0.8), pal["rubble"], false,
			Vector3(0, rng.randf_range(0, PI), rng.randf_range(-0.1, 0.1)))

	# La propia cámara de seguridad, visible en el encuadre: cierra el chiste
	# de que lo que ves ES esta cámara.
	# --- luz sobre la fila ---
	# Sin esto los jugadores eran manchas negras: el resplandor de la entrada no
	# llega hasta la cola y el farol de la calle esta 10 m mas atras.
	BuildKit.box(root, Vector3(0, 5.4, -14.6), Vector3(3.2, 0.14, 0.5), pal["dark_steel"])
	BuildKit.box(root, Vector3(0, 5.30, -14.6), Vector3(2.6, 0.10, 0.3), pal["bulb_pale"])
	BuildKit.spot(root, Vector3(0, 5.25, -14.6), Vector3(0, 0, -15.6),
		Color(0.95, 0.86, 0.72), 4.2, 16.0, 60.0, true)
	# Relleno DESDE EL LADO DE LA CAMARA: la luz cenital sola les dejaba la cara
	# y el pecho (que es lo que mira la camara) en sombra.
	BuildKit.spot(root, Vector3(4.6, 3.6, -9.6), Vector3(-0.6, 1.1, -15.0),
		Color(0.85, 0.72, 0.95), 2.6, 16.0, 52.0)
	BuildKit.omni(root, Vector3(0, 2.6, -15.2), Color(0.9, 0.55, 0.75), 1.8, 13.0)
	BuildKit.beam(root, Vector3(-1.6, 5.45, -14.6), Vector3(-7.6, 6.6, -14.6), 0.04, pal["dark_steel"])

	var cam_body := Node3D.new()
	cam_body.position = Vector3(8.3, 5.6, -8.4)
	cam_body.rotation.y = -0.9
	root.add_child(cam_body)
	BuildKit.box(cam_body, Vector3(0, 0, 0), Vector3(0.5, 0.26, 0.26), pal["paint_worn"])
	BuildKit.cylinder(cam_body, Vector3(-0.3, 0, 0), 0.10, 0.14, pal["rubber_black"], false,
		Vector3(0, 0, PI * 0.5))
	BuildKit.box(cam_body, Vector3(0.28, 0.08, 0), Vector3(0.06, 0.06, 0.06), pal["neon_red_dim"])
	BuildKit.beam(cam_body, Vector3(0.2, 0.1, 0), Vector3(0.7, 0.5, 0), 0.03, pal["dark_steel"])
	anim.sway(cam_body, 5.0, 0.22, 0.0)


# =============================================================================
# 4. VESTUARIO -- menú de apariencia. Fondo negro, plataforma giratoria y tres
#    luces. Nada más: acá el que tiene que leerse es el personaje.
# =============================================================================

static func build_studio() -> Node3D:
	var root := _new_set("SetStudio")
	var pal := Palette.create()
	var anim := _animator(root)

	_env(root, Color(0.014, 0.013, 0.020), Color(0.20, 0.20, 0.28), 0.22,
		Color(0.10, 0.10, 0.16), 0.020, 0.35)

	# Caja negra alrededor: evita que se vea el vacío del mundo si la cámara
	# se corre, y da una superficie donde el rim light rebota.
	BuildKit.box(root, Vector3(0, 3.0, 4.6), Vector3(16.0, 8.0, 0.3), pal["void"])
	BuildKit.box(root, Vector3(0, 3.0, -4.6), Vector3(16.0, 8.0, 0.3), pal["void"])
	for sx in [-6.0, 6.0]:
		BuildKit.box(root, Vector3(sx, 3.0, 0), Vector3(0.3, 8.0, 9.5), pal["void"])
	BuildKit.box(root, Vector3(0, -0.12, 0), Vector3(16.0, 0.24, 9.5), pal["concrete_floor"])

	# Plataforma giratoria, corrida a la derecha para dejar libre la columna de
	# categorías. El aro es un ANILLO DE TACOS, no un disco emisivo: un disco de
	# 1.6 m encendido tapaba medio cuadro con un plato de luz turquesa.
	var turn := Vector3(0.85, 0, 0)
	BuildKit.cylinder(root, turn + Vector3(0, -0.02, 0), 1.45, 0.10, pal["dark_steel"])
	BuildKit.cylinder(root, turn + Vector3(0, -0.10, 0), 1.10, 0.14, pal["paint_worn"])
	var rim := BuildKit.emissive(Color(0.10, 0.45, 0.52), Color(0.14, 0.78, 0.90), 0.9)
	for i in 28:
		var ar := TAU * i / 28.0
		BuildKit.box(root, turn + Vector3(cos(ar) * 1.44, 0.035, sin(ar) * 1.44),
			Vector3(0.20, 0.02, 0.06), rim, false, Vector3(0, -ar, 0))
	for i in 8:
		var ah := TAU * i / 8.0 + 0.2
		BuildKit.box(root, turn + Vector3(cos(ah) * 1.20, 0.035, sin(ah) * 1.20),
			Vector3(0.26, 0.02, 0.10), pal["hazard_mark"], false, Vector3(0, -ah, 0))

	# --- luces de estudio ---
	# Key: adelante-arriba-izquierda, cálida. Es la que dibuja el volumen.
	BuildKit.spot(root, turn + Vector3(2.4, 3.6, -2.6), turn + Vector3(0, 1.2, 0),
		Color(1.0, 0.88, 0.72), 11.0, 12.0, 34.0, true)
	# Rim magenta desde atrás: despega la silueta del fondo negro.
	BuildKit.spot(root, turn + Vector3(-2.0, 2.9, 2.6), turn + Vector3(0, 1.3, 0),
		Color(1.0, 0.25, 0.65), 6.5, 11.0, 38.0)
	# Fill frío y flojo del otro lado, para que la sombra no sea un agujero.
	BuildKit.omni(root, turn + Vector3(-2.4, 1.8, -2.0), Color(0.45, 0.62, 0.95), 2.8, 9.0)
	var under := BuildKit.omni(root, turn + Vector3(0, 0.25, 0), Color(0.15, 0.8, 0.95), 0.5, 2.6)
	anim.blink(under, 0.35, 0.7, 1.3, 0.0)

	# Trípodes apenas insinuados en la penumbra
	for sx2 in [2.4, -2.0]:
		BuildKit.cylinder(root, turn + Vector3(sx2, 1.4, -2.6 if sx2 > 0 else 2.6), 0.05, 2.8,
			pal["dark_steel"])

	# DOS encuadres, porque los personajes miden 1.70 y 2.30 m: con uno solo, al
	# Atrapador se le veían las rodillas y nada más. La cámara mira apenas a la
	# derecha de la plataforma para que el muñeco caiga fuera del panel de
	# piezas, no detrás de él.
	root.set_meta("shots", {
		"rat": _shot(Vector3(2.15, 1.02, -3.30), Vector3(1.72, 0.86, 0.0), 40.0),
		"seeker": _shot(Vector3(2.45, 1.35, -4.55), Vector3(1.95, 1.16, 0.0), 40.0),
	})
	root.set_meta("actor", Transform3D(Basis(), turn))
	return root
