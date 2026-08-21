class_name MenuCameraDirector
extends Node3D
## Cámara del menú. Es un pivote (este nodo) con la Camera3D adentro:
##
##   MenuCameraDirector  <- lo mueven los tweens entre encuadres
##     └ Camera3D        <- le sumamos el temblor de cámara en mano
##
## Están separados a propósito. Si el temblor se escribiera sobre el mismo
## nodo que anima el tween, cada cuadro se pisarían mutuamente: el tween
## setearía la pose del encuadre y el temblor la pisaría, o al revés, según el
## orden de ejecución. Con dos nodos, el movimiento y el temblor se COMPONEN.

## Amplitud del temblor. Muy chico a propósito: a 480x270 un temblor de
## verdad se convierte en ruido de píxeles.
const SHAKE_POS := 0.010
const SHAKE_ROT := 0.16   # grados

var camera: Camera3D

var _shake: float = 1.0
var _t: float = 0.0
var _tween: Tween


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)


func _process(delta: float) -> void:
	_t += delta
	# Tres senos de frecuencias primas entre sí: no se repite a simple vista y
	# cuesta tres multiplicaciones.
	camera.position = Vector3(
		sin(_t * 1.30) * SHAKE_POS + sin(_t * 0.47) * SHAKE_POS * 0.6,
		cos(_t * 1.07) * SHAKE_POS,
		sin(_t * 0.71) * SHAKE_POS * 0.5) * _shake
	camera.rotation_degrees = Vector3(
		sin(_t * 0.83) * SHAKE_ROT,
		cos(_t * 0.61) * SHAKE_ROT,
		sin(_t * 0.39) * SHAKE_ROT * 0.7) * _shake


## 0 = cámara clavada (la del vestuario, que es un trípode), 1 = en mano.
func set_shake(amount: float) -> void:
	_shake = amount


func snap(shot: Dictionary) -> void:
	_kill_tween()
	transform = shot["xf"]
	camera.fov = shot["fov"]


## Mueve la cámara a otro encuadre. El default (EASE_IN_OUT / TRANS_CUBIC) es
## el que hace que el movimiento arranque y frene solo; lineal se lee como un
## error de motor, no como una cámara.
func move_to(shot: Dictionary, duration: float,
		trans: Tween.TransitionType = Tween.TRANS_CUBIC,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> Tween:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "transform", shot["xf"], duration).set_trans(trans).set_ease(ease_type)
	_tween.tween_property(camera, "fov", shot["fov"], duration).set_trans(trans).set_ease(ease_type)
	return _tween


## Empuje lento y continuo hacia adelante. Es lo que mantiene vivo un encuadre
## fijo (la pantalla de título) sin pedirle nada al jugador.
func drift(shot: Dictionary, distance: float, duration: float) -> void:
	_kill_tween()
	var xf: Transform3D = shot["xf"]
	var target := xf.translated_local(Vector3(0, 0, -distance))
	transform = xf
	camera.fov = shot["fov"]
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "transform", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "transform", xf, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
