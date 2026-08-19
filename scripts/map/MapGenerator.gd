extends Node3D
class_name MapGenerator
## =============================================================================
## COMPLEJO SUBTERRÁNEO CLANDESTINO (ESTILO BUCKSHOT ROULETTE) - GENERACIÓN DESDE CERO
## =============================================================================
## Blueprint arquitectónico de 36m x 36m con 9 salas temáticas realistas e interconectadas:
##
##   [ SEGURIDAD & ACCESO ] ─── [ ALMACÉN DE CARGA ] ─── [ TALLER DE REPARACIONES ]
##            │                            │                            │
##   [ BAR & LOUNGE VIP ]   ─── [ SALÓN DE RULETA  ] ─── [ SALA DE CALDERAS     ]
##            │                            │                            │
##   [ SALA VIP DE PÓKER ]  ─── [ BAÑOS & TUBERÍAS ] ─── [ BÓVEDA & CAJA FUERTE  ]
##
## - Estructura física cerrada y sólida (sin huecos al vacío ni salidas falsas).
## - Suelo y techo monolíticos con acabados específicos por zona.
## - Mobiliario y props 3D detallados con colisiones reales (Mesa central, Barra,
##   Calderas, Cubículos de baño, Estanterías de carga, Casilleros, Tuberías y Lámparas).
## - Puntos de spawn estratégicos y distribuidos.
## =============================================================================

@export var room_size: float = 12.0
@export var wall_height: float = 3.6

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

	mat_bulb_amber = StandardMaterial3D.new()
	mat_bulb_amber.albedo_color = Color(1.0, 0.75, 0.4)
	mat_bulb_amber.emission_enabled = true
	mat_bulb_amber.emission = Color(1.0, 0.68, 0.28)
	mat_bulb_amber.emission_energy_multiplier = 3.0

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


func generate(seed_value: int = -1) -> void:
	for c in get_children():
		c.queue_free()
	hider_spawn_points.clear()
	seeker_spawn_point = Vector3.ZERO

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

	# 3. TABIQUES INTERNOS DIVISORIOS CON PUERTAS
	_build_internal_partitions()

	# 4. CONDUCTOS DE VENTILACIÓN Y TUBERÍAS SUSPENDIDAS
	_build_infrastructure()

	# 5. SALAS TEMÁTICAS INDIVIDUALES CON PROPS 3D DETALLADOS
	_build_gambling_arena(Vector3(0, 0, 0))                          # (0, 0)
	_build_grimy_bar(Vector3(-room_size, 0, 0))                      # (-1, 0)
	_build_boiler_facility(Vector3(room_size, 0, 0))                 # (1, 0)
	_build_cargo_storage(Vector3(0, 0, -room_size))                  # (0, -1)
	_build_restrooms_complex(Vector3(0, 0, room_size))               # (0, 1)
	_build_security_airlock(Vector3(-room_size, 0, -room_size))      # (-1, -1)
	_build_maintenance_workshop(Vector3(room_size, 0, -room_size))   # (1, -1)
	_build_vip_poker_lounge(Vector3(-room_size, 0, room_size))       # (-1, 1)
	_build_reinforced_vault(Vector3(room_size, 0, room_size))        # (1, 1)

	# 6. CONFIGURAR PUNTOS DE SPAWN ESTRATÉGICOS
	_setup_tactical_spawns()


## Tabiques interiores con puertas entre las 9 salas
func _build_internal_partitions() -> void:
	var door_w := 2.6
	var door_h := 2.5
	var wall_thick := 0.3

	# Divisiones Verticales en X = -room_size/2 (-6m) y X = +room_size/2 (+6m)
	for x_line in [-room_size * 0.5, room_size * 0.5]:
		for z_room in [-room_size, 0.0, room_size]:
			_create_partition_wall(
				Vector3(x_line, 0, z_room),
				room_size,
				wall_height,
				door_w,
				door_h,
				wall_thick,
				true, # vertical
				mat_concrete_wall
			)

	# Divisiones Horizontales en Z = -room_size/2 (-6m) y Z = +room_size/2 (+6m)
	for z_line in [-room_size * 0.5, room_size * 0.5]:
		for x_room in [-room_size, 0.0, room_size]:
			_create_partition_wall(
				Vector3(x_room, 0, z_line),
				room_size,
				wall_height,
				door_w,
				door_h,
				wall_thick,
				false, # horizontal
				mat_concrete_wall
			)


## Muro divisorio con vano y marco de puerta
func _create_partition_wall(center: Vector3, length: float, height: float, door_w: float, door_h: float, thick: float, vertical: bool, mat: StandardMaterial3D) -> void:
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

## 1. SALÓN DE RULETA / GAMBLING ARENA (Centro)
func _build_gambling_arena(pos: Vector3) -> void:
	# Suelo de madera desgastada
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 0.4, 0.04, room_size - 0.4), mat_wood_floor)

	# 4 Columnas de hormigón con refuerzo metálico
	var col_dist := 3.6
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			_create_box(pos + Vector3(dx * col_dist, wall_height * 0.5, dz * col_dist), Vector3(0.8, wall_height, 0.8), mat_concrete_wall)
			_create_box(pos + Vector3(dx * col_dist, 0.2, dz * col_dist), Vector3(0.95, 0.4, 0.95), mat_rust_metal)

	# LA MESA DEL DEALER (Mesa central de apuestas icónica)
	_create_box(pos + Vector3(0, 0.4, 0), Vector3(3.2, 0.8, 1.8), mat_aged_wood)
	_create_box(pos + Vector3(0, 0.82, 0), Vector3(2.8, 0.05, 1.4), mat_table_felt)

	# Cenicero y botellas sobre la mesa
	_create_cylinder(pos + Vector3(0.8, 0.86, 0.3), 0.08, 0.04, mat_rust_metal)
	_create_cylinder(pos + Vector3(0.9, 0.95, -0.3), 0.04, 0.22, mat_rust_metal)

	# 2 Sillas pesadas enfrentadas (Dealer vs Jugador)
	_create_chair(pos + Vector3(0, 0, 1.3), 0.0)
	_create_chair(pos + Vector3(0, 0, -1.3), PI)

	# Lámpara cónica colgante baja directamente sobre la mesa (Sombras duras y luz cálida)
	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 1.8, Color(1.0, 0.65, 0.25), 1.8, 8.0)

	# Máquina de cigarrillos oxidada contra la pared
	_create_box(pos + Vector3(4.8, 1.1, -2.5), Vector3(0.8, 2.2, 1.2), mat_rust_metal)


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
	_create_hanging_lamp(pos + Vector3(-1.5, wall_height, -2.2), 1.4, Color(1.0, 0.5, 0.15), 1.2, 6.5)
	_create_hanging_lamp(pos + Vector3(2.5, wall_height, 2.5), 1.4, Color(0.9, 0.3, 0.1), 1.0, 5.5)


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
	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 1.0, Color(0.95, 0.75, 0.4), 1.2, 7.5)


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
	_create_fluorescent_fixture(pos + Vector3(0, wall_height - 0.05, 0), Color(0.6, 0.95, 0.85), 1.5, 8.5)


## 6. OFICINA DE SEGURIDAD & ENTRADA (Noroeste - Spawn Seeker)
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

	_create_hanging_lamp(pos + Vector3(0, wall_height, 1.0), 1.2, Color(0.9, 0.7, 0.4), 0.9, 6.0)


## 7. TALLER DE REPARACIONES (Noreste)
func _build_maintenance_workshop(pos: Vector3) -> void:
	# Mesa pesada de carpintería / tornería
	_create_box(pos + Vector3(-3.8, 0.5, 0), Vector3(0.9, 1.0, 3.6), mat_rust_metal)
	_create_box(pos + Vector3(-4.4, 1.6, 0), Vector3(0.08, 1.2, 3.4), mat_hazard_mark)

	# Compresor de aire cilíndrico
	_create_cylinder(pos + Vector3(2.5, 0.8, -3.5), 0.45, 1.6, mat_pipe_industrial)

	# Carro de herramientas rodante
	_create_box(pos + Vector3(1.5, 0.45, 2.2), Vector3(0.8, 0.9, 1.1), mat_rust_metal)

	_create_fluorescent_fixture(pos + Vector3(0, wall_height - 0.05, 0), Color(0.95, 0.85, 0.65), 1.2, 7.5)


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

	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 1.6, Color(1.0, 0.5, 0.15), 1.5, 6.5)


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

	_create_hanging_lamp(pos + Vector3(0, wall_height, 0), 1.2, Color(0.95, 0.4, 0.15), 1.1, 6.0)


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

func _setup_tactical_spawns() -> void:
	# El Seeker aparece en la Oficina de Seguridad / Entrada
	seeker_spawn_point = Vector3(-room_size, 0.8, -room_size)

	# Los Hiders aparecen estratégicamente ocultos por las distintas salas
	hider_spawn_points = [
		Vector3(0, 0.8, 0) + Vector3(3.6, 0, 3.6),                    # Salón Ruleta: tras pilar
		Vector3(-room_size, 0.8, 0) + Vector3(3.2, 0, 3.2),            # Bar: tras el sofá VIP
		Vector3(room_size, 0.8, 0) + Vector3(3.2, 0, 3.2),             # Calderas: tras los barriles
		Vector3(0, 0.8, room_size) + Vector3(-2.7, 0, -4.2),           # Baños: dentro del cubículo
		Vector3(0, 0.8, -room_size) + Vector3(0, 0, 0),                 # Almacén: pasillo entre estantes
		Vector3(room_size, 0.8, -room_size) + Vector3(-3.2, 0, 0),      # Taller: tras la mesa
		Vector3(-room_size, 0.8, room_size) + Vector3(0, 0, 0),         # Sala VIP Póker
		Vector3(room_size, 0.8, room_size) + Vector3(1.8, 0, 1.8),     # Bóveda: tras las cajas
	]
	hider_spawn_points.shuffle()


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
