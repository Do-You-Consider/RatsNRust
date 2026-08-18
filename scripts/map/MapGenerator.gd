extends Node3D
class_name MapGenerator
## Genera un laberinto de salas conectadas:
## 1. Backtracking recursivo -> spanning tree (garantiza que todo esté conectado)
## 2. Braiding -> abre conexiones extra al azar (loops, menos "puro pasillo")
## 3. Salas grandes forzadas -> algunos bloques de 2x2 celdas quedan totalmente
##    abiertos entre sí, formando cuartos más grandes en vez de todo del mismo
##    tamaño
## 4. Aberturas de ancho variable + altura de techo variable por celda, para
##    que ninguna sala se sienta idéntica a la anterior
## 5. Props (cajones/barriles) random como obstáculos/escondites

@export var grid_size: int = 6
@export var cell_size: float = 8.0
@export var wall_height: float = 3.2
@export var braid_chance: float = 0.18
@export var big_room_ratio: float = 0.22 ## fracción de celdas usadas como semilla de sala grande
@export var prop_chance: float = 0.6

var rng := RandomNumberGenerator.new()

## Un punto de spawn por Hider (uno por celda disponible, para que nadie
## quede apilado con otro jugador) y uno solo para el Seeker.
var hider_spawn_points: Array[Vector3] = []
var seeker_spawn_point: Vector3 = Vector3.ZERO

var _cells: Array = []
var _open: Dictionary = {}

const FLOOR_COLOR := Color(0.08, 0.075, 0.07)
const WALL_COLOR := Color(0.20, 0.11, 0.07)
const WALL_COLOR_ALT := Color(0.13, 0.13, 0.14)
const CEIL_COLOR := Color(0.02, 0.018, 0.015)

const PROP_COLORS := [
	Color(0.35, 0.18, 0.08),
	Color(0.22, 0.22, 0.24),
	Color(0.45, 0.24, 0.05),
	Color(0.15, 0.15, 0.12),
	Color(0.30, 0.09, 0.06),
]


func generate(seed_value: int = -1) -> void:
	for c in get_children():
		c.queue_free()
	hider_spawn_points.clear()
	seeker_spawn_point = Vector3.ZERO
	_open.clear()

	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value

	_build_maze()
	_braid_maze()
	_carve_big_rooms()
	_build_geometry()


func _build_maze() -> void:
	_cells = []
	for x in grid_size:
		var col := []
		for y in grid_size:
			col.append(false)
		_cells.append(col)

	var stack: Array = [Vector2i(0, 0)]
	_cells[0][0] = true

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var neighbors := _unvisited_neighbors(current)
		if neighbors.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = neighbors[rng.randi() % neighbors.size()]
		_open["%d,%d,%s" % [current.x, current.y, _dir_name(current, next)]] = true
		_open["%d,%d,%s" % [next.x, next.y, _dir_name(next, current)]] = true
		_cells[next.x][next.y] = true
		stack.append(next)


func _braid_maze() -> void:
	var deltas: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for x in grid_size:
		for y in grid_size:
			var cell := Vector2i(x, y)
			for d in deltas:
				var n: Vector2i = cell + d
				if n.x >= grid_size or n.y >= grid_size:
					continue
				var dir := _dir_name(cell, n)
				if not _is_open(x, y, dir) and rng.randf() < braid_chance:
					_open["%d,%d,%s" % [x, y, dir]] = true
					_open["%d,%d,%s" % [n.x, n.y, _dir_name(n, cell)]] = true


## Elige bloques de 2x2 celdas al azar y abre TODAS las conexiones internas,
## formando una sala grande de verdad en vez de 4 cuartitos iguales. Esto es
## lo que rompe más la sensación de "grilla pareja y predecible".
func _carve_big_rooms() -> void:
	if grid_size < 3:
		return
	var seed_count: int = max(1, int(grid_size * grid_size * big_room_ratio / 4.0))
	for i in seed_count:
		var x := rng.randi_range(0, grid_size - 2)
		var y := rng.randi_range(0, grid_size - 2)
		_force_open(Vector2i(x, y), Vector2i(x + 1, y))
		_force_open(Vector2i(x, y), Vector2i(x, y + 1))
		_force_open(Vector2i(x + 1, y), Vector2i(x + 1, y + 1))
		_force_open(Vector2i(x, y + 1), Vector2i(x + 1, y + 1))


func _force_open(a: Vector2i, b: Vector2i) -> void:
	_open["%d,%d,%s" % [a.x, a.y, _dir_name(a, b)]] = true
	_open["%d,%d,%s" % [b.x, b.y, _dir_name(b, a)]] = true


func _unvisited_neighbors(cell: Vector2i) -> Array:
	var result: Array = []
	var deltas: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in deltas:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.x < grid_size and n.y >= 0 and n.y < grid_size and not _cells[n.x][n.y]:
			result.append(n)
	return result


func _dir_name(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if d == Vector2i(0, -1):
		return "N"
	if d == Vector2i(0, 1):
		return "S"
	if d == Vector2i(-1, 0):
		return "W"
	return "E"


func _is_open(x: int, y: int, dir: String) -> bool:
	return _open.get("%d,%d,%s" % [x, y, dir], false)


func _build_geometry() -> void:
	for x in grid_size:
		for y in grid_size:
			_build_cell(x, y)
	_compute_spawn_points()


## Un punto de spawn distinto por cada celda disponible (menos la del Seeker),
## barajado, para repartir a los Hiders sin que queden apilados entre sí.
func _compute_spawn_points() -> void:
	var seeker_cell := Vector2i(grid_size - 1, grid_size - 1)
	seeker_spawn_point = _cell_center(seeker_cell.x, seeker_cell.y) + Vector3(0, 1.0, 0)

	var cells: Array[Vector2i] = []
	for x in grid_size:
		for y in grid_size:
			var c := Vector2i(x, y)
			if c != seeker_cell:
				cells.append(c)
	cells.shuffle()

	hider_spawn_points.clear()
	for c in cells:
		hider_spawn_points.append(_cell_center(c.x, c.y) + Vector3(0, 1.0, 0))


func _cell_center(x: int, y: int) -> Vector3:
	return Vector3(x * cell_size, 0.0, y * cell_size)


func _rand_variant(base: Color) -> Color:
	var f := rng.randf_range(0.85, 1.18)
	return Color(clamp(base.r * f, 0.0, 1.0), clamp(base.g * f, 0.0, 1.0), clamp(base.b * f, 0.0, 1.0))


func _build_cell(x: int, y: int) -> void:
	var origin := _cell_center(x, y)
	var half := cell_size * 0.5
	# altura de techo variable por celda -> ninguna sala se siente idéntica
	var height := wall_height * rng.randf_range(0.85, 1.2)

	var floor_color := _rand_variant(FLOOR_COLOR)
	var wall_color := _rand_variant(WALL_COLOR)
	var wall_color_alt := _rand_variant(WALL_COLOR_ALT)

	_add_box(origin + Vector3(0, -0.1, 0), Vector3(cell_size, 0.2, cell_size), floor_color)
	_add_box(origin + Vector3(0, height + 0.1, 0), Vector3(cell_size, 0.2, cell_size), CEIL_COLOR)

	if not _is_open(x, y, "N"):
		_add_wall_segment(origin, Vector3(0, 0, -half), cell_size, height, wall_color)
	else:
		_add_wall_with_gap(origin, Vector3(0, 0, -half), cell_size, height, _rand_gap(), true, wall_color)

	if not _is_open(x, y, "S"):
		_add_wall_segment(origin, Vector3(0, 0, half), cell_size, height, wall_color)
	else:
		_add_wall_with_gap(origin, Vector3(0, 0, half), cell_size, height, _rand_gap(), true, wall_color)

	if not _is_open(x, y, "W"):
		_add_wall_segment(origin, Vector3(-half, 0, 0), cell_size, height, wall_color_alt, true)
	else:
		_add_wall_with_gap(origin, Vector3(-half, 0, 0), cell_size, height, _rand_gap(), false, wall_color_alt)

	if not _is_open(x, y, "E"):
		_add_wall_segment(origin, Vector3(half, 0, 0), cell_size, height, wall_color_alt, true)
	else:
		_add_wall_with_gap(origin, Vector3(half, 0, 0), cell_size, height, _rand_gap(), false, wall_color_alt)

	var light := OmniLight3D.new()
	light.position = origin + Vector3(0, height - 0.6, 0)
	light.light_color = Color(0.85, 0.42, 0.22)
	light.light_energy = rng.randf_range(0.55, 0.95)
	light.omni_range = cell_size * 1.3
	add_child(light)

	_add_props(origin)


## Ancho de abertura variable: a veces una puerta angosta, a veces casi toda
## la pared abierta (se siente como una sala fusionada con la de al lado).
func _rand_gap() -> float:
	return cell_size * rng.randf_range(0.3, 0.62)


func _add_props(origin: Vector3) -> void:
	if rng.randf() > prop_chance:
		return
	var count := rng.randi_range(1, 3)
	for i in count:
		var offset := Vector3(
			rng.randf_range(-cell_size * 0.32, cell_size * 0.32),
			0.0,
			rng.randf_range(-cell_size * 0.32, cell_size * 0.32)
		)
		if rng.randf() < 0.5:
			_add_barrel(origin + offset)
		else:
			_add_crate(origin + offset)


func _add_crate(base_pos: Vector3) -> void:
	var size := Vector3(
		rng.randf_range(0.6, 1.3),
		rng.randf_range(0.6, 1.5),
		rng.randf_range(0.6, 1.3)
	)
	var color: Color = PROP_COLORS[rng.randi() % PROP_COLORS.size()]
	var body := _add_box(base_pos + Vector3(0, size.y * 0.5, 0), size, color)
	body.rotate_y(rng.randf_range(0.0, TAU))


func _add_barrel(base_pos: Vector3) -> void:
	var radius := rng.randf_range(0.35, 0.55)
	var height := rng.randf_range(0.9, 1.4)
	var color: Color = PROP_COLORS[rng.randi() % PROP_COLORS.size()]

	var body := StaticBody3D.new()
	body.position = base_pos + Vector3(0, height * 0.5, 0)
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_instance.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.15
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)


func _add_wall_segment(origin: Vector3, offset: Vector3, length: float, height: float, color: Color, vertical: bool = false) -> void:
	if vertical:
		_add_box(origin + offset + Vector3(0, height * 0.5, 0), Vector3(0.2, height, length), color)
	else:
		_add_box(origin + offset + Vector3(0, height * 0.5, 0), Vector3(length, height, 0.2), color)


func _add_wall_with_gap(origin: Vector3, offset: Vector3, length: float, height: float, gap: float, horizontal: bool, color: Color) -> void:
	var seg_len: float = (length - gap) * 0.5
	var center_offset: float = (length + gap) * 0.25
	if horizontal:
		_add_box(origin + offset + Vector3(-center_offset, height * 0.5, 0), Vector3(seg_len, height, 0.2), color)
		_add_box(origin + offset + Vector3(center_offset, height * 0.5, 0), Vector3(seg_len, height, 0.2), color)
	else:
		_add_box(origin + offset + Vector3(0, height * 0.5, -center_offset), Vector3(0.2, height, seg_len), color)
		_add_box(origin + offset + Vector3(0, height * 0.5, center_offset), Vector3(0.2, height, seg_len), color)


func _add_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	return body
