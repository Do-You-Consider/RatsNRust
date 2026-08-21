class_name RoomDiscovery
extends Node
## Descubrimiento de salas en la red local por UDP.
##
## El jugador NUNCA ve una IP: busca por NOMBRE DE SALA. La IP existe pero es
## un detalle de transporte que se resuelve solo.
##
## Cómo funciona:
##   1. El cliente manda un datagrama de pregunta a broadcast (y a loopback,
##      para poder probar dos instancias en la misma máquina).
##   2. Cada host con una sala abierta contesta con su ficha: nombre, uuid,
##      jugadores, cupo, duración de ronda.
##   3. El cliente arma la lista. El ping sale de comparar el timestamp que
##      mandó él mismo y que el host devuelve tal cual -- así se mide RTT real
##      sin que los relojes de las dos máquinas tengan que estar en hora.
##
## El UUID es lo que desempata dos salas que se llamen igual: los nombres los
## escribe el jugador y nada impide dos "SALA 1" en la misma red.

signal rooms_found(rooms: Array)

const DISCOVERY_PORT := 7778
const QUERY := "RNR_Q"
const ANSWER := "RNR_A"
const SCAN_TIME := 1.4      # segundos que esperamos respuestas
const MAX_PACKET := 1024

## Ficha que publica este peer si es host. La setea NetworkManager.
var advertised: Dictionary = {}

var _host_socket: PacketPeerUDP = null
var _scan_socket: PacketPeerUDP = null
var _scan_time_left: float = 0.0
var _found: Dictionary = {}   # uuid -> ficha


static func make_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in 8:
		s += "%04x" % rng.randi_range(0, 0xFFFF)
	return s


## Forma corta para mostrar al lado del nombre de la sala.
static func short_uuid(uuid: String) -> String:
	return uuid.substr(0, 6).to_upper()


func _process(delta: float) -> void:
	_poll_host()
	_poll_scan(delta)


# ------------------------------------------------------------------- host

## Empieza a contestar preguntas. `info` = { name, uuid, players, max, duration }.
func start_advertising(info: Dictionary) -> void:
	advertised = info
	if _host_socket != null:
		return
	_host_socket = PacketPeerUDP.new()
	var err := _host_socket.bind(DISCOVERY_PORT, "*")
	if err != OK:
		push_warning("RoomDiscovery: no se pudo abrir el puerto %d (%s). La sala no va a aparecer en la lista." % [DISCOVERY_PORT, err])
		_host_socket = null


func update_advertised(info: Dictionary) -> void:
	if _host_socket != null:
		advertised = info


func stop_advertising() -> void:
	advertised = {}
	if _host_socket != null:
		_host_socket.close()
		_host_socket = null


func _poll_host() -> void:
	if _host_socket == null:
		return
	while _host_socket.get_available_packet_count() > 0:
		var raw := _host_socket.get_packet().get_string_from_utf8()
		var from_ip := _host_socket.get_packet_ip()
		var from_port := _host_socket.get_packet_port()
		var msg = JSON.parse_string(raw)
		if typeof(msg) != TYPE_DICTIONARY or msg.get("k", "") != QUERY:
			continue
		if advertised.is_empty():
			continue

		var reply := advertised.duplicate()
		reply["k"] = ANSWER
		# Devolvemos el timestamp del cliente sin tocarlo: el RTT lo calcula él.
		reply["t"] = msg.get("t", 0)
		_host_socket.set_dest_address(from_ip, from_port)
		_host_socket.put_packet(JSON.stringify(reply).to_utf8_buffer())


# --------------------------------------------------------------- búsqueda

func is_scanning() -> bool:
	return _scan_time_left > 0.0


func scan() -> void:
	_close_scan()
	_found.clear()

	_scan_socket = PacketPeerUDP.new()
	_scan_socket.set_broadcast_enabled(true)
	# Puerto 0 = el sistema elige uno libre. Hay que bindear igual: si no, el
	# socket no tiene dónde recibir las respuestas.
	if _scan_socket.bind(0, "*") != OK:
		push_warning("RoomDiscovery: no se pudo abrir socket de búsqueda.")
		_scan_socket = null
		rooms_found.emit([])
		return

	var payload := JSON.stringify({"k": QUERY, "t": Time.get_ticks_msec()}).to_utf8_buffer()
	# Broadcast para la LAN + loopback explícito, que es lo que permite probar
	# host y cliente en la misma PC (Windows no siempre devuelve el broadcast
	# a la propia máquina).
	for target in ["255.255.255.255", "127.0.0.1"]:
		_scan_socket.set_dest_address(target, DISCOVERY_PORT)
		_scan_socket.put_packet(payload)

	_scan_time_left = SCAN_TIME


func _poll_scan(delta: float) -> void:
	if _scan_socket == null:
		return

	while _scan_socket.get_available_packet_count() > 0:
		var raw := _scan_socket.get_packet().get_string_from_utf8()
		var ip := _scan_socket.get_packet_ip()
		var msg = JSON.parse_string(raw)
		if typeof(msg) != TYPE_DICTIONARY or msg.get("k", "") != ANSWER:
			continue

		var uuid := str(msg.get("uuid", ""))
		if uuid.is_empty():
			continue
		_found[uuid] = {
			"name": str(msg.get("name", "SALA")),
			"uuid": uuid,
			"short": short_uuid(uuid),
			"players": int(msg.get("players", 1)),
			"max": int(msg.get("max", 8)),
			"duration": float(msg.get("duration", 300.0)),
			"ip": ip,
			"ping": maxi(0, Time.get_ticks_msec() - int(msg.get("t", 0))),
		}

	_scan_time_left -= delta
	if _scan_time_left <= 0.0:
		var rooms: Array = _found.values()
		rooms.sort_custom(func(a, b): return a["ping"] < b["ping"])
		_close_scan()
		rooms_found.emit(rooms)


func _close_scan() -> void:
	_scan_time_left = 0.0
	if _scan_socket != null:
		_scan_socket.close()
		_scan_socket = null


func _exit_tree() -> void:
	stop_advertising()
	_close_scan()
