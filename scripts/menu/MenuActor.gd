class_name MenuActor
extends Node3D
## Un personaje dentro de un set del menú: el rig segmentado del juego más lo
## necesario para moverlo por la escenografía (caminar un recorrido, girar,
## cambiar de pose).
##
## No usa CharacterBody3D ni física: en el menú no hay nada con qué chocar y
## el recorrido está autorado a mano. Un tween sobre `position` es exacto,
## barato y reproducible en todos los peers.

const WALK_SPEED := 1.55
const TURN_TIME := 0.28

var rig: CharacterRig
var role: int = GameState.Role.SEEKER

var _pose: String = "menu/wait_a"
var _walking: bool = false


static func create(for_role: int, cfg: CharacterAppearance = null) -> MenuActor:
	var a := MenuActor.new()
	a.role = for_role
	a.rig = CharacterRig.create_menu(for_role, cfg)
	a.add_child(a.rig)
	return a


func set_appearance(cfg: CharacterAppearance) -> void:
	rig.apply_appearance(cfg)


## `pose_name` sin prefijo: "lean_rail", "wait_a", "present"...
func set_pose(pose_name: String) -> void:
	_pose = "%s/%s" % [MenuAnimations.LIBRARY_NAME, pose_name]
	if not _walking:
		rig.set_locomotion(_pose)


func play_once(anim_name: String) -> void:
	rig.play_one_shot("%s/%s" % [MenuAnimations.LIBRARY_NAME, anim_name])


## Gira para mirar a un punto del mundo. El rig mira hacia -Z, así que el yaw
## sale de atan2 sobre la dirección invertida.
func face_point(target: Vector3, duration: float = TURN_TIME) -> void:
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_turn_to(atan2(-dir.x, -dir.z), duration)


func _turn_to(yaw: float, duration: float) -> void:
	# Camino más corto: sin esto, ir de 179° a -179° da una vuelta completa.
	var current := rotation.y
	while yaw - current > PI:
		yaw -= TAU
	while yaw - current < -PI:
		yaw += TAU
	if duration <= 0.0:
		rotation.y = yaw
		return
	var t := create_tween()
	t.tween_property(self, "rotation:y", yaw, duration).set_trans(Tween.TRANS_SINE)


## Recorre los puntos a pie. El primer punto se ignora si ya estamos ahí: los
## recorridos del set arrancan en la posición del actor.
func walk_along(points: Array, speed: float = WALK_SPEED) -> void:
	if points.size() < 2:
		return
	_walking = true
	rig.set_locomotion("walk")

	for i in range(1, points.size()):
		var to: Vector3 = points[i]
		var dist := position.distance_to(to)
		if dist < 0.02:
			continue
		face_point(to, minf(TURN_TIME, dist / speed))
		var t := create_tween()
		t.tween_property(self, "position", to, dist / speed).set_trans(Tween.TRANS_LINEAR)
		await t.finished
		if not is_inside_tree():
			return

	_walking = false
	rig.set_locomotion(_pose)


## Igual que walk_along pero sin esperar: lo usa la salida en grupo, donde ocho
## actores tienen que arrancar a caminar en el mismo cuadro.
func walk_to(target: Vector3, speed: float = WALK_SPEED) -> Tween:
	_walking = true
	rig.set_locomotion("walk")
	face_point(target)
	var dist := position.distance_to(target)
	var t := create_tween()
	t.tween_property(self, "position", target, maxf(0.1, dist / speed)).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func():
		_walking = false
		if is_instance_valid(rig):
			rig.set_locomotion(_pose))
	return t
