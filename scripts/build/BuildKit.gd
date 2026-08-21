class_name BuildKit
extends RefCounted
## Primitivas de construcción compartidas entre el mapa de juego
## (MapGenerator) y la escenografía del menú (MenuSets).
##
## Todo lo que dibujamos son primitivas de Godot con material_override: no hay
## un solo .obj en el proyecto. Antes estas funciones eran métodos privados de
## MapGenerator y colgaban siempre de `self`; acá reciben el parent explícito,
## que es lo que permite reusarlas para armar props compuestos bajo un pivote
## rotado y para construir los sets del menú.
##
## Convención: `has_collision = false` por defecto. En el menú NADA necesita
## colisión (no hay física, solo cámara y muñecos animados por tween), y en el
## mapa el llamador ya venía pasando el flag explícito.


# ------------------------------------------------------------- materiales

static func matte(albedo: Color, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metallic
	return m


static func emissive(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


## Negro plano sin sombreado: recortes/siluetas que tienen que leerse igual
## sin importar de dónde venga la luz.
static func unshaded(albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Emisivo transparente: haces de luz, vidrio de monitor, humo plano.
static func glow_alpha(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# -------------------------------------------------------------- geometría

static func box(parent: Node3D, center: Vector3, size: Vector3, mat: StandardMaterial3D,
		has_collision: bool = false, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	if not has_collision:
		return _mesh_node(parent, mesh, mat, center, rot)

	var body := StaticBody3D.new()
	body.position = center
	body.rotation = rot
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body


static func cylinder(parent: Node3D, center: Vector3, radius: float, height: float,
		mat: StandardMaterial3D, has_collision: bool = false, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	if not has_collision:
		return _mesh_node(parent, cyl, mat, center, rot)

	var body := StaticBody3D.new()
	body.position = center
	body.rotation = rot
	parent.add_child(body)

	var mi := MeshInstance3D.new()
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


static func sphere(parent: Node3D, center: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	return _mesh_node(parent, sph, mat, center, Vector3.ZERO) as MeshInstance3D


## Cilindro estirado entre dos puntos (cables, tensores, caños, haces).
##
## La orientación se resuelve con matemática pura en vez de look_at(): look_at()
## trabaja en espacio GLOBAL, así que dentro de un pivote rotado (cabezales de
## luz, abanicos de láser) daba haces apuntando a cualquier lado.
static func beam(parent: Node3D, from: Vector3, to: Vector3, radius: float,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var length := from.distance_to(to)
	if length < 0.01:
		return null
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 6

	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	var dir := from.direction_to(to)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# looking_at deja el eje -Z sobre dir; el cilindro crece en +Y, de ahí el
	# cuarto de vuelta sobre X.
	var b := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	mi.transform = Transform3D(b, (from + to) * 0.5)
	parent.add_child(mi)
	return mi


## Plano vertical/horizontal barato (carteles, charcos, paneles de vidrio).
static func quad(parent: Node3D, center: Vector3, size: Vector2, mat: StandardMaterial3D,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	return _mesh_node(parent, q, mat, center, rot) as MeshInstance3D


## Colisión sin malla (redes de seguridad del mapa).
static func barrier(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body


# ------------------------------------------------------------------- luz

static func omni(parent: Node3D, pos: Vector3, color: Color, energy: float,
		light_range: float, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = shadows
	parent.add_child(l)
	l.position = pos
	return l


static func spot(parent: Node3D, pos: Vector3, aim: Vector3, color: Color, energy: float,
		light_range: float, angle: float, shadows: bool = false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = light_range
	l.spot_angle = angle
	l.spot_attenuation = 1.1
	l.shadow_enabled = shadows
	parent.add_child(l)
	l.position = pos
	if pos.distance_to(aim) > 0.01:
		# Un foco apuntando recto para abajo (los cabezales de la pista) deja
		# el vector "arriba" colineal con la mirada y Godot avisa. Elegimos otro
		# de referencia: el giro sobre el eje Z local de un cono es invisible.
		var dir := pos.direction_to(aim)
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		l.look_at_from_position(pos, aim, up)
	return l


# ---------------------------------------------------------------- interno

static func _mesh_node(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D,
		pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi
