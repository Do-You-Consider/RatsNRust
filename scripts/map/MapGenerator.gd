extends Node3D
class_name MapGenerator
## =============================================================================
## WAREHOUSE RAVE -- NAVE INDUSTRIAL ABANDONADA DE 4 PLANTAS
## =============================================================================
## Reescritura completa del mapa. La idea: una warehouse de ladrillo tomada por
## una rave clandestina. TODO lo jugable pasa en planta baja; los 3 niveles de
## arriba son pura ambientación (pasarelas, barandas, siluetas mirando hacia
## abajo, cerchas del techo) visibles desde el atrio central.
##
## PLANTA BAJA (66m x 66m, grid fijo de 9 zonas de 22m):
##
##   [ TALLER      ] ── [ DEPÓSITO CARGA ] ── [ CHILL ROOM NE ]
##         │                    │                     │
##   [ BAR & LOUNGE ] ── [ PISTA + DJ SET ] ── [ SALA CALDERAS ]
##         │                (ATRIO 18m)               │
##   [ BAÑOS        ] ── [ ENTRADA/CARGA  ] ── [ CHILL ROOM SE ]
##
## VERTICALIDAD:
## - La pista de baile central es un atrio abierto hasta las cerchas (18m).
## - Las 8 zonas perimetrales tienen techo a 4.5m; encima de ellas hay 3
##   niveles decorativos NO jugables (anillos de losa con barandas hacia el
##   atrio, pasarelas cruzando el vacío, siluetas estáticas, luz roja tenue).
## - Escalera derrumbada en la entrada (bloqueada con escombros + reja +
##   colisión invisible): nadie sube ni con glitches.
##
## Iluminación: punto medio techno-oscuro / neón -- base opresiva con strobe
## blanco y rojo profundo en la pista, acentos magenta (DJ), cian (bar) y
## violeta (chill rooms). Arriba, penumbra con acentos rojos sucios.
##
## Contrato con Game.gd (idéntico al mapa anterior):
##   generate(seed) / hider_spawn_points / seeker_spawn_point / club_music
## Determinista con la seed: todos los peers construyen el mismo mapa.
## =============================================================================

@export var room_size: float = 22.0 # lado de cada zona del grid 3x3

## Arrastrá acá el .ogg/.mp3 que quieras que suene desde la cabina del DJ
## (audio 3D posicional: fuerte en la pista, se apaga en las zonas vecinas).
@export var club_music: AudioStream

# --- Alturas de la nave -------------------------------------------------------
const PLAY_H := 4.5        # techo de las zonas jugables perimetrales
const LEVEL_H := 4.5       # alto de cada nivel decorativo
const DECO_LEVELS := 3     # niveles no jugables sobre la planta baja
const ROOF_Y := PLAY_H + LEVEL_H * DECO_LEVELS # 18.0 -- arranque del techo
const WALL_H := ROOF_Y + 0.5                   # muros exteriores hasta el techo
const SLAB_T := 0.35       # espesor de losa de cada nivel

var rng := RandomNumberGenerator.new()

var hider_spawn_points: Array[Vector3] = []
var seeker_spawn_point: Vector3 = Vector3.ZERO

# Tweens de efectos (strobe, parpadeos): hay que matarlos al regenerar para
# que no queden apuntando a luces liberadas de la partida anterior.
var _fx_tweens: Array[Tween] = []

# --- Paleta de materiales -----------------------------------------------------
var mat_concrete_floor: StandardMaterial3D
var mat_concrete_wall: StandardMaterial3D
var mat_brick: StandardMaterial3D
var mat_tile_floor: StandardMaterial3D
var mat_tile_wall: StandardMaterial3D
var mat_wood_floor: StandardMaterial3D
var mat_rust_metal: StandardMaterial3D
var mat_dark_steel: StandardMaterial3D
var mat_grate: StandardMaterial3D
var mat_aged_wood: StandardMaterial3D
var mat_leather_brown: StandardMaterial3D
var mat_pipe_industrial: StandardMaterial3D
var mat_hazard_mark: StandardMaterial3D
var mat_rubble: StandardMaterial3D
var mat_fabric_red: StandardMaterial3D
var mat_mattress: StandardMaterial3D
var mat_shrinkwrap: StandardMaterial3D
var mat_silhouette: StandardMaterial3D
var mat_mirror: StandardMaterial3D

var mat_neon_magenta: StandardMaterial3D
var mat_neon_cyan: StandardMaterial3D
var mat_neon_violet: StandardMaterial3D
var mat_neon_red_dim: StandardMaterial3D
var mat_led_warm: StandardMaterial3D
var mat_moon_glass: StandardMaterial3D
var mat_fire_orange: StandardMaterial3D
var mat_crt_phosphor: StandardMaterial3D
var mat_exit_green: StandardMaterial3D
var mat_bulb_pale: StandardMaterial3D
var mat_laser_green: StandardMaterial3D


func _init() -> void:
	_init_palette()


func _matte(albedo: Color, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metallic
	return m


func _emissive(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


func _init_palette() -> void:
	mat_concrete_floor = _matte(Color(0.08, 0.075, 0.07), 0.95)
	mat_concrete_wall = _matte(Color(0.15, 0.135, 0.12), 0.9)
	mat_brick = _matte(Color(0.19, 0.085, 0.06), 0.92)
	mat_tile_floor = _matte(Color(0.09, 0.15, 0.13), 0.45)
	mat_tile_wall = _matte(Color(0.12, 0.22, 0.19), 0.4)
	mat_wood_floor = _matte(Color(0.14, 0.09, 0.05), 0.85)
	mat_rust_metal = _matte(Color(0.32, 0.16, 0.08), 0.55, 0.8)
	mat_dark_steel = _matte(Color(0.20, 0.21, 0.23), 0.35, 0.9)
	mat_grate = _matte(Color(0.13, 0.14, 0.15), 0.5, 0.85)
	mat_aged_wood = _matte(Color(0.22, 0.12, 0.06), 0.85)
	mat_leather_brown = _matte(Color(0.14, 0.07, 0.04), 0.7)
	mat_pipe_industrial = _matte(Color(0.60, 0.40, 0.08), 0.4, 0.7)
	mat_hazard_mark = _matte(Color(0.55, 0.45, 0.08), 0.65, 0.4)
	mat_rubble = _matte(Color(0.30, 0.28, 0.26), 0.98)
	mat_fabric_red = _matte(Color(0.22, 0.05, 0.07), 0.95)
	mat_mattress = _matte(Color(0.42, 0.38, 0.30), 0.95)
	mat_shrinkwrap = _matte(Color(0.55, 0.58, 0.60), 0.3)

	# Siluetas de las pasarelas: negro casi puro y SIN sombreado, para que se
	# lean como recortes contra el resplandor rojo aunque la luz cambie.
	mat_silhouette = StandardMaterial3D.new()
	mat_silhouette.albedo_color = Color(0.015, 0.012, 0.02)
	mat_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_mirror = _matte(Color(0.85, 0.85, 0.9), 0.05, 1.0)

	mat_neon_magenta = _emissive(Color(1.0, 0.15, 0.55), Color(1.0, 0.1, 0.55), 2.6)
	mat_neon_cyan = _emissive(Color(0.15, 0.85, 0.95), Color(0.1, 0.8, 0.95), 2.4)
	mat_neon_violet = _emissive(Color(0.6, 0.2, 1.0), Color(0.55, 0.15, 1.0), 2.2)
	mat_neon_red_dim = _emissive(Color(0.7, 0.08, 0.06), Color(0.9, 0.1, 0.08), 1.1)
	mat_led_warm = _emissive(Color(1.0, 0.7, 0.3), Color(1.0, 0.65, 0.25), 1.8)
	mat_moon_glass = _emissive(Color(0.5, 0.58, 0.7), Color(0.55, 0.65, 0.85), 0.8)
	mat_fire_orange = _emissive(Color(1.0, 0.3, 0.05), Color(1.0, 0.35, 0.08), 3.5)
	mat_crt_phosphor = _emissive(Color(0.1, 0.45, 0.2), Color(0.15, 0.75, 0.3), 1.4)
	mat_exit_green = _emissive(Color(0.15, 0.8, 0.3), Color(0.1, 0.9, 0.3), 1.8)
	mat_bulb_pale = _emissive(Color(0.9, 0.88, 0.92), Color(0.92, 0.9, 0.95), 2.2)
	mat_laser_green = _emissive(Color(0.2, 1.0, 0.3), Color(0.15, 1.0, 0.25), 3.0)


# =============================================================================
# LAYOUT FIJO -- la arquitectura vertical necesita el atrio en el centro, así
# que el edificio es siempre el mismo; la seed randomiza el "desgaste": qué
# pasos del anillo perimetral están tapiados, escombros, cables colgando,
# posiciones de las siluetas y el orden de los spawns.
# =============================================================================

## Escondite sugerido dentro de cada zona (offset local al centro de la zona).
const ZONE_HIDE_OFFSETS := {
	"dance": Vector3(9.2, 0.8, -9.2),    # detrás de la torre de parlantes del DJ
	"bar": Vector3(1.7, 0.8, -5.3),      # el pasillo detrás de la barra
	"banos": Vector3(-1.4, 0.8, 8.8),    # último cubículo (el de la puerta caída)
	"chill_ne": Vector3(0.0, 0.8, -4.35),# detrás del respaldo del sofá grande
	"chill_se": Vector3(5.0, 0.8, 7.6),  # rincón de los colchones
	"boiler": Vector3(-8.6, 0.8, 8.6),   # detrás de la pila de barriles
	"cargo": Vector3(2.0, 0.8, -2.0),    # el pasillo entre estanterías
	"workshop": Vector3(9.0, 0.8, 9.0),  # detrás de los tambores de aceite
}

var _zone_centers: Dictionary = {}


func generate(seed_value: int = -1) -> void:
	for t in _fx_tweens:
		if t != null and t.is_valid():
			t.kill()
	_fx_tweens.clear()
	for c in get_children():
		c.queue_free()
	hider_spawn_points.clear()
	seeker_spawn_point = Vector3.ZERO
	_zone_centers.clear()

	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value

	var r := room_size
	_zone_centers = {
		"dance": Vector3.ZERO,
		"bar": Vector3(-r, 0, 0),
		"boiler": Vector3(r, 0, 0),
		"cargo": Vector3(0, 0, -r),
		"entrance": Vector3(0, 0, r),
		"workshop": Vector3(-r, 0, -r),
		"chill_ne": Vector3(r, 0, -r),
		"banos": Vector3(-r, 0, r),
		"chill_se": Vector3(r, 0, r),
	}

	_build_shell()
	_build_ground_partitions()
	_build_perimeter_ceiling()
	_build_upper_levels()
	_build_roof_structure()
	_build_silhouettes()

	_build_dance_atrium(_zone_centers["dance"])
	_build_bar(_zone_centers["bar"])
	_build_boiler(_zone_centers["boiler"])
	_build_cargo(_zone_centers["cargo"])
	_build_entrance(_zone_centers["entrance"])
	_build_workshop(_zone_centers["workshop"])
	_build_chill_room(_zone_centers["chill_ne"], 0)
	_build_banos(_zone_centers["banos"])
	_build_chill_room(_zone_centers["chill_se"], 1)

	_setup_spawns()


# =============================================================================
# CASCARÓN: piso, muros exteriores de ladrillo (altura completa), techo
# =============================================================================

func _build_shell() -> void:
	var total := room_size * 3.0
	var half := total * 0.5

	# Piso monolítico de hormigón
	_create_box(Vector3(0, -0.25, 0), Vector3(total + 4.0, 0.5, total + 4.0), mat_concrete_floor)

	# Muros exteriores de ladrillo hasta el techo (sellado, sin salidas)
	var thick := 0.6
	_create_box(Vector3(0, WALL_H * 0.5, -half), Vector3(total + thick * 2.0, WALL_H, thick), mat_brick)
	_create_box(Vector3(0, WALL_H * 0.5, half), Vector3(total + thick * 2.0, WALL_H, thick), mat_brick)
	_create_box(Vector3(-half, WALL_H * 0.5, 0), Vector3(thick, WALL_H, total + thick * 2.0), mat_brick)
	_create_box(Vector3(half, WALL_H * 0.5, 0), Vector3(thick, WALL_H, total + thick * 2.0), mat_brick)

	# Zócalo de hormigón en la base de los muros (planta baja)
	for side in [-1, 1]:
		_create_box(Vector3(0, 0.6, side * (half - 0.35)), Vector3(total, 1.2, 0.15), mat_concrete_wall, false)
		_create_box(Vector3(side * (half - 0.35), 0.6, 0), Vector3(0.15, 1.2, total), mat_concrete_wall, false)

	# Techo (nadie llega, sin colisión)
	_create_box(Vector3(0, WALL_H + 0.25, 0), Vector3(total + 4.0, 0.5, total + 4.0), _matte(Color(0.06, 0.055, 0.06), 0.95), false)

	# Ventanales rotos en la banda superior de los 4 muros: vidrio pálido
	# "iluminado por la luna", visibles en diagonal desde el atrio.
	var win_y := ROOF_Y - 2.4
	var face := half - 0.45
	for wall_side in [-1, 1]:
		for offset in [-room_size * 0.7, 0.0, room_size * 0.7]:
			# Muros norte/sur
			_create_broken_window(Vector3(offset, win_y, wall_side * face), true)
			# Muros este/oeste
			_create_broken_window(Vector3(wall_side * face, win_y, offset), false)


func _create_broken_window(pos: Vector3, on_z_wall: bool) -> void:
	var pane := Vector3(2.4, 1.7, 0.08) if on_z_wall else Vector3(0.08, 1.7, 2.4)
	_create_box(pos, pane, mat_moon_glass, false)
	if on_z_wall:
		_create_box(pos, Vector3(2.6, 0.09, 0.1), mat_dark_steel, false)
		_create_box(pos, Vector3(0.09, 1.85, 0.1), mat_dark_steel, false)
		if rng.randf() < 0.5: # travesaño caído -- vidrio "roto"
			_create_box(pos, Vector3(0.08, 2.1, 0.1), mat_dark_steel, false, Vector3(0, 0, 0.55))
	else:
		_create_box(pos, Vector3(0.1, 0.09, 2.6), mat_dark_steel, false)
		_create_box(pos, Vector3(0.1, 1.85, 0.09), mat_dark_steel, false)
		if rng.randf() < 0.5:
			_create_box(pos, Vector3(0.1, 2.1, 0.08), mat_dark_steel, false, Vector3(0.55, 0, 0))


# =============================================================================
# TABIQUES DE PLANTA BAJA
# =============================================================================

func _build_ground_partitions() -> void:
	var hr := room_size * 0.5 # 11 -- media zona = borde del atrio
	var r := room_size

	# --- Aberturas del atrio hacia las 4 zonas cardinales ---
	# Norte (depósito): corrida hacia el oeste para no chocar con la cabina DJ
	_build_wall_with_opening(Vector3(0, 0, -hr), r, PLAY_H, 5.0, 3.4, -6.5, 0.3, false, mat_concrete_wall)
	# Sur (entrada): la boca principal del club, bien ancha
	_build_wall_with_opening(Vector3(0, 0, hr), r, PLAY_H, 7.0, 3.6, 0.0, 0.3, false, mat_concrete_wall)
	# Oeste (bar) y Este (calderas)
	_build_wall_with_opening(Vector3(-hr, 0, 0), r, PLAY_H, 5.0, 3.2, 0.0, 0.3, true, mat_concrete_wall)
	_build_wall_with_opening(Vector3(hr, 0, 0), r, PLAY_H, 5.0, 3.2, 0.0, 0.3, true, mat_concrete_wall)

	# Tira de neón perimetral del atrio, montada arriba de las aberturas
	# (el "trim" arquitectónico del club: magenta y cian alternados)
	var trim_y := PLAY_H - 0.12
	_create_box(Vector3(0, trim_y, -hr + 0.22), Vector3(r - 1.0, 0.07, 0.05), mat_neon_magenta, false)
	_create_box(Vector3(0, trim_y, hr - 0.22), Vector3(r - 1.0, 0.07, 0.05), mat_neon_cyan, false)
	_create_box(Vector3(-hr + 0.22, trim_y, 0), Vector3(0.05, 0.07, r - 1.0), mat_neon_cyan, false)
	_create_box(Vector3(hr - 0.22, trim_y, 0), Vector3(0.05, 0.07, r - 1.0), mat_neon_magenta, false)

	# --- Anillo perimetral: pasos entre zonas vecinas. La seed tapia 2 de los
	# 8 pasos, así el recorrido cambia partida a partida sin tocar el edificio.
	var ring_passages := [
		{"c": Vector3(-hr, 0, -r), "v": true},  # taller | depósito
		{"c": Vector3(hr, 0, -r), "v": true},   # depósito | chill NE
		{"c": Vector3(r, 0, -hr), "v": false},  # chill NE | calderas
		{"c": Vector3(r, 0, hr), "v": false},   # calderas | chill SE
		{"c": Vector3(hr, 0, r), "v": true},    # chill SE | entrada
		{"c": Vector3(-hr, 0, r), "v": true},   # entrada | baños
		{"c": Vector3(-r, 0, hr), "v": false},  # baños | bar
		{"c": Vector3(-r, 0, -hr), "v": false}, # bar | taller
	]
	var order := range(ring_passages.size())
	_seeded_shuffle(order)
	var sealed := {order[0]: true, order[1]: true}
	for i in ring_passages.size():
		var p: Dictionary = ring_passages[i]
		if sealed.has(i):
			_build_wall_with_opening(p["c"], r, PLAY_H, 0.0, 0.0, 0.0, 0.3, p["v"], mat_concrete_wall, false)
		else:
			_build_wall_with_opening(p["c"], r, PLAY_H, 3.0, 2.8, 0.0, 0.3, p["v"], mat_concrete_wall)


## Muro de un tramo de zona: macizo (is_open=false) o con vano descentrable
## (off = corrimiento del centro del vano a lo largo del muro) y jambas de
## acero oxidado.
func _build_wall_with_opening(center: Vector3, length: float, height: float, ow: float, oh: float, off: float, thick: float, vertical: bool, mat: StandardMaterial3D, is_open: bool = true) -> void:
	if not is_open or ow <= 0.0:
		var solid_size := Vector3(thick, height, length) if vertical else Vector3(length, height, thick)
		_create_box(center + Vector3(0, height * 0.5, 0), solid_size, mat)
		return

	var a_len := (length * 0.5) + (off - ow * 0.5) # tramo del lado negativo
	var b_len := (length * 0.5) - (off + ow * 0.5) # tramo del lado positivo
	var a_center := -length * 0.5 + a_len * 0.5
	var b_center := length * 0.5 - b_len * 0.5
	var lintel_h := height - oh

	if vertical:
		if a_len > 0.05:
			_create_box(center + Vector3(0, height * 0.5, a_center), Vector3(thick, height, a_len), mat)
		if b_len > 0.05:
			_create_box(center + Vector3(0, height * 0.5, b_center), Vector3(thick, height, b_len), mat)
		_create_box(center + Vector3(0, oh + lintel_h * 0.5, off), Vector3(thick, lintel_h, ow), mat)
		_create_box(center + Vector3(0, oh * 0.5, off - ow * 0.5), Vector3(thick * 1.25, oh, 0.1), mat_rust_metal)
		_create_box(center + Vector3(0, oh * 0.5, off + ow * 0.5), Vector3(thick * 1.25, oh, 0.1), mat_rust_metal)
		_create_box(center + Vector3(0, oh, off), Vector3(thick * 1.25, 0.1, ow), mat_rust_metal)
	else:
		if a_len > 0.05:
			_create_box(center + Vector3(a_center, height * 0.5, 0), Vector3(a_len, height, thick), mat)
		if b_len > 0.05:
			_create_box(center + Vector3(b_center, height * 0.5, 0), Vector3(b_len, height, thick), mat)
		_create_box(center + Vector3(off, oh + lintel_h * 0.5, 0), Vector3(ow, lintel_h, thick), mat)
		_create_box(center + Vector3(off - ow * 0.5, oh * 0.5, 0), Vector3(0.1, oh, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(off + ow * 0.5, oh * 0.5, 0), Vector3(0.1, oh, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(off, oh, 0), Vector3(ow, 0.1, thick * 1.25), mat_rust_metal)


## El techo de las zonas perimetrales es a la vez la losa del primer nivel
## decorativo. Con colisión: es el "cielo" real del área jugable.
func _build_perimeter_ceiling() -> void:
	_build_ring_slab(PLAY_H, true)


## Losa en anillo (deja el hueco del atrio en el centro) a la altura level_y.
func _build_ring_slab(level_y: float, with_collision: bool) -> void:
	var total := room_size * 3.0
	var hr := room_size * 0.5
	var strip_d := room_size # profundidad de las tiras norte/sur
	var y := level_y + SLAB_T * 0.5
	var slab_mat := mat_concrete_floor if with_collision else mat_grate

	# Tiras norte y sur (ancho completo) + tiras este y oeste (entre ambas)
	_create_box(Vector3(0, y, -room_size), Vector3(total, SLAB_T, strip_d), slab_mat, with_collision)
	_create_box(Vector3(0, y, room_size), Vector3(total, SLAB_T, strip_d), slab_mat, with_collision)
	_create_box(Vector3(-room_size, y, 0), Vector3(strip_d, SLAB_T, room_size), slab_mat, with_collision)
	_create_box(Vector3(room_size, y, 0), Vector3(strip_d, SLAB_T, room_size), slab_mat, with_collision)

	# Canto de losa hacia el atrio con tira emisiva roja tenue: es lo que hace
	# legibles los niveles desde la pista, aun en penumbra.
	var edge_y := level_y + SLAB_T * 0.5
	_create_box(Vector3(0, edge_y, -hr - 0.05), Vector3(room_size + 0.4, 0.08, 0.05), mat_neon_red_dim, false)
	_create_box(Vector3(0, edge_y, hr + 0.05), Vector3(room_size + 0.4, 0.08, 0.05), mat_neon_red_dim, false)
	_create_box(Vector3(-hr - 0.05, edge_y, 0), Vector3(0.05, 0.08, room_size + 0.4), mat_neon_red_dim, false)
	_create_box(Vector3(hr + 0.05, edge_y, 0), Vector3(0.05, 0.08, room_size + 0.4), mat_neon_red_dim, false)


# =============================================================================
# NIVELES DECORATIVOS (NO JUGABLES) + PASARELAS + COLUMNAS
# =============================================================================

func _build_upper_levels() -> void:
	var hr := room_size * 0.5

	# Columnas de acero en las 4 esquinas del atrio, de piso a techo
	for cx in [-hr, hr]:
		for cz in [-hr, hr]:
			_create_box(Vector3(cx, WALL_H * 0.5, cz), Vector3(0.55, WALL_H, 0.55), mat_dark_steel)

	for i in range(1, DECO_LEVELS + 1):
		var level_y := PLAY_H + (i - 1) * LEVEL_H
		var rail_base := level_y + SLAB_T

		# La losa del nivel 1 ya existe (techo jugable); niveles 2 y 3 acá.
		if i > 1:
			_build_ring_slab(level_y, false)

		# Barandas hacia el atrio en los 4 bordes
		_create_railing(Vector3(0, rail_base, -hr - 0.2), room_size, true)
		_create_railing(Vector3(0, rail_base, hr + 0.2), room_size, true)
		_create_railing(Vector3(-hr - 0.2, rail_base, 0), room_size, false)
		_create_railing(Vector3(hr + 0.2, rail_base, 0), room_size, false)

		# Puertas negras de oficinas muertas sobre los muros exteriores
		# (huecos oscuros sin sombreado: profundidad falsa, costo cero)
		var face := room_size * 1.5 - 0.5
		for offset in [-room_size, 0.0, room_size]:
			var jitter := rng.randf_range(-3.0, 3.0)
			_create_box(Vector3(offset + jitter, rail_base + 1.2, -face), Vector3(1.3, 2.4, 0.15), mat_silhouette, false)
			_create_box(Vector3(offset - jitter, rail_base + 1.2, face), Vector3(1.3, 2.4, 0.15), mat_silhouette, false)

		# Clutter abandonado cerca del borde: pilas de cajas, algún barril
		for k in 3:
			var edge := rng.randi_range(0, 3)
			var along := rng.randf_range(-hr + 2.0, hr - 2.0)
			var depth := rng.randf_range(1.2, 3.5)
			var p := Vector3.ZERO
			match edge:
				0: p = Vector3(along, rail_base, -hr - depth)
				1: p = Vector3(along, rail_base, hr + depth)
				2: p = Vector3(-hr - depth, rail_base, along)
				3: p = Vector3(hr + depth, rail_base, along)
			if rng.randf() < 0.6:
				_create_crate_stack(p, rng.randi_range(1, 3), false)
			else:
				_create_cylinder(p + Vector3(0, 0.45, 0), 0.36, 0.9, mat_rust_metal, false)

		# LEDs rojos de "equipo muerto" en las columnas, uno por nivel
		for cx in [-hr, hr]:
			for cz in [-hr, hr]:
				_create_box(Vector3(cx * 0.965, rail_base + 1.6, cz * 0.965), Vector3(0.1, 0.1, 0.1), mat_neon_red_dim, false)

		# Penumbra roja del nivel: dos omnis tenues en esquinas opuestas
		var flip := 1.0 if i % 2 == 0 else -1.0
		_add_omni(Vector3(-9.0 * flip, rail_base + 2.3, -9.0), Color(0.9, 0.12, 0.1), 0.5, 9.0)
		_add_omni(Vector3(9.0 * flip, rail_base + 2.3, 9.0), Color(0.9, 0.12, 0.1), 0.5, 9.0)

	# --- Pasarelas cruzando el vacío del atrio ---
	# Nivel 2: cruza de oeste a este; Nivel 3: de norte a sur.
	_build_catwalk(Vector3(0, PLAY_H + LEVEL_H, 3.0), true)
	_build_catwalk(Vector3(-3.0, PLAY_H + LEVEL_H * 2.0, 0), false)

	# Cables sueltos colgando del techo hacia el vacío
	for k in 5:
		var cx := rng.randf_range(-8.5, 8.5)
		var cz := rng.randf_range(-8.5, 8.5)
		var drop := rng.randf_range(2.5, 6.5)
		_create_beam(Vector3(cx, ROOF_Y, cz), Vector3(cx + rng.randf_range(-0.4, 0.4), ROOF_Y - drop, cz), 0.025, mat_dark_steel)


## Pasarela de rejilla con barandas a ambos lados y tensores al techo.
func _build_catwalk(center: Vector3, along_x: bool) -> void:
	var length := room_size
	var deck_y := center.y + SLAB_T - 0.075
	var deck_size := Vector3(length, 0.15, 1.8) if along_x else Vector3(1.8, 0.15, length)
	_create_box(Vector3(center.x, deck_y, center.z), deck_size, mat_grate, false)

	var rail_base := center.y + SLAB_T
	if along_x:
		_create_railing(Vector3(center.x, rail_base, center.z - 0.85), length, true)
		_create_railing(Vector3(center.x, rail_base, center.z + 0.85), length, true)
		for hx in [-7.0, 7.0]:
			_create_beam(Vector3(center.x + hx, deck_y, center.z), Vector3(center.x + hx, ROOF_Y, center.z), 0.05, mat_dark_steel)
	else:
		_create_railing(Vector3(center.x - 0.85, rail_base, center.z), length, false)
		_create_railing(Vector3(center.x + 0.85, rail_base, center.z), length, false)
		for hz in [-7.0, 7.0]:
			_create_beam(Vector3(center.x, deck_y, center.z + hz), Vector3(center.x, ROOF_Y, center.z + hz), 0.05, mat_dark_steel)


## Baranda industrial: 2 largueros + parantes cada ~3.6m. Sin colisión (nadie
## llega ahí arriba).
func _create_railing(center: Vector3, length: float, along_x: bool) -> void:
	for rail_h in [0.55, 1.05]:
		var rail_size := Vector3(length, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, length)
		_create_box(center + Vector3(0, rail_h, 0), rail_size, mat_rust_metal, false)
	var posts := 7
	for p in posts:
		var t: float = lerpf(-length * 0.5 + 0.2, length * 0.5 - 0.2, float(p) / float(posts - 1))
		var post_pos := center + (Vector3(t, 0.525, 0) if along_x else Vector3(0, 0.525, t))
		_create_box(post_pos, Vector3(0.06, 1.05, 0.06), mat_rust_metal, false)


# =============================================================================
# TECHO: CERCHAS + CLARABOYA ROTA
# =============================================================================

func _build_roof_structure() -> void:
	var total := room_size * 3.0 - 2.0
	var chord_top := ROOF_Y - 0.35
	var chord_bot := ROOF_Y - 1.55

	for tz in [-8.0, 0.0, 8.0]:
		_create_box(Vector3(0, chord_top, tz), Vector3(total, 0.26, 0.26), mat_dark_steel, false)
		_create_box(Vector3(0, chord_bot, tz), Vector3(total, 0.26, 0.26), mat_dark_steel, false)
		var verts := 9
		for v in verts:
			var vx: float = lerpf(-total * 0.5 + 1.0, total * 0.5 - 1.0, float(v) / float(verts - 1))
			_create_box(Vector3(vx, (chord_top + chord_bot) * 0.5, tz), Vector3(0.2, chord_top - chord_bot, 0.2), mat_dark_steel, false)
			if v < verts - 1:
				var nx: float = lerpf(-total * 0.5 + 1.0, total * 0.5 - 1.0, float(v + 1) / float(verts - 1))
				var from_y := chord_bot if v % 2 == 0 else chord_top
				var to_y := chord_top if v % 2 == 0 else chord_bot
				_create_beam(Vector3(vx, from_y, tz), Vector3(nx, to_y, tz), 0.08, mat_dark_steel)

	# Claraboya rota: paneles pálidos entre cerchas, "luz de luna" cayendo al atrio
	for pz in [-4.0, 4.0]:
		_create_box(Vector3(0, ROOF_Y - 0.1, pz), Vector3(9.0, 0.1, 3.2), mat_moon_glass, false)
		_create_box(Vector3(0, ROOF_Y - 0.15, pz), Vector3(9.4, 0.12, 0.18), mat_dark_steel, false)

	for sp in [Vector3(-3.5, 0, -4.0), Vector3(3.5, 0, 4.0)]:
		var beam := SpotLight3D.new()
		beam.light_color = Color(0.6, 0.7, 0.95)
		beam.light_energy = 1.1
		beam.spot_range = ROOF_Y + 1.0
		beam.spot_angle = 13.0
		beam.shadow_enabled = true
		add_child(beam)
		var beam_pos := Vector3(sp.x, ROOF_Y - 0.4, sp.z)
		beam.look_at_from_position(beam_pos, beam_pos + Vector3(0, -1, 0), Vector3(0, 0, -1))


# =============================================================================
# SILUETAS -- figuras quietas en las barandas, mirando la rave desde arriba
# =============================================================================

func _build_silhouettes() -> void:
	var hr := room_size * 0.5
	# (nivel, borde 0=N 1=S 2=O 3=E) fijos; la posición sobre el borde la da la seed
	var spots := [
		[1, 0], [1, 3], [1, 1],
		[2, 2], [2, 1],
		[3, 0], [3, 2],
	]
	var rim_count := 0
	for s in spots:
		var level: int = s[0]
		var edge: int = s[1]
		var base_y := PLAY_H + (level - 1) * LEVEL_H + SLAB_T
		var along := rng.randf_range(-hr + 1.5, hr - 1.5)
		var pos := Vector3.ZERO
		var face := 0.0
		match edge:
			0:
				pos = Vector3(along, base_y, -hr - 0.65)
				face = PI
			1:
				pos = Vector3(along, base_y, hr + 0.65)
				face = 0.0
			2:
				pos = Vector3(-hr - 0.65, base_y, along)
				face = -PI * 0.5
			3:
				pos = Vector3(hr + 0.65, base_y, along)
				face = PI * 0.5
		_create_silhouette(pos, face)
		# Resplandor rojo de contraluz detrás de las figuras: sin esto son
		# invisibles contra la penumbra -- el contraluz es lo que las delata
		if rim_count < 4:
			var back := (Vector3(0, 0, -1.4) if edge == 0 else Vector3(0, 0, 1.4) if edge == 1 else Vector3(-1.4, 0, 0) if edge == 2 else Vector3(1.4, 0, 0))
			_add_omni(pos + back + Vector3(0, 1.6, 0), Color(0.95, 0.1, 0.08), 0.85, 5.0)
			rim_count += 1

	# Una figura más, parada en el medio de la pasarela del nivel 2
	_create_silhouette(Vector3(rng.randf_range(-5.0, 5.0), PLAY_H + LEVEL_H + SLAB_T, 3.0 - 0.55), 0.0)


## Figura humana simplificada: torso apenas inclinado hacia adelante (apoyada
## en la baranda) + cabeza. Negro sin sombreado, sin colisión.
func _create_silhouette(base_pos: Vector3, face_y: float) -> void:
	_create_box(base_pos + Vector3(0, 0.98, 0), Vector3(0.52, 1.28, 0.30), mat_silhouette, false, Vector3(0.12, face_y, 0))
	_create_sphere(base_pos + Vector3(sin(face_y) * 0.12, 1.76, cos(face_y) * 0.12), 0.13, mat_silhouette)
	_create_box(base_pos + Vector3(0, 0.35, 0), Vector3(0.4, 0.75, 0.26), mat_silhouette, false, Vector3(0, face_y, 0))


# =============================================================================
# ZONA CENTRAL: PISTA DE BAILE + DJ SET (el atrio)
# =============================================================================

func _build_dance_atrium(pos: Vector3) -> void:
	# --- Piso LED estilo disco, centrado y con lugar libre alrededor ---
	var tile := 2.0
	var tiles := 6
	var span := tile * tiles
	var start := -span * 0.5 + tile * 0.5
	var tile_colors := [
		Color(0.9, 0.1, 0.5), Color(0.15, 0.85, 0.95),
		Color(0.6, 0.15, 1.0), Color(0.95, 0.25, 0.15),
	]
	for ix in tiles:
		for iz in tiles:
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			var tile_mat := _emissive(c * 0.85, c, 1.25)
			_create_box(pos + Vector3(start + ix * tile, 0.03, start + iz * tile + 0.5), Vector3(tile - 0.08, 0.06, tile - 0.08), tile_mat, false)

	# --- Cabina del DJ, contra el muro norte, corrida al este (la abertura
	# norte quedó corrida al oeste justamente para esto) ---
	var bx := 4.0
	var bz := -9.0
	_create_box(pos + Vector3(bx, 0.5, bz), Vector3(6.0, 1.0, 2.4), mat_dark_steel)
	_create_box(pos + Vector3(bx, 1.06, bz), Vector3(5.4, 0.12, 1.9), mat_rust_metal)
	# Bandejas + displays
	for dx in [-1.1, 0.0, 1.1]:
		_create_box(pos + Vector3(bx + dx, 1.17, bz), Vector3(0.5, 0.1, 0.42), mat_dark_steel, false)
		_create_box(pos + Vector3(bx + dx, 1.23, bz + 0.14), Vector3(0.3, 0.03, 0.09), mat_neon_cyan, false)
	# Panel frontal magenta de la cabina (la cara que ve toda la pista)
	_create_box(pos + Vector3(bx, 0.55, bz + 1.26), Vector3(5.8, 0.85, 0.08), mat_neon_magenta, false)
	_add_omni(pos + Vector3(bx, 2.6, bz + 0.4), Color(1.0, 0.15, 0.6), 1.5, 9.5)

	# Música del DJ: audio 3D posicional, se re-loopea sola.
	if club_music != null:
		var music_player := AudioStreamPlayer3D.new()
		music_player.stream = club_music
		music_player.unit_size = 22.0
		music_player.max_db = 3.0
		add_child(music_player)
		music_player.position = pos + Vector3(bx, 1.5, bz)
		music_player.play()
		music_player.finished.connect(func(): music_player.play())

	# --- Torres de parlantes flanqueando la cabina ---
	for sx in [0.4, 7.6]:
		_create_box(pos + Vector3(sx, 1.2, bz), Vector3(1.2, 2.4, 1.1), mat_dark_steel)
		_create_box(pos + Vector3(sx, 2.7, bz), Vector3(0.95, 0.6, 0.9), mat_dark_steel)
		var grill := mat_neon_cyan if sx < bx else mat_neon_magenta
		_create_box(pos + Vector3(sx, 1.4, bz + 0.58), Vector3(0.8, 1.5, 0.04), grill, false)

	# Subwoofers al frente de la cabina
	for sx in [2.0, 6.0]:
		_create_box(pos + Vector3(sx, 0.55, bz + 1.9), Vector3(1.3, 1.1, 1.1), mat_dark_steel)

	# --- Lásers: haces finos emisivos desde las torres, cruzando el atrio ---
	_create_beam(pos + Vector3(0.4, 3.3, bz), pos + Vector3(-8.5, 8.0, 9.0), 0.025, mat_laser_green)
	_create_beam(pos + Vector3(0.4, 3.3, bz), pos + Vector3(6.0, 9.5, 9.5), 0.025, mat_laser_green)
	_create_beam(pos + Vector3(7.6, 3.3, bz), pos + Vector3(8.5, 8.0, 9.0), 0.025, mat_neon_magenta)
	_create_beam(pos + Vector3(7.6, 3.3, bz), pos + Vector3(-6.0, 11.0, 8.0), 0.025, mat_neon_violet)

	# --- Bola de espejos colgando del techo del atrio, a media altura ---
	_create_beam(pos + Vector3(0, ROOF_Y, 0.5), pos + Vector3(0, 7.8, 0.5), 0.02, mat_dark_steel)
	_create_sphere(pos + Vector3(0, 7.2, 0.5), 0.6, mat_mirror)

	# --- Luces de show: 4 spots de color desde las columnas del atrio ---
	var show_colors := [Color(1.0, 0.15, 0.55), Color(0.15, 0.85, 0.95), Color(0.6, 0.15, 1.0), Color(0.95, 0.3, 0.1)]
	var corners := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	for i in 4:
		var spot := SpotLight3D.new()
		spot.light_color = show_colors[i]
		spot.light_energy = 1.9
		spot.spot_range = 16.0
		spot.spot_angle = 26.0
		add_child(spot)
		spot.look_at_from_position(pos + corners[i] * 9.6 + Vector3(0, 6.2, 0), pos + Vector3(0, 0.8, 0.5), Vector3.UP)

	# --- Strobe blanco: el corazón del "techno oscuro". Flash corto, pausa. ---
	var strobe := OmniLight3D.new()
	strobe.light_color = Color(1.0, 0.97, 0.92)
	strobe.light_energy = 0.0
	strobe.omni_range = 15.0
	add_child(strobe)
	strobe.position = pos + Vector3(0, 6.5, 0.5)
	var tw := create_tween().set_loops()
	tw.tween_property(strobe, "light_energy", 3.2, 0.04)
	tw.tween_property(strobe, "light_energy", 0.0, 0.06)
	tw.tween_property(strobe, "light_energy", 2.4, 0.04)
	tw.tween_property(strobe, "light_energy", 0.0, 0.07)
	tw.tween_interval(0.62)
	_fx_tweens.append(tw)

	# Relleno rojo profundo, apenas para que la pista no sea negro absoluto
	_add_omni(pos + Vector3(0, 4.5, 0.5), Color(0.85, 0.08, 0.1), 0.5, 15.0)


# =============================================================================
# BAR & LOUNGE (oeste)
# =============================================================================

func _build_bar(pos: Vector3) -> void:
	# Piso de madera gastada del sector
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_wood_floor, false)

	# Barra larga mirando al atrio, con pasillo de servicio detrás
	_create_box(pos + Vector3(3.0, 0.575, -2.0), Vector3(0.9, 1.15, 8.0), mat_aged_wood)
	_create_box(pos + Vector3(3.0, 1.19, -2.0), Vector3(1.05, 0.08, 8.4), mat_rust_metal)
	# Taburetes
	for sz in [-5.2, -3.6, -2.0, -0.4, 1.2]:
		_create_cylinder(pos + Vector3(4.3, 0.47, sz), 0.24, 0.94, mat_leather_brown)

	# Estantería de botellas contra el fondo del pasillo
	_create_box(pos + Vector3(0.8, 1.3, -2.0), Vector3(0.4, 2.6, 7.2), mat_aged_wood)
	var bottle_colors := [Color(0.2, 0.9, 0.5), Color(0.9, 0.5, 0.15), Color(0.3, 0.5, 0.95), Color(0.85, 0.2, 0.3)]
	for shelf_y in [1.25, 1.85, 2.45]:
		_create_box(pos + Vector3(1.05, shelf_y, -2.0), Vector3(0.32, 0.05, 6.8), mat_dark_steel, false)
		for b in 7:
			var bz: float = -5.0 + b * 1.0 + rng.randf_range(-0.15, 0.15)
			var bc: Color = bottle_colors[rng.randi_range(0, bottle_colors.size() - 1)]
			_create_box(pos + Vector3(1.05, shelf_y + 0.25, bz), Vector3(0.13, 0.4, 0.13), _emissive(bc, bc, 0.6), false)

	# Heladera de bebidas con frente cian
	_create_box(pos + Vector3(0.8, 0.8, 2.6), Vector3(0.8, 1.6, 1.0), mat_dark_steel)
	_create_box(pos + Vector3(1.22, 0.85, 2.6), Vector3(0.05, 1.2, 0.8), mat_neon_cyan, false)

	# Cartel de neón del bar, colgado sobre la barra
	_create_box(pos + Vector3(3.0, 3.3, -2.0), Vector3(0.1, 0.24, 5.0), mat_neon_cyan, false)
	_create_beam(pos + Vector3(3.0, PLAY_H, -4.2), pos + Vector3(3.0, 3.42, -4.2), 0.02, mat_dark_steel)
	_create_beam(pos + Vector3(3.0, PLAY_H, 0.2), pos + Vector3(3.0, 3.42, 0.2), 0.02, mat_dark_steel)

	# Lounge de sofás en la esquina suroeste
	_create_box(pos + Vector3(-6.5, 0.3, 5.5), Vector3(3.0, 0.6, 1.0), mat_leather_brown)
	_create_box(pos + Vector3(-6.5, 0.65, 6.15), Vector3(3.0, 1.3, 0.4), mat_leather_brown)
	_create_box(pos + Vector3(-8.3, 0.3, 4.0), Vector3(1.0, 0.6, 2.6), mat_leather_brown)
	_create_box(pos + Vector3(-8.9, 0.65, 4.0), Vector3(0.4, 1.3, 2.6), mat_leather_brown)
	_create_box(pos + Vector3(-6.0, 0.28, 3.6), Vector3(1.3, 0.56, 0.9), mat_aged_wood)

	_create_hanging_lamp(pos + Vector3(3.0, PLAY_H, -2.0), 1.4, Color(0.2, 0.85, 0.95), 1.2, 7.0)
	_create_hanging_lamp(pos + Vector3(-6.5, PLAY_H, 5.0), 1.6, Color(1.0, 0.55, 0.2), 0.9, 6.0)


# =============================================================================
# BAÑOS (suroeste)
# =============================================================================

func _build_banos(pos: Vector3) -> void:
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_tile_floor, false)
	# Revestimiento de azulejos en el muro sur
	_create_box(pos + Vector3(0, 1.3, 10.4), Vector3(room_size - 1.5, 2.6, 0.12), mat_tile_wall, false)

	# 4 cubículos contra el muro sur. El último tiene la puerta caída en el
	# piso: es el escondite marcado de la zona.
	var first_x := -7.0
	var cw := 1.6
	for i in 5:
		var px := first_x + i * cw
		_create_box(pos + Vector3(px, 1.15, 8.5), Vector3(0.08, 2.3, 3.0), mat_rust_metal)
	for i in 4:
		var cx := first_x + i * cw + cw * 0.5
		_create_box(pos + Vector3(cx, 0.37, 9.4), Vector3(0.5, 0.74, 0.65), mat_tile_wall)
		if i < 3:
			_create_box(pos + Vector3(cx, 1.1, 7.1), Vector3(1.4, 2.1, 0.06), mat_aged_wood)
	# La puerta del cubículo 4, arrancada, tirada en el piso
	_create_box(pos + Vector3(first_x + 3.5 * cw + 0.9, 0.05, 6.2), Vector3(1.4, 0.07, 2.1), mat_aged_wood, true, Vector3(0, 0.35, 0))

	# Lavamanos + espejo contra el muro este
	_create_box(pos + Vector3(9.7, 0.45, 0), Vector3(0.75, 0.9, 6.0), mat_concrete_wall)
	_create_box(pos + Vector3(10.15, 1.6, 0), Vector3(0.05, 1.0, 5.6), mat_mirror, false)
	for sz in [-2.0, 0.0, 2.0]:
		_create_box(pos + Vector3(9.6, 0.95, sz), Vector3(0.5, 0.12, 0.5), mat_tile_wall, false)

	# Caño con pérdida en la esquina + charco
	_create_cylinder(pos + Vector3(-9.6, 2.25, -9.6), 0.12, PLAY_H, mat_pipe_industrial)
	_create_box(pos + Vector3(-9.0, 0.015, -8.8), Vector3(2.2, 0.03, 1.8), _matte(Color(0.05, 0.09, 0.1), 0.1), false)

	# Segundo fluorescente fijo sobre los cubículos + luz pálida en lavamanos
	# (energías altas a propósito: el azulejo oscuro se come mucha luz)
	_create_fluorescent_fixture(pos + Vector3(-3.5, PLAY_H - 0.05, 5.6), Color(0.4, 0.85, 0.9), 2.2, 10.0)
	_add_omni(pos + Vector3(9.3, 2.6, 0), Color(0.7, 0.8, 0.85), 1.1, 6.0)

	# Fluorescente frío parpadeando: el clásico baño de club quemado
	var flicker := _create_fluorescent_fixture(pos + Vector3(0, PLAY_H - 0.05, 0.0), Color(0.3, 0.9, 0.95), 2.0, 10.0)
	var tw := create_tween().set_loops()
	tw.tween_interval(1.35)
	tw.tween_property(flicker, "light_energy", 0.3, 0.05)
	tw.tween_property(flicker, "light_energy", 2.0, 0.07)
	tw.tween_interval(0.22)
	tw.tween_property(flicker, "light_energy", 0.6, 0.04)
	tw.tween_property(flicker, "light_energy", 2.0, 0.05)
	_fx_tweens.append(tw)


# =============================================================================
# CHILL ROOMS / RESTING ROOMS (variant 0 = NE cálida, 1 = SE violeta)
# =============================================================================

func _build_chill_room(pos: Vector3, variant: int) -> void:
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_wood_floor, false)
	_create_box(pos + Vector3(0, 0.045, -0.8), Vector3(7.0, 0.03, 6.0), mat_fabric_red, false)

	# Sofás en U alrededor de la mesa baja
	_create_box(pos + Vector3(0, 0.28, -2.8), Vector3(4.0, 0.56, 1.1), mat_leather_brown)
	_create_box(pos + Vector3(0, 0.55, -3.45), Vector3(4.0, 1.1, 0.35), mat_leather_brown)
	_create_box(pos + Vector3(-2.9, 0.28, -0.6), Vector3(1.1, 0.56, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(-3.5, 0.55, -0.6), Vector3(0.35, 1.1, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(2.9, 0.28, -0.6), Vector3(1.1, 0.56, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(3.5, 0.55, -0.6), Vector3(0.35, 1.1, 3.2), mat_leather_brown)

	# Mesa baja (un cajón dado vuelta) con velitas encima
	_create_box(pos + Vector3(0, 0.25, -0.8), Vector3(1.3, 0.5, 0.95), mat_aged_wood)
	for c in 3:
		_create_box(pos + Vector3(-0.35 + c * 0.35, 0.55, -0.8), Vector3(0.06, 0.1, 0.06), mat_led_warm, false)

	# Rincón de colchones tirados en el piso
	_create_box(pos + Vector3(6.3, 0.14, 6.6), Vector3(2.1, 0.28, 1.5), mat_mattress)
	_create_box(pos + Vector3(7.2, 0.4, 7.6), Vector3(2.1, 0.26, 1.5), mat_mattress, true, Vector3(0, 0.5, 0))
	_create_box(pos + Vector3(5.9, 0.35, 6.2), Vector3(0.6, 0.16, 0.42), mat_fabric_red, false)

	# Guirnalda de luces contra el muro norte
	for b in 8:
		var lx: float = lerpf(-8.0, 8.0, float(b) / 7.0)
		var bulb_mat := mat_led_warm if (b % 2 == 0) == (variant == 0) else mat_neon_violet
		_create_box(pos + Vector3(lx, 2.9 + sin(float(b) * 1.7) * 0.15, -10.3), Vector3(0.09, 0.12, 0.09), bulb_mat, false)

	# Lámpara de pie + lámpara colgante sobre los sofás: los resting rooms son
	# el refugio "cálido" del club, tienen que invitar a quedarse (y verse)
	_create_cylinder(pos + Vector3(-6.0, 0.8, 5.0), 0.05, 1.6, mat_dark_steel)
	_create_sphere(pos + Vector3(-6.0, 1.75, 5.0), 0.22, mat_bulb_pale)
	var lamp_color := Color(1.0, 0.55, 0.2) if variant == 0 else Color(0.6, 0.25, 1.0)
	_add_omni(pos + Vector3(-6.0, 1.9, 5.0), lamp_color, 1.5, 9.5, true)
	var couch_color := Color(1.0, 0.45, 0.15) if variant == 0 else Color(0.75, 0.35, 1.0)
	_create_hanging_lamp(pos + Vector3(0, PLAY_H, -1.5), 1.8, couch_color, 1.2, 8.5)
	# Resplandor tenue de la guirnalda
	_add_omni(pos + Vector3(0, 2.6, -9.5), couch_color, 0.5, 6.0)

	# Pósters viejos apenas luminosos
	_create_box(pos + Vector3(-10.35, 1.9, -3.0), Vector3(0.05, 1.4, 1.0), _emissive(Color(0.5, 0.2, 0.5), Color(0.6, 0.2, 0.6), 0.35), false)
	_create_box(pos + Vector3(4.0, 2.1, -10.35), Vector3(1.0, 1.4, 0.05), _emissive(Color(0.2, 0.4, 0.6), Color(0.2, 0.5, 0.7), 0.35), false)


# =============================================================================
# SALA DE CALDERAS (este)
# =============================================================================

func _build_boiler(pos: Vector3) -> void:
	# Caldera cilíndrica gigante con boca de fuego
	_create_cylinder(pos + Vector3(3, 1.6, -3), 1.5, 3.2, mat_rust_metal)
	_create_cylinder(pos + Vector3(3, 3.8, -3), 0.35, 1.2, mat_dark_steel)
	_create_box(pos + Vector3(3, 0.6, -1.42), Vector3(0.8, 0.5, 0.14), mat_fire_orange, false)
	for g in 3:
		_create_box(pos + Vector3(2.2 + g * 0.8, 2.1, -1.55), Vector3(0.18, 0.18, 0.06), mat_led_warm, false)

	# Cañería troncal cruzando la sala + bajadas sobre el muro norte
	_create_beam(pos + Vector3(-9.5, 3.9, -3), pos + Vector3(9.5, 3.9, -3), 0.18, mat_pipe_industrial)
	for pz in [-2.0, 0.0, 2.0]:
		_create_cylinder(pos + Vector3(9.9, 2.1, pz), 0.15, 4.2, mat_pipe_industrial)

	# Tablero eléctrico con marcas de peligro
	_create_box(pos + Vector3(2, 1.4, -10.1), Vector3(1.2, 1.8, 0.35), mat_hazard_mark)
	_create_box(pos + Vector3(2.35, 1.7, -9.9), Vector3(0.12, 0.12, 0.06), mat_neon_red_dim, false)

	# Barriles de combustible apilados (el escondite queda detrás)
	var barrels := [Vector3(-6.2, 0, 6.2), Vector3(-7.2, 0, 6.8), Vector3(-6.0, 0, 7.4), Vector3(-7.0, 0, 5.6)]
	for b in barrels:
		_create_cylinder(pos + b + Vector3(0, 0.45, 0), 0.38, 0.9, mat_rust_metal)
	_create_cylinder(pos + Vector3(-6.6, 1.35, 6.5), 0.38, 0.9, mat_rust_metal)

	# Resplandor del fuego + fluorescente industrial
	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.3, 0.08)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 8.5
	fire_light.shadow_enabled = true
	add_child(fire_light)
	fire_light.position = pos + Vector3(3, 1.1, -0.6)

	_create_fluorescent_fixture(pos + Vector3(-2, PLAY_H - 0.05, 3), Color(0.4, 0.95, 0.9), 1.2, 8.0)


# =============================================================================
# DEPÓSITO DE CARGA (norte)
# =============================================================================

func _build_cargo(pos: Vector3) -> void:
	# Dos estanterías largas paralelas: el pasillo entre ambas es el escondite
	_create_pallet_rack(pos + Vector3(-2, 0, -4.5), 12.0, 3.2)
	_create_pallet_rack(pos + Vector3(-2, 0, 0.5), 12.0, 3.2)
	_create_pallet_rack(pos + Vector3(4, 0, 6.0), 7.0, 3.2)

	# Autoelevador abandonado
	_create_box(pos + Vector3(-7.5, 0.5, 5.0), Vector3(1.2, 1.0, 2.0), mat_hazard_mark)
	_create_box(pos + Vector3(-7.5, 1.35, 4.4), Vector3(1.0, 0.7, 0.15), mat_dark_steel)
	_create_box(pos + Vector3(-7.5, 1.2, 6.1), Vector3(0.18, 2.4, 0.18), mat_dark_steel)
	for fx in [-0.35, 0.35]:
		_create_box(pos + Vector3(-7.5 + fx, 0.06, 6.7), Vector3(0.12, 0.06, 1.1), mat_dark_steel)

	# Pallet envuelto en film + cajas sueltas
	_create_box(pos + Vector3(8.5, 0.65, -8.5), Vector3(1.2, 1.3, 1.2), mat_shrinkwrap)
	_create_crate_stack(pos + Vector3(-8.5, 0, -8.0), 3, true)
	_create_crate_stack(pos + Vector3(8.0, 0, 1.5), 2, true)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, -2), 1.3, Color(0.55, 0.25, 1.0), 1.2, 8.5)
	_create_fluorescent_fixture(pos + Vector3(4, PLAY_H - 0.05, 6), Color(0.4, 0.9, 0.95), 1.0, 7.0)


# =============================================================================
# TALLER (noroeste)
# =============================================================================

func _build_workshop(pos: Vector3) -> void:
	# Mesa de trabajo contra el muro norte + panel de herramientas
	_create_box(pos + Vector3(0, 0.95, -9.6), Vector3(6.5, 0.12, 1.1), mat_aged_wood)
	for lx in [-3.0, 3.0]:
		for lz in [-10.0, -9.2]:
			_create_box(pos + Vector3(lx, 0.45, lz), Vector3(0.1, 0.9, 0.1), mat_dark_steel)
	_create_box(pos + Vector3(0, 0.45, -9.6), Vector3(6.0, 0.08, 0.9), mat_dark_steel, false)
	_create_box(pos + Vector3(0, 2.2, -10.3), Vector3(6.0, 1.6, 0.08), mat_aged_wood, false)
	for t in 6:
		_create_box(pos + Vector3(-2.2 + t * 0.9, 2.2 + (0.25 if t % 2 == 0 else -0.2), -10.24), Vector3(0.12, 0.4, 0.05), mat_dark_steel, false)
	# Morsa sobre la mesa
	_create_box(pos + Vector3(-2.4, 1.15, -9.6), Vector3(0.45, 0.3, 0.35), mat_rust_metal)

	# Compresor + carro de herramientas
	_create_cylinder(pos + Vector3(6.5, 0.8, -6.0), 0.5, 1.6, mat_pipe_industrial)
	_create_box(pos + Vector3(6.5, 1.7, -6.0), Vector3(0.5, 0.3, 0.4), mat_dark_steel)
	_create_box(pos + Vector3(2.0, 0.5, -4.0), Vector3(0.9, 1.0, 1.2), mat_rust_metal)
	_create_chair(pos + Vector3(-1.0, 0, -8.2), PI)

	# Tambores de aceite en la esquina sureste (escondite detrás)
	for d in [Vector3(7.3, 0, 7.3), Vector3(8.2, 0, 6.6), Vector3(6.7, 0, 8.3)]:
		_create_cylinder(pos + d + Vector3(0, 0.45, 0), 0.4, 0.9, mat_rust_metal)

	# Cadenas colgando del techo
	for c in 3:
		var cx := rng.randf_range(-3.0, 4.0)
		var cz := rng.randf_range(-2.0, 3.0)
		_create_beam(pos + Vector3(cx, PLAY_H, cz), pos + Vector3(cx, PLAY_H - rng.randf_range(1.6, 2.4), cz), 0.03, mat_dark_steel)

	_create_fluorescent_fixture(pos + Vector3(0, PLAY_H - 0.05, -6), Color(0.4, 0.95, 0.9), 1.3, 8.0)
	_create_hanging_lamp(pos + Vector3(5, PLAY_H, 5), 1.5, Color(1.0, 0.6, 0.25), 0.8, 6.0)


# =============================================================================
# ENTRADA / DOCK DE CARGA (sur) -- spawn del Atrapador + escalera derrumbada
# =============================================================================

func _build_entrance(pos: Vector3) -> void:
	# Portón de carga cerrado (por acá "entraba" la gente: ahora sellado)
	_create_box(pos + Vector3(0, 2.1, 10.55), Vector3(7.0, 4.2, 0.22), mat_dark_steel)
	for rib in 6:
		_create_box(pos + Vector3(0, 0.6 + rib * 0.6, 10.42), Vector3(7.0, 0.1, 0.05), mat_rust_metal, false)
	_create_box(pos + Vector3(0, 0.02, 9.4), Vector3(7.0, 0.04, 1.4), mat_hazard_mark, false)
	_create_box(pos + Vector3(0, 4.15, 10.4), Vector3(1.2, 0.35, 0.1), mat_exit_green, false)

	# Cabina de seguridad/tickets con monitor CRT muerto-vivo
	_create_box(pos + Vector3(-7, 1.25, 4), Vector3(2.2, 2.5, 2.2), mat_concrete_wall)
	_create_box(pos + Vector3(-7, 1.7, 5.12), Vector3(1.4, 0.9, 0.06), mat_crt_phosphor, false)
	_add_omni(pos + Vector3(-7, 1.9, 5.6), Color(0.25, 0.85, 0.4), 0.5, 3.5)

	# Vallas de fila hacia la boca del atrio
	for side in [-1.6, 1.6]:
		var prev := Vector3.ZERO
		for i in 4:
			var post := pos + Vector3(side, 0, 8.0 - i * 1.5)
			_create_cylinder(post + Vector3(0, 0.5, 0), 0.06, 1.0, mat_dark_steel)
			if i > 0:
				_create_beam(prev + Vector3(0, 0.92, 0), post + Vector3(0, 0.92, 0), 0.03, mat_rust_metal)
			prev = post

	# Grafitis de neón en el muro oeste (dos tajos cruzados magenta/cian)
	_create_box(pos + Vector3(-10.4, 1.8, -2.0), Vector3(0.06, 1.8, 0.3), mat_neon_magenta, false, Vector3(0.5, 0, 0))
	_create_box(pos + Vector3(-10.4, 1.8, -2.0), Vector3(0.06, 1.8, 0.3), mat_neon_cyan, false, Vector3(-0.5, 0, 0))

	# --- ESCALERA DERRUMBADA contra el muro este: sube 8 escalones y muere en
	# escombros + reja. Cuenta la historia de los pisos de arriba y deja claro
	# que no se sube. Colisión invisible por si alguien lo intenta igual. ---
	var rise := 0.34
	for i in 8:
		var h := rise * (i + 1)
		_create_box(pos + Vector3(9.3, h * 0.5, 7.0 - i * 0.6), Vector3(2.2, h, 0.6), mat_concrete_wall)
	# Escombros al tope
	for k in 5:
		var s := rng.randf_range(0.35, 0.85)
		_create_box(pos + Vector3(9.3 + rng.randf_range(-0.7, 0.7), 2.9 + k * 0.18, 1.6 + rng.randf_range(-0.5, 0.5)), Vector3(s, s * 0.7, s), mat_rubble, true, Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0, PI), 0))
	# Reja caída tapando el hueco
	_create_box(pos + Vector3(9.3, 3.6, 2.2), Vector3(2.2, 1.9, 0.08), mat_grate, false, Vector3(-0.35, 0, 0))
	# Red de seguridad invisible
	_create_invisible_barrier(pos + Vector3(9.3, 3.9, 1.6), Vector3(2.6, 2.6, 2.0))
	# Luz roja sucia marcando la escalera muerta
	_add_omni(pos + Vector3(9.3, 3.8, 4.5), Color(0.95, 0.15, 0.1), 1.0, 7.0)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, 5.5), 1.4, Color(0.75, 0.8, 0.95), 1.4, 9.0)
	_create_hanging_lamp(pos + Vector3(-5.5, PLAY_H, 0.5), 1.6, Color(0.9, 0.5, 0.2), 0.9, 6.5)


# =============================================================================
# SPAWNS
# =============================================================================

func _setup_spawns() -> void:
	# El Atrapador arranca en la entrada, del lado opuesto del edificio a la
	# mayoría de los escondites.
	seeker_spawn_point = _zone_centers["entrance"] + Vector3(0, 0.8, 2.0)

	hider_spawn_points.clear()
	for key in ZONE_HIDE_OFFSETS.keys():
		hider_spawn_points.append(_zone_centers[key] + ZONE_HIDE_OFFSETS[key])
	_seeded_shuffle(hider_spawn_points)


## Fisher-Yates con NUESTRA rng seedeada (no Array.shuffle(), que usa el RNG
## global y daría un resultado distinto en cada cliente).
func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# =============================================================================
# HELPERS DE PROPS COMPUESTOS
# =============================================================================

func _create_crate_stack(base: Vector3, count: int, with_collision: bool) -> void:
	for i in count:
		var s := 1.15 - i * 0.18
		var mat := mat_aged_wood if i % 2 == 0 else mat_dark_steel
		_create_box(base + Vector3(rng.randf_range(-0.1, 0.1), 0.28 + i * 0.52, rng.randf_range(-0.1, 0.1)), Vector3(s, 0.52, s), mat, with_collision, Vector3(0, rng.randf_range(-0.3, 0.3), 0))


func _create_pallet_rack(pos: Vector3, length: float, height: float) -> void:
	var w := 0.95
	for dx in [-length * 0.5, 0.0, length * 0.5]:
		for dz in [-w * 0.5, w * 0.5]:
			_create_box(pos + Vector3(dx, height * 0.5, dz), Vector3(0.09, height, 0.09), mat_rust_metal)
	for h in [0.75, 1.65, 2.55]:
		_create_box(pos + Vector3(0, h, 0), Vector3(length, 0.06, w), mat_rust_metal)
		_create_box(pos + Vector3(length * 0.28, h + 0.28, 0), Vector3(0.7, 0.5, 0.65), mat_aged_wood)
		_create_box(pos + Vector3(-length * 0.22, h + 0.25, 0), Vector3(0.55, 0.45, 0.55), mat_aged_wood)


func _create_chair(pos: Vector3, rot_y: float) -> void:
	var base := Node3D.new()
	base.position = pos
	base.rotation.y = rot_y
	add_child(base)
	_add_primitive_box(base, Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), mat_aged_wood)
	_add_primitive_box(base, Vector3(0, 0.75, -0.2), Vector3(0.45, 0.55, 0.06), mat_aged_wood)
	for dx in [-0.18, 0.18]:
		for dz in [-0.18, 0.18]:
			_add_primitive_box(base, Vector3(dx, 0.22, dz), Vector3(0.05, 0.44, 0.05), mat_dark_steel)


func _create_hanging_lamp(pos: Vector3, cable_len: float, color: Color, energy: float, light_range: float) -> void:
	_create_cylinder(pos - Vector3(0, cable_len * 0.5, 0), 0.02, cable_len, mat_dark_steel, false)
	_create_cylinder(pos - Vector3(0, cable_len, 0), 0.35, 0.2, mat_rust_metal, false)
	_create_cylinder(pos - Vector3(0, cable_len + 0.05, 0), 0.12, 0.1, mat_bulb_pale, false)
	_add_omni(pos - Vector3(0, cable_len + 0.25, 0), color, energy, light_range, true)


func _create_fluorescent_fixture(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	_create_box(pos, Vector3(0.3, 0.1, 1.8), mat_dark_steel, false)
	_create_box(pos - Vector3(0, 0.06, 0), Vector3(0.12, 0.05, 1.6), mat_neon_cyan, false)
	return _add_omni(pos - Vector3(0, 0.3, 0), color, energy, light_range, true)


func _add_omni(pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool = false) -> OmniLight3D:
	var omni := OmniLight3D.new()
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = light_range
	omni.shadow_enabled = shadows
	add_child(omni)
	omni.position = pos
	return omni


# =============================================================================
# PRIMITIVAS
# =============================================================================

func _create_box(center: Vector3, size: Vector3, mat: StandardMaterial3D, has_collision: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	if has_collision:
		var body := StaticBody3D.new()
		body.position = center
		body.rotation = rot
		add_child(body)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		return body
	else:
		var mi := MeshInstance3D.new()
		mi.position = center
		mi.rotation = rot
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		return mi


func _create_cylinder(center: Vector3, radius: float, height: float, mat: StandardMaterial3D, has_collision: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	if has_collision:
		var body := StaticBody3D.new()
		body.position = center
		body.rotation = rot
		add_child(body)

		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height
		mi.mesh = cyl
		mi.material_override = mat
		body.add_child(mi)

		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		col.shape = shape
		body.add_child(col)
		return body
	else:
		var mi := MeshInstance3D.new()
		mi.position = center
		mi.rotation = rot
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height
		mi.mesh = cyl
		mi.material_override = mat
		add_child(mi)
		return mi


func _create_sphere(center: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.position = center
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	mi.mesh = sph
	mi.material_override = mat
	add_child(mi)
	return mi


## Cilindro entre dos puntos arbitrarios: lásers, cables colgando, tensores de
## pasarela, cañerías cruzadas, sogas de las vallas. Sin colisión.
func _create_beam(from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mid := (from + to) * 0.5
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = mat
	add_child(mi)
	var dir := from.direction_to(to)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.look_at_from_position(mid, to, up)
	mi.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


## Colisión sin malla: red de seguridad (p.ej. arriba de la escalera rota).
func _create_invisible_barrier(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


func _add_primitive_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
