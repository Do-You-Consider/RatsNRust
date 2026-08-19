extends Node3D
## Orquesta la partida: genera el mapa (con la seed que mandó el host),
## spawnea el jugador de cada peer vía MultiplayerSpawner, chequea la
## condición de victoria (host) y actualiza el HUD local simplificado.

const PlayerScene := preload("res://scenes/player/Player.tscn")
const CATCH_RADIUS := 1.6

@onready var map_generator: MapGenerator = $MapGenerator
@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner

@onready var timer_label: Label = $UI/TopHUD/TimerLabel
@onready var status_label: Label = $UI/TopHUD/StatusLabel
@onready var intro_banner: CenterContainer = $UI/IntroBanner
@onready var intro_role_label: Label = $UI/IntroBanner/VBox/RoleTitle
@onready var intro_obj_label: Label = $UI/IntroBanner/VBox/RoleObjective
@onready var role_badge_label: Label = $UI/RoleBadge/RoleLabel

var _hiders_caught: Dictionary = {}


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	map_generator.generate(GameState.map_seed)

	if multiplayer.is_server():
		_spawn_all_players()

	_setup_hud()


func _setup_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	var role := GameState.get_role(my_id)

	if role == GameState.Role.SEEKER:
		intro_role_label.text = "ERES EL COBRADOR"
		intro_role_label.modulate = Color(1.0, 0.28, 0.18)
		intro_obj_label.text = "CAZA A TODAS LAS RATAS ANTES DE QUE SE AGOTE EL TIEMPO"
		role_badge_label.text = "[ COBRADOR ]"
		role_badge_label.modulate = Color(1.0, 0.35, 0.2)
	else:
		intro_role_label.text = "ERES UNA RATA"
		intro_role_label.modulate = Color(0.4, 0.9, 0.55)
		intro_obj_label.text = "ESCONDETE Y SOBREVIVE HASTA EL FINAL DE LA RONDA"
		role_badge_label.text = "[ RATA ]"
		role_badge_label.modulate = Color(0.4, 0.9, 0.55)

	# Animación de desvanecimiento suave del banner de inicio (fade-out a los 2.5 segundos)
	intro_banner.modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(intro_banner, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): intro_banner.visible = false)


## Cada Hider recibe un punto de spawn distinto (map_generator.hider_spawn_points),
## el Seeker spawnea en su propio punto (opuesto en el laberinto).
func _spawn_all_players() -> void:
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())

	var hider_index := 0
	for id in ids:
		var role := GameState.get_role(id)
		var spawn_pos: Vector3
		if role == GameState.Role.SEEKER:
			spawn_pos = map_generator.seeker_spawn_point
		else:
			var points := map_generator.hider_spawn_points
			spawn_pos = points[hider_index % points.size()] if points.size() > 0 else map_generator.seeker_spawn_point
			hider_index += 1
		spawner.spawn({"id": id, "spawn": spawn_pos})


func _spawn_player(data: Dictionary) -> Node:
	var player := PlayerScene.instantiate()
	player.name = str(data.id)
	player.set_multiplayer_authority(data.id)
	player.position = data.spawn
	return player


func _process(delta: float) -> void:
	if multiplayer.is_server() and GameState.round_active:
		GameState.round_time_left = max(0.0, GameState.round_time_left - delta)
		_check_catches()
		if GameState.round_time_left <= 0.0:
			NetworkManager.end_round("hiders")

	var total_secs := int(ceil(GameState.round_time_left))
	var mins := total_secs / 60
	var secs := total_secs % 60
	timer_label.text = "%02d:%02d" % [mins, secs]

	if total_secs <= 30:
		timer_label.modulate = Color(1.0, 0.3, 0.2)
	else:
		timer_label.modulate = Color(0.9, 0.72, 0.35)

	var total_hiders := 0
	var caught_count := 0
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) == GameState.Role.HIDER:
			total_hiders += 1
			if _hiders_caught.get(pid, false):
				caught_count += 1
	var active_hiders: int = maxi(0, total_hiders - caught_count)
	if total_hiders > 0:
		status_label.text = "RATAS VIVAS: %d / %d" % [active_hiders, total_hiders]
	else:
		status_label.text = "RATAS VIVAS: --"


## Solo corre en el host: revisa distancia del Seeker a cada Hider vivo.
## Cuando TODOS los Hiders fueron atrapados, gana el Seeker.
func _check_catches() -> void:
	var seeker_pos := Vector3.ZERO
	var seeker_found := false
	var hider_ids: Array = []

	for child in players_root.get_children():
		var pid := int(child.name)
		match GameState.get_role(pid):
			GameState.Role.SEEKER:
				seeker_pos = child.global_position
				seeker_found = true
			GameState.Role.HIDER:
				hider_ids.append(pid)

	if not seeker_found or hider_ids.is_empty():
		return

	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) != GameState.Role.HIDER:
			continue
		if _hiders_caught.get(pid, false):
			continue
		if child.global_position.distance_to(seeker_pos) < CATCH_RADIUS:
			_hiders_caught[pid] = true

	for pid in hider_ids:
		if not _hiders_caught.get(pid, false):
			return

	NetworkManager.end_round("seeker")
