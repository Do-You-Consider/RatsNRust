class_name MenuAnimations
extends RefCounted
## Animaciones que solo existen en el menú: poses de escenografía, no de
## juego. Se agregan al rig como una AnimationLibrary aparte ("menu"), así el
## rig de partida no paga el costo de construirlas y los nombres no chocan
## con los de RigAnimations.
##
## Misma convención que RigAnimations: TODO es un offset en GRADOS sobre la
## pose de reposo (RigBuilder.rest_pose). Nunca rotaciones absolutas -- si no,
## el encorvado del Atrapador desaparecería en cuanto reprodujéramos una de
## estas.
##
## Recordatorio de signos (sacado de RigAnimations):
##   CHEST  +X = inclinarse hacia adelante
##   HEAD   +X = mirar hacia abajo,  +Y = girar a la izquierda
##   UA*    -X = brazo hacia adelante,  Z se abre hacia afuera del cuerpo
##   FA*    +X = flexionar el codo
##   TH*    +X = pierna adelante,  SHIN* -X = doblar la rodilla

const LIBRARY_NAME := "menu"

## Loops disponibles. Se reproducen con rig.set_locomotion("menu/<nombre>").
const LOOPS := ["lean_rail", "watch_monitors", "wait_a", "wait_b", "present"]


static func build_library(p: Dictionary, pose: Dictionary) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("lean_rail", _lean_rail(p, pose))
	lib.add_animation("watch_monitors", _watch_monitors(p, pose))
	lib.add_animation("wait_a", _wait_a(p, pose))
	lib.add_animation("wait_b", _wait_b(p, pose))
	lib.add_animation("present", _present(p, pose))
	lib.add_animation("open_door", _open_door(p, pose))
	lib.add_animation("point_screen", _point_screen(p, pose))
	return lib


# ---------------------------------------------------------------- helpers
# Reusamos los de RigAnimations vía nombres locales para no duplicar lógica
# de tracks: son estáticos y públicos de hecho (GDScript no tiene privados).

static func _anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


static func _rot(a: Animation, pose: Dictionary, path: String, keys: Array) -> void:
	if not pose.has(path):
		return
	var base: Vector3 = pose[path]
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath(path + ":rotation"))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	a.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		a.track_insert_key(idx, k[0], RigBuilder.deg_vec(base + k[1]))


static func _pos(a: Animation, keys: Array) -> void:
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath(RigBuilder.J_ROOT + ":position"))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	a.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		a.track_insert_key(idx, k[0], k[1])


static func _v(x: float, y := 0.0, z := 0.0) -> Vector3:
	return Vector3(x, y, z)


# ------------------------------------------------------------------ poses

## PANTALLA 1: apoyado en la baranda mirando la pista desde arriba.
## El peso está en los antebrazos sobre el pasamanos, no en las piernas: por
## eso el torso va MUY adelante (26°) y las rodillas quedan casi rectas.
static func _lean_rail(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(5.2, true)
	# Se acerca a la baranda y respira. El -0.12 en Z es lo que apoya el
	# cuerpo contra el pasamanos en vez de dejarlo flotando detrás.
	_pos(a, [
		[0.0, Vector3(0, -0.05, -0.12)],
		[2.6, Vector3(0, -0.035, -0.12)],
		[5.2, Vector3(0, -0.05, -0.12)]])

	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(26, 0, 0)], [2.6, _v(24, 0, 0)], [5.2, _v(26, 0, 0)]])
	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(-6, 2, 0)], [2.6, _v(-6, -2, 0)], [5.2, _v(-6, 2, 0)]])

	# Mira la pista: cabeza abajo, barriendo despacio de un lado al otro.
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(-8, 0, 0)],
		[1.4, _v(-6, 11, 0)],
		[2.8, _v(-10, 0, 0)],
		[4.0, _v(-7, -13, 0)],
		[5.2, _v(-8, 0, 0)]])

	# Antebrazos apoyados en el pasamanos, hombros hundidos hacia adelante.
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-52, 0, 3)], [2.6, _v(-50, 0, 3)], [5.2, _v(-52, 0, 3)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-52, 0, -3)], [2.6, _v(-50, 0, -3)], [5.2, _v(-52, 0, -3)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(38)], [2.6, _v(36)], [5.2, _v(38)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(38)], [2.6, _v(36)], [5.2, _v(38)]])

	# Una pierna cruzada por detrás: pose de estar parado ahí hace rato.
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(6, 0, 0)], [5.2, _v(6, 0, 0)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(2, 0, -3)], [5.2, _v(2, 0, -3)]])
	_rot(a, pose, RigBuilder.J_SHINL, [[0.0, _v(-8)], [5.2, _v(-8)]])
	_rot(a, pose, RigBuilder.J_SHINR, [[0.0, _v(-14)], [5.2, _v(-14)]])
	return a


## PANTALLA 2: parado frente al muro de monitores, barriendo las pantallas.
## El barrido de cabeza es MUY lento a propósito: es lo que vende que está
## mirando nueve cámaras y no que se le trabó la animación.
static func _watch_monitors(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(7.4, true)
	_pos(a, [
		[0.0, Vector3(-0.015, 0, 0)],
		[3.7, Vector3(0.015, -0.01, 0)],
		[7.4, Vector3(-0.015, 0, 0)]])

	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(0, 4, 0)], [3.7, _v(0, -4, 0)], [7.4, _v(0, 4, 0)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(2, -3, 0)], [3.7, _v(3, 3, 0)], [7.4, _v(2, -3, 0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(3, -14, 0)],
		[1.8, _v(1, 4, 0)],
		[3.0, _v(2, 16, 0)],
		[5.0, _v(4, 2, 0)],
		[7.4, _v(3, -14, 0)]])

	# Brazos cruzados flojo: el izquierdo sostiene el codo derecho.
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-16, 0, 9)], [3.7, _v(-14, 0, 9)], [7.4, _v(-16, 0, 9)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-14, 0, -8)], [3.7, _v(-16, 0, -8)], [7.4, _v(-14, 0, -8)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(74)], [3.7, _v(70)], [7.4, _v(74)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(68)], [3.7, _v(72)], [7.4, _v(68)]])
	return a


## PANTALLA 3 (afuera): espera con cambio de peso y miradas alrededor.
static func _wait_a(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(6.1, true)
	_pos(a, [
		[0.0, Vector3(-0.02, 0, 0)],
		[1.5, Vector3(-0.02, -0.015, 0)],
		[3.0, Vector3(0.02, 0, 0)],
		[4.6, Vector3(0.02, -0.015, 0)],
		[6.1, Vector3(-0.02, 0, 0)]])

	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(0, 0, -3)], [3.0, _v(0, 0, 3)], [6.1, _v(0, 0, -3)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(1, 0, 2)], [3.0, _v(2, 0, -2)], [6.1, _v(1, 0, 2)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0, 0, 0)],
		[1.2, _v(-3, 22, 0)],
		[2.4, _v(0, 6, 0)],
		[3.9, _v(4, -18, 0)],
		[5.0, _v(0, -4, 0)],
		[6.1, _v(0, 0, 0)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-3, 0, 1)], [3.0, _v(2, 0, -1)], [6.1, _v(-3, 0, 1)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(2, 0, -1)], [3.0, _v(-3, 0, 1)], [6.1, _v(2, 0, -1)]])
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(0, 0, 2)], [6.1, _v(0, 0, 2)]])
	_rot(a, pose, RigBuilder.J_SHINR, [[0.0, _v(-4)], [3.0, _v(-11)], [6.1, _v(-4)]])
	return a


## PANTALLA 3 (afuera), variante: brazos cruzados, cuerpo más cerrado. Con dos
## variantes alcanza para que una fila de 8 jugadores no parezca clonada.
static func _wait_b(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(5.4, true)
	_pos(a, [
		[0.0, Vector3(0, -0.01, 0)],
		[2.7, Vector3(0, 0.005, 0)],
		[5.4, Vector3(0, -0.01, 0)]])

	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(7, 4, 0)], [2.7, _v(6, -3, 0)], [5.4, _v(7, 4, 0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(2, -5, 0)], [1.9, _v(5, 9, 0)], [3.6, _v(1, -9, 0)], [5.4, _v(2, -5, 0)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-22, 0, 12)], [2.7, _v(-20, 0, 12)], [5.4, _v(-22, 0, 12)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-20, 0, -11)], [2.7, _v(-22, 0, -11)], [5.4, _v(-20, 0, -11)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(88)], [5.4, _v(88)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(84)], [5.4, _v(84)]])
	_rot(a, pose, RigBuilder.J_SHINL, [[0.0, _v(-6)], [5.4, _v(-6)]])
	return a


## PANTALLA 4: pose de vidriera para el menú de apariencia. Pecho arriba,
## brazos apenas separados del cuerpo para que se vean las manos y no se
## pierdan contra las caderas cuando haya guantes que mirar.
static func _present(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(4.4, true)
	_pos(a, [
		[0.0, Vector3(0, 0, 0)], [2.2, Vector3(0, 0.012, 0)], [4.4, Vector3(0, 0, 0)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(-4, 0, 0)], [2.2, _v(-2, 0, 0)], [4.4, _v(-4, 0, 0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(-2, 0, 0)], [2.2, _v(-1, 0, 0)], [4.4, _v(-2, 0, 0)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-2, 0, -7)], [2.2, _v(0, 0, -8)], [4.4, _v(-2, 0, -7)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-2, 0, 7)], [2.2, _v(0, 0, 8)], [4.4, _v(-2, 0, 7)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(10)], [2.2, _v(12)], [4.4, _v(10)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(10)], [2.2, _v(12)], [4.4, _v(10)]])
	return a


# -------------------------------------------------------------- one-shots

## TRANSICIÓN PANTALLA 1 -> 2: estira el brazo derecho y empuja la puerta.
## Dura lo mismo que el tramo de puerta del MenuCameraDirector; si tocás uno,
## tocá el otro.
static func _open_door(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(1.15, false)
	_pos(a, [
		[0.0, Vector3.ZERO],
		[0.45, Vector3(0, 0, -0.06)],
		[1.15, Vector3(0, 0, -0.14)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(0)], [0.45, _v(6)], [0.8, _v(4)], [1.15, _v(2)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(0)], [0.35, _v(-62, 0, -6)], [0.7, _v(-70, 0, -10)], [1.15, _v(-38, 0, -4)]])
	_rot(a, pose, RigBuilder.J_FAR, [
		[0.0, _v(6)], [0.35, _v(26)], [0.7, _v(10)], [1.15, _v(20)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(0)], [0.7, _v(10, 0, 3)], [1.15, _v(4, 0, 1)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0)], [0.45, _v(2, -6, 0)], [1.15, _v(0, -2, 0)]])
	return a


## Señala un monitor. Lo dispara la sala de cámaras cada tanto para que el
## Atrapador no sea una estatua durante toda la navegación de menú.
static func _point_screen(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(1.6, false)
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(2, -3, 0)], [0.5, _v(4, -10, 0)], [1.1, _v(4, -10, 0)], [1.6, _v(2, -3, 0)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-14, 0, -8)], [0.5, _v(-74, 0, -14)], [1.1, _v(-72, 0, -14)], [1.6, _v(-14, 0, -8)]])
	_rot(a, pose, RigBuilder.J_FAR, [
		[0.0, _v(68)], [0.5, _v(8)], [1.1, _v(6)], [1.6, _v(68)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(3, -14, 0)], [0.5, _v(2, -6, 0)], [1.6, _v(3, -14, 0)]])
	return a
