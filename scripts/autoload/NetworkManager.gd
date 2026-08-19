extends Node
## Autoload: maneja la creación/unión de salas multiplayer (ENet).
## Se registra en project.godot -> [autoload] como "NetworkManager".

signal server_created
signal connected_to_server
signal server_disconnected
signal connection_failed
signal player_connected(id: int)
signal player_disconnected(id: int)
signal lobby_synced(count: int, host_ip: String)
signal game_started
signal round_ended(winner: String)

const PORT := 7777
const MAX_PLAYERS := 8
const GAME_SCENE := "res://scenes/game/Game.tscn"
const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

var lobby_host_ip: String = "127.0.0.1"
var lobby_player_count: int = 1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func create_room() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("create_room error: %s" % err)
		return false
	multiplayer.multiplayer_peer = peer
	lobby_host_ip = get_local_ip()
	lobby_player_count = 1
	server_created.emit()
	_sync_lobby()
	return true


func join_room(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("join_room error: %s" % err)
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	lobby_host_ip = address


func leave_room() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	lobby_player_count = 1


func _sync_lobby() -> void:
	if not multiplayer.is_server():
		return
	var count := multiplayer.get_peers().size() + 1
	lobby_player_count = count
	_rpc_sync_lobby.rpc(count, lobby_host_ip)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(count: int, host_ip: String) -> void:
	lobby_player_count = count
	lobby_host_ip = host_ip
	lobby_synced.emit(count, host_ip)


## Solo el host puede llamar esto. Elige un Seeker al azar entre todos los
## conectados (host incluido), sincroniza los roles y manda a todos a la
## escena de juego.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	if ids.size() < 2:
		push_warning("Necesitás al menos 2 jugadores para empezar.")
		return

	var seeker_id: int = ids[randi() % ids.size()]
	var roles: Dictionary = {}
	for pid in ids:
		roles[pid] = GameState.Role.SEEKER if pid == seeker_id else GameState.Role.HIDER

	var map_seed: int = randi()
	_rpc_start_game.rpc(roles, map_seed)


@rpc("authority", "call_local", "reliable")
func _rpc_start_game(roles: Dictionary, map_seed: int) -> void:
	GameState.reset()
	GameState.player_roles = roles
	GameState.map_seed = map_seed
	GameState.round_time_left = GameState.round_duration
	GameState.round_active = true
	game_started.emit()
	get_tree().change_scene_to_file(GAME_SCENE)


## Solo el host puede llamar esto: termina la ronda y manda a todos de vuelta
## a la sala de espera (el menú), mostrando quién ganó.
## winner: "hiders" (sobrevivieron el tiempo) o "seeker" (atrapó a todos).
func end_round(winner: String) -> void:
	if not multiplayer.is_server():
		return
	if not GameState.round_active:
		return
	_rpc_end_round.rpc(winner)


@rpc("authority", "call_local", "reliable")
func _rpc_end_round(winner: String) -> void:
	GameState.round_active = false
	GameState.last_result = winner
	round_ended.emit(winner)
	get_tree().change_scene_to_file(MENU_SCENE)


func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			return ip
	return "127.0.0.1"


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)
	if multiplayer.is_server():
		_sync_lobby()


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)
	if multiplayer.is_server():
		_sync_lobby()


func _on_connection_failed() -> void:
	leave_room()
	connection_failed.emit()


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_server_disconnected() -> void:
	leave_room()
	server_disconnected.emit()
