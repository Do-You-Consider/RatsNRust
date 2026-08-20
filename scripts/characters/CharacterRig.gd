class_name CharacterRig
extends Node3D
## Modelo animado de un personaje. Se construye entero por código a partir
## de un perfil de proporciones (CharacterProfiles), igual que el mapa.
##
## Es el único punto que va a tocar el sistema de customización futuro:
##   rig.apply_appearance(cfg)                 -> colores por parte
##   rig.attach_to_socket("Socket_Head", esc)  -> gorros, máscaras, mochilas
##
## Y el único punto que toca el juego para la presentación:
##   rig.set_locomotion("walk")   -> loop de base (idle/walk/run/crawl/...)
##   rig.play_one_shot("attack")  -> se superpone y vuelve solo al loop
##   rig.set_look(pitch, yaw)     -> la cabeza sigue a la cámara
##   rig.hit_burst() / rig.dust_burst()

signal one_shot_finished(anim_name: String)

const BLEND := 0.15

## Recorrido del cuello. Más que esto y la cabeza se despega del torso: el
## resto del giro lo hace el cuerpo entero (el yaw del CharacterBody3D).
const LOOK_PITCH_LIMIT := 40.0
const LOOK_YAW_LIMIT := 32.0

var profile: Dictionary = {}
var parts: Dictionary = {}      # part_id -> MeshInstance3D
var sockets: Dictionary = {}    # socket_name -> Node3D
var pose: Dictionary = {}       # joint_path -> Vector3 (grados)

var _anim: AnimationPlayer
var _locomotion: String = "idle"
var _one_shot: String = ""
var _appearance: CharacterAppearance
var _materials: Dictionary = {} # part_id -> StandardMaterial3D
var _attachments: Dictionary = {} # socket_name -> Node
var _hit_fx: GPUParticles3D
var _dust_fx: GPUParticles3D
var _look_pivot: Node3D


## `arms_only` arma el viewmodel de primera persona: el mismo rig y las
## mismas animaciones, pero solo se ven los brazos. Compartir el rig es lo
## que garantiza que el brazo que ves vos y el que ven los demás nunca se
## desincronicen.
static func create(role: int, arms_only := false) -> CharacterRig:
	var rig := CharacterRig.new()
	rig.name = "Rig"
	rig._build(CharacterProfiles.for_role(role), arms_only)
	rig.apply_appearance(CharacterAppearance.default_for_role(role))
	return rig


func _build(p: Dictionary, arms_only: bool) -> void:
	profile = p

	var built := RigBuilder.build(self, p)
	parts = built.parts
	sockets = built.sockets
	pose = built.pose

	_look_pivot = get_node_or_null(RigBuilder.J_NECKLOOK) as Node3D

	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	add_child(_anim)
	_anim.add_animation_library("", RigAnimations.build_library(p, pose))
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.play("idle")

	if arms_only:
		for part_id in parts.keys():
			if not RigBuilder.ARM_PARTS.has(part_id):
				(parts[part_id] as MeshInstance3D).visible = false
		for mi in parts.values():
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_build_particles(p)


# ------------------------------------------------------------- animación

func set_locomotion(state: String) -> void:
	if _locomotion == state:
		return
	_locomotion = state
	if _one_shot == "":
		_anim.play(state, BLEND)


func play_one_shot(anim_name: String) -> void:
	_one_shot = anim_name
	_anim.play(anim_name, BLEND)


## Corta el one-shot en curso y vuelve al loop de locomoción (lo usa el
## derribo: si te derriban a mitad de un flinch, gana el derribo).
func clear_one_shot() -> void:
	_one_shot = ""
	_anim.play(_locomotion, BLEND)


func _on_animation_finished(anim_name: String) -> void:
	if anim_name != _one_shot:
		return
	_one_shot = ""
	_anim.play(_locomotion, BLEND)
	one_shot_finished.emit(anim_name)


## Congela la animación unos milisegundos. Es el "hit-stop" del golpe: da la
## sensación de impacto sin tocar Engine.time_scale, que en multiplayer
## desincronizaría la física local.
func hit_stop(seconds: float) -> void:
	if _anim.speed_scale == 0.0:
		return
	_anim.speed_scale = 0.0
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(self):
		_anim.speed_scale = 1.0


## Orienta la cabeza. Rota un pivote que ninguna animación toca, así la
## mirada se COMPONE con la animación en curso en vez de pelearse con ella
## (escribir la rotación del cuello desde _process no serviría: el
## AnimationPlayer la pisa cada cuadro).
func set_look(pitch_rad: float, yaw_rad: float) -> void:
	if _look_pivot == null:
		return
	_look_pivot.rotation = Vector3(
		clampf(pitch_rad, -deg_to_rad(LOOK_PITCH_LIMIT), deg_to_rad(LOOK_PITCH_LIMIT)),
		clampf(yaw_rad, -deg_to_rad(LOOK_YAW_LIMIT), deg_to_rad(LOOK_YAW_LIMIT)),
		0.0)


# ----------------------------------------------------------- customización

func apply_appearance(cfg: CharacterAppearance) -> void:
	_appearance = cfg
	for part_id in parts.keys():
		var mat := _material_for(part_id)
		var col := cfg.color_for(part_id)
		mat.albedo_color = col
		if cfg.is_emissive(part_id):
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 2.2
		else:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.emission_enabled = false
		(parts[part_id] as MeshInstance3D).material_override = mat

	for socket_name in cfg.attachments.keys():
		var path: String = cfg.attachments[socket_name]
		if path == "":
			detach_socket(socket_name)
		elif ResourceLoader.exists(path):
			attach_to_socket(socket_name, load(path))


func attach_to_socket(socket_name: String, scene: PackedScene) -> void:
	var socket := sockets.get(socket_name) as Node3D
	if socket == null or scene == null:
		return
	detach_socket(socket_name)
	var inst := scene.instantiate()
	socket.add_child(inst)
	_attachments[socket_name] = inst


func detach_socket(socket_name: String) -> void:
	var prev := _attachments.get(socket_name) as Node
	if prev != null and is_instance_valid(prev):
		prev.queue_free()
	_attachments.erase(socket_name)


func _material_for(part_id: String) -> StandardMaterial3D:
	if _materials.has(part_id):
		return _materials[part_id]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_materials[part_id] = mat
	return mat


# ------------------------------------------------------------- partículas

func _build_particles(p: Dictionary) -> void:
	var chest_y: float = CharacterProfiles.chest_y(p)
	_hit_fx = _make_particles(Color(0.42, 0.05, 0.05), 14, 0.45, 3.4, 55.0, 0.055)
	_hit_fx.name = "HitParticles"
	add_child(_hit_fx)
	_hit_fx.position = Vector3(0, chest_y + (p.chest_size as Vector3).y * 0.5, -0.15)

	_dust_fx = _make_particles(Color(0.42, 0.40, 0.36), 18, 0.9, 1.5, 88.0, 0.075)
	_dust_fx.name = "DustParticles"
	add_child(_dust_fx)
	_dust_fx.position = Vector3(0, 0.08, -0.3)


func _make_particles(color: Color, amount: int, lifetime: float, speed: float,
		spread: float, size: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 0.4, -1)
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -7.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.damping_min = 1.0
	pm.damping_max = 3.0

	# Se apagan hacia el final en vez de desaparecer de golpe.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex

	# Quads planos sin sombreado: mismo lenguaje visual que el resto.
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	quad.material = mat

	var fx := GPUParticles3D.new()
	fx.draw_pass_1 = quad
	fx.process_material = pm
	fx.amount = amount
	fx.lifetime = lifetime
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.emitting = false
	return fx


func hit_burst() -> void:
	if _hit_fx != null:
		_hit_fx.restart()
		_hit_fx.emitting = true


func dust_burst() -> void:
	if _dust_fx != null:
		_dust_fx.restart()
		_dust_fx.emitting = true
