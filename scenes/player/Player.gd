extends CharacterBody3D
## Controller FPS. Solo el peer dueño (is_multiplayer_authority) procesa
## input/física/cámara local; en el resto de las instancias este nodo solo
## refleja la posición/rotación que llega por el MultiplayerSynchronizer.
##
## POV asimétrico:
## - Hider: ambiente neutro (sin el filtro rojo) + linterna blanca propia.
## - Seeker: usa el WorldEnvironment de la escena (rojo/opresivo, sin linterna).

const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var speed: float = 6.0
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	# El nombre del nodo es el peer id (lo setea Game._spawn_player), así que
	# esto funciona igual en la instancia local y en las copias remotas.
	var player_id := int(name)
	var role := GameState.get_role(player_id)
	var is_local := is_multiplayer_authority()

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
	_pitch = head.rotation.x


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
