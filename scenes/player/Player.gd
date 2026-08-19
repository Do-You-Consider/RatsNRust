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
const BOB_AMPLITUDE := 0.045
const STEP_MOVE_THRESHOLD := 0.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var body: Node3D = $Body
@onready var torso: MeshInstance3D = $Body/Torso
@onready var head_mesh: MeshInstance3D = $Body/HeadMesh
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer

var speed: float = 6.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _base_camera_y: float = 0.0
var _last_pos: Vector3
var _step_timer: float = 0.0


func _ready() -> void:
	# El nombre del nodo es el peer id (lo setea Game._spawn_player), así que
	# esto funciona igual en la instancia local y en las copias remotas.
	var player_id := int(name)
	var role := GameState.get_role(player_id)
	var is_local := is_multiplayer_authority()

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
	_last_pos = global_position


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


func _update_head_bob(delta: float, is_walking: bool) -> void:
	if is_walking:
		_bob_time += delta * BOB_FREQUENCY
		var bob_offset := sin(_bob_time) * BOB_AMPLITUDE
		var sway := cos(_bob_time * 0.5) * BOB_AMPLITUDE * 0.5
		camera.position = Vector3(sway, _base_camera_y + bob_offset, 0)
	else:
		_bob_time = 0.0
		camera.position = camera.position.lerp(Vector3(0, _base_camera_y, 0), delta * 8.0)


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


## Corre en TODAS las instancias (dueño y remotas) porque se basa en la
## posición real del nodo, que ya llega sincronizada -- así se escuchan los
## pasos de cualquier jugador, no solo los propios.
func _process(delta: float) -> void:
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	var speed_now: float = moved / max(delta, 0.0001)

	if speed_now > STEP_MOVE_THRESHOLD:
		_step_timer -= delta
		if _step_timer <= 0.0:
			footstep_player.stream = ProceduralSound.get_footstep_stream()
			footstep_player.pitch_scale = randf_range(0.9, 1.1)
			footstep_player.play()
			_step_timer = clamp(0.55 - speed_now * 0.02, 0.28, 0.55)
	else:
		_step_timer = 0.0
