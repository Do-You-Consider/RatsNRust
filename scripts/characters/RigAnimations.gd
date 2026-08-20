class_name RigAnimations
extends RefCounted
## Construye la AnimationLibrary del rig segmentado, por código.
##
## Todos los keys se expresan como OFFSETS EN GRADOS sobre la pose de reposo
## (RigBuilder.rest_pose): así el encorvado del Atrapador y la apertura de
## brazos se mantienen en todas las animaciones sin repetirlos a mano, y
## cambiar el perfil no obliga a rehacer las animaciones.
##
## Pose de derribo: se rota el Root -88° en X. Eso mapea el eje local +Y
## (arriba del personaje) al eje mundial -Z (adelante), o sea que el cuerpo
## queda tirado boca abajo con la cabeza hacia adelante, pivotando sobre los
## pies -- exactamente como caer de frente. Las animaciones de arrastre se
## construyen dentro de ese marco.

const DOWN_ROT_X := -88.0

## Estados de locomoción (loop) y one-shots. Los nombres son los que usa
## CharacterRig.set_locomotion() / play_one_shot().
const LOCOMOTION := ["idle", "walk", "run", "downed_idle", "crawl"]


static func build_library(p: Dictionary, pose: Dictionary) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var down_y: float = (p.hips_size as Vector3).z * 0.5

	lib.add_animation("idle", _idle(p, pose))
	lib.add_animation("walk", _walk(p, pose))
	lib.add_animation("run", _run(p, pose))
	lib.add_animation("hit_react", _hit_react(p, pose))
	lib.add_animation("knockdown", _knockdown(p, pose, down_y))
	lib.add_animation("downed_idle", _downed_idle(p, pose, down_y))
	lib.add_animation("crawl", _crawl(p, pose, down_y))
	lib.add_animation("attack", _attack(p, pose))
	lib.add_animation("attack_recover", _attack_recover(p, pose))
	lib.add_animation("attack_whiff", _attack_whiff(p, pose))
	return lib


# ---------------------------------------------------------------- helpers

static func _anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


## Track de rotación sobre una articulación. `keys` = [[tiempo, Vector3 de
## offset en grados], ...]. Si la articulación no existe en este perfil
## (p. ej. porque el perfil no la define) el track se omite en silencio.
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


## Track de posición del Root, en metros absolutos.
static func _pos(a: Animation, keys: Array) -> void:
	var idx := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(idx, NodePath(RigBuilder.J_ROOT + ":position"))
	a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	a.value_track_set_update_mode(idx, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		a.track_insert_key(idx, k[0], k[1])


static func _v(x: float, y := 0.0, z := 0.0) -> Vector3:
	return Vector3(x, y, z)



# ------------------------------------------------------------ locomoción

static func _idle(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(3.2, true)
	_pos(a, [[0.0, Vector3.ZERO], [1.6, Vector3(0, -0.012, 0)], [3.2, Vector3.ZERO]])
	_rot(a, pose, RigBuilder.J_CHEST, [[0.0, _v(0)], [1.6, _v(1.6)], [3.2, _v(0)]])
	# Mira despacio a los costados: barato y hace que no parezca una estatua.
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0, 0, 0)], [0.9, _v(0, 9, 0)], [1.8, _v(0, 0, 0)],
		[2.5, _v(0, -7, 0)], [3.2, _v(0, 0, 0)]])
	_rot(a, pose, RigBuilder.J_UAL, [[0.0, _v(0)], [1.6, _v(1.5, 0, -1.2)], [3.2, _v(0)]])
	_rot(a, pose, RigBuilder.J_UAR, [[0.0, _v(0)], [1.6, _v(1.5, 0, 1.2)], [3.2, _v(0)]])
	return a


static func _gait(p: Dictionary, pose: Dictionary, dur: float, thigh: float,
		knee: float, arm: float, bob: float, lean: float) -> Animation:
	var a := _anim(dur, true)
	var q := dur * 0.25
	var h := dur * 0.5
	var q3 := dur * 0.75

	_pos(a, [
		[0.0, Vector3.ZERO], [q, Vector3(0, bob, 0)], [h, Vector3.ZERO],
		[q3, Vector3(0, bob, 0)], [dur, Vector3.ZERO]])

	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(lean, 0, 1.4)], [h, _v(lean, 0, -1.4)], [dur, _v(lean, 0, 1.4)]])
	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(0, 4, 0)], [h, _v(0, -4, 0)], [dur, _v(0, 4, 0)]])

	_rot(a, pose, RigBuilder.J_THL, [
		[0.0, _v(thigh)], [q, _v(0)], [h, _v(-thigh)], [q3, _v(0)], [dur, _v(thigh)]])
	_rot(a, pose, RigBuilder.J_THR, [
		[0.0, _v(-thigh)], [q, _v(0)], [h, _v(thigh)], [q3, _v(0)], [dur, _v(-thigh)]])
	_rot(a, pose, RigBuilder.J_SHINL, [
		[0.0, _v(-knee * 0.2)], [q, _v(-knee)], [h, _v(-knee * 0.3)],
		[q3, _v(-knee * 0.1)], [dur, _v(-knee * 0.2)]])
	_rot(a, pose, RigBuilder.J_SHINR, [
		[0.0, _v(-knee * 0.3)], [q, _v(-knee * 0.1)], [h, _v(-knee * 0.2)],
		[q3, _v(-knee)], [dur, _v(-knee * 0.3)]])

	# Los brazos van en contrafase con la pierna del mismo lado.
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-arm)], [q, _v(0)], [h, _v(arm)], [q3, _v(0)], [dur, _v(-arm)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(arm)], [q, _v(0)], [h, _v(-arm)], [q3, _v(0)], [dur, _v(arm)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(6)], [h, _v(18)], [dur, _v(6)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(18)], [h, _v(6)], [dur, _v(18)]])

	return a


static func _walk(p: Dictionary, pose: Dictionary) -> Animation:
	return _gait(p, pose, 0.9, 22.0, 34.0, 18.0, 0.028, 0.0)


static func _run(p: Dictionary, pose: Dictionary) -> Animation:
	return _gait(p, pose, 0.62, 38.0, 58.0, 32.0, 0.045, 8.0)


# --------------------------------------------------------------- impacto

static func _hit_react(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(0.38, false)
	_pos(a, [[0.0, Vector3.ZERO], [0.14, Vector3(0, -0.02, 0.07)], [0.38, Vector3.ZERO]])
	# El torso se arquea hacia atrás y el brazo sube a cubrirse.
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(0)], [0.10, _v(-15, 0, 5)], [0.24, _v(-6, 0, 2)], [0.38, _v(0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0)], [0.10, _v(18, 14, 0)], [0.24, _v(7, 6, 0)], [0.38, _v(0)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(0)], [0.12, _v(42, 0, -14)], [0.38, _v(0)]])
	_rot(a, pose, RigBuilder.J_FAL, [
		[0.0, _v(6)], [0.12, _v(95)], [0.38, _v(6)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(0)], [0.12, _v(30, 0, 10)], [0.38, _v(0)]])
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(0)], [0.14, _v(-10)], [0.38, _v(0)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(0)], [0.14, _v(8)], [0.38, _v(0)]])
	return a


## Caída de frente pivotando sobre los pies, con un rebote al tocar el piso.
static func _knockdown(p: Dictionary, pose: Dictionary, down_y: float) -> Animation:
	var a := _anim(0.75, false)
	_pos(a, [
		[0.0, Vector3.ZERO],
		[0.12, Vector3(0, 0.09, 0)],
		[0.35, Vector3(0, 0.06, 0)],
		[0.52, Vector3(0, down_y + 0.06, 0)],
		[0.62, Vector3(0, down_y, 0)],
		[0.75, Vector3(0, down_y, 0)]])
	_rot(a, pose, RigBuilder.J_ROOT, [
		[0.0, _v(0)],
		[0.12, _v(-16, 0, 4)],
		[0.35, _v(-54, 0, 2)],
		[0.52, _v(DOWN_ROT_X - 4, 0, 0)],
		[0.62, _v(DOWN_ROT_X + 3, 0, 0)],
		[0.75, _v(DOWN_ROT_X, 0, 0)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(0)], [0.2, _v(-18)], [0.52, _v(10)], [0.75, _v(4)]])
	# Los brazos manotean y terminan adelante, listos para arrastrarse.
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(0)], [0.18, _v(-70, 0, -22)], [0.52, _v(-20, 0, -14)], [0.75, _v(-22, 0, -12)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(0)], [0.18, _v(-70, 0, 22)], [0.52, _v(-20, 0, 14)], [0.75, _v(-22, 0, 12)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(6)], [0.52, _v(28)], [0.75, _v(24)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(6)], [0.52, _v(28)], [0.75, _v(24)]])
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(0)], [0.2, _v(22)], [0.75, _v(6)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(0)], [0.2, _v(-14)], [0.75, _v(9)]])
	_rot(a, pose, RigBuilder.J_SHINL, [[0.0, _v(0)], [0.35, _v(-40)], [0.75, _v(-12)]])
	_rot(a, pose, RigBuilder.J_SHINR, [[0.0, _v(0)], [0.35, _v(-28)], [0.75, _v(-16)]])
	return a


static func _downed_base(a: Animation, pose: Dictionary, down_y: float, dur: float) -> void:
	_pos(a, [[0.0, Vector3(0, down_y, 0)], [dur, Vector3(0, down_y, 0)]])


static func _downed_idle(p: Dictionary, pose: Dictionary, down_y: float) -> Animation:
	var a := _anim(3.6, true)
	_downed_base(a, pose, down_y, 3.6)
	# Respiración pesada: el cuerpo se hincha y la cabeza se despega apenas.
	_rot(a, pose, RigBuilder.J_ROOT, [
		[0.0, _v(DOWN_ROT_X)], [1.8, _v(DOWN_ROT_X - 2.5)], [3.6, _v(DOWN_ROT_X)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(4)], [1.8, _v(9)], [3.6, _v(4)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0, 0, 0)], [1.2, _v(-10, 8, 0)], [2.4, _v(-4, -6, 0)], [3.6, _v(0, 0, 0)]])
	_rot(a, pose, RigBuilder.J_UAL, [[0.0, _v(-22, 0, -12)], [1.8, _v(-26, 0, -14)], [3.6, _v(-22, 0, -12)]])
	_rot(a, pose, RigBuilder.J_UAR, [[0.0, _v(-22, 0, 12)], [1.8, _v(-26, 0, 14)], [3.6, _v(-22, 0, 12)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(24)], [3.6, _v(24)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(24)], [3.6, _v(24)]])
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(6)], [1.8, _v(9)], [3.6, _v(6)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(9)], [1.8, _v(5)], [3.6, _v(9)]])
	_rot(a, pose, RigBuilder.J_SHINL, [[0.0, _v(-12)], [3.6, _v(-12)]])
	_rot(a, pose, RigBuilder.J_SHINR, [[0.0, _v(-16)], [1.8, _v(-24)], [3.6, _v(-16)]])
	return a


## Arrastre boca abajo: los brazos tiran alternados hacia adelante y las
## piernas van de remolque. El desplazamiento real lo hace el CharacterBody3D
## a GameState.crawl_speed; acá solo va el movimiento de las extremidades.
static func _crawl(p: Dictionary, pose: Dictionary, down_y: float) -> Animation:
	var a := _anim(1.5, true)
	_pos(a, [
		[0.0, Vector3(0, down_y, 0)],
		[0.375, Vector3(0, down_y + 0.02, 0)],
		[0.75, Vector3(0, down_y, 0)],
		[1.125, Vector3(0, down_y + 0.02, 0)],
		[1.5, Vector3(0, down_y, 0)]])
	# Cabeceo del cuerpo entero al empujar con cada brazo.
	_rot(a, pose, RigBuilder.J_ROOT, [
		[0.0, _v(DOWN_ROT_X, 0, 3)], [0.75, _v(DOWN_ROT_X, 0, -3)], [1.5, _v(DOWN_ROT_X, 0, 3)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(6, 8, 0)], [0.75, _v(6, -8, 0)], [1.5, _v(6, 8, 0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(-8, -6, 0)], [0.75, _v(-8, 6, 0)], [1.5, _v(-8, -6, 0)]])
	# Brazo izquierdo estira mientras el derecho empuja, y viceversa.
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-34, 0, -10)], [0.75, _v(-6, 0, -18)], [1.5, _v(-34, 0, -10)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(-6, 0, 18)], [0.75, _v(-34, 0, 10)], [1.5, _v(-6, 0, 18)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(14)], [0.75, _v(46)], [1.5, _v(14)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(46)], [0.75, _v(14)], [1.5, _v(46)]])
	# Piernas de remolque, apenas acompañan.
	_rot(a, pose, RigBuilder.J_THL, [[0.0, _v(4, 6, 0)], [0.75, _v(11, -4, 0)], [1.5, _v(4, 6, 0)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(11, -6, 0)], [0.75, _v(4, 4, 0)], [1.5, _v(11, -6, 0)]])
	_rot(a, pose, RigBuilder.J_SHINL, [[0.0, _v(-10)], [0.75, _v(-24)], [1.5, _v(-10)]])
	_rot(a, pose, RigBuilder.J_SHINR, [[0.0, _v(-24)], [0.75, _v(-10)], [1.5, _v(-24)]])
	return a


# ---------------------------------------------------------------- ataque

## Golpe: anticipación (0 -> 0.25) y descarga (0.25 -> 0.45). El pedido de
## golpe al servidor sale al terminar la anticipación, no al hacer clic: esos
## 0.25s son la ventana real que tiene la rata para salir del cono.
static func _attack(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(0.45, false)
	_pos(a, [
		[0.0, Vector3.ZERO], [0.25, Vector3(0, 0.02, 0.05)],
		[0.42, Vector3(0, -0.02, -0.08)], [0.45, Vector3(0, -0.015, -0.07)]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(0)], [0.18, _v(-95, 0, 14)], [0.25, _v(-125, 0, 18)],
		[0.42, _v(55, 0, -6)], [0.45, _v(48, 0, -4)]])
	_rot(a, pose, RigBuilder.J_FAR, [
		[0.0, _v(6)], [0.25, _v(-60)], [0.42, _v(10)], [0.45, _v(12)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(0)], [0.25, _v(26, 0, -18)], [0.45, _v(-14, 0, -6)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(6)], [0.25, _v(48)], [0.45, _v(20)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(0)], [0.25, _v(-6, -22, 0)], [0.45, _v(10, 26, 0)]])
	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(0)], [0.25, _v(0, -10, 0)], [0.45, _v(0, 12, 0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [
		[0.0, _v(0)], [0.25, _v(0, -8, 0)], [0.45, _v(0, 6, 0)]])
	return a


## Vuelta a la guardia después de conectar. Corta y controlada: pegar bien
## se premia con recuperar rápido.
static func _attack_recover(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(0.42, false)
	_pos(a, [[0.0, Vector3(0, -0.015, -0.07)], [0.42, Vector3.ZERO]])
	_rot(a, pose, RigBuilder.J_UAR, [[0.0, _v(48, 0, -4)], [0.2, _v(20, 0, 0)], [0.42, _v(0)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(12)], [0.42, _v(6)]])
	_rot(a, pose, RigBuilder.J_UAL, [[0.0, _v(-14, 0, -6)], [0.42, _v(0)]])
	_rot(a, pose, RigBuilder.J_FAL, [[0.0, _v(20)], [0.42, _v(6)]])
	_rot(a, pose, RigBuilder.J_CHEST, [[0.0, _v(10, 26, 0)], [0.2, _v(4, 8, 0)], [0.42, _v(0)]])
	_rot(a, pose, RigBuilder.J_HIPS, [[0.0, _v(0, 12, 0)], [0.42, _v(0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [[0.0, _v(0, 6, 0)], [0.42, _v(0)]])
	return a


## Fallar cuesta: el swing sigue de largo, el cuerpo se pasa de rosca y
## tarda casi medio segundo más en volver a la guardia.
static func _attack_whiff(p: Dictionary, pose: Dictionary) -> Animation:
	var a := _anim(0.62, false)
	_pos(a, [
		[0.0, Vector3(0, -0.015, -0.07)], [0.2, Vector3(0, -0.05, -0.16)],
		[0.42, Vector3(0, -0.02, -0.06)], [0.62, Vector3.ZERO]])
	_rot(a, pose, RigBuilder.J_UAR, [
		[0.0, _v(48, 0, -4)], [0.18, _v(85, 0, -18)], [0.4, _v(40, 0, -8)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_FAR, [[0.0, _v(12)], [0.18, _v(-4)], [0.62, _v(6)]])
	_rot(a, pose, RigBuilder.J_UAL, [
		[0.0, _v(-14, 0, -6)], [0.2, _v(-38, 0, -26)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_CHEST, [
		[0.0, _v(10, 26, 0)], [0.2, _v(16, 48, 0)], [0.42, _v(6, 15, 0)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_HIPS, [
		[0.0, _v(0, 12, 0)], [0.2, _v(0, 30, 0)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_ROOT, [
		[0.0, _v(0)], [0.2, _v(0, 0, 6)], [0.42, _v(0, 0, -3)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_THR, [[0.0, _v(0)], [0.2, _v(-16)], [0.62, _v(0)]])
	_rot(a, pose, RigBuilder.J_HEAD, [[0.0, _v(0, 6, 0)], [0.2, _v(0, 20, 0)], [0.62, _v(0)]])
	return a
