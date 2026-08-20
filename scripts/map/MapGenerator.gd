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

# --- Caras interiores de los muros, en coordenadas LOCALES de zona -----------
# Todo prop "montado en pared" tiene que apoyarse en estas caras. El muro
# exterior es de ladrillo de 0.6 centrado en el borde del edificio (±33), así
# que su cara interior cae en ±10.7 locales; los tabiques interiores son de
# 0.3 y su cara cae en ±10.85. Clavar 10.1/10.3 "a ojo" dejaba carteles,
# espejos y tableros flotando hasta 0.7m en el aire.
const FACE_EXT := 10.7     # cara interior del muro exterior de ladrillo
const FACE_BASE := 10.575  # cara del zócalo de hormigón (solo hasta y = 1.2)
const FACE_PART := 10.85   # cara interior de un tabique de 0.3

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
var mat_rubber_black: StandardMaterial3D
var mat_paint_worn: StandardMaterial3D

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
	mat_rubber_black = _matte(Color(0.05, 0.05, 0.055), 0.95)
	mat_paint_worn = _matte(Color(0.28, 0.30, 0.31), 0.8)

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
	"banos": Vector3(-1.4, 0.8, 8.2),    # último cubículo (el de la puerta caída)
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
	# Los paneles van EMBUTIDOS en la cara interior del muro (32.7), no 0.25m
	# adelante como estaban: así el marco no flota sobre el ladrillo.
	var face := half - 0.05
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

		# Clutter abandonado cerca del borde: pilas de cajas, barriles, pallets
		# y bobinas de cable. Sin colisión (nadie sube), así que sale gratis y
		# es lo que le saca la sensación de "losa vacía" a los niveles.
		for k in 6:
			var edge := rng.randi_range(0, 3)
			var along := rng.randf_range(-hr + 2.0, hr - 2.0)
			var depth := rng.randf_range(1.2, 4.5)
			var p := Vector3.ZERO
			match edge:
				0: p = Vector3(along, rail_base, -hr - depth)
				1: p = Vector3(along, rail_base, hr + depth)
				2: p = Vector3(-hr - depth, rail_base, along)
				3: p = Vector3(hr + depth, rail_base, along)
			var roll := rng.randf()
			if roll < 0.42:
				_create_crate_stack(p, rng.randi_range(1, 3), false)
			elif roll < 0.68:
				_create_cylinder(p + Vector3(0, 0.45, 0), 0.36, 0.9, mat_rust_metal, false)
			elif roll < 0.86:
				# Pallets tirados de canto contra la baranda
				_create_box(p + Vector3(0, 0.6, 0), Vector3(1.2, 1.15, 0.12), mat_aged_wood, false, Vector3(0, rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.2)))
			else:
				# Bobina de cable de obra
				_create_cylinder(p + Vector3(0, 0.55, 0), 0.55, 0.5, mat_aged_wood, false, Vector3(0, 0, PI * 0.5))

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

	# Cables sueltos colgando del techo hacia el vacío. Se esquiva la franja de
	# la pasarela del nivel 3 (x = -3.0 ± 0.9 + barandas): si no, los cables la
	# atraviesan y se ven "clavados" en la rejilla.
	for k in 5:
		var cx := rng.randf_range(-8.5, 8.5)
		var cz := rng.randf_range(-8.5, 8.5)
		if absf(cx + 3.0) < 1.6:
			cx += 1.6 if cx > -3.0 else -1.6
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
	# --- Piso LED estilo disco: 4 materiales COMPARTIDOS que pulsan en
	# secuencia (chase de 4 tiempos). Antes eran 36 materiales fijos y el piso
	# quedaba muerto; ahora son 4 tweens en total para las 36 baldosas. ---
	var tile := 2.0
	var tiles := 6
	var span := tile * tiles
	var start := -span * 0.5 + tile * 0.5
	var tile_colors := [
		Color(0.9, 0.1, 0.5), Color(0.15, 0.85, 0.95),
		Color(0.6, 0.15, 1.0), Color(0.95, 0.25, 0.15),
	]
	var tile_mats: Array[StandardMaterial3D] = []
	for ci in tile_colors.size():
		var c: Color = tile_colors[ci]
		tile_mats.append(_emissive(c * 0.85, c, 0.55))
	for ix in tiles:
		for iz in tiles:
			var mi := (ix + iz) % tile_mats.size()
			_create_box(pos + Vector3(start + ix * tile, 0.03, start + iz * tile + 0.5), Vector3(tile - 0.08, 0.06, tile - 0.08), tile_mats[mi], false)

	# El chase: en cada tiempo un color sube a tope y los otros tres caen.
	# Los 4 tweens duran lo mismo, así no se desfasan con el correr de la noche.
	var beat := 0.22
	var floor_quads := [Vector3(-3.5, 0, -2.5), Vector3(3.5, 0, -2.5), Vector3(3.5, 0, 3.5), Vector3(-3.5, 0, 3.5)]
	for m in tile_mats.size():
		var ttw := create_tween().set_loops()
		# Omni tenue por cuadrante: sin esto el pulso del piso no baña a nadie
		# (la emisión sola no ilumina). Late en el mismo tiempo que su color.
		var quad_light := _add_omni(pos + floor_quads[m] + Vector3(0, 0.9, 0), tile_colors[m], 0.0, 8.5)
		var ltw := create_tween().set_loops()
		for step in tile_mats.size():
			var target := 3.4 if step == m else 0.5
			var lit := 1.15 if step == m else 0.08
			ttw.tween_property(tile_mats[m], "emission_energy_multiplier", target, beat)
			ltw.tween_property(quad_light, "light_energy", lit, beat)
		_fx_tweens.append(ttw)
		_fx_tweens.append(ltw)

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

	# --- Lásers: dos abanicos montados en las torres, barriendo el atrio en
	# péndulo (antes eran 4 haces sueltos y clavados en el aire). ---
	_create_laser_fan(pos + Vector3(0.4, 3.35, bz + 0.15), -0.32, mat_laser_green, 4, 0.45, 3.1)
	_create_laser_fan(pos + Vector3(7.6, 3.35, bz + 0.15), 0.34, mat_neon_magenta, 4, 0.52, 2.4)

	# --- Bola de espejos girando: el giro se lee por las facetas y, sobre
	# todo, por los dos haces angostos que cuelgan de ella y barren la pista ---
	_create_beam(pos + Vector3(0, ROOF_Y, 0.5), pos + Vector3(0, 7.8, 0.5), 0.02, mat_dark_steel)
	var ball := Node3D.new()
	ball.position = pos + Vector3(0, 7.2, 0.5)
	add_child(ball)
	_add_mesh_sphere(ball, Vector3.ZERO, 0.6, mat_mirror)
	for f in 12:
		var fa := TAU * float(f) / 12.0
		var fy := sin(float(f) * 2.3) * 0.36
		var fr := sqrt(maxf(0.36 - fy * fy, 0.02))
		_add_mesh_box(ball, Vector3(cos(fa) * fr, fy, sin(fa) * fr), Vector3(0.17, 0.17, 0.04), mat_bulb_pale, Vector3(0, -fa, 0))
	for bs in [-1.0, 1.0]:
		var bspot := SpotLight3D.new()
		bspot.light_color = Color(0.85, 0.9, 1.0)
		bspot.light_energy = 2.4
		bspot.spot_range = 13.0
		bspot.spot_angle = 8.0
		ball.add_child(bspot)
		bspot.position = Vector3(bs * 0.5, -0.15, 0)
		bspot.rotation = Vector3(-1.1, bs * PI * 0.5, 0)
	var btw := create_tween().set_loops()
	btw.tween_property(ball, "rotation:y", TAU, 9.0).from(0.0)
	_fx_tweens.append(btw)

	# --- Luces de show: 4 cabezales móviles colgados de las columnas del
	# atrio. Cada uno barre en péndulo con período distinto, así el patrón
	# nunca se repite igual y la pista deja de verse "iluminada de fábrica". ---
	var show_colors := [Color(1.0, 0.15, 0.55), Color(0.15, 0.85, 0.95), Color(0.6, 0.15, 1.0), Color(0.95, 0.3, 0.1)]
	var corners := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	var sweeps := [0.72, 0.58, 0.8, 0.64]
	var periods := [2.6, 3.3, 2.9, 3.7]
	for i in 4:
		var mount: Vector3 = pos + corners[i] * 10.3 + Vector3(0, 6.4, 0)
		# Cada cabezal apunta al cuadrante OPUESTO: así el haz cruza la pista
		# entera y en el barrido lame también los props del perímetro (mesas,
		# tarimas, torres de PA), que si no quedaban invisibles en la penumbra.
		var aim := pos + Vector3(-corners[i].x * 4.5, 0.9, -corners[i].z * 4.5 + 0.5)
		_create_moving_head(mount, aim, show_colors[i], 2.6, sweeps[i], periods[i])

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

	# --- Relleno del atrio ---------------------------------------------------
	# El piso LED ocupa 12x12 y dejaba ~5m de hormigón pelado contra los muros.
	# Todo lo que va acá respeta las 4 bocas del atrio (norte x -9..-4, sur
	# x ±3.5, este/oeste z ±2.5) y el escondite de la zona (9.2, -9.2).
	for tp in [Vector3(-8.6, 0, -4.2), Vector3(-8.2, 0, 4.8), Vector3(8.6, 0, 4.6), Vector3(8.9, 0, -4.4)]:
		_create_high_table(pos + tp, rng.randi_range(1, 3))

	# Tarimas go-gó en dos esquinas: dan verticalidad y tapan la vista en
	# diagonal sin cerrar ninguna línea de visión larga del Atrapador.
	_create_gogo_platform(pos + Vector3(-10.0, 0, -9.3), 1.7, mat_neon_magenta)
	_create_gogo_platform(pos + Vector3(9.7, 0, 9.7), 1.7, mat_neon_cyan)

	# Flight cases de gira apilados al costado de la cabina
	_create_flight_case(pos + Vector3(9.5, 0, -6.0), Vector3(1.1, 0.75, 0.8), 0.18)
	_create_flight_case(pos + Vector3(10.2, 0, -4.3), Vector3(0.9, 1.05, 0.75), -0.32)
	_create_flight_case(pos + Vector3(9.4, 0.77, -6.0), Vector3(0.95, 0.5, 0.7), -0.1)

	# Torres de PA contra el muro oeste (el club sonaba fuerte en serio)
	for pz in [-6.5, 6.5]:
		_create_box(pos + Vector3(-10.25, 0.85, pz), Vector3(1.1, 1.7, 1.2), mat_dark_steel)
		_create_box(pos + Vector3(-10.25, 2.15, pz), Vector3(0.95, 0.9, 1.0), mat_dark_steel)
		_create_box(pos + Vector3(-9.66, 1.9, pz), Vector3(0.04, 0.7, 0.7), mat_neon_cyan, false)

	# Vallas de contención tumbadas + basura de after
	_create_fallen_barrier(pos + Vector3(-7.5, 0, 9.3), 0.42)
	_create_fallen_barrier(pos + Vector3(6.8, 0, 8.6), -1.15)
	_create_debris_scatter(pos + Vector3(-8.0, 0, 0.5), 2.4, 7)
	_create_debris_scatter(pos + Vector3(7.8, 0, 7.6), 2.4, 7)
	_create_debris_scatter(pos + Vector3(0.0, 0, 8.6), 3.2, 9)


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

	# --- Relleno de la mitad norte y del centro (era piso de madera pelado) ---
	# Mesa de pool despedazada: el landmark que le faltaba al sector norte.
	var pool := pos + Vector3(-6.0, 0, -8.0)
	_create_box(pool + Vector3(0, 0.72, 0), Vector3(1.55, 0.18, 2.85), mat_tile_floor)
	for rail in [Vector3(0.82, 0.85, 0.0), Vector3(-0.82, 0.85, 0.0)]:
		_create_box(pool + rail, Vector3(0.16, 0.14, 2.85), mat_aged_wood)
	for rail_z in [-1.5, 1.5]:
		_create_box(pool + Vector3(0, 0.85, rail_z), Vector3(1.8, 0.14, 0.16), mat_aged_wood)
	for lx in [-0.6, 0.6]:
		for lz in [-1.15, 1.15]:
			_create_box(pool + Vector3(lx, 0.32, lz), Vector3(0.18, 0.64, 0.18), mat_aged_wood)
	for b in 4:
		_create_sphere(pool + Vector3(rng.randf_range(-0.55, 0.55), 0.87, rng.randf_range(-1.15, 1.15)), 0.055, mat_bulb_pale)
	_create_beam(pool + Vector3(-0.5, 0.86, -1.2), pool + Vector3(0.35, 0.9, 1.0), 0.03, mat_aged_wood)
	_create_hanging_lamp(pool + Vector3(0, PLAY_H, 0), 2.2, Color(0.95, 0.85, 0.6), 0.9, 5.5)

	# Mesas con sillas repartidas por el sector
	_create_table_set(pos + Vector3(-3.2, 0, -8.6), 0.35)
	_create_table_set(pos + Vector3(-8.2, 0, -3.4), -0.5)
	_create_table_set(pos + Vector3(-4.6, 0, 0.8), 0.9)

	# Depósito improvisado contra el muro oeste: cajones de botellas y barriles
	_create_bottle_crates(pos + Vector3(-10.1, 0, -6.0), 3)
	_create_bottle_crates(pos + Vector3(-10.05, 0, -4.7), 2)
	for kz in [-8.6, -7.7]:
		_create_cylinder(pos + Vector3(-10.15, 0.44, kz), 0.34, 0.88, mat_dark_steel)
	_create_cylinder(pos + Vector3(-9.35, 0.44, -8.2), 0.34, 0.88, mat_dark_steel)

	# Rockola muerta contra el tabique norte (fuera del vano, que va en x ±1.5)
	_create_box(pos + Vector3(4.2, 0.85, -10.5), Vector3(1.3, 1.7, 0.7), mat_aged_wood)
	_create_box(pos + Vector3(4.2, 1.35, -10.13), Vector3(1.0, 0.6, 0.06), _emissive(Color(0.5, 0.15, 0.35), Color(0.7, 0.2, 0.5), 0.5), false)
	_add_omni(pos + Vector3(4.2, 1.5, -9.7), Color(0.85, 0.25, 0.6), 0.45, 4.0)

	_create_debris_scatter(pos + Vector3(-5.5, 0, -5.0), 2.6, 8)
	_create_debris_scatter(pos + Vector3(-2.0, 0, 5.5), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(3.0, PLAY_H, -2.0), 1.4, Color(0.2, 0.85, 0.95), 1.2, 7.0)
	_create_hanging_lamp(pos + Vector3(-6.5, PLAY_H, 5.0), 1.6, Color(1.0, 0.55, 0.2), 0.9, 6.0)
	_create_fluorescent_fixture(pos + Vector3(-4.0, PLAY_H - 0.05, -8.0), Color(0.45, 0.9, 0.95), 0.9, 7.5)


# =============================================================================
# BAÑOS (suroeste)
# =============================================================================

func _build_banos(pos: Vector3) -> void:
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_tile_floor, false)
	# Revestimiento de azulejos en el muro sur (apoyado en la cara real del
	# muro exterior, no 0.24 adelante como estaba)
	_create_box(pos + Vector3(0, 1.3, FACE_EXT - 0.06), Vector3(room_size - 1.5, 2.6, 0.12), mat_tile_wall, false)

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

	# Lavamanos + espejo contra el tabique este. OJO: el vano baños<->entrada
	# cae en z ±1.5 de esta misma pared, así que el mueble arranca en z = 2.25
	# (antes iba de -3 a 3 y dejaba la puerta detrás de un espejo, con 0.77m
	# de paso). Y todo apoya en FACE_PART, no en 10.15.
	var sink_z := 5.0
	_create_box(pos + Vector3(FACE_PART - 0.375, 0.45, sink_z), Vector3(0.75, 0.9, 5.5), mat_concrete_wall)
	_create_box(pos + Vector3(FACE_PART - 0.025, 1.6, sink_z), Vector3(0.05, 1.0, 5.1), mat_mirror, false)
	for sz in [-1.7, 0.0, 1.7]:
		_create_box(pos + Vector3(FACE_PART - 0.42, 0.95, sink_z + sz), Vector3(0.5, 0.12, 0.5), mat_tile_wall, false)
		_create_cylinder(pos + Vector3(FACE_PART - 0.12, 1.06, sink_z + sz), 0.03, 0.22, mat_pipe_industrial, false)

	# Caño con pérdida arrimado a la esquina noroeste + charco
	_create_cylinder(pos + Vector3(-FACE_EXT + 0.14, 2.25, -FACE_PART + 0.14), 0.12, PLAY_H, mat_pipe_industrial)
	_create_box(pos + Vector3(-9.0, 0.015, -8.8), Vector3(2.2, 0.03, 1.8), _matte(Color(0.05, 0.09, 0.1), 0.1), false)

	# --- Relleno de la mitad norte (era todo azulejo pelado) -----------------
	# Mingitorios sobre el muro oeste (exterior), con tabiques separadores
	for uz in [-6.2, -5.1, -4.0]:
		_create_urinal(pos + Vector3(-FACE_EXT, 0, uz), 1.0)
	for dz in [-6.75, -5.65, -4.55, -3.45]:
		_create_box(pos + Vector3(-FACE_EXT + 0.3, 1.25, dz), Vector3(0.6, 1.3, 0.05), mat_tile_wall)
	_create_beam(pos + Vector3(-FACE_EXT + 0.12, 1.95, -6.9), pos + Vector3(-FACE_EXT + 0.12, 1.95, -3.3), 0.045, mat_pipe_industrial)

	# Carro de limpieza abandonado en el medio + cubículo derrumbado al oeste
	_create_cleaning_cart(pos + Vector3(-5.2, 0, 3.4), 0.6)
	_create_rubble_pile(pos + Vector3(-9.2, 0, 8.2), 5, 0.9)
	_create_box(pos + Vector3(-10.35, 1.05, 6.4), Vector3(0.12, 2.1, 1.4), mat_rust_metal, true, Vector3(0, 0, -0.22))
	_create_box(pos + Vector3(-8.4, 0.06, 4.9), Vector3(1.4, 0.08, 2.1), mat_aged_wood, true, Vector3(0, 0.8, 0))

	# Tacho volcado, secamanos roto y baldosas sueltas
	_create_cylinder(pos + Vector3(-2.0, 0.3, 1.2), 0.32, 0.9, mat_dark_steel, true, Vector3(PI * 0.5, 0.4, 0))
	_create_box(pos + Vector3(-FACE_EXT + 0.11, 1.35, 0.6), Vector3(0.22, 0.35, 0.3), mat_paint_worn, false)
	_create_debris_scatter(pos + Vector3(-4.0, 0, -1.0), 3.2, 9)
	_create_debris_scatter(pos + Vector3(3.5, 0, -6.0), 3.0, 7)

	# Rejilla de piso en el centro (el agua va a algún lado)
	_create_box(pos + Vector3(0.5, 0.045, 0.5), Vector3(0.6, 0.03, 0.6), mat_grate, false)

	# Segundo fluorescente fijo sobre los cubículos + luz pálida en lavamanos
	# (energías altas a propósito: el azulejo oscuro se come mucha luz)
	_create_fluorescent_fixture(pos + Vector3(-3.5, PLAY_H - 0.05, 5.6), Color(0.4, 0.85, 0.9), 2.2, 10.0)
	_add_omni(pos + Vector3(9.3, 2.6, sink_z), Color(0.7, 0.8, 0.85), 1.1, 6.0)
	_create_fluorescent_fixture(pos + Vector3(-7.0, PLAY_H - 0.05, -5.0), Color(0.35, 0.85, 0.9), 1.4, 8.0)

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
	# El NE es una esquina del edificio (muro norte de ladrillo) y el SE da al
	# pasillo (tabique): la cara donde apoyan guirnalda y póster cambia.
	var north_face := -FACE_EXT if variant == 0 else -FACE_PART
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

	# Guirnalda de luces colgada del muro norte: las bombitas apoyan en la cara
	# del muro y el cable las une (antes flotaban a 0.3-0.55m, sueltas).
	var garland_y := 3.05
	var bulb_z := north_face + 0.05
	_create_beam(pos + Vector3(-8.4, garland_y + 0.28, bulb_z), pos + Vector3(0.0, garland_y - 0.05, bulb_z), 0.02, mat_dark_steel)
	_create_beam(pos + Vector3(0.0, garland_y - 0.05, bulb_z), pos + Vector3(8.4, garland_y + 0.28, bulb_z), 0.02, mat_dark_steel)
	for b in 8:
		var lx: float = lerpf(-8.0, 8.0, float(b) / 7.0)
		var bulb_mat := mat_led_warm if (b % 2 == 0) == (variant == 0) else mat_neon_violet
		_create_box(pos + Vector3(lx, garland_y + sin(float(b) * 1.7) * 0.15, bulb_z), Vector3(0.09, 0.12, 0.09), bulb_mat, false)

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

	# Pósters viejos apenas luminosos, pegados a la cara real del muro
	_create_box(pos + Vector3(-FACE_PART + 0.025, 1.9, -3.0), Vector3(0.05, 1.4, 1.0), _emissive(Color(0.5, 0.2, 0.5), Color(0.6, 0.2, 0.6), 0.35), false)
	_create_box(pos + Vector3(4.0, 2.1, north_face + 0.025), Vector3(1.0, 1.4, 0.05), _emissive(Color(0.2, 0.4, 0.6), Color(0.2, 0.5, 0.7), 0.35), false)
	_create_box(pos + Vector3(-FACE_PART + 0.025, 2.2, 4.5), Vector3(0.05, 1.1, 0.8), _emissive(Color(0.45, 0.35, 0.15), Color(0.6, 0.45, 0.15), 0.3), false)

	# --- Relleno: el sofá en U ocupaba el centro y el resto era piso vacío ---
	# Pufs y almohadones desparramados (el lado oeste, fuera del paso del vano
	# que cae en z ±1.5 sobre el tabique)
	var puff_mat := mat_fabric_red if variant == 0 else mat_leather_brown
	_create_bean_bag(pos + Vector3(-6.5, 0, 3.2), puff_mat)
	_create_bean_bag(pos + Vector3(-7.9, 0, 4.7), mat_mattress)
	_create_bean_bag(pos + Vector3(-5.2, 0, 4.6), puff_mat)
	for c in 4:
		_create_box(pos + Vector3(-8.4 + rng.randf_range(-0.8, 0.8), 0.11, -5.5 + rng.randf_range(-1.2, 1.2)), Vector3(0.75, 0.22, 0.6), mat_mattress, false, Vector3(0, rng.randf_range(0, PI), 0))

	# Estante bajo con equipo de música contra el tabique oeste
	_create_box(pos + Vector3(-FACE_PART + 0.28, 0.35, -7.6), Vector3(0.55, 0.7, 2.2), mat_aged_wood)
	_create_box(pos + Vector3(-FACE_PART + 0.28, 0.92, -7.6), Vector3(0.5, 0.44, 1.1), mat_dark_steel)
	_create_box(pos + Vector3(-FACE_PART + 0.55, 0.92, -7.6), Vector3(0.04, 0.3, 0.9), mat_crt_phosphor, false)
	_add_omni(pos + Vector3(-9.6, 1.3, -7.6), Color(0.2, 0.8, 0.35), 0.35, 3.5)

	# Mesa-carrete y ceniceros de pie en el lado este
	_create_cable_spool(pos + Vector3(7.4, 0, -6.4), 0.62)
	for ax in [4.6, -3.0]:
		_create_cylinder(pos + Vector3(ax, 0.5, 5.4), 0.16, 1.0, mat_dark_steel)
		_create_cylinder(pos + Vector3(ax, 1.03, 5.4), 0.2, 0.08, mat_rust_metal, false)

	# Cajón-mesa con botellas y velas al este de los sofás
	_create_box(pos + Vector3(5.2, 0.3, 1.4), Vector3(1.1, 0.6, 1.1), mat_aged_wood)
	for bq in 3:
		_create_cylinder(pos + Vector3(4.85 + bq * 0.35, 0.74, 1.4 + rng.randf_range(-0.25, 0.25)), 0.05, 0.28, mat_moon_glass, false)
	_create_box(pos + Vector3(5.6, 0.68, 1.1), Vector3(0.07, 0.16, 0.07), mat_led_warm, false)

	# Telas colgando del techo: parten la línea de visión sin bloquear el paso
	for dz in [-6.5, 2.0]:
		_create_box(pos + Vector3(-1.5, 3.4, dz), Vector3(2.6, 2.2, 0.04), puff_mat, false, Vector3(0, 0.25, 0))
		_create_beam(pos + Vector3(-2.8, PLAY_H - 0.05, dz - 0.3), pos + Vector3(-0.2, PLAY_H - 0.05, dz + 0.3), 0.02, mat_dark_steel)

	_create_debris_scatter(pos + Vector3(0.0, 0, 4.5), 3.0, 8)
	_create_debris_scatter(pos + Vector3(-6.0, 0, -2.0), 2.6, 6)


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

	# --- Cañería troncal + bajadas sobre el muro ESTE (el comentario viejo
	# decía "norte" pero siempre estuvieron al este). Ahora el troncal muere
	# contra la pared, dobla en un colector y de ahí bajan las tres columnas,
	# con ménsulas a la pared: antes flotaban a 0.65m, sueltas en el aire. ---
	var east_face := FACE_EXT - 0.15
	var trunk_z := -5.5
	_create_beam(pos + Vector3(-FACE_PART + 0.18, 3.9, trunk_z), pos + Vector3(east_face, 3.9, trunk_z), 0.18, mat_pipe_industrial)
	_create_beam(pos + Vector3(east_face, 3.9, trunk_z), pos + Vector3(east_face, 3.9, 2.6), 0.15, mat_pipe_industrial)
	for hx in [-8.0, -3.5, 1.0, 6.0]:
		_create_beam(pos + Vector3(hx, PLAY_H, trunk_z), pos + Vector3(hx, 4.08, trunk_z), 0.03, mat_dark_steel)
	for pz in [-2.0, 0.0, 2.0]:
		_create_cylinder(pos + Vector3(east_face, 1.95, pz), 0.15, 3.9, mat_pipe_industrial)
		for by in [1.1, 3.0]:
			_create_box(pos + Vector3(FACE_EXT - 0.06, by, pz), Vector3(0.12, 0.14, 0.34), mat_dark_steel, false)
		_create_cylinder(pos + Vector3(east_face - 0.3, 1.55, pz), 0.05, 0.34, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
		_create_cylinder(pos + Vector3(east_face - 0.48, 1.55, pz), 0.16, 0.05, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))

	# Tablero eléctrico apoyado en el tabique norte y CORRIDO al este: antes
	# arrancaba en x = 1.4 y se comía la jamba del vano (que va en x ±1.5).
	_create_box(pos + Vector3(3.6, 1.4, -FACE_PART + 0.175), Vector3(1.2, 1.8, 0.35), mat_hazard_mark)
	_create_box(pos + Vector3(3.95, 1.7, -FACE_PART + 0.38), Vector3(0.12, 0.12, 0.06), mat_neon_red_dim, false)
	_create_beam(pos + Vector3(3.6, 2.3, -FACE_PART + 0.1), pos + Vector3(3.6, PLAY_H, -FACE_PART + 0.1), 0.04, mat_dark_steel)

	# Barriles de combustible apilados (el escondite queda detrás)
	var barrels := [Vector3(-6.2, 0, 6.2), Vector3(-7.2, 0, 6.8), Vector3(-6.0, 0, 7.4), Vector3(-7.0, 0, 5.6)]
	for b in barrels:
		_create_cylinder(pos + b + Vector3(0, 0.45, 0), 0.38, 0.9, mat_rust_metal)
	_create_cylinder(pos + Vector3(-6.6, 1.35, 6.5), 0.38, 0.9, mat_rust_metal)

	# --- Relleno del oeste y del sur (eran 10x20m de hormigón vacío) --------
	# Tanques horizontales sobre cunas contra el noroeste
	_create_horizontal_tank(pos + Vector3(-6.8, 1.15, -6.6), 4.6, 0.85, true)
	_create_horizontal_tank(pos + Vector3(-6.8, 1.05, -8.9), 4.0, 0.75, true)
	_create_beam(pos + Vector3(-8.9, 2.0, -6.6), pos + Vector3(-8.9, 2.0, -8.9), 0.07, mat_pipe_industrial)

	# Pila de carbón / escoria en la esquina noroeste
	for k in 7:
		var cs := rng.randf_range(0.5, 1.1)
		_create_box(pos + Vector3(-9.4 + rng.randf_range(-1.0, 1.0), cs * 0.35, -9.6 + rng.randf_range(-0.9, 0.9)), Vector3(cs, cs * 0.7, cs), mat_rubble, k < 3, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, PI), rng.randf_range(-0.4, 0.4)))
	_create_box(pos + Vector3(-7.6, 0.35, -9.0), Vector3(0.9, 0.7, 0.7), mat_dark_steel, true, Vector3(0, 0.4, 0))

	# Tramo de cañería baja cruzando el piso. Va cortado al medio a propósito:
	# el hueco de 1.6m deja pasar caminando hacia el escondite de los barriles
	# y el resto queda como obstáculo bajo (se salta).
	for seg in [Vector3(-7.6, 0, 0), Vector3(-1.6, 0, 0)]:
		_create_cylinder(pos + seg + Vector3(0, 0.38, 5.6), 0.24, 4.4, mat_pipe_industrial, true, Vector3(0, 0, PI * 0.5))
	for sx in [-9.4, -5.7, -3.5, 0.4]:
		_create_box(pos + Vector3(sx, 0.08, 5.6), Vector3(0.4, 0.16, 0.7), mat_dark_steel)

	# Caldera chica hermana, al sureste
	_create_cylinder(pos + Vector3(7.2, 1.1, 5.6), 1.0, 2.2, mat_rust_metal)
	_create_cylinder(pos + Vector3(7.2, 2.75, 5.6), 0.25, 1.1, mat_dark_steel)
	_create_beam(pos + Vector3(7.2, 3.3, 5.6), pos + Vector3(east_face, 3.85, 2.6), 0.1, mat_pipe_industrial)
	_create_box(pos + Vector3(7.2, 0.55, 4.55), Vector3(0.55, 0.4, 0.12), mat_fire_orange, false)
	_add_omni(pos + Vector3(7.2, 0.8, 4.2), Color(1.0, 0.35, 0.1), 0.9, 5.0)

	# Banco de válvulas y manómetros contra el muro este
	for vz in [7.4, 8.6]:
		_create_cylinder(pos + Vector3(FACE_EXT - 0.3, 1.5, vz), 0.34, 0.08, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
		_create_box(pos + Vector3(FACE_EXT - 0.12, 1.5, vz), Vector3(0.24, 0.24, 0.24), mat_pipe_industrial, false)
	_create_box(pos + Vector3(FACE_EXT - 0.09, 2.4, 8.0), Vector3(0.18, 0.7, 1.6), mat_hazard_mark, false)
	for gq in 3:
		_create_cylinder(pos + Vector3(FACE_EXT - 0.19, 2.4, 7.4 + gq * 0.6), 0.11, 0.05, mat_moon_glass, false, Vector3(0, 0, PI * 0.5))

	_create_debris_scatter(pos + Vector3(-3.0, 0, -1.0), 3.0, 7)
	_create_debris_scatter(pos + Vector3(2.0, 0, 8.0), 3.0, 6)

	# Resplandor del fuego + fluorescente industrial
	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.3, 0.08)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 8.5
	fire_light.shadow_enabled = true
	add_child(fire_light)
	fire_light.position = pos + Vector3(3, 1.1, -0.6)

	_create_fluorescent_fixture(pos + Vector3(-2, PLAY_H - 0.05, 3), Color(0.4, 0.95, 0.9), 1.2, 8.0)
	# Sin esto, el noroeste (tanques y pila de carbón) queda en negro absoluto
	# Energía alta a propósito: el acero de los tanques es metallic 0.8 y sin
	# reflejos se come toda la luz -- con 1.2 no se veía nada.
	_create_fluorescent_fixture(pos + Vector3(-6.8, PLAY_H - 0.05, -7.5), Color(0.5, 0.9, 0.85), 2.2, 11.0)


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

	# --- Relleno del sector este (quedaban ~9x18m de piso libre) ------------
	# Estantería cruzada de norte a sur: cierra el vacío del este sin tapar el
	# vano hacia el chill NE (que va en z ±1.5 sobre el tabique)
	_create_pallet_rack(pos + Vector3(8.4, 0, -2.5), 8.0, 3.2, PI * 0.5)

	# Pallets, zorra y bidones sueltos
	_create_pallet_stack(pos + Vector3(6.8, 0, 4.6), 4, 0.2)
	_create_pallet_stack(pos + Vector3(9.3, 0, 6.0), 3, -0.35)
	_create_pallet_jack(pos + Vector3(5.2, 0, -8.4), 1.1)
	_create_cable_spool(pos + Vector3(-9.6, 0, 8.8), 0.85)
	_create_cable_spool(pos + Vector3(-8.2, 0, 9.6), 0.6)
	for bx in [-9.0, -8.1, -7.2, -6.3]:
		_create_cylinder(pos + Vector3(bx, 0.45, -FACE_EXT + 0.38), 0.38, 0.9, mat_rust_metal)
	_create_cylinder(pos + Vector3(-8.55, 1.35, -FACE_EXT + 0.38), 0.38, 0.9, mat_rust_metal)

	# Cajones envueltos en film y marcas de carga en el piso
	_create_box(pos + Vector3(6.2, 0.75, 9.0), Vector3(1.3, 1.5, 1.3), mat_shrinkwrap)
	_create_box(pos + Vector3(3.6, 0.6, 9.4), Vector3(1.1, 1.2, 1.1), mat_shrinkwrap)
	for mz in [-1.0, 1.0]:
		_create_box(pos + Vector3(-6.5, 0.025, mz * 2.6 + 7.0), Vector3(5.0, 0.03, 0.18), mat_hazard_mark, false)
	_create_debris_scatter(pos + Vector3(1.0, 0, 4.0), 3.4, 8)
	_create_debris_scatter(pos + Vector3(8.0, 0, -8.0), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, -2), 1.3, Color(0.55, 0.25, 1.0), 1.2, 8.5)
	_create_fluorescent_fixture(pos + Vector3(4, PLAY_H - 0.05, 6), Color(0.4, 0.9, 0.95), 1.0, 7.0)
	_create_fluorescent_fixture(pos + Vector3(8.4, PLAY_H - 0.05, -6.5), Color(0.4, 0.9, 0.95), 0.9, 7.0)


# =============================================================================
# TALLER (noroeste)
# =============================================================================

func _build_workshop(pos: Vector3) -> void:
	# Mesa de trabajo contra el muro norte + panel de herramientas. Todo apoya
	# en FACE_EXT: antes el panel estaba a -10.3 con la pared en -10.7 y se
	# veía colgado en el aire, con la mesa despegada medio metro.
	var bench_z := -FACE_EXT + 0.55
	_create_box(pos + Vector3(0, 0.95, bench_z), Vector3(6.5, 0.12, 1.1), mat_aged_wood)
	for lx in [-3.0, 3.0]:
		for lz in [-0.4, 0.4]:
			_create_box(pos + Vector3(lx, 0.45, bench_z + lz), Vector3(0.1, 0.9, 0.1), mat_dark_steel)
	_create_box(pos + Vector3(0, 0.45, bench_z), Vector3(6.0, 0.08, 0.9), mat_dark_steel, false)
	_create_box(pos + Vector3(0, 2.2, -FACE_EXT + 0.04), Vector3(6.0, 1.6, 0.08), mat_aged_wood, false)
	for t in 6:
		_create_box(pos + Vector3(-2.2 + t * 0.9, 2.2 + (0.25 if t % 2 == 0 else -0.2), -FACE_EXT + 0.105), Vector3(0.12, 0.4, 0.05), mat_dark_steel, false)
	# Morsa sobre la mesa
	_create_box(pos + Vector3(-2.4, 1.15, bench_z), Vector3(0.45, 0.3, 0.35), mat_rust_metal)

	# Compresor + carro de herramientas
	_create_cylinder(pos + Vector3(6.5, 0.8, -6.0), 0.5, 1.6, mat_pipe_industrial)
	_create_box(pos + Vector3(6.5, 1.7, -6.0), Vector3(0.5, 0.3, 0.4), mat_dark_steel)
	_create_box(pos + Vector3(2.0, 0.5, -4.0), Vector3(0.9, 1.0, 1.2), mat_rust_metal)
	_create_chair(pos + Vector3(-1.0, 0, -8.2), PI)

	# Tambores de aceite en la esquina sureste (escondite detrás)
	for d in [Vector3(7.3, 0, 7.3), Vector3(8.2, 0, 6.6), Vector3(6.7, 0, 8.3)]:
		_create_cylinder(pos + d + Vector3(0, 0.45, 0), 0.4, 0.9, mat_rust_metal)

	# Cadenas sueltas colgando del techo
	for c in 2:
		var cx := rng.randf_range(-3.0, 4.0)
		var cz := rng.randf_range(-2.0, 3.0)
		_create_beam(pos + Vector3(cx, PLAY_H, cz), pos + Vector3(cx, PLAY_H - rng.randf_range(1.6, 2.4), cz), 0.03, mat_dark_steel)

	# --- Aparejo con un motor colgando: las cadenas ahora sostienen ALGO ----
	var hoist := pos + Vector3(2.6, 0, 1.2)
	_create_beam(hoist + Vector3(-2.2, PLAY_H - 0.2, 0), hoist + Vector3(2.2, PLAY_H - 0.2, 0), 0.09, mat_dark_steel)
	_create_box(hoist + Vector3(0, PLAY_H - 0.45, 0), Vector3(0.45, 0.4, 0.5), mat_rust_metal, false)
	_create_beam(hoist + Vector3(0, PLAY_H - 0.6, 0), hoist + Vector3(0, 1.85, 0), 0.035, mat_dark_steel)
	_create_box(hoist + Vector3(0, 1.42, 0), Vector3(0.95, 0.85, 1.15), mat_dark_steel)
	_create_box(hoist + Vector3(0, 1.95, 0), Vector3(0.55, 0.25, 0.7), mat_rust_metal)
	_create_cylinder(hoist + Vector3(0.62, 1.3, 0), 0.18, 0.5, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
	# Bandeja de aceite abajo, para que el motor "esté trabajándose"
	_create_box(hoist + Vector3(0, 0.06, 0), Vector3(1.4, 0.12, 1.4), mat_dark_steel)
	_create_box(hoist + Vector3(0.1, 0.135, 0.1), Vector3(1.1, 0.02, 1.1), _matte(Color(0.03, 0.025, 0.02), 0.15), false)
	# Portátil de taller colgada del aparejo, apuntando al motor
	_create_hanging_lamp(hoist + Vector3(1.1, PLAY_H - 0.3, 0.5), 1.9, Color(1.0, 0.9, 0.7), 1.3, 6.0)

	# --- Relleno del oeste y del centro-sur --------------------------------
	# Chasis quemado: el landmark del taller y buena cobertura para esconderse
	_create_wreck_car(pos + Vector3(-5.0, 0, 3.4), 0.38)

	# Estantería metálica contra el muro oeste
	_create_shelf_unit(pos + Vector3(-FACE_EXT + 0.32, 0, -2.5), 5.0, PI * 0.5)

	# Pilas de neumáticos y bidones
	_create_tire_stack(pos + Vector3(-7.6, 0, -5.6), 4)
	_create_tire_stack(pos + Vector3(-8.6, 0, -4.4), 3)
	_create_tire_stack(pos + Vector3(-6.6, 0, 7.4), 5)
	for dz in [8.6, 9.4]:
		_create_cylinder(pos + Vector3(-2.4, 0.45, dz), 0.34, 0.9, mat_pipe_industrial)
	_create_box(pos + Vector3(0.5, 0.4, 8.8), Vector3(1.6, 0.8, 1.0), mat_rust_metal, true, Vector3(0, 0.3, 0))

	# Manchas de aceite y basura de taller
	for oi in 3:
		_create_box(pos + Vector3(rng.randf_range(-6.0, 4.0), 0.024, rng.randf_range(-4.0, 6.0)), Vector3(rng.randf_range(1.2, 2.4), 0.02, rng.randf_range(1.0, 2.0)), _matte(Color(0.03, 0.025, 0.02), 0.2), false, Vector3(0, rng.randf_range(0, PI), 0))
	_create_debris_scatter(pos + Vector3(-3.0, 0, -6.0), 3.0, 7)
	_create_debris_scatter(pos + Vector3(4.0, 0, 2.0), 3.0, 6)

	_create_fluorescent_fixture(pos + Vector3(0, PLAY_H - 0.05, -6), Color(0.4, 0.95, 0.9), 1.3, 8.0)
	_create_hanging_lamp(pos + Vector3(5, PLAY_H, 5), 1.5, Color(1.0, 0.6, 0.25), 0.8, 6.0)
	_create_hanging_lamp(pos + Vector3(-6.5, PLAY_H, 1.0), 1.2, Color(0.9, 0.85, 0.8), 0.9, 6.5)


# =============================================================================
# ENTRADA / DOCK DE CARGA (sur) -- spawn del Atrapador + escalera derrumbada
# =============================================================================

func _build_entrance(pos: Vector3) -> void:
	# Portón de carga cerrado (por acá "entraba" la gente: ahora sellado),
	# embutido contra la cara real del muro sur
	_create_box(pos + Vector3(0, 2.1, FACE_EXT - 0.11), Vector3(7.0, 4.2, 0.22), mat_dark_steel)
	for rib in 6:
		_create_box(pos + Vector3(0, 0.6 + rib * 0.6, FACE_EXT - 0.245), Vector3(7.0, 0.1, 0.05), mat_rust_metal, false)
	_create_box(pos + Vector3(0, 0.02, 9.4), Vector3(7.0, 0.04, 1.4), mat_hazard_mark, false)
	# Cartel de salida arriba del portón (antes se superponía con la chapa)
	_create_box(pos + Vector3(0, 4.45, FACE_EXT - 0.05), Vector3(1.2, 0.35, 0.1), mat_exit_green, false)
	_add_omni(pos + Vector3(0, 4.3, 9.9), Color(0.15, 0.9, 0.35), 0.5, 4.5)

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

	# Grafitis de neón en el tabique oeste (dos tajos cruzados magenta/cian).
	# Pegados a la cara del tabique y corridos a z = -3.5: en -2.0 quedaban
	# montados sobre la jamba del vano hacia baños (que va en z ±1.5).
	_create_box(pos + Vector3(-FACE_PART + 0.03, 1.8, -3.5), Vector3(0.06, 1.8, 0.3), mat_neon_magenta, false, Vector3(0.5, 0, 0))
	_create_box(pos + Vector3(-FACE_PART + 0.03, 1.8, -3.5), Vector3(0.06, 1.8, 0.3), mat_neon_cyan, false, Vector3(-0.5, 0, 0))

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

	# --- Relleno del hall (era el sector más pelado del mapa) ---------------
	# Banco de lockers contra el tabique oeste, fuera del vano hacia baños
	_create_locker_bank(pos + Vector3(-FACE_PART + 0.25, 0, -7.0), 6, PI * 0.5)
	_create_locker_bank(pos + Vector3(-FACE_PART + 0.25, 0, 5.6), 4, PI * 0.5)
	# Cartelera del club arriba de los lockers
	_create_box(pos + Vector3(-FACE_PART + 0.06, 2.55, -7.0), Vector3(0.08, 1.2, 2.4), mat_aged_wood, false)
	for fl in 5:
		_create_box(pos + Vector3(-FACE_PART + 0.11, 2.2 + rng.randf_range(0.0, 0.9), -8.0 + rng.randf_range(0.0, 2.0)), Vector3(0.02, 0.34, 0.26), _emissive(Color(0.4, 0.4, 0.45), Color(0.5, 0.5, 0.6), 0.25), false, Vector3(rng.randf_range(-0.15, 0.15), 0, 0))

	# Mesa de cacheo + silla al costado de la fila
	_create_box(pos + Vector3(-4.2, 0.78, 6.4), Vector3(2.0, 0.1, 0.8), mat_aged_wood)
	for lx in [-1.85, 1.85]:
		for lz in [-0.3, 0.3]:
			_create_box(pos + Vector3(-4.2 + lx * 0.5, 0.38, 6.4 + lz), Vector3(0.08, 0.76, 0.08), mat_dark_steel)
	_create_chair(pos + Vector3(-4.2, 0, 7.6), PI)
	_create_box(pos + Vector3(-3.6, 0.9, 6.4), Vector3(0.35, 0.14, 0.3), mat_dark_steel)

	# Guardarropa: mostrador y perchero detrás
	_create_box(pos + Vector3(4.6, 0.55, 8.7), Vector3(3.2, 1.1, 0.7), mat_aged_wood)
	_create_box(pos + Vector3(4.6, 1.13, 8.7), Vector3(3.4, 0.08, 0.85), mat_rust_metal)
	_create_beam(pos + Vector3(3.2, 1.8, 9.7), pos + Vector3(6.2, 1.8, 9.7), 0.04, mat_rust_metal)
	for hz in 6:
		_create_box(pos + Vector3(3.4 + hz * 0.55, 1.4, 9.7), Vector3(0.4, 0.75, 0.14), mat_fabric_red, false, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
	_add_omni(pos + Vector3(4.6, 2.1, 8.9), Color(0.9, 0.6, 0.3), 0.6, 5.0)

	# Molinete roto y valla tumbada al final de la fila
	_create_cylinder(pos + Vector3(3.6, 0.5, 3.6), 0.18, 1.0, mat_dark_steel)
	for ta in 3:
		var tang := -0.4 + ta * 1.2
		_create_beam(pos + Vector3(3.6, 0.9, 3.6), pos + Vector3(3.6 + cos(tang) * 0.75, 0.9, 3.6 + sin(tang) * 0.75), 0.04, mat_rust_metal)
	_create_fallen_barrier(pos + Vector3(-1.2, 0, 9.2), 1.35)

	# Tacho volcado y basura de la puerta
	_create_cylinder(pos + Vector3(6.8, 0.32, 5.2), 0.34, 0.95, mat_dark_steel, true, Vector3(PI * 0.5, 0.9, 0))
	_create_debris_scatter(pos + Vector3(6.0, 0, 5.6), 2.2, 8)
	_create_debris_scatter(pos + Vector3(-6.5, 0, -4.5), 3.0, 7)
	_create_debris_scatter(pos + Vector3(0.0, 0, 6.5), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, 5.5), 1.4, Color(0.75, 0.8, 0.95), 1.4, 9.0)
	_create_hanging_lamp(pos + Vector3(-5.5, PLAY_H, 0.5), 1.6, Color(0.9, 0.5, 0.2), 0.9, 6.5)
	_create_fluorescent_fixture(pos + Vector3(-6.0, PLAY_H - 0.05, -7.0), Color(0.5, 0.85, 0.95), 1.1, 8.0)


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


func _create_pallet_rack(pos: Vector3, length: float, height: float, rot_y: float = 0.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var w := 0.95
	for dx in [-length * 0.5, 0.0, length * 0.5]:
		for dz in [-w * 0.5, w * 0.5]:
			_add_primitive_box(root, Vector3(dx, height * 0.5, dz), Vector3(0.09, height, 0.09), mat_rust_metal)
	for h in [0.75, 1.65, 2.55]:
		_add_primitive_box(root, Vector3(0, h, 0), Vector3(length, 0.06, w), mat_rust_metal)
		_add_primitive_box(root, Vector3(length * 0.28, h + 0.28, 0), Vector3(0.7, 0.5, 0.65), mat_aged_wood)
		_add_primitive_box(root, Vector3(-length * 0.22, h + 0.25, 0), Vector3(0.55, 0.45, 0.55), mat_aged_wood)


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


# =============================================================================
# LUCES DE SHOW ANIMADAS
# =============================================================================

## Cabezal móvil colgado de una columna del atrio: yugo + luminaria + spot, con
## barrido en péndulo. Que la luz salga de un cuerpo visible es la mitad del
## efecto; la otra mitad es que se mueva.
func _create_moving_head(mount: Vector3, aim: Vector3, color: Color, energy: float, sweep: float, period: float) -> void:
	var d := aim - mount
	var flat := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var tilt := atan2(-d.y, maxf(flat, 0.01))

	# Ménsula fija a la columna
	_create_box(mount + Vector3(0, 0.3, 0), Vector3(0.34, 0.14, 0.34), mat_dark_steel, false)

	var pivot := Node3D.new()
	pivot.position = mount
	pivot.rotation.y = yaw
	add_child(pivot)
	_add_mesh_box(pivot, Vector3(0, 0.12, 0), Vector3(0.36, 0.12, 0.22), mat_dark_steel)
	for sx in [-0.17, 0.17]:
		_add_mesh_box(pivot, Vector3(sx, -0.1, 0), Vector3(0.05, 0.36, 0.16), mat_dark_steel)

	var head := Node3D.new()
	head.rotation.x = -tilt
	pivot.add_child(head)
	_add_mesh_cylinder(head, Vector3(0, -0.12, -0.18), 0.13, 0.46, mat_dark_steel, Vector3(PI * 0.5, 0, 0))
	_add_mesh_cylinder(head, Vector3(0, -0.12, -0.41), 0.115, 0.03, _emissive(color, color, 3.2), Vector3(PI * 0.5, 0, 0))

	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_range = 21.0
	spot.spot_angle = 15.0
	spot.spot_angle_attenuation = 0.9
	head.add_child(spot)
	spot.position = Vector3(0, -0.12, -0.43)

	var tw := create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", yaw + sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:y", yaw - sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw)

	# El cabeceo va con otro período: así el patrón nunca se cierra sobre sí
	var tw2 := create_tween().set_loops()
	tw2.tween_property(head, "rotation:x", -tilt + 0.18, period * 1.41).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(head, "rotation:x", -tilt - 0.1, period * 1.41).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw2)


## Abanico de láseres saliendo de un cabezal, barriendo el atrio. Los haces se
## construyen en el espacio LOCAL del pivot, así rotan todos juntos.
func _create_laser_fan(origin: Vector3, base_yaw: float, mat: StandardMaterial3D, count: int, sweep: float, period: float) -> void:
	var pivot := Node3D.new()
	pivot.position = origin
	pivot.rotation.y = base_yaw
	add_child(pivot)
	_add_mesh_box(pivot, Vector3(0, 0, 0.08), Vector3(0.32, 0.24, 0.36), mat_dark_steel)
	_add_mesh_box(pivot, Vector3(0, 0, 0.27), Vector3(0.18, 0.1, 0.03), mat)
	for i in count:
		var t: float = float(i) / maxf(float(count - 1), 1.0) - 0.5
		var end := Vector3(t * 10.5, 5.0 + absf(t) * 3.4, 18.5)
		_add_beam(pivot, Vector3(0, 0, 0.26), end, 0.025, mat)

	var tw := create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", base_yaw + sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:y", base_yaw - sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw)
	var tw2 := create_tween().set_loops()
	tw2.tween_property(pivot, "rotation:z", 0.24, period * 0.67).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(pivot, "rotation:z", -0.24, period * 0.67).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw2)


# =============================================================================
# PROPS DE RELLENO
# =============================================================================

## Mesa alta de bar, la típica de pie, con vasos abandonados arriba.
func _create_high_table(pos: Vector3, glasses: int = 2) -> void:
	_create_cylinder(pos + Vector3(0, 0.04, 0), 0.42, 0.08, mat_dark_steel)
	_create_cylinder(pos + Vector3(0, 0.55, 0), 0.08, 1.02, mat_dark_steel)
	_create_cylinder(pos + Vector3(0, 1.09, 0), 0.55, 0.07, mat_aged_wood)
	# Velita LED: sin esto la mesa es un poste negro invisible en la penumbra
	_create_cylinder(pos + Vector3(0, 1.19, 0), 0.05, 0.13, mat_led_warm, false)
	_add_omni(pos + Vector3(0, 1.32, 0), Color(1.0, 0.6, 0.25), 0.55, 2.8)
	for g in glasses:
		var a := rng.randf_range(0.0, TAU)
		var dd := rng.randf_range(0.16, 0.34)
		_create_cylinder(pos + Vector3(cos(a) * dd, 1.2, sin(a) * dd), 0.045, 0.16, mat_moon_glass, false)


## Tarima go-gó: cajón con zócalo de neón y barra de apoyo atrás.
func _create_gogo_platform(pos: Vector3, size: float, neon: StandardMaterial3D) -> void:
	_create_box(pos + Vector3(0, 0.35, 0), Vector3(size, 0.7, size), mat_dark_steel)
	_create_box(pos + Vector3(0, 0.73, 0), Vector3(size + 0.14, 0.06, size + 0.14), mat_rust_metal, false)
	for s in [-1.0, 1.0]:
		# Zócalo de neón alto: es lo que hace legible la tarima desde la pista
		_create_box(pos + Vector3(s * size * 0.51, 0.36, 0), Vector3(0.05, 0.5, size * 0.92), neon, false)
		_create_box(pos + Vector3(0, 0.36, s * size * 0.51), Vector3(size * 0.92, 0.5, 0.05), neon, false)
		_create_cylinder(pos + Vector3(s * size * 0.42, 1.3, -size * 0.42), 0.04, 1.1, mat_rust_metal, false)
	_add_omni(pos + Vector3(0, 0.45, 0), neon.emission, 0.7, 4.5)
	_create_beam(pos + Vector3(-size * 0.42, 1.83, -size * 0.42), pos + Vector3(size * 0.42, 1.83, -size * 0.42), 0.04, mat_rust_metal)


## Flight case de gira.
func _create_flight_case(pos: Vector3, size: Vector3, rot_y: float) -> void:
	var rot := Vector3(0, rot_y, 0)
	_create_box(pos + Vector3(0, size.y * 0.5, 0), size, mat_dark_steel, true, rot)
	_create_box(pos + Vector3(0, size.y + 0.02, 0), Vector3(size.x * 0.94, 0.04, size.z * 0.94), mat_rust_metal, false, rot)
	_create_box(pos + Vector3(0, size.y * 0.55, 0), Vector3(size.x * 1.03, 0.05, size.z * 1.03), mat_rust_metal, false, rot)


## Valla de contención tumbada: desorden post-rave que no tapa el paso.
func _create_fallen_barrier(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.07, -0.45), Vector3(2.2, 0.06, 0.06), mat_rust_metal)
	_add_primitive_box(root, Vector3(0, 0.34, 0.45), Vector3(2.2, 0.06, 0.06), mat_rust_metal)
	for bx in [-0.95, -0.32, 0.32, 0.95]:
		_add_primitive_box(root, Vector3(bx, 0.2, 0.0), Vector3(0.05, 0.05, 0.95), mat_rust_metal)
	for lx in [-1.0, 1.0]:
		_add_primitive_box(root, Vector3(lx, 0.2, -0.72), Vector3(0.07, 0.42, 0.07), mat_dark_steel)


## Basura fina de after: vasos, latas, volantes. SIN colisión a propósito, para
## que llene el piso sin trabar a nadie.
func _create_debris_scatter(pos: Vector3, spread: float, count: int) -> void:
	for i in count:
		var p := pos + Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var kind := rng.randi_range(0, 2)
		if kind == 0:
			_create_cylinder(p + Vector3(0, 0.05, 0), 0.045, 0.11, mat_shrinkwrap, false, Vector3(PI * 0.5, rng.randf_range(0, PI), 0))
		elif kind == 1:
			_create_box(p + Vector3(0, 0.012, 0), Vector3(0.22, 0.01, 0.16), mat_mattress, false, Vector3(0, rng.randf_range(0, PI), 0))
		else:
			_create_cylinder(p + Vector3(0, 0.035, 0), 0.032, 0.12, mat_dark_steel, false, Vector3(PI * 0.5, rng.randf_range(0, PI), 0))


## Mesa baja con dos sillas enfrentadas.
func _create_table_set(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.73, 0), Vector3(1.1, 0.07, 1.1), mat_aged_wood)
	for dx in [-0.45, 0.45]:
		for dz in [-0.45, 0.45]:
			_add_primitive_box(root, Vector3(dx, 0.36, dz), Vector3(0.07, 0.72, 0.07), mat_dark_steel)
	_add_mesh_cylinder(root, Vector3(rng.randf_range(-0.3, 0.3), 0.85, rng.randf_range(-0.3, 0.3)), 0.05, 0.18, mat_moon_glass)
	_create_chair(pos + Vector3(cos(rot_y) * 1.05, 0, -sin(rot_y) * 1.05), rot_y - PI * 0.5)
	_create_chair(pos - Vector3(cos(rot_y) * 1.05, 0, -sin(rot_y) * 1.05), rot_y + PI * 0.5)


## Cajones de botellas apilados.
func _create_bottle_crates(pos: Vector3, count: int) -> void:
	for i in count:
		var y := 0.16 + i * 0.32
		var jx := rng.randf_range(-0.08, 0.08)
		var jz := rng.randf_range(-0.08, 0.08)
		var rot := Vector3(0, rng.randf_range(-0.25, 0.25), 0)
		_create_box(pos + Vector3(jx, y, jz), Vector3(0.62, 0.32, 0.44), mat_aged_wood, true, rot)
		for b in 3:
			_create_box(pos + Vector3(jx - 0.18 + b * 0.18, y + 0.22, jz), Vector3(0.09, 0.18, 0.09), mat_moon_glass, false, rot)


## Banco de lockers: las puertas miran al +Z local.
func _create_locker_bank(pos: Vector3, units: int, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var w := 0.45
	var total := units * w
	_add_primitive_box(root, Vector3(0, 0.95, 0), Vector3(total, 1.9, 0.5), mat_dark_steel)
	for i in units:
		var lx := -total * 0.5 + w * 0.5 + i * w
		_add_mesh_box(root, Vector3(lx, 1.4, 0.26), Vector3(w - 0.05, 0.86, 0.03), mat_paint_worn)
		_add_mesh_box(root, Vector3(lx, 0.48, 0.26), Vector3(w - 0.05, 0.86, 0.03), mat_paint_worn)
		_add_mesh_box(root, Vector3(lx + w * 0.28, 1.15, 0.29), Vector3(0.04, 0.14, 0.03), mat_rust_metal)


## Estantería metálica con cajas: el largo corre sobre el X local.
func _create_shelf_unit(pos: Vector3, length: float, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var d := 0.6
	var levels := [0.45, 1.05, 1.65]
	for sx in [-length * 0.5, length * 0.5]:
		for sz in [-d * 0.5, d * 0.5]:
			_add_primitive_box(root, Vector3(sx, 1.0, sz), Vector3(0.06, 2.0, 0.06), mat_rust_metal)
	for h in levels:
		_add_primitive_box(root, Vector3(0, h, 0), Vector3(length, 0.05, d), mat_rust_metal)
	for k in 6:
		var bh: float = levels[rng.randi_range(0, 2)]
		_add_mesh_box(root, Vector3(rng.randf_range(-length * 0.42, length * 0.42), bh + 0.2, rng.randf_range(-0.08, 0.08)), Vector3(0.4, 0.34, 0.38), mat_aged_wood, Vector3(0, rng.randf_range(-0.2, 0.2), 0))


## Pila de neumáticos.
func _create_tire_stack(pos: Vector3, count: int) -> void:
	for i in count:
		_create_cylinder(pos + Vector3(rng.randf_range(-0.07, 0.07), 0.11 + i * 0.22, rng.randf_range(-0.07, 0.07)), 0.42, 0.22, mat_rubber_black)


## Mingitorio de pared; inward_x = hacia dónde sobresale respecto del muro.
func _create_urinal(pos: Vector3, inward_x: float) -> void:
	_create_box(pos + Vector3(inward_x * 0.21, 0.95, 0), Vector3(0.42, 0.62, 0.36), mat_tile_wall)
	_create_box(pos + Vector3(inward_x * 0.24, 0.62, 0), Vector3(0.34, 0.06, 0.28), mat_tile_wall, false)
	_create_cylinder(pos + Vector3(inward_x * 0.08, 1.45, 0), 0.04, 0.36, mat_pipe_industrial, false)


## Carro de limpieza con balde y palo de piso.
func _create_cleaning_cart(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.5, 0), Vector3(0.55, 0.6, 0.85), mat_hazard_mark)
	_add_mesh_box(root, Vector3(0, 0.94, -0.32), Vector3(0.5, 0.06, 0.06), mat_dark_steel)
	for wx in [-0.22, 0.22]:
		for wz in [-0.3, 0.3]:
			_add_mesh_cylinder(root, Vector3(wx, 0.1, wz), 0.09, 0.05, mat_dark_steel, Vector3(0, 0, PI * 0.5))
	_add_mesh_cylinder(root, Vector3(0.14, 1.3, 0.26), 0.03, 1.5, mat_aged_wood, Vector3(0.28, 0, 0.14))
	_add_mesh_box(root, Vector3(0.3, 0.16, 0.62), Vector3(0.34, 0.32, 0.34), mat_mattress)


## Tanque horizontal sobre cunas.
func _create_horizontal_tank(pos: Vector3, length: float, radius: float, along_x: bool) -> void:
	var rot := Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
	_create_cylinder(pos, radius, length, mat_rust_metal, true, rot)
	for s in [-1.0, 1.0]:
		var off := Vector3(s * length * 0.32, 0, 0) if along_x else Vector3(0, 0, s * length * 0.32)
		_create_box(Vector3(pos.x + off.x, (pos.y - radius) * 0.5, pos.z + off.z), Vector3(radius * 1.3, maxf(pos.y - radius, 0.2), radius * 1.3), mat_dark_steel)
	_create_box(pos + Vector3(0, radius + 0.14, 0), Vector3(0.26, 0.28, 0.26), mat_pipe_industrial, false)


## Pallets vacíos apilados.
func _create_pallet_stack(pos: Vector3, count: int, rot_y: float) -> void:
	for i in count:
		var rot := Vector3(0, rot_y + i * 0.05, 0)
		var y := 0.09 + i * 0.16
		_create_box(pos + Vector3(0, y, 0), Vector3(1.2, 0.06, 1.0), mat_aged_wood, true, rot)
		_create_box(pos + Vector3(0, y - 0.05, 0), Vector3(1.15, 0.06, 0.15), mat_aged_wood, false, rot)


## Zorra hidráulica.
func _create_pallet_jack(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	for fx in [-0.28, 0.28]:
		_add_primitive_box(root, Vector3(fx, 0.08, 0.55), Vector3(0.16, 0.12, 1.5), mat_hazard_mark)
	_add_primitive_box(root, Vector3(0, 0.3, -0.32), Vector3(0.5, 0.5, 0.42), mat_dark_steel)
	_add_mesh_cylinder(root, Vector3(0, 0.98, -0.58), 0.04, 1.25, mat_rust_metal, Vector3(0.32, 0, 0))


## Carrete de cable de obra, tumbado de canto.
func _create_cable_spool(pos: Vector3, radius: float) -> void:
	var w := radius * 0.9
	var rot := Vector3(0, 0, PI * 0.5)
	_create_cylinder(pos + Vector3(0, radius, 0), radius * 0.62, w, mat_dark_steel, true, rot)
	for s in [-1.0, 1.0]:
		_create_cylinder(pos + Vector3(s * w * 0.5, radius, 0), radius, 0.07, mat_aged_wood, true, rot)
	_create_cylinder(pos + Vector3(0, radius, 0), radius * 0.9, w * 0.7, mat_dark_steel, false, rot)


## Chasis quemado: cobertura alta para esconderse en el taller.
func _create_wreck_car(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.62, 0), Vector3(1.85, 0.55, 4.1), mat_rust_metal)
	_add_primitive_box(root, Vector3(0, 1.12, -0.35), Vector3(1.7, 0.5, 1.9), mat_dark_steel)
	_add_mesh_box(root, Vector3(0, 1.22, 0.62), Vector3(1.5, 0.42, 0.06), mat_silhouette, Vector3(-0.45, 0, 0))
	_add_mesh_box(root, Vector3(0, 0.32, 2.03), Vector3(1.7, 0.3, 0.12), mat_dark_steel)
	for wx in [-0.86, 0.86]:
		for wz in [-1.35, 1.35]:
			_add_mesh_cylinder(root, Vector3(wx, 0.34, wz), 0.34, 0.22, mat_rubber_black, Vector3(0, 0, PI * 0.5))


## Puf de los chill rooms.
func _create_bean_bag(pos: Vector3, mat: StandardMaterial3D) -> void:
	_create_cylinder(pos + Vector3(0, 0.22, 0), 0.6, 0.44, mat)
	_create_sphere(pos + Vector3(0, 0.42, 0), 0.48, mat)


## Montón de escombros: los dos primeros con colisión, el resto decorativo.
func _create_rubble_pile(pos: Vector3, count: int, spread: float) -> void:
	for i in count:
		var s := rng.randf_range(0.22, 0.6)
		_create_box(pos + Vector3(rng.randf_range(-spread, spread), s * 0.4, rng.randf_range(-spread, spread)), Vector3(s, s * 0.75, s * 0.9), mat_rubble, i < 2, Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, PI), rng.randf_range(-0.3, 0.3)))


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
	_add_beam(self, from, to, radius, mat)


## Igual que _create_beam pero colgando de un parent arbitrario y resolviendo
## la orientación con matemática pura en vez de look_at(): look_at() trabaja en
## espacio GLOBAL, así que dentro de un pivot rotado (cabezales, abanicos de
## láser) daba haces apuntando a cualquier lado.
func _add_beam(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var length := from.distance_to(to)
	if length < 0.01:
		return null
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = mat
	var dir := from.direction_to(to)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# looking_at deja el eje -Z sobre dir; el cilindro crece en +Y, de ahí el
	# cuarto de vuelta sobre X (idéntico al rotate_object_local de antes).
	var b := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	mi.transform = Transform3D(b, (from + to) * 0.5)
	parent.add_child(mi)
	return mi


## Mesh sin colisión colgando de un parent arbitrario (los props compuestos que
## viven bajo un Node3D rotado los necesitan: _create_box siempre cuelga de self).
func _add_mesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.position = pos
	mi.rotation = rot
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_mesh_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.position = pos
	mi.rotation = rot
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _add_mesh_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.position = pos
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	mi.mesh = sph
	mi.material_override = mat
	parent.add_child(mi)
	return mi


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
