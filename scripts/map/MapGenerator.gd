extends Node3D
class_name MapGenerator
## =============================================================================
## WAREHOUSE CLANDESTINA / RAVE TECHNO (ESTILO BUCKSHOT ROULETTE) - GENERACIÓN DESDE CERO
## =============================================================================
## Blueprint arquitectónico de una nave industrial real: 66m x 66m totales,
## 7m de altura de techo, 9 zonas temáticas interconectadas:
##
##   [ SEGURIDAD & CELDA  ] ─── [ ALMACÉN DE CARGA ] ─── [ TALLER DE REPARACIONES ]
##            │                            │                            │
##   [ BAR & LOUNGE VIP ]   ─── [ PISTA DE BAILE + DJ ] ─── [ SALA DE CALDERAS     ]
##            │                            │                            │
##   [ SALA VIP DE PÓKER ]  ─── [ BAÑOS & TUBERÍAS ] ─── [ BÓVEDA & CAJA FUERTE  ]
##
## La pista de baile central tiene una claraboya en el techo (panel emisivo +
## focos hacia abajo simulando luz de ventanas de nave industrial) y una
## cabina de DJ con reproducción de música propia (ver export "club_music").
## - Estructura física cerrada y sólida (sin huecos al vacío ni salidas falsas).
## - Suelo y techo monolíticos con acabados específicos por zona.
## - Mobiliario y props 3D detallados con colisiones reales (Mesa central, Barra,
##   Calderas, Cubículos de baño, Estanterías de carga, Casilleros, Tuberías y Lámparas).
## - Puntos de spawn estratégicos y distribuidos.
## =============================================================================

@export var room_size: float = 22.0 # antes 18.0 -- ancho real de nave industrial
@export var wall_height: float = 7.0 # antes 4.8 -- altura real de warehouse (armadura metálica expuesta)

## Arrastrá acá el .ogg/.mp3 que quieras que suene desde la cabina del DJ
## (seleccioná el nodo MapGenerator en Game.tscn y usá este campo en el
## Inspector). Es audio 3D posicional -- se escucha más fuerte cerca de la
## pista y se va apagando en las salas vecinas. Si se deja vacío, no suena
## nada (sin fallback artificial).
@export var club_music: AudioStream

var rng := RandomNumberGenerator.new()

var hider_spawn_points: Array[Vector3] = []
var seeker_spawn_point: Vector3 = Vector3.ZERO

# Paleta de Materiales Industriales / Buckshot
var mat_concrete_floor: StandardMaterial3D
var mat_wood_floor: StandardMaterial3D
var mat_tile_floor: StandardMaterial3D
var mat_concrete_wall: StandardMaterial3D
var mat_tile_wall: StandardMaterial3D
var mat_rust_metal: StandardMaterial3D
var mat_dark_steel: StandardMaterial3D
var mat_aged_wood: StandardMaterial3D
var mat_table_felt: StandardMaterial3D
var mat_leather_brown: StandardMaterial3D
var mat_pipe_industrial: StandardMaterial3D
var mat_hazard_mark: StandardMaterial3D
var mat_bulb_amber: StandardMaterial3D
var mat_tube_cyan: StandardMaterial3D
var mat_crt_phosphor: StandardMaterial3D
var mat_fire_orange: StandardMaterial3D


func _init() -> void:
	_init_palette()


func _init_palette() -> void:
	mat_concrete_floor = StandardMaterial3D.new()
	mat_concrete_floor.albedo_color = Color(0.08, 0.075, 0.07)
	mat_concrete_floor.roughness = 0.95

	mat_wood_floor = StandardMaterial3D.new()
	mat_wood_floor.albedo_color = Color(0.14, 0.09, 0.05)
	mat_wood_floor.roughness = 0.85

	mat_tile_floor = StandardMaterial3D.new()
	mat_tile_floor.albedo_color = Color(0.09, 0.15, 0.13)
	mat_tile_floor.roughness = 0.45

	mat_concrete_wall = StandardMaterial3D.new()
	mat_concrete_wall.albedo_color = Color(0.16, 0.14, 0.12)
	mat_concrete_wall.roughness = 0.9

	mat_tile_wall = StandardMaterial3D.new()
	mat_tile_wall.albedo_color = Color(0.12, 0.22, 0.19)
	mat_tile_wall.roughness = 0.4

	mat_rust_metal = StandardMaterial3D.new()
	mat_rust_metal.albedo_color = Color(0.32, 0.16, 0.08)
	mat_rust_metal.metallic = 0.8
	mat_rust_metal.roughness = 0.55

	mat_dark_steel = StandardMaterial3D.new()
	mat_dark_steel.albedo_color = Color(0.20, 0.21, 0.23)
	mat_dark_steel.metallic = 0.9
	mat_dark_steel.roughness = 0.35

	mat_aged_wood = StandardMaterial3D.new()
	mat_aged_wood.albedo_color = Color(0.22, 0.12, 0.06)
	mat_aged_wood.roughness = 0.85

	mat_table_felt = StandardMaterial3D.new()
	mat_table_felt.albedo_color = Color(0.05, 0.18, 0.09)
	mat_table_felt.roughness = 0.95

	mat_leather_brown = StandardMaterial3D.new()
	mat_leather_brown.albedo_color = Color(0.14, 0.07, 0.04)
	mat_leather_brown.roughness = 0.7

	mat_pipe_industrial = StandardMaterial3D.new()
	mat_pipe_industrial.albedo_color = Color(0.60, 0.40, 0.08)
	mat_pipe_industrial.metallic = 0.7
	mat_pipe_industrial.roughness = 0.4

	mat_hazard_mark = StandardMaterial3D.new()
	mat_hazard_mark.albedo_color = Color(0.55, 0.45, 0.08)
	mat_hazard_mark.metallic = 0.4
	mat_hazard_mark.roughness = 0.65

	# Vidrio del portalámparas: neutro/pálido a propósito -- el color real de
	# la vibe (magenta, cian, violeta) lo pone la luz OmniLight de cada sala,
	# no la carcasa, así no hay choque entre el vidrio y el tinte de neón.
	mat_bulb_amber = StandardMaterial3D.new()
	mat_bulb_amber.albedo_color = Color(0.9, 0.88, 0.92)
	mat_bulb_amber.emission_enabled = true
	mat_bulb_amber.emission = Color(0.92, 0.9, 0.95)
	mat_bulb_amber.emission_energy_multiplier = 2.2

	mat_tube_cyan = StandardMaterial3D.new()
	mat_tube_cyan.albedo_color = Color(0.7, 0.95, 0.9)
	mat_tube_cyan.emission_enabled = true
	mat_tube_cyan.emission = Color(0.55, 0.95, 0.85)
	mat_tube_cyan.emission_energy_multiplier = 2.5

	mat_crt_phosphor = StandardMaterial3D.new()
	mat_crt_phosphor.albedo_color = Color(0.1, 0.45, 0.2)
	mat_crt_phosphor.emission_enabled = true
	mat_crt_phosphor.emission = Color(0.15, 0.75, 0.3)
	mat_crt_phosphor.emission_energy_multiplier = 2.0

	mat_fire_orange = StandardMaterial3D.new()
	mat_fire_orange.albedo_color = Color(1.0, 0.3, 0.05)
	mat_fire_orange.emission_enabled = true
	mat_fire_orange.emission = Color(1.0, 0.35, 0.08)
	mat_fire_orange.emission_energy_multiplier = 3.5


## Qué sala (con todos sus props) cae en qué posición del grid, y qué puertas
## entre salas están abiertas o cerradas, se decide con la seed -- así cada
## partida tiene un layout distinto sin perder el detalle hecho a mano.
var _room_positions: Dictionary = {}
var _door_open: Dictionary = {}

const GRID_POSITIONS_COUNT := 3 # grid de 3x3 salas
const ROOM_HIDE_OFFSETS := {
	"gambling": Vector3(-3.1, 0.8, -6.4), # detrás de la torre de parlantes de la cabina DJ
	"bar": Vector3(3.2, 0.8, 3.2),
	"boiler": Vector3(3.2, 0.8, 3.2),
	"cargo": Vector3(0.0, 0.8, 0.0),
	"restrooms": Vector3(-2.7, 0.8, -4.2),
	"workshop": Vector3(-3.2, 0.8, 0.0),
	"poker": Vector3(0.0, 0.8, 0.0),
	"vault": Vector3(1.8, 0.8, 1.8),
}


func generate(seed_value: int = -1) -> void:
	for c in get_children():
		c.queue_free()
	hider_spawn_points.clear()
	seeker_spawn_point = Vector3.ZERO
	_room_positions.clear()
	_door_open.clear()

	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value

	_build_monolithic_facility()


## Construye toda la instalación desde cero
func _build_monolithic_facility() -> void:
	var total_size := room_size * 3.0
	var half_total := total_size * 0.5

	# 1. CIMENTACIÓN BASE Y TECHO REFORZADO (Sellado 100% hermético)
	_create_box(Vector3(0, -0.25, 0), Vector3(total_size + 4.0, 0.5, total_size + 4.0), mat_concrete_floor)
	_create_box(Vector3(0, wall_height + 0.25, 0), Vector3(total_size + 4.0, 0.5, total_size + 4.0), mat_concrete_wall)

	# 2. MUROS PERIMETRALES EXTERIORES (Sólidos, sin aberturas hacia el exterior)
	var thick := 0.6
	_create_box(Vector3(0, wall_height * 0.5, -half_total), Vector3(total_size + thick * 2.0, wall_height, thick), mat_concrete_wall)
	_create_box(Vector3(0, wall_height * 0.5, half_total), Vector3(total_size + thick * 2.0, wall_height, thick), mat_concrete_wall)
	_create_box(Vector3(-half_total, wall_height * 0.5, 0), Vector3(thick, wall_height, total_size + thick * 2.0), mat_concrete_wall)
	_create_box(Vector3(half_total, wall_height * 0.5, 0), Vector3(thick, wall_height, total_size + thick * 2.0), mat_concrete_wall)

	# 3. CONECTIVIDAD RANDOM ENTRE SALAS (spanning tree + loops extra) y
	#    TABIQUES INTERNOS que respetan esa conectividad (puerta o muro sólido)
	_generate_connectivity()
	_build_internal_partitions()

	# 4. CONDUCTOS DE VENTILACIÓN Y TUBERÍAS SUSPENDIDAS
	_build_infrastructure()

	# 5. SALAS TEMÁTICAS EN POSICIONES RANDOM DEL GRID (mismos props de siempre,
	#    layout distinto en cada partida)
	_place_rooms()

	# 6. CLARABOYA: luz de "ventanas de techo" cayendo sobre la pista de baile
	_build_skylight()

	# 7. CONFIGURAR PUNTOS DE SPAWN ESTRATÉGICOS (según dónde cayó cada sala)
	_setup_tactical_spawns()


## Panel emisivo embebido en el techo, directo arriba de la sala que quedó
## asignada como pista de baile, + un par de focos apuntando hacia abajo
## simulando luz colándose por las ventanas del techo de la warehouse
## (se nota especialmente por la niebla del ambiente).
func _build_skylight() -> void:
	var dance_pos: Vector3 = _room_positions.get("gambling", Vector3.ZERO)
	var panel_size := room_size * 0.55

	var skylight_mat := StandardMaterial3D.new()
	skylight_mat.albedo_color = Color(0.75, 0.82, 0.95)
	skylight_mat.emission_enabled = true
	skylight_mat.emission = Color(0.7, 0.8, 1.0)
	skylight_mat.emission_energy_multiplier = 3.0
	_create_box(dance_pos + Vector3(0, wall_height + 0.05, 0), Vector3(panel_size, 0.15, panel_size), skylight_mat, false)

	# Marco de vigas cruzadas (look de armadura industrial)
	for offset in [-panel_size * 0.25, panel_size * 0.25]:
		_create_box(dance_pos + Vector3(offset, wall_height + 0.02, 0), Vector3(0.2, 0.2, panel_size), mat_dark_steel, false)
		_create_box(dance_pos + Vector3(0, wall_height + 0.02, offset), Vector3(panel_size, 0.2, 0.2), mat_dark_steel, false)

	# Focos simulando la luz que se cuela por las ventanas del techo
	var beam_offsets := [Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5), Vector3(2.5, 0, -2.5)]
	for offset in beam_offsets:
		var beam := SpotLight3D.new()
		beam.light_color = Color(0.75, 0.85, 1.0)
		beam.light_energy = 1.4
		beam.spot_range = wall_height + 1.0
		beam.spot_angle = 18.0
		add_child(beam)
		beam.position = dance_pos + offset + Vector3(0, wall_height - 0.2, 0)
		# Apunta derecho hacia abajo. Vector3.UP como "up" sería degenerado acá
		# (paralelo a la dirección), por eso usamos un vector perpendicular.
		beam.look_at(beam.position + Vector3(0, -1, 0), Vector3(0, 0, -1))


## Determinista con la seed: recorre el grid de 3x3 salas con backtracking
## (spanning tree, garantiza que todo esté conectado) y después abre loops
## extra al azar para que no sea un único camino obligatorio.
func _generate_connectivity() -> void:
	var visited: Dictionary = {}
	var start := Vector2i(0, 0)
	visited[start] = true
	var stack: Array = [start]

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var neighbors := _unvisited_grid_neighbors(current, visited)
		if neighbors.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = neighbors[rng.randi_range(0, neighbors.size() - 1)]
		_open_door(current, next)
		visited[next] = true
		stack.append(next)

	# Loops extra: con varias salas grandes conviene más probabilidad que en
	# el laberinto viejo de celdas chicas, si no se siente demasiado cerrado.
	for gx in GRID_POSITIONS_COUNT:
		for gy in GRID_POSITIONS_COUNT:
			var cell := Vector2i(gx, gy)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = cell + d
				if n.x >= GRID_POSITIONS_COUNT or n.y >= GRID_POSITIONS_COUNT:
					continue
				if not _is_door_open(cell, n) and rng.randf() < 0.35:
					_open_door(cell, n)


func _unvisited_grid_neighbors(cell: Vector2i, visited: Dictionary) -> Array:
	var result: Array = []
	var deltas := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in deltas:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.x < GRID_POSITIONS_COUNT and n.y >= 0 and n.y < GRID_POSITIONS_COUNT and not visited.has(n):
			result.append(n)
	return result


func _open_door(a: Vector2i, b: Vector2i) -> void:
	_door_open["%d,%d,%d,%d" % [a.x, a.y, b.x, b.y]] = true
	_door_open["%d,%d,%d,%d" % [b.x, b.y, a.x, a.y]] = true


func _is_door_open(a: Vector2i, b: Vector2i) -> bool:
	return _door_open.get("%d,%d,%d,%d" % [a.x, a.y, b.x, b.y], false)


## Fisher-Yates con NUESTRA rng seedeada (no Array.shuffle(), que usa el RNG
## global y daría un resultado distinto en cada cliente -- todos los peers
## tienen que construir exactamente el mismo mapa a partir de la misma seed).
func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Las 9 salas (con todos sus props tal cual las hizo cada builder) se
## reparten en posiciones random del grid 3x3 -- mismo contenido artesanal,
## layout distinto en cada partida.
func _place_rooms() -> void:
	var grid_positions: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(-room_size, 0, 0), Vector3(room_size, 0, 0),
		Vector3(0, 0, -room_size), Vector3(0, 0, room_size),
		Vector3(-room_size, 0, -room_size), Vector3(room_size, 0, -room_size),
		Vector3(-room_size, 0, room_size), Vector3(room_size, 0, room_size),
	]
	_seeded_shuffle(grid_positions)

	var room_keys := ["gambling", "bar", "boiler", "cargo", "restrooms", "security", "workshop", "poker", "vault"]

	for i in room_keys.size():
		var key: String = room_keys[i]
		var pos: Vector3 = grid_positions[i]
		_room_positions[key] = pos
		match key:
			"gambling":
				_build_gambling_arena(pos)
			"bar":
				_build_grimy_bar(pos)
			"boiler":
				_build_boiler_facility(pos)
			"cargo":
				_build_cargo_storage(pos)
			"restrooms":
				_build_restrooms_complex(pos)
			"security":
				_build_security_airlock(pos)
			"workshop":
				_build_maintenance_workshop(pos)
			"poker":
				_build_vip_poker_lounge(pos)
			"vault":
				_build_reinforced_vault(pos)

		# Vestimenta extra de club/warehouse en cada sala: al agrandar el
		# tamaño de sala (room_size), el mobiliario original -pensado para
		# salas más chicas- quedó disperso y se sentía vacío. Esto suma
		# densidad visual pareja en las 9 salas sin tocar el contenido
		# temático original de cada builder.
		_add_club_dressing(pos)


## Vestimenta genérica de club/warehouse para cualquier sala: parlantes PA,
## pallets apilados, un par de barriles sueltos y una tira de luces LED en
## el techo. Se ubica en las esquinas para no chocar con el mobiliario
## específico de cada sala (que suele estar más cerca del centro). Esto es
## lo que compensa la densidad de props que se diluyó al agrandar room_size.
func _add_club_dressing(pos: Vector3) -> void:
	var half := room_size * 0.5
	var inset := half - 1.6

	# Parlantes PA apilados en una esquina, con rejilla cian que brilla
	var speaker_corner := pos + Vector3(inset, 0, inset)
	_create_box(speaker_corner + Vector3(0, 0.9, 0), Vector3(1.1, 1.8, 1.0), mat_dark_steel)
	_create_box(speaker_corner + Vector3(0, 2.05, 0), Vector3(0.85, 0.5, 0.8), mat_dark_steel)

	var speaker_mat := StandardMaterial3D.new()
	speaker_mat.albedo_color = Color(0.15, 0.85, 0.95)
	speaker_mat.emission_enabled = true
	speaker_mat.emission = Color(0.1, 0.8, 0.95)
	speaker_mat.emission_energy_multiplier = 2.0
	_create_box(speaker_corner + Vector3(0, 0.9, 0.51), Vector3(0.7, 1.2, 0.04), speaker_mat, false)

	var speaker_light := OmniLight3D.new()
	speaker_light.position = speaker_corner + Vector3(0, 2.1, 0.5)
	speaker_light.light_color = Color(0.2, 0.85, 0.95)
	speaker_light.light_energy = 0.55
	speaker_light.omni_range = 3.2
	add_child(speaker_light)

	# Pallets de cajas apiladas en la esquina opuesta
	var stack_corner := pos + Vector3(-inset, 0, -inset)
	for i in 3:
		var box_size := Vector3(1.15, 0.5, 1.15)
		var stack_pos := stack_corner + Vector3(0, 0.28 + i * 0.52, 0)
		var mat := mat_aged_wood if i % 2 == 0 else mat_dark_steel
		_create_box(stack_pos, box_size, mat)

	# Barriles sueltos -- posición semi-random pero determinista con la seed
	for i in 2:
		var offset := Vector3(
			rng.randf_range(-room_size * 0.28, room_size * 0.28),
			0.0,
			rng.randf_range(-room_size * 0.28, room_size * 0.28)
		)
		_create_cylinder(pos + offset + Vector3(0, 0.45, 0), 0.34, 0.9, mat_rust_metal)

	# Tira de luces LED montada CONTRA la pared cerca del techo (antes quedaba
	# flotando en el medio del aire sin ningún soporte -- ahora queda pegada
	# a la pared, como una instalación real)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(1.0, 0.15, 0.55)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 0.1, 0.55)
	strip_mat.emission_energy_multiplier = 2.5

	var strip_y := wall_height - 0.35
	var steps := 5
	for i in steps:
		var t := float(i) / float(steps - 1)
		var lx: float = lerpf(-half + 1.0, half - 1.0, t)
		# Riel metálico de montaje (da la sensación de estar atornillado)
		_create_box(pos + Vector3(lx, strip_y, -half + 0.08), Vector3(0.55, 0.1, 0.05), mat_dark_steel, false)
		_create_box(pos + Vector3(lx, strip_y, half - 0.08), Vector3(0.55, 0.1, 0.05), mat_dark_steel, false)
		# Tira LED propiamente dicha, pegada al riel
		_create_box(pos + Vector3(lx, strip_y, -half + 0.14), Vector3(0.5, 0.05, 0.05), strip_mat, false)
		_create_box(pos + Vector3(lx, strip_y, half - 0.14), Vector3(0.5, 0.05, 0.05), strip_mat, false)

	var strip_light := OmniLight3D.new()
	strip_light.position = pos + Vector3(0, strip_y - 0.3, 0)
	strip_light.light_color = Color(1.0, 0.2, 0.6)
	strip_light.light_energy = 0.4
	strip_light.omni_range = room_size * 0.6
	add_child(strip_light)


## Tabiques interiores entre las 9 salas: puerta con marco si la conectividad
## random dice que ese paso está abierto, o muro sólido si está cerrado.
func _build_internal_partitions() -> void:
	var door_w := 2.6
	var door_h := 2.5
	var wall_thick := 0.3
	var coord_to_grid := {-room_size: 0, 0.0: 1, room_size: 2}

	# Divisiones Verticales en X = -room_size/2 (-6m) y X = +room_size/2 (+6m)
	for x_line in [-room_size * 0.5, room_size * 0.5]:
		var gx_left: int = 0 if x_line < 0.0 else 1
		for z_room in [-room_size, 0.0, room_size]:
			var gy: int = coord_to_grid[z_room]
			var is_door: bool = _is_door_open(Vector2i(gx_left, gy), Vector2i(gx_left + 1, gy))
			_create_partition_wall(
				Vector3(x_line, 0, z_room),
				room_size,
				wall_height,
				door_w,
				door_h,
				wall_thick,
				true, # vertical
				mat_concrete_wall,
				is_door
			)

	# Divisiones Horizontales en Z = -room_size/2 (-6m) y Z = +room_size/2 (+6m)
	for z_line in [-room_size * 0.5, room_size * 0.5]:
		var gy_top: int = 0 if z_line < 0.0 else 1
		for x_room in [-room_size, 0.0, room_size]:
			var gx: int = coord_to_grid[x_room]
			var is_door: bool = _is_door_open(Vector2i(gx, gy_top), Vector2i(gx, gy_top + 1))
			_create_partition_wall(
				Vector3(x_room, 0, z_line),
				room_size,
				wall_height,
				door_w,
				door_h,
				wall_thick,
				false, # horizontal
				mat_concrete_wall,
				is_door
			)


## Muro divisorio: con vano y marco de puerta si is_door, o macizo si no.
func _create_partition_wall(center: Vector3, length: float, height: float, door_w: float, door_h: float, thick: float, vertical: bool, mat: StandardMaterial3D, is_door: bool = true) -> void:
	if not is_door:
		if vertical:
			_create_box(center + Vector3(0, height * 0.5, 0), Vector3(thick, height, length), mat)
		else:
			_create_box(center + Vector3(0, height * 0.5, 0), Vector3(length, height, thick), mat)
		return

	var side_len := (length - door_w) * 0.5
	var side_offset := (length + door_w) * 0.25
	var lintel_h := height - door_h

	if vertical:
		_create_box(center + Vector3(0, height * 0.5, -side_offset), Vector3(thick, height, side_len), mat)
		_create_box(center + Vector3(0, height * 0.5, side_offset), Vector3(thick, height, side_len), mat)
		_create_box(center + Vector3(0, door_h + lintel_h * 0.5, 0), Vector3(thick, lintel_h, door_w), mat)
		# Marco de puerta metálico
		_create_box(center + Vector3(0, door_h * 0.5, -door_w * 0.5), Vector3(thick * 1.25, door_h, 0.08), mat_rust_metal)
		_create_box(center + Vector3(0, door_h * 0.5, door_w * 0.5), Vector3(thick * 1.25, door_h, 0.08), mat_rust_metal)
		_create_box(center + Vector3(0, door_h, 0), Vector3(thick * 1.25, 0.08, door_w), mat_rust_metal)
	else:
		_create_box(center + Vector3(-side_offset, height * 0.5, 0), Vector3(side_len, height, thick), mat)
		_create_box(center + Vector3(side_offset, height * 0.5, 0), Vector3(side_len, height, thick), mat)
		_create_box(center + Vector3(0, door_h + lintel_h * 0.5, 0), Vector3(door_w, lintel_h, thick), mat)
		# Marco de puerta metálico
		_create_box(center + Vector3(-door_w * 0.5, door_h * 0.5, 0), Vector3(0.08, door_h, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(door_w * 0.5, door_h * 0.5, 0), Vector3(0.08, door_h, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(0, door_h, 0), Vector3(door_w, 0.08, thick * 1.25), mat_rust_metal)


## Conductos HVAC y vigas de soporte en el techo
func _build_infrastructure() -> void:
	var total_size := room_size * 3.0
	# Vigas de acero en cruz
	for x in [-room_size, 0.0, room_size]:
		_create_box(Vector3(x, wall_height - 0.15, 0), Vector3(0.3, 0.3, total_size), mat_dark_steel, false)
	for z in [-room_size, 0.0, room_size]:
		_create_box(Vector3(0, wall_height - 0.15, z), Vector3(total_size, 0.3, 0.3), mat_dark_steel, false)

	# Conductos de ventilación galvanizados suspendidos
	_create_box(Vector3(0, wall_height - 0.45, 0), Vector3(total_size * 0.85, 0.4, 0.7), mat_dark_steel, false)
	_create_box(Vector3(0, wall_height - 0.45, 0), Vector3(0.7, 0.4, total_size * 0.85), mat_dark_steel, false)


# ==============================================================================
# SALAS TEMÁTICAS DETALLADAS (BUCKSHOT ROULETTE AESTHETIC)
# ==============================================================================

## 1. PISTA DE BAILE PRINCIPAL + DJ SET (Centro) -- el corazón del club
func _build_gambling_arena(pos: Vector3) -> void:
	# Piso de pista con panels de colores alternados (estilo disco clásico)
	var tile_size := 1.5
	var tiles_per_side := 6
	var floor_span := tile_size * tiles_per_side
	var start := -floor_span * 0.5 + tile_size * 0.5
	var tile_colors := [
		Color(0.9, 0.1, 0.5), Color(0.15, 0.85, 0.95),
		Color(0.6, 0.15, 1.0), Color(1.0, 0.5, 0.05),
	]
	_create_box(pos + Vector3(0, -0.05, 0), Vector3(room_size - 0.4, 0.1, room_size - 0.4), mat_concrete_floor)
	for ix in tiles_per_side:
		for iz in tiles_per_side:
			var tx: float = start + ix * tile_size
			var tz: float = start + iz * tile_size
			var tile_mat := StandardMaterial3D.new()
			var c: Color = tile_colors[(ix + iz) % tile_colors.size()]
			tile_mat.albedo_color = c
			tile_mat.emission_enabled = true
			tile_mat.emission = c
			tile_mat.emission_energy_multiplier = 1.4
			_create_box(pos + Vector3(tx, 0.03, tz), Vector3(tile_size - 0.06, 0.06, tile_size - 0.06), tile_mat, false)

	# DJ BOOTH elevado contra la pared norte
	var booth_z: float = -room_size * 0.5 + 1.6
	_create_box(pos + Vector3(0, 0.5, booth_z), Vector3(4.2, 1.0, 1.6), mat_dark_steel)
	_create_box(pos + Vector3(0, 1.05, booth_z), Vector3(3.8, 0.1, 1.3), mat_rust_metal)
	_create_box(pos + Vector3(0, 1.15, booth_z - 0.3), Vector3(1.6, 0.12, 0.5), mat_dark_steel)

	# Música del DJ (opcional, tu propio .ogg/.mp3 desde el Inspector).
	# Audio 3D posicional -- se re-loopea sola sin importar la configuración
	# de import del archivo.
	if club_music != null:
		var music_player := AudioStreamPlayer3D.new()
		music_player.stream = club_music
		music_player.unit_size = 22.0
		music_player.max_db = 3.0
		add_child(music_player)
		music_player.position = pos + Vector3(0, 1.4, booth_z)
		music_player.play()
		music_player.finished.connect(func(): music_player.play())

	# Torres de parlantes flanqueando la cabina (una de las dos es el escondite)
	for side in [-1, 1]:
		var speaker_x: float = side * 3.1
		_create_box(pos + Vector3(speaker_x, 1.1, booth_z), Vector3(1.1, 2.2, 1.0), mat_dark_steel)
		_create_box(pos + Vector3(speaker_x, 1.1, booth_z + 0.51), Vector3(0.9, 1.8, 0.05), mat_dark_steel)

		var glow_mat := StandardMaterial3D.new()
		var glow_c: Color = Color(0.15, 0.85, 0.95) if side < 0 else Color(0.9, 0.1, 0.5)
		glow_mat.albedo_color = glow_c
		glow_mat.emission_enabled = true
		glow_mat.emission = glow_c
		glow_mat.emission_energy_multiplier = 2.0
		_create_box(pos + Vector3(speaker_x, 1.9, booth_z + 0.53), Vector3(0.7, 0.35, 0.03), glow_mat, false)

	# Baranda separando la cabina de la pista
	_create_box(pos + Vector3(0, 0.5, booth_z + 1.0), Vector3(4.6, 0.06, 0.06), mat_dark_steel, false)
	for bx in [-2.2, -1.1, 0.0, 1.1, 2.2]:
		_create_box(pos + Vector3(bx, 0.25, booth_z + 1.0), Vector3(0.05, 0.5, 0.05), mat_dark_steel)

	# "Bola de espejos" simplificada colgando del centro
	_create_cylinder(pos + Vector3(0, wall_height - 0.4, 0), 0.02, 1.2, mat_dark_steel, false)
	var mirror_mat := StandardMaterial3D.new()
	mirror_mat.albedo_color = Color(0.85, 0.85, 0.9)
	mirror_mat.metallic = 1.0
	mirror_mat.roughness = 0.05
	_create_cylinder(pos + Vector3(0, wall_height - 1.0, 0), 0.55, 0.55, mirror_mat, false)

	# 4 focos de "show" apuntando al centro desde las esquinas
	var show_colors := [Color(1.0, 0.15, 0.55), Color(0.15, 0.85, 0.95), Color(0.6, 0.15, 1.0), Color(1.0, 0.5, 0.05)]
	var corner_dirs := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	for i in 4:
		var corner_pos: Vector3 = pos + corner_dirs[i] * (room_size * 0.4) + Vector3(0, wall_height - 0.3, 0)
		var spot := SpotLight3D.new()
		spot.light_color = show_colors[i]
		spot.light_energy = 2.0
		spot.spot_range = room_size * 0.7
		spot.spot_angle = 28.0
		add_child(spot)
		spot.global_position = corner_pos
		spot.look_at(pos + Vector3(0, 0.5, 0), Vector3.UP)

	# Luz de relleno general de pista
	var floor_light := OmniLight3D.new()
	floor_light.position = pos + Vector3(0, wall_height - 1.5, 0)
	floor_light.light_color = Color(0.8, 0.3, 0.9)
	floor_light.light_energy = 0.6
	floor_light.omni_range = room_size * 0.7
	add_child(floor_light)


## 2. EL BAR & VIP LOUNGE (Oeste)
func _build_grimy_bar(pos: Vector3) -> void:
	# Barra de bar en L
	_create_box(pos + Vector3(-1.5, 0.55, -2.2), Vector3(4.2, 1.1, 0.8), mat_aged_wood)
	_create_box(pos + Vector3(0.2, 0.55, -0.8), Vector3(0.8, 1.1, 2.0), mat_aged_wood)
	_create_box(pos + Vector3(-1.5, 1.12, -2.2), Vector3(4.4, 0.08, 0.95), mat_rust_metal)

	# Taburetes de bar frente a la barra
	for x in [-3.0, -2.0, -1.0]:
		_create_cylinder(pos + Vector3(x, 0.45, -1.1), 0.22, 0.9, mat_leather_brown)

	# Estantería trasera de botellas
	_create_box(pos + Vector3(-1.5, 1.6, -5.2), Vector3(4.0, 1.8, 0.35), mat_aged_wood)
	for h in [1.0, 1.6, 2.2]:
		_create_box(pos + Vector3(-1.5, h, -5.0), Vector3(3.8, 0.05, 0.3), mat_dark_steel)

	# Sofá esquinero de cuero / Booth VIP (Escondite detrás del respaldo)
	_create_box(pos + Vector3(3.2, 0.35, 3.2), Vector3(2.8, 0.7, 1.0), mat_leather_brown)
	_create_box(pos + Vector3(4.1, 0.75, 3.2), Vector3(0.5, 1.5, 2.8), mat_leather_brown)
	_create_box(pos + Vector3(3.2, 0.75, 4.1), Vector3(2.8, 1.5, 0.5), mat_leather_brown)
	_create_box(pos + Vector3(2.2, 0.25, 2.2), Vector3(1.2, 0.5, 0.8), mat_aged_wood)

	# Iluminación de bar tenue
	_create_hanging_lamp(pos + Vector3(-1.5, wall_height, -2.2), 3.6, Color(0.2, 0.85, 0.95), 1.3, 7.0)
	_create_hanging_lamp(pos + Vector3(2.5, wall_height, 2.5), 3.6, Color(0.9, 0.1, 0.5), 1.1, 6.0)


## 3. SALA DE CALDERAS & GENERADOR (Este)
func _build_boiler_facility(pos: Vector3) -> void:
	# Caldera cilíndrica central gigante
	_create_cylinder(pos + Vector3(0, 1.4, 0), 1.35, 2.8, mat_rust_metal)
	_create_box(pos + Vector3(0, 0.6, 1.35), Vector3(0.8, 0.5, 0.15), mat_fire_orange) # Brillo de fuego

	# Tuberías principales de vapor
	_create_cylinder(pos + Vector3(0, 2.8, 0), 0.35, 1.4, mat_dark_steel)
	_create_box(pos + Vector3(0, wall_height - 0.3, 0), Vector3(room_size * 0.8, 0.22, 0.22), mat_pipe_industrial, false)

	# Tableros eléctricos con marcas de peligro
	_create_box(pos + Vector3(-4.8, 1.5, 1.5), Vector3(0.35, 1.8, 1.2), mat_hazard_mark)
	_create_box(pos + Vector3(-4.8, 1.5, -1.5), Vector3(0.35, 1.8, 1.2), mat_rust_metal)

	# Pilas de barriles de combustible en la esquina
	var barrels := [Vector3(3.2, 0, 3.2), Vector3(4.0, 0, 3.0), Vector3(3.5, 0, 4.2), Vector3(3.6, 0.9, 3.6)]
	for b in barrels:
		_create_cylinder(pos + b + Vector3(0, 0.45, 0), 0.38, 0.9, mat_rust_metal)

	# Foco de emergencia rojo/fuego
	var fire_light := OmniLight3D.new()
	fire_light.position = pos + Vector3(0, 1.2, 1.8)
	fire_light.light_color = Color(1.0, 0.3, 0.08)
	fire_light.light_energy = 2.0
	fire_light.omni_range = 8.5
	fire_light.shadow_enabled = true
	add_child(fire_light)


## 4. ALMACÉN DE CARGA & ESTANTERÍAS (Norte)
func _build_cargo_storage(pos: Vector3) -> void:
	# 2 Estanterías industriales metálicas paralelas de doble piso (Aisle de sigilo)
	_create_pallet_rack(pos + Vector3(-2.2, 0, 0), 4.6, 2.8)
	_create_pallet_rack(pos + Vector3(2.2, 0, 0), 4.6, 2.8)

	# Cajas apiladas en esquinas para cobertura
	_create_box(pos + Vector3(-3.8, 0.6, 3.8), Vector3(1.3, 1.2, 1.3), mat_aged_wood)
	_create_box(pos + Vector3(-3.8, 1.5, 3.8), Vector3(0.8, 0.6, 0.8), mat_aged_wood)
	_create_box(pos + Vector3(3.8, 0.5, -3.8), Vector3(1.2, 1.0, 1.2), mat_aged_wood)

	# Iluminación de depósito
	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 3.2, Color(0.55, 0.25, 1.0), 1.3, 8.0)


## 5. BAÑOS & TUBERÍAS DE DRENAJE (Sur)
func _build_restrooms_complex(pos: Vector3) -> void:
	# Suelo y paredes de azulejos verde-azulados
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 0.4, 0.04, room_size - 0.4), mat_tile_floor)

	# 3 Cubículos de inodoro cerrados (Hiders pueden entrar a esconderse)
	for i in 3:
		var cx := -3.4 + i * 1.5
		# Tabique lateral
		_create_box(pos + Vector3(cx, 1.1, -3.2), Vector3(0.08, 2.2, 2.8), mat_rust_metal)
		# Taza de baño
		_create_box(pos + Vector3(cx + 0.7, 0.35, -4.2), Vector3(0.45, 0.7, 0.6), mat_tile_wall)
		# Puerta con pequeña rendija
		_create_box(pos + Vector3(cx + 0.35, 1.05, -1.8), Vector3(0.7, 2.1, 0.06), mat_aged_wood)

	# Tabique de cierre
	_create_box(pos + Vector3(-3.4 + 3 * 1.5, 1.1, -3.2), Vector3(0.08, 2.2, 2.8), mat_rust_metal)

	# Mostrador de lavamanos y espejo
	_create_box(pos + Vector3(3.6, 0.45, 0), Vector3(0.8, 0.9, 3.6), mat_concrete_wall)
	_create_box(pos + Vector3(4.1, 1.5, 0), Vector3(0.05, 0.9, 3.2), mat_dark_steel)

	# Tubo fluorescente parpadeante frío
	_create_fluorescent_fixture(pos + Vector3(0, wall_height - 0.05, 0), Color(0.3, 0.9, 0.95), 1.6, 9.0)


## 6. OFICINA DE SEGURIDAD & CELDA DE CONTENCIÓN (Noroeste - Spawn Atrapador)
func _build_security_airlock(pos: Vector3) -> void:
	# Puesto de control / Escritorio con monitores CRT de fósforo verde
	_create_box(pos + Vector3(0, 0.4, -2.4), Vector3(3.2, 0.8, 1.2), mat_dark_steel)
	_create_box(pos + Vector3(-0.7, 1.0, -2.4), Vector3(0.6, 0.5, 0.5), mat_crt_phosphor)
	_create_box(pos + Vector3(0.7, 1.0, -2.4), Vector3(0.6, 0.5, 0.5), mat_crt_phosphor)
	_create_chair(pos + Vector3(0, 0, -1.4), 0.0)

	# Banco de 4 casilleros metálicos altos
	for i in 4:
		var lx := -3.5 + i * 0.7
		_create_box(pos + Vector3(lx, 1.15, 3.8), Vector3(0.65, 2.3, 0.5), mat_rust_metal)

	# Luz fría de monitores + lámpara superior
	var crt_light := OmniLight3D.new()
	crt_light.position = pos + Vector3(0, 1.8, -2.2)
	crt_light.light_color = Color(0.25, 0.85, 0.4)
	crt_light.light_energy = 1.0
	crt_light.omni_range = 4.5
	add_child(crt_light)

	_create_hanging_lamp(pos + Vector3(0, wall_height, 1.0), 3.4, Color(1.0, 0.2, 0.6), 1.0, 6.5)

	_build_holding_cell(pos + Vector3(3.6, 0, 1.2))


## Celda de contención de donde escapó el Atrapador: rejas en 3 lados, una
## abertura al frente (la puerta forzada), catre volcado y cadena colgando.
## Luz roja de alarma en vez del resto de la paleta neón de la sala, para
## que se lea claramente distinta -- es la escena del "quiebre".
func _build_holding_cell(cell_center: Vector3) -> void:
	var cell_w := 2.6
	var cell_d := 2.6
	var bar_h := 2.2
	var bar_spacing := 0.32

	# Reja trasera (cerrada)
	var back_bars := int(cell_w / bar_spacing)
	for i in back_bars:
		var bx: float = -cell_w * 0.5 + i * bar_spacing
		_create_box(cell_center + Vector3(bx, bar_h * 0.5, -cell_d * 0.5), Vector3(0.05, bar_h, 0.05), mat_rust_metal)

	# Reja lateral (cerrada)
	var side_bars := int(cell_d / bar_spacing)
	for i in side_bars:
		var bz: float = -cell_d * 0.5 + i * bar_spacing
		_create_box(cell_center + Vector3(-cell_w * 0.5, bar_h * 0.5, bz), Vector3(0.05, bar_h, 0.05), mat_rust_metal)

	# Reja frontal ROTA -- hueco de la puerta forzada, por acá se escapó
	var front_bars := int(cell_w / bar_spacing)
	for i in front_bars:
		var bx: float = -cell_w * 0.5 + i * bar_spacing
		if absf(bx) < cell_w * 0.28:
			continue
		_create_box(cell_center + Vector3(bx, bar_h * 0.5, cell_d * 0.5), Vector3(0.05, bar_h, 0.05), mat_rust_metal)

	# Marco superior/lateral
	_create_box(cell_center + Vector3(0, bar_h, -cell_d * 0.5), Vector3(cell_w, 0.08, 0.08), mat_dark_steel)
	_create_box(cell_center + Vector3(-cell_w * 0.5, bar_h, 0), Vector3(0.08, 0.08, cell_d), mat_dark_steel)

	# Catre metálico volcado + colchón fino
	_create_box(cell_center + Vector3(0.2, 0.32, -0.6), Vector3(1.7, 0.12, 0.75), mat_dark_steel)
	_create_box(cell_center + Vector3(0.2, 0.4, -0.6), Vector3(1.6, 0.1, 0.7), mat_leather_brown)

	# Cadena colgando de la reja rota
	_create_cylinder(cell_center + Vector3(cell_w * 0.28, bar_h * 0.6, cell_d * 0.5), 0.02, bar_h * 0.5, mat_dark_steel)

	var cell_light := OmniLight3D.new()
	cell_light.position = cell_center + Vector3(0, bar_h + 0.3, 0)
	cell_light.light_color = Color(0.95, 0.15, 0.15)
	cell_light.light_energy = 0.7
	cell_light.omni_range = 4.0
	add_child(cell_light)


## 7. TALLER DE REPARACIONES (Noreste)
func _build_maintenance_workshop(pos: Vector3) -> void:
	# Mesa pesada de carpintería / tornería
	_create_box(pos + Vector3(-3.8, 0.5, 0), Vector3(0.9, 1.0, 3.6), mat_rust_metal)
	_create_box(pos + Vector3(-4.4, 1.6, 0), Vector3(0.08, 1.2, 3.4), mat_hazard_mark)

	# Compresor de aire cilíndrico
	_create_cylinder(pos + Vector3(2.5, 0.8, -3.5), 0.45, 1.6, mat_pipe_industrial)

	# Carro de herramientas rodante
	_create_box(pos + Vector3(1.5, 0.45, 2.2), Vector3(0.8, 0.9, 1.1), mat_rust_metal)

	_create_fluorescent_fixture(pos + Vector3(0, wall_height - 0.05, 0), Color(0.4, 0.95, 0.9), 1.3, 8.0)


## 8. SALA PRIVADA DE PÓKER VIP (Suroeste)
func _build_vip_poker_lounge(pos: Vector3) -> void:
	# Mesa redonda de póker VIP
	_create_cylinder(pos + Vector3(0, 0.42, 0), 1.1, 0.84, mat_aged_wood)
	_create_cylinder(pos + Vector3(0, 0.85, 0), 1.0, 0.05, mat_table_felt)

	# Maletín de contrabando sobre la mesa
	_create_box(pos + Vector3(0.2, 0.92, 0.1), Vector3(0.45, 0.1, 0.3), mat_dark_steel)

	# 3 Sillones de cuero amplios
	for a in [0.0, 2.1, 4.2]:
		var offset := Vector3(cos(a) * 1.8, 0, sin(a) * 1.8)
		_create_box(pos + offset + Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), mat_leather_brown)

	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 3.8, Color(0.7, 0.15, 1.0), 1.6, 7.0)


## 9. BÓVEDA & CAJA FUERTE (Sureste)
func _build_reinforced_vault(pos: Vector3) -> void:
	# Puerta de bóveda acorazada con rueda central
	_create_box(pos + Vector3(0, 1.4, 4.8), Vector3(2.6, 2.8, 0.4), mat_dark_steel)
	_create_cylinder(pos + Vector3(0, 1.4, 4.5), 0.6, 0.3, mat_rust_metal)

	# Rejas metálicas de seguridad
	_create_box(pos + Vector3(-2.2, 1.1, -1.0), Vector3(0.08, 2.2, 2.6), mat_dark_steel)

	# Cajas fuertes pequeñas y lingoteras apiladas
	_create_box(pos + Vector3(2.0, 0.3, 2.0), Vector3(1.0, 0.6, 1.0), mat_rust_metal)
	_create_box(pos + Vector3(2.0, 0.8, 2.0), Vector3(0.8, 0.4, 0.8), mat_dark_steel)
	_create_box(pos + Vector3(2.8, 0.25, 1.6), Vector3(0.6, 0.5, 0.8), mat_aged_wood)

	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 3.4, Color(1.0, 0.1, 0.35), 1.2, 6.5)


# ==============================================================================
# HELPERS DE CONSTRUCCIÓN DE PROPS
# ==============================================================================

func _create_chair(pos: Vector3, rot_y: float) -> void:
	var base := Node3D.new()
	base.position = pos
	base.rotation.y = rot_y
	add_child(base)

	# Asiento
	_add_primitive_box(base, Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), mat_aged_wood)
	# Respaldo
	_add_primitive_box(base, Vector3(0, 0.75, -0.2), Vector3(0.45, 0.55, 0.06), mat_aged_wood)
	# Patas
	for dx in [-0.18, 0.18]:
		for dz in [-0.18, 0.18]:
			_add_primitive_box(base, Vector3(dx, 0.22, dz), Vector3(0.05, 0.44, 0.05), mat_dark_steel)


func _create_pallet_rack(pos: Vector3, length: float, height: float) -> void:
	var w := 0.95
	for dx in [-length * 0.5, 0.0, length * 0.5]:
		for dz in [-w * 0.5, w * 0.5]:
			_create_box(pos + Vector3(dx, height * 0.5, dz), Vector3(0.08, height, 0.08), mat_rust_metal)

	for h in [0.75, 1.55, 2.35]:
		_create_box(pos + Vector3(0, h, 0), Vector3(length, 0.06, w), mat_rust_metal)
		_create_box(pos + Vector3(length * 0.25, h + 0.25, 0), Vector3(0.6, 0.45, 0.6), mat_aged_wood)
		_create_box(pos + Vector3(-length * 0.25, h + 0.22, 0), Vector3(0.5, 0.4, 0.5), mat_aged_wood)


func _create_hanging_lamp(pos: Vector3, cable_len: float, color: Color, energy: float, light_range: float) -> void:
	_create_cylinder(pos - Vector3(0, cable_len * 0.5, 0), 0.02, cable_len, mat_dark_steel, false)
	_create_cylinder(pos - Vector3(0, cable_len, 0), 0.35, 0.2, mat_rust_metal, false)
	_create_cylinder(pos - Vector3(0, cable_len + 0.05, 0), 0.12, 0.1, mat_bulb_amber, false)

	var omni := OmniLight3D.new()
	omni.position = pos - Vector3(0, cable_len + 0.2, 0)
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = light_range
	omni.shadow_enabled = true
	add_child(omni)


func _create_fluorescent_fixture(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	_create_box(pos, Vector3(0.3, 0.1, 1.8), mat_dark_steel, false)
	_create_box(pos - Vector3(0, 0.06, 0), Vector3(0.12, 0.05, 1.6), mat_tube_cyan, false)

	var omni := OmniLight3D.new()
	omni.position = pos - Vector3(0, 0.3, 0)
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = light_range
	omni.shadow_enabled = true
	add_child(omni)


# ==============================================================================
# SPAWN TÁCTICO
# ==============================================================================

## Los puntos de escondite son los mismos de siempre (tras el pilar, el sofá,
## los barriles, etc.) pero ahora se ubican donde haya caído cada sala esta
## partida, porque el layout completo se randomiza con la seed.
func _setup_tactical_spawns() -> void:
	# El Seeker aparece en la sala que quedó asignada como Oficina de Seguridad
	seeker_spawn_point = _room_positions["security"] + Vector3(0, 0.8, 0)

	hider_spawn_points.clear()
	for key in ROOM_HIDE_OFFSETS.keys():
		hider_spawn_points.append(_room_positions[key] + ROOM_HIDE_OFFSETS[key])
	_seeded_shuffle(hider_spawn_points)


# ==============================================================================
# PRIMITIVAS Y COLISIONES BÁSICAS
# ==============================================================================

func _create_box(center: Vector3, size: Vector3, mat: StandardMaterial3D, has_collision: bool = true) -> Node3D:
	if has_collision:
		var body := StaticBody3D.new()
		body.position = center
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
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		return mi


func _create_cylinder(center: Vector3, radius: float, height: float, mat: StandardMaterial3D, has_collision: bool = true) -> Node3D:
	if has_collision:
		var body := StaticBody3D.new()
		body.position = center
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
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = height
		mi.mesh = cyl
		mi.material_override = mat
		add_child(mi)
		return mi


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
