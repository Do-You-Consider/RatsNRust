extends Node
## Autoload: salas multiplayer (ENet) + roster de la sala de espera.
## Se registra en project.godot -> [autoload] como "NetworkManager".
##
## Las salas se buscan POR NOMBRE, no por IP: RoomDiscovery hace un barrido
## UDP de la red local y devuelve fichas {nombre, uuid, jugadores, ping}. El
## uuid es lo que desempata dos salas con el mismo nombre.
##
## El roster (quién está, cómo se llama, si está listo y con qué apariencia)
## vive en el host y se replica entero en cada cambio. Es chico -- 8 entradas
## como mucho -- así que replicarlo completo sale más barato que llevar
## deltas, y no hay forma de que un cliente quede desincronizado.

signal server_created
signal connected_to_server
signal server_disconnected
signal connection_failed
signal player_connected(id: int)
signal player_disconnected(id: int)
signal roster_updated
signal rooms_found(rooms: Array)
signal game_started
signal round_ended(winner: String)
## Todos los peers arrancan la animación de entrada a la discoteca.
signal launch_sequence_started

const PORT := 7777
const MAX_PLAYERS := 8
const GAME_SCENE := "res://scenes/game/Game.tscn"
const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

## Cuánto dura la animación de "todos entran al boliche" antes del cambio de
## escena. Tiene que coincidir con MenuFlow.LAUNCH_TIME.
const LAUNCH_TIME := 3.2

## Config de la sala actual. La arma el host y viaja a todos en cada sync.
var room_config: Dictionary = {
	"name": "SALA",
	"uuid": "",
	"max_players": MAX_PLAYERS,
	"round_duration": 300.0,
}

## id de peer -> { "name": String, "ready": bool, "app": { rol(int): Dictionary } }
var roster: Dictionary = {}

var discovery: RoomDiscovery


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	discovery = RoomDiscovery.new()
	discovery.name = "RoomDiscovery"
	add_child(discovery)
	discovery.rooms_found.connect(func(rooms): rooms_found.emit(rooms))


# ------------------------------------------------------------------ salas

## `config` acepta name / max_players / round_duration. El uuid lo generamos
## acá: es lo único que garantiza que dos salas homónimas sean distinguibles.
func create_room(config: Dictionary = {}) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var max_players: int = clampi(int(config.get("max_players", MAX_PLAYERS)), 2, MAX_PLAYERS)
	var err := peer.create_server(PORT, max_players)
	if err != OK:
		push_error("create_room error: %s" % err)
		return false

	multiplayer.multiplayer_peer = peer
	room_config = {
		"name": str(config.get("name", "SALA")).strip_edges(),
		"uuid": RoomDiscovery.make_uuid(),
		"max_players": max_players,
		"round_duration": clampf(float(config.get("round_duration", 300.0)), 60.0, 1800.0),
	}
	if room_config["name"].is_empty():
		room_config["name"] = "SALA DE %s" % PlayerProfile.player_name

	roster.clear()
	roster[1] = _local_entry()
	discovery.start_advertising(_room_advert())

	server_created.emit()
	roster_updated.emit()
	return true


## Se une a una sala descubierta. `room` es una ficha de RoomDiscovery.
func join_room(room: Dictionary) -> void:
	var address := str(room.get("ip", "127.0.0.1"))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("join_room error: %s" % err)
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	# Provisorio hasta que llegue el primer sync del host: sirve para que la
	# sala de espera muestre el nombre correcto desde el primer cuadro.
	room_config["name"] = str(room.get("name", "SALA"))
	room_config["uuid"] = str(room.get("uuid", ""))


func find_rooms() -> void:
	discovery.scan()


func leave_room() -> void:
	discovery.stop_advertising()
	if is_connected_to_room():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	roster.clear()
	roster_updated.emit()


## OJO: `multiplayer.multiplayer_peer` NO sirve para esto. Desde Godot 4.4 la
## MultiplayerAPI arranca con un OfflineMultiplayerPeer puesto, así que la
## comparación contra null da true SIEMPRE y el menú creía estar en una sala
## apenas abrías el juego (arrancaba en la sala de espera en vez del título).
func is_connected_to_room() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func _local_entry() -> Dictionary:
	return {
		"name": PlayerProfile.player_name,
		"ready": false,
		"app": PlayerProfile.appearance_dicts(),
	}


func _room_advert() -> Dictionary:
	return {
		"name": room_config["name"],
		"uuid": room_config["uuid"],
		"players": roster.size(),
		"max": room_config["max_players"],
		"duration": room_config["round_duration"],
	}


# ----------------------------------------------------------------- roster

## El cliente se presenta apenas la conexión está viva. El host no puede
## adivinar nombre ni apariencia: solo el cliente los tiene.
@rpc("any_peer", "reliable")
func _register_player(pname: String, apps: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	# Re-registrarse (pasa al volver del menú de apariencia) NO tiene que
	# borrar el "listo" que el jugador ya había confirmado.
	var was_ready: bool = bool((roster.get(id, {}) as Dictionary).get("ready", false))
	roster[id] = {
		"name": pname.substr(0, 20),
		"ready": was_ready,
		# Las claves de rol vuelven del RPC como int igual, pero normalizamos
		# por las dudas: una clave String acá pinta un muñeco gris en partida.
		"app": _normalize_apps(apps),
	}
	_sync_roster()


static func _normalize_apps(apps: Dictionary) -> Dictionary:
	var out := {}
	for k in apps.keys():
		out[int(k)] = apps[k]
	return out


func _sync_roster() -> void:
	if not multiplayer.is_server():
		return
	discovery.update_advertised(_room_advert())
	_rpc_sync_roster.rpc(roster, room_config)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_roster(new_roster: Dictionary, config: Dictionary) -> void:
	var fixed := {}
	for k in new_roster.keys():
		var entry: Dictionary = new_roster[k]
		entry["app"] = _normalize_apps(entry.get("app", {}))
		fixed[int(k)] = entry
	roster = fixed
	room_config = config
	roster_updated.emit()


## Vuelve a publicar nombre y apariencia locales. Lo llama el menú al salir
## del vestuario. El host no puede mandarse un RPC a sí mismo (rpc_id(1) desde
## el peer 1 no ejecuta nada sin call_local), así que se escribe directo.
func update_local_profile() -> void:
	if not is_connected_to_room():
		return
	if multiplayer.is_server():
		var was_ready: bool = bool((roster.get(1, {}) as Dictionary).get("ready", false))
		var entry := _local_entry()
		entry["ready"] = was_ready
		roster[1] = entry
		_sync_roster()
	else:
		_register_player.rpc_id(1, PlayerProfile.player_name, PlayerProfile.appearance_dicts())


func set_ready(value: bool) -> void:
	if not is_connected_to_room():
		return
	_request_ready.rpc_id(1, value)


@rpc("any_peer", "call_local", "reliable")
func _request_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not roster.has(id):
		return
	roster[id]["ready"] = value
	_sync_roster()


func is_ready(id: int) -> bool:
	return bool((roster.get(id, {}) as Dictionary).get("ready", false))


func player_name_of(id: int) -> String:
	return str((roster.get(id, {}) as Dictionary).get("name", "JUGADOR %d" % id))


## Orden estable del roster. Sin esto, cada peer dibujaría a los muñecos de
## afuera del boliche en un orden distinto (Dictionary no garantiza orden
## entre máquinas) y "el jugador 2" sería otro en cada pantalla.
func sorted_ids() -> Array:
	var ids: Array = roster.keys()
	ids.sort()
	return ids


func all_ready() -> bool:
	if roster.size() < 2:
		return false
	for id in roster.keys():
		if not roster[id].get("ready", false):
			return false
	return true


# --------------------------------------------------------------- arranque

## Solo el host. Dispara la animación de entrada en TODOS los peers y recién
## después manda a todos a la escena de juego: si cambiáramos de escena en el
## acto, el jugador nunca vería la animación que acaba de disparar.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	if not all_ready():
		push_warning("Faltan jugadores listos.")
		return

	_rpc_launch.rpc()

	await get_tree().create_timer(LAUNCH_TIME).timeout
	if not multiplayer.is_server() or not is_connected_to_room():
		return

	var ids: Array = sorted_ids()
	if ids.size() < 2:
		return

	var seeker_id: int = ids[randi() % ids.size()]
	var roles: Dictionary = {}
	var appearances: Dictionary = {}
	for pid in ids:
		var role: int = GameState.Role.SEEKER if pid == seeker_id else GameState.Role.HIDER
		roles[pid] = role
		var app: Dictionary = (roster[pid] as Dictionary).get("app", {})
		appearances[pid] = app.get(role, {})

	var names: Dictionary = {}
	for pid in ids:
		names[pid] = roster[pid].get("name", "")

	_rpc_start_game.rpc(roles, randi(), appearances, names, float(room_config["round_duration"]))


@rpc("authority", "call_local", "reliable")
func _rpc_launch() -> void:
	launch_sequence_started.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_start_game(roles: Dictionary, map_seed: int, appearances: Dictionary,
		names: Dictionary, duration: float) -> void:
	GameState.reset()
	GameState.player_roles = roles
	GameState.player_appearances = appearances
	GameState.player_names = names
	GameState.init_rat_states()
	GameState.map_seed = map_seed
	GameState.round_duration = duration
	GameState.round_time_left = duration
	GameState.round_active = true
	game_started.emit()
	get_tree().change_scene_to_file(GAME_SCENE)


## Solo el host: termina la ronda y manda a todos de vuelta a la sala de
## espera. winner: "hiders" o "seeker".
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

	# Volver de una ronda no te deja "listo" para la siguiente: si no, el host
	# podría relanzar sin que nadie haya confirmado.
	if multiplayer.is_server():
		for id in roster.keys():
			roster[id]["ready"] = false
		call_deferred("_sync_roster")

	get_tree().change_scene_to_file(MENU_SCENE)


func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			return ip
	return "127.0.0.1"


# --------------------------------------------------------------- callbacks

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)
	if multiplayer.is_server():
		roster.erase(id)
		_sync_roster()


func _on_connection_failed() -> void:
	leave_room()
	connection_failed.emit()


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, PlayerProfile.player_name, PlayerProfile.appearance_dicts())
	connected_to_server.emit()


func _on_server_disconnected() -> void:
	leave_room()
	server_disconnected.emit()
