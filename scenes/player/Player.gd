extends CharacterBody3D
## Controller FPS. Solo el peer dueño (is_multiplayer_authority) procesa
## input/física/cámara local; en el resto de las instancias este nodo solo
## refleja la posición/rotación que llega por el MultiplayerSynchronizer.
##
## POV asimétrico:
## - Hider: ambiente neutro (sin el filtro rojo) + linterna blanca propia.
## - Seeker: usa el WorldEnvironment de la escena (rojo/opresivo, sin linterna).
##
## El modelo (CharacterRig) se arma por código según el rol -- Atrapador
## grande y encorvado, Rata de altura normal -- y se oculta para el jugador
## local (estás en primera persona, no te ves a vos mismo). El Atrapador
## local ve en su lugar un viewmodel de brazos colgado de la cámara, que
## reproduce las MISMAS animaciones que el cuerpo, así nunca se desfasan.
##
## Este script maneja movimiento y presentación. La lógica de combate
## (validación, HP, condición de victoria) vive en Game.gd.

const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025
const BOB_FREQUENCY := 7.0
const BOB_AMPLITUDE_VERTICAL := 0.045
const BOB_AMPLITUDE_HORIZONTAL := 0.11 # antes era la mitad del vertical; ahora es notablemente mayor
const BOB_ROLL_DEGREES := 2.2 # leve inclinación de cámara en la misma fase del sway
const BOB_BLEND_SPEED := 5.0 # qué tan rápido entra/sale el bobbing (más bajo = más suave)
const STEP_MOVE_THRESHOLD := 0.5
const RUN_ANIM_THRESHOLD := 5.2 # a partir de acá el rig usa "run" en vez de "walk"

## Combate (presentación). Los valores de validación están en Game.gd.
const HIT_STAGGER := 0.45     # tiempo sin control al recibir un golpe
const HIT_KNOCKBACK := 4.5    # empuje del golpe
const DOWN_KNOCKBACK := 6.0   # empuje del golpe que derriba
const KNOCKBACK_DAMP := 9.0   # cuánto se frena el empuje por segundo
const HIT_STOP := 0.06        # congelado de animación al conectar
const SHAKE_TIME := 0.16
const SHAKE_HIT_MAG := 1.6    # grados, al pegar
const SHAKE_TAKE_MAG := 3.2   # grados, al recibir
const FOV_PUNCH := 6.0

## Seguimiento de cabeza. El pitch sale de Head:rotation.x (que ya viaja por
## el MultiplayerSynchronizer); el yaw NO se manda, se deduce de cuánto giró
## el cuerpo este cuadro: la cabeza se queda atrás y después alcanza al
## torso. Eso es lo que hace que girar no parezca mover un bloque rígido.
const LOOK_PITCH_FOLLOW := 14.0
const LOOK_YAW_FOLLOW := 7.0
const LOOK_YAW_LAG := 0.055
const LOOK_DOWNED_SCALE := 0.5

## Cámara del derribado: pegada al piso y un poco adelante. No la pongo en
## la cabeza real del modelo (que al caer de frente queda ~1.3 m adelante)
## porque a esa distancia se mete dentro de las paredes.
const DOWNED_EYE := Vector3(0, 0.38, -0.55)
const DOWNED_PITCH_MIN := -70.0
const DOWNED_PITCH_MAX := 40.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var heartbeat_player: AudioStreamPlayer = $HeartbeatPlayer

## Arrastrá acá los .ogg de pasos desde el FileSystem del editor (seleccioná
## el nodo Player en Player.tscn y usá este campo en el Inspector). Si se
## deja vacío, no suena nada (ya no hay fallback artificial).
@export var footstep_sounds: Array[AudioStream] = []

## .ogg del latido (loop corto de 1 pulso alcanza, se re-dispara solo).
## Se acelera y sube de volumen cuanto más cerca esté el Atrapador. Solo
## suena para el Hider local -- nadie más lo escucha, es tu propio pulso.
@export var heartbeat_sound: AudioStream

const HEARTBEAT_MAX_RANGE := 26.0 # antes 16.0 -- se empieza a sentir desde más lejos
const HEARTBEAT_MIN_RANGE := 3.0 # a esta distancia (o menos) suena al máximo
const HEARTBEAT_MIN_PITCH := 0.85
const HEARTBEAT_MAX_PITCH := 1.9
const HEARTBEAT_MIN_VOLUME_DB := -32.0
const HEARTBEAT_MAX_VOLUME_DB := -3.0

var speed: float = 6.0
var rig: CharacterRig
var arms: CharacterRig

var _profile: Dictionary = {}
var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _bob_blend: float = 0.0 # 0 = quieto, 1 = caminando -- se interpola, nunca salta
var _base_camera_y: float = 0.0
var _step_timer: float = 0.0
var _is_local: bool = false
var _role: int = GameState.Role.NONE

var _downed: bool = false
var _stagger_time: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _swing_pending: bool = false   # el one-shot "attack" todavía está corriendo
var _swing_result: int = -1        # -1 sin resolver, 0 falló, 1 conectó
var _prev_yaw: float = 0.0
var _look_pitch: float = 0.0
var _look_yaw: float = 0.0
var _shake_time: float = 0.0
var _shake_mag: float = 0.0
var _base_fov: float = 78.0
var _fov_punch: float = 0.0


func _ready() -> void:
	# El nombre del nodo es el peer id (lo setea Game._spawn_player), así que
	# esto funciona igual en la instancia local y en las copias remotas.
	var player_id := int(name)
	var role := GameState.get_role(player_id)
	var is_local := is_multiplayer_authority()
	_role = role
	_is_local = is_local
	_profile = CharacterProfiles.for_role(role)

	_build_body(role, is_local)

	camera.current = is_local
	flashlight.visible = (role == GameState.Role.HIDER)

	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		speed = GameState.seeker_speed if role == GameState.Role.SEEKER else GameState.hider_speed
		if role == GameState.Role.HIDER:
			camera.environment = _build_hider_environment()
		# Seeker: camera.environment queda en null -> usa el WorldEnvironment
		# de la escena (el ambiente rojo/tenso ya configurado en Game.tscn).

	_yaw = rotation.y
	_prev_yaw = rotation.y
	_pitch = head.rotation.x
	_base_camera_y = camera.position.y
	_base_fov = camera.fov

	if is_local:
		call_deferred("_resolve_spawn_overlap")

	# Un jugador que aparece cuando la rata ya estaba derribada tiene que
	# verla en el piso, no parada: el estado vive en GameState y se replica.
	if role == GameState.Role.HIDER and GameState.is_downed(player_id):
		set_downed(true, false)

	if is_local and role == GameState.Role.HIDER and heartbeat_sound != null:
		heartbeat_player.stream = heartbeat_sound
		heartbeat_player.finished.connect(_on_heartbeat_finished)
		# OJO: no arranca sonando acá. Se prende/apaga en _update_heartbeat()
		# solo cuando el Atrapador está realmente en rango -- si lo dejábamos
		# sonando siempre a -32db "por si acaso", en la práctica es
		# inaudible y parece que no funciona.


## Arma el modelo del rol, ajusta la cápsula de colisión a sus proporciones
## y sube la cámara a la altura de ojos que corresponde. El Atrapador queda
## a 2.14 m y la Rata a 1.58 m: la diferencia de POV es la mitad de lo que
## hace que uno intimide y el otro se sienta chico.
func _build_body(role: int, is_local: bool) -> void:
	rig = CharacterRig.create(role)
	add_child(rig)
	rig.visible = not is_local
	rig.one_shot_finished.connect(_on_rig_one_shot_finished)

	# La forma es un SubResource compartido entre instancias de la escena:
	# sin duplicar, cambiarle el radio al Atrapador también se lo cambiaría
	# a las Ratas.
	var shape := (collider.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	shape.radius = _profile.col_radius
	shape.height = _profile.col_height
	collider.shape = shape
	collider.position = Vector3(0, _profile.col_height * 0.5, 0)

	head.position = Vector3(0, _profile.eye_y, 0)

	if is_local and role == GameState.Role.SEEKER:
		arms = CharacterRig.create(role, true)
		camera.add_child(arms)
		var s := 0.7
		arms.scale = Vector3(s, s, s)
		arms.position = Vector3(0, -(CharacterProfiles.shoulder_world_y(_profile) * s + 0.10), 0.30)


func _on_heartbeat_finished() -> void:
	if _is_local and _role == GameState.Role.HIDER and not _downed:
		heartbeat_player.play()


## Si el punto de spawn quedó superpuesto con geometría (pared, prop, borde
## de puerta), lo empuja afuera antes de que el jugador tenga control. Evita
## quedar trabado dentro de algo al generarse el mapa.
func _resolve_spawn_overlap() -> void:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var shape := SphereShape3D.new()
	shape.radius = float(_profile.col_radius) * 1.15

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	for i in 6:
		query.transform = Transform3D(Basis(), global_position + Vector3(0, float(_profile.col_height) * 0.5, 0))
		var result := space_state.get_rest_info(query)
		if result.is_empty():
			return
		var normal: Vector3 = result.get("normal", Vector3.UP)
		var depth: float = result.get("depth", 0.1)
		global_position += normal * (depth + 0.05)


## Ambiente propio del Hider: neutro, sin tinte rojo, un poco más de luz
## ambiental para poder orientarse guiándose por la linterna.
func _build_hider_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.38)
	env.ambient_light_energy = 0.22
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.06)
	env.fog_light_energy = 1.0
	env.fog_density = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.03
	return env


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		var pitch_min := deg_to_rad(DOWNED_PITCH_MIN) if _downed else deg_to_rad(-80.0)
		var pitch_max := deg_to_rad(DOWNED_PITCH_MAX) if _downed else deg_to_rad(80.0)
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, pitch_min, pitch_max)
		rotation.y = _yaw
		head.rotation.x = _pitch
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var input_dir := _get_input_dir()

	# Aturdido: perdés el control unos instantes, pero el empuje sigue.
	if _stagger_time > 0.0:
		_stagger_time -= delta
		input_dir = Vector2.ZERO

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := GameState.crawl_speed if _downed else speed

	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DAMP * delta)

	velocity.x = direction.x * current_speed + _knockback.x
	velocity.z = direction.z * current_speed + _knockback.z

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	# Red de seguridad anti-caída al vacío
	if global_position.y < -3.0:
		global_position.y = 1.0
		velocity = Vector3.ZERO

	_update_head_bob(delta, input_dir.length() > 0.0 and is_on_floor())


## El bobbing se controla con un "blend" (0→1) que se interpola con
## move_toward en vez de prender/apagar de golpe -- así, aunque sueltes la
## tecla de movimiento en pleno pico de la onda, la amplitud se apaga
## gradualmente en vez de saltar a la posición neutra.
##
## Arrastrándose el bobbing es más lento y con más balanceo lateral: se
## siente el esfuerzo de tirar del cuerpo con los brazos.
func _update_head_bob(delta: float, is_walking: bool) -> void:
	var target_blend := 1.0 if is_walking else 0.0
	_bob_blend = move_toward(_bob_blend, target_blend, delta * BOB_BLEND_SPEED)

	var freq := BOB_FREQUENCY * (0.35 if _downed else 1.0)
	if _bob_blend > 0.001:
		_bob_time += delta * freq
	else:
		_bob_time = 0.0

	var amp_v := BOB_AMPLITUDE_VERTICAL * (0.6 if _downed else 1.0)
	var amp_h := BOB_AMPLITUDE_HORIZONTAL * (1.6 if _downed else 1.0)
	var roll_deg := BOB_ROLL_DEGREES * (2.2 if _downed else 1.0)

	var bob_offset := sin(_bob_time) * amp_v * _bob_blend
	var sway := cos(_bob_time * 0.5) * amp_h * _bob_blend
	var roll := cos(_bob_time * 0.5) * deg_to_rad(roll_deg) * _bob_blend

	# Sacudón de cámara del combate: se suma al bobbing y decae solo.
	var shake := Vector3.ZERO
	if _shake_time > 0.0:
		var k := _shake_time / SHAKE_TIME
		shake = Vector3(
			randf_range(-1.0, 1.0) * _shake_mag * k,
			randf_range(-1.0, 1.0) * _shake_mag * k,
			randf_range(-1.0, 1.0) * _shake_mag * k * 0.5)

	camera.position = Vector3(sway, _base_camera_y + bob_offset, 0)
	camera.rotation = Vector3(deg_to_rad(shake.x), deg_to_rad(shake.y), roll + deg_to_rad(shake.z))


func _get_input_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	return dir.normalized()


## Usa los .ogg reales si arrastraron alguno al array del Inspector. Si el
## array está vacío no reproduce nada (sin fallback artificial).
func _pick_footstep_stream() -> AudioStream:
	if footstep_sounds.is_empty():
		return null
	return footstep_sounds[randi() % footstep_sounds.size()]


## Corre en TODAS las instancias (dueño y remotas). Usa la VELOCIDAD real
## (sincronizada por red), no la posición cruda: medir distancia recorrida
## cuadro a cuadro es ruidoso -- move_and_slide() hace micro-ajustes de
## "snap al piso" incluso parado, y eso alcanzaba a disparar pasos con el
## jugador quieto.
func _process(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	_update_locomotion(horizontal_speed)
	_update_look(delta)
	_update_footsteps(delta, horizontal_speed)

	if _shake_time > 0.0:
		_shake_time = max(0.0, _shake_time - delta)
	if _fov_punch > 0.001:
		_fov_punch = move_toward(_fov_punch, 0.0, FOV_PUNCH * 4.0 * delta)
		camera.fov = _base_fov + _fov_punch

	if _is_local and _role == GameState.Role.HIDER and heartbeat_sound != null:
		_update_heartbeat()


## Elige el loop del rig a partir de la velocidad ya replicada. Como el dato
## viene del MultiplayerSynchronizer, las copias remotas eligen la misma
## animación que la local sin mandar un solo byte extra.
func _update_locomotion(horizontal_speed: float) -> void:
	if rig == null:
		return
	var state: String
	if _downed:
		state = "crawl" if horizontal_speed > 0.2 else "downed_idle"
	elif horizontal_speed > RUN_ANIM_THRESHOLD:
		state = "run"
	elif horizontal_speed > STEP_MOVE_THRESHOLD:
		state = "walk"
	else:
		state = "idle"
	rig.set_locomotion(state)
	if arms != null:
		arms.set_locomotion(state)


## Corre en TODAS las instancias. En la local el rig está oculto, pero se
## anima igual: es el mismo nodo que ven los demás, así que no hay dos
## caminos distintos que puedan desincronizarse.
func _update_look(delta: float) -> void:
	if rig == null:
		return

	var scale_factor := LOOK_DOWNED_SCALE if _downed else 1.0
	var target_pitch: float = head.rotation.x * scale_factor

	var yaw_rate := angle_difference(_prev_yaw, rotation.y) / maxf(delta, 0.0001)
	_prev_yaw = rotation.y
	# Signo negativo: si el cuerpo gira a la izquierda, la cabeza queda
	# apuntando a la derecha RESPECTO DEL TORSO hasta que lo alcanza.
	var target_yaw := clampf(-yaw_rate * LOOK_YAW_LAG, -0.8, 0.8) * scale_factor

	_look_pitch = lerpf(_look_pitch, target_pitch, 1.0 - exp(-LOOK_PITCH_FOLLOW * delta))
	_look_yaw = lerpf(_look_yaw, target_yaw, 1.0 - exp(-LOOK_YAW_FOLLOW * delta))
	rig.set_look(_look_pitch, _look_yaw)


func _update_footsteps(delta: float, horizontal_speed: float) -> void:
	if horizontal_speed <= STEP_MOVE_THRESHOLD and not (_downed and horizontal_speed > 0.2):
		_step_timer = 0.0
		if footstep_player.playing:
			footstep_player.stop()
		return

	_step_timer -= delta
	if _step_timer > 0.0:
		return

	var stream := _pick_footstep_stream()
	if stream != null:
		footstep_player.stream = stream
		# Arrastrándose el sonido es más grave, más espaciado y más bajo:
		# se sigue oyendo (una rata derribada no es invisible) pero mucho
		# menos que unos pasos.
		footstep_player.pitch_scale = randf_range(0.55, 0.68) if _downed else randf_range(0.9, 1.1)
		footstep_player.volume_db = -12.0 if _downed else 0.0
		footstep_player.play()

	# Antes bajaba hasta 0.28s con el Hider (más rápido, 6.5), y si el
	# .ogg dura más que eso cada .play() corta el clip anterior a la
	# mitad -- suena entrecortado. Le damos más aire al intervalo.
	if _downed:
		_step_timer = 1.5
	else:
		_step_timer = clamp(0.6 - horizontal_speed * 0.025, 0.38, 0.6)


## Prende/apaga el latido según si el Atrapador está en rango, y ajusta
## pitch/volumen según distancia. Solo se llama para el Hider local.
func _update_heartbeat() -> void:
	# Ya derribada, la rata deja de escuchar su propio pulso: el peligro
	# inmediato pasó, ya te alcanzaron.
	if _downed:
		if heartbeat_player.playing:
			heartbeat_player.stop()
		return

	var atrapador := _find_atrapador()
	if atrapador == null:
		if heartbeat_player.playing:
			heartbeat_player.stop()
		return

	var dist := global_position.distance_to(atrapador.global_position)
	if dist > HEARTBEAT_MAX_RANGE:
		if heartbeat_player.playing:
			heartbeat_player.stop()
		return

	if not heartbeat_player.playing:
		heartbeat_player.play()

	var t: float = 1.0 - clamp((dist - HEARTBEAT_MIN_RANGE) / (HEARTBEAT_MAX_RANGE - HEARTBEAT_MIN_RANGE), 0.0, 1.0)
	heartbeat_player.pitch_scale = lerpf(HEARTBEAT_MIN_PITCH, HEARTBEAT_MAX_PITCH, t)
	heartbeat_player.volume_db = lerpf(HEARTBEAT_MIN_VOLUME_DB, HEARTBEAT_MAX_VOLUME_DB, t)


## Busca al Seeker entre los hermanos bajo el mismo nodo "Players" (Game.gd
## los agrupa ahí al spawnear). No hace falta ninguna referencia extra a
## Game.gd, la posición ya llega sincronizada por el MultiplayerSynchronizer.
func _find_atrapador() -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child == self:
			continue
		if child is CharacterBody3D and GameState.get_role(int(child.name)) == GameState.Role.SEEKER:
			return child
	return null


# ============================================================== COMBATE
# Todo lo de acá abajo lo llama Game.gd. Este script solo presenta: no
# decide si un golpe fue válido ni cuánta vida queda.

func is_downed() -> bool:
	return _downed


## Arranca el swing. Corre en TODOS los peers (el atacante lo dispara al
## hacer clic, el resto al recibir el broadcast), así la anticipación se ve
## en todas las pantallas casi al mismo tiempo.
func play_swing() -> void:
	_swing_pending = true
	_swing_result = -1
	if rig != null:
		rig.play_one_shot("attack")
	if arms != null:
		arms.play_one_shot("attack")


## Llega el veredicto del servidor. Si el swing todavía está en el aire, se
## guarda y lo encadena _on_rig_one_shot_finished(); si ya terminó, se
## encadena en el acto.
func resolve_swing(hit: bool) -> void:
	_swing_result = 1 if hit else 0
	if hit and _is_local:
		_shake(SHAKE_HIT_MAG)
		if rig != null:
			rig.hit_stop(HIT_STOP)
		if arms != null:
			arms.hit_stop(HIT_STOP)
	if not _swing_pending:
		_play_swing_followup()


func _on_rig_one_shot_finished(anim_name: String) -> void:
	if anim_name != "attack":
		return
	_swing_pending = false
	_play_swing_followup()


## Sin veredicto todavía (paquete en camino) asumimos recover: es la
## recuperación corta, así que en el peor caso el castigo por fallar llega
## un instante tarde en vez de castigar de más a quien sí pegó.
func _play_swing_followup() -> void:
	var anim := "attack_whiff" if _swing_result == 0 else "attack_recover"
	_swing_result = -1
	if rig != null:
		rig.play_one_shot(anim)
	if arms != null:
		arms.play_one_shot(anim)


## Recibe un golpe. `from_position` es de dónde vino (para el empuje) y
## `downed` dice si este golpe fue el que la derribó.
func receive_hit(from_position: Vector3, downed: bool) -> void:
	var dir := global_position - from_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -global_transform.basis.z

	_stagger_time = HIT_STAGGER
	_knockback = dir * (DOWN_KNOCKBACK if downed else HIT_KNOCKBACK)

	if rig != null:
		rig.hit_burst()
		if downed:
			rig.play_one_shot("knockdown")
			rig.dust_burst()
		else:
			rig.play_one_shot("hit_react")

	if _is_local:
		_shake(SHAKE_TAKE_MAG)
		_fov_punch = FOV_PUNCH
		camera.fov = _base_fov + _fov_punch

	if downed:
		set_downed(true, true)


## Aplica (o saca) el estado de derribado. `animated` en false lo pone de
## una, sin la caída -- es lo que usa un peer que llega tarde y encuentra a
## la rata ya en el piso.
func set_downed(value: bool, animated := true) -> void:
	if _downed == value:
		return
	_downed = value

	if value:
		# La cápsula pasa a estar acostada, alineada con el cuerpo que quedó
		# tirado hacia adelante: si dejábamos la cápsula parada, el Atrapador
		# atravesaba el modelo caminando.
		var lying := CapsuleShape3D.new()
		lying.radius = float(_profile.col_radius) * 0.85
		lying.height = float(_profile.height) * 0.92
		collider.shape = lying
		collider.rotation.x = PI * 0.5
		collider.position = Vector3(0, lying.radius, -float(_profile.height) * 0.34)

		_pitch = clamp(_pitch, deg_to_rad(DOWNED_PITCH_MIN), deg_to_rad(DOWNED_PITCH_MAX))
		head.rotation.x = _pitch
		if animated:
			var tw := create_tween()
			tw.tween_property(head, "position", DOWNED_EYE, 0.55).set_ease(Tween.EASE_OUT)
		else:
			head.position = DOWNED_EYE
			if rig != null:
				rig.set_locomotion("downed_idle")
				rig.clear_one_shot()
	else:
		var standing := CapsuleShape3D.new()
		standing.radius = _profile.col_radius
		standing.height = _profile.col_height
		collider.shape = standing
		collider.rotation.x = 0.0
		collider.position = Vector3(0, float(_profile.col_height) * 0.5, 0)
		head.position = Vector3(0, _profile.eye_y, 0)


func _shake(magnitude: float) -> void:
	_shake_time = SHAKE_TIME
	_shake_mag = magnitude
