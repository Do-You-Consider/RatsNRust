extends Node3D
## Orquesta la partida: genera el mapa (con la seed que mandó el host),
## spawnea el jugador de cada peer vía MultiplayerSpawner, maneja el atrape
## por click (validado en el servidor) y actualiza el HUD local simplificado.

const PlayerScene := preload("res://scenes/player/Player.tscn")
const CATCH_RADIUS := 1.6 # distancia real a la que el click de atrape es válido
const CATCH_PROMPT_RANGE := 2.4 # un poco más generoso, para que el ícono avise antes

@onready var map_generator: MapGenerator = $MapGenerator
@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner

@onready var timer_label: Label = $UI/TopHUD/TimerLabel
@onready var status_label: Label = $UI/TopHUD/StatusLabel
@onready var intro_banner: CenterContainer = $UI/IntroBanner
@onready var intro_role_label: Label = $UI/IntroBanner/VBox/RoleTitle
@onready var intro_obj_label: Label = $UI/IntroBanner/VBox/RoleObjective
@onready var role_badge_label: Label = $UI/RoleBadge/RoleLabel
@onready var catch_prompt: VBoxContainer = $UI/CatchPrompt

var _hiders_caught: Dictionary = {}
var _my_role: int = GameState.Role.NONE
var _nearby_hider_id: int = -1


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	map_generator.generate(GameState.map_seed)

	if multiplayer.is_server():
		_spawn_all_players()

	_my_role = GameState.get_role(multiplayer.get_unique_id())
	_setup_hud()


func _setup_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	var role := GameState.get_role(my_id)

	if role == GameState.Role.SEEKER:
		intro_role_label.text = "ERES EL ATRAPADOR"
		intro_role_label.modulate = Color(1.0, 0.28, 0.18)
		intro_obj_label.text = "CAZA A TODAS LAS RATAS ANTES DE QUE SE AGOTE EL TIEMPO"
		role_badge_label.text = "[ ATRAPADOR ]"
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


func _unhandled_input(event: InputEvent) -> void:
	if _my_role != GameState.Role.SEEKER:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _nearby_hider_id != -1:
			_request_catch.rpc_id(1, _nearby_hider_id)


func _process(delta: float) -> void:
	if GameState.round_active:
		GameState.round_time_left = max(0.0, GameState.round_time_left - delta)

	if multiplayer.is_server() and GameState.round_active:
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

	if _my_role == GameState.Role.SEEKER:
		_update_catch_prompt()


## Solo se llama para el Seeker local: busca el Hider vivo más cercano y
## mueve/muestra el ícono de "clic para atrapar" siguiendo su posición real
## en pantalla (proyección 3D->2D con la cámara local), no fijo al centro.
func _update_catch_prompt() -> void:
	var my_player := players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	if my_player == null:
		catch_prompt.visible = false
		_nearby_hider_id = -1
		return

	var closest_id := -1
	var closest_node: Node3D = null
	var closest_dist := CATCH_PROMPT_RANGE
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) != GameState.Role.HIDER:
			continue
		if _hiders_caught.get(pid, false):
			continue
		var d: float = child.global_position.distance_to(my_player.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_id = pid
			closest_node = child

	_nearby_hider_id = closest_id

	if closest_id == -1 or closest_node == null:
		catch_prompt.visible = false
		return

	var cam := my_player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		catch_prompt.visible = false
		return

	# Un poco arriba de los pies, altura aproximada de cabeza/torso
	var target_pos: Vector3 = closest_node.global_position + Vector3(0, 1.5, 0)
	if cam.is_position_behind(target_pos):
		catch_prompt.visible = false
		return

	var screen_pos := cam.unproject_position(target_pos)
	catch_prompt.visible = true
	# Centrado horizontalmente sobre el objetivo, un poco arriba de su cabeza
	catch_prompt.position = screen_pos - catch_prompt.size * 0.5 - Vector2(0, 34)


## El cliente pide atrapar; SOLO el servidor decide si es válido (evita que
## un cliente modificado se auto-declare ganador). Verifica que quien pide
## sea realmente el Seeker y que la distancia real sea correcta -- el
## CATCH_PROMPT_RANGE del lado del cliente es solo para avisar antes, la
## verdad está acá.
@rpc("any_peer", "reliable")
func _request_catch(hider_id: int) -> void:
	if not multiplayer.is_server():
		return

	var requester_id := multiplayer.get_remote_sender_id()
	if GameState.get_role(requester_id) != GameState.Role.SEEKER:
		return
	if _hiders_caught.get(hider_id, false):
		return

	var seeker_node := players_root.get_node_or_null(str(requester_id))
	var hider_node := players_root.get_node_or_null(str(hider_id))
	if seeker_node == null or hider_node == null:
		return
	if seeker_node.global_position.distance_to(hider_node.global_position) > CATCH_RADIUS:
		return

	_hiders_caught[hider_id] = true
	_check_all_caught()


## Solo corre en el host: si ya no queda ningún Hider libre, gana el Seeker.
func _check_all_caught() -> void:
	if not multiplayer.is_server():
		return

	var hider_ids: Array = []
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) == GameState.Role.HIDER:
			hider_ids.append(pid)

	if hider_ids.is_empty():
		return
	for pid in hider_ids:
		if not _hiders_caught.get(pid, false):
			return

	NetworkManager.end_round("seeker")
