extends CharacterBody3D
## Controller FPS. Solo el peer dueño (is_multiplayer_authority) procesa
## input/física/cámara local; en el resto de las instancias este nodo solo
## refleja la posición/rotación que llega por el MultiplayerSynchronizer.
##
## POV asimétrico:
## - Hider: ambiente neutro (sin el filtro rojo) + linterna blanca propia.
## - Seeker: usa el WorldEnvironment de la escena (rojo/opresivo, sin linterna).
##
## El cuerpo (Body/Torso/HeadMesh) se oculta para el jugador local (estás en
## primera persona, no te ves a vos mismo) pero se ve para los demás -- es el
## modelo básico low-poly del jugador, coloreado según su rol.

const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025
const BOB_FREQUENCY := 7.0
const BOB_AMPLITUDE_VERTICAL := 0.045
const BOB_AMPLITUDE_HORIZONTAL := 0.11 # antes era la mitad del vertical; ahora es notablemente mayor
const BOB_ROLL_DEGREES := 2.2 # leve inclinación de cámara en la misma fase del sway
const BOB_BLEND_SPEED := 5.0 # qué tan rápido entra/sale el bobbing (más bajo = más suave)
const STEP_MOVE_THRESHOLD := 0.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var body: Node3D = $Body
@onready var torso: MeshInstance3D = $Body/Torso
@onready var head_mesh: MeshInstance3D = $Body/HeadMesh
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
var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _bob_blend: float = 0.0 # 0 = quieto, 1 = caminando -- se interpola, nunca salta
var _base_camera_y: float = 0.0
var _step_timer: float = 0.0
var _is_local: bool = false
var _role: int = GameState.Role.NONE


func _ready() -> void:
	# El nombre del nodo es el peer id (lo setea Game._spawn_player), así que
	# esto funciona igual en la instancia local y en las copias remotas.
	var player_id := int(name)
	var role := GameState.get_role(player_id)
	var is_local := is_multiplayer_authority()
	_role = role
	_is_local = is_local

	camera.current = is_local
	flashlight.visible = (role == GameState.Role.HIDER)
	body.visible = not is_local

	_apply_role_appearance(role)

	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		speed = GameState.seeker_speed if role == GameState.Role.SEEKER else GameState.hider_speed
		if role == GameState.Role.HIDER:
			camera.environment = _build_hider_environment()
		# Seeker: camera.environment queda en null -> usa el WorldEnvironment
		# de la escena (el ambiente rojo/tenso ya configurado en Game.tscn).

	_yaw = rotation.y
	_pitch = head.rotation.x
	_base_camera_y = camera.position.y

	if is_local:
		call_deferred("_resolve_spawn_overlap")

	if is_local and role == GameState.Role.HIDER and heartbeat_sound != null:
		heartbeat_player.stream = heartbeat_sound
		heartbeat_player.finished.connect(_on_heartbeat_finished)
		# OJO: no arranca sonando acá. Se prende/apaga en _update_heartbeat()
		# solo cuando el Atrapador está realmente en rango -- si lo dejábamos
		# sonando siempre a -32db "por si acaso", en la práctica es
		# inaudible y parece que no funciona.


func _on_heartbeat_finished() -> void:
	if _is_local and _role == GameState.Role.HIDER:
		heartbeat_player.play()


## Si el punto de spawn quedó superpuesto con geometría (pared, prop, borde
## de puerta), lo empuja afuera antes de que el jugador tenga control. Evita
## quedar trabado dentro de algo al generarse el mapa.
func _resolve_spawn_overlap() -> void:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var shape := SphereShape3D.new()
	shape.radius = 0.42

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	for i in 6:
		query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
		var result := space_state.get_rest_info(query)
		if result.is_empty():
			return
		var normal: Vector3 = result.get("normal", Vector3.UP)
		var depth: float = result.get("depth", 0.1)
		global_position += normal * (depth + 0.05)


func _apply_role_appearance(role: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	if role == GameState.Role.SEEKER:
		mat.albedo_color = Color(0.12, 0.03, 0.03)
	else:
		mat.albedo_color = Color(0.35, 0.33, 0.28)
	torso.material_override = mat
	head_mesh.material_override = mat


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
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80), deg_to_rad(80))
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
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

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
func _update_head_bob(delta: float, is_walking: bool) -> void:
	var target_blend := 1.0 if is_walking else 0.0
	_bob_blend = move_toward(_bob_blend, target_blend, delta * BOB_BLEND_SPEED)

	if _bob_blend > 0.001:
		_bob_time += delta * BOB_FREQUENCY
	else:
		_bob_time = 0.0

	var bob_offset := sin(_bob_time) * BOB_AMPLITUDE_VERTICAL * _bob_blend
	var sway := cos(_bob_time * 0.5) * BOB_AMPLITUDE_HORIZONTAL * _bob_blend
	var roll := cos(_bob_time * 0.5) * deg_to_rad(BOB_ROLL_DEGREES) * _bob_blend

	camera.position = Vector3(sway, _base_camera_y + bob_offset, 0)
	camera.rotation.z = roll


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

	if horizontal_speed > STEP_MOVE_THRESHOLD:
		_step_timer -= delta
		if _step_timer <= 0.0:
			var stream := _pick_footstep_stream()
			if stream != null:
				footstep_player.stream = stream
				footstep_player.pitch_scale = randf_range(0.9, 1.1)
				footstep_player.play()
			# Antes bajaba hasta 0.28s con el Hider (más rápido, 6.5), y si el
			# .ogg dura más que eso cada .play() corta el clip anterior a la
			# mitad -- suena entrecortado. Le damos más aire al intervalo.
			_step_timer = clamp(0.6 - horizontal_speed * 0.025, 0.38, 0.6)
	else:
		_step_timer = 0.0
		if footstep_player.playing:
			footstep_player.stop()

	if _is_local and _role == GameState.Role.HIDER and heartbeat_sound != null:
		_update_heartbeat()


## Prende/apaga el latido según si el Atrapador está en rango, y ajusta
## pitch/volumen según distancia. Solo se llama para el Hider local.
func _update_heartbeat() -> void:
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
