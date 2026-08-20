extends Control

@onready var panel_main: Control = $CenterArea/MainCard/Margin/VBox/PanelMain
@onready var panel_play: Control = $CenterArea/MainCard/Margin/VBox/PanelPlay
@onready var panel_join: Control = $CenterArea/MainCard/Margin/VBox/PanelJoin
@onready var panel_lobby: Control = $CenterArea/MainCard/Margin/VBox/PanelLobby
@onready var lobby_box: Control = $CenterArea/MainCard/Margin/VBox/PanelLobby/LobbyBox
@onready var lobby_label: Label = $CenterArea/MainCard/Margin/VBox/PanelLobby/LobbyBox/LobbyLabel
@onready var status_label: Label = $StatusLabel
@onready var result_banner: PanelContainer = $CenterArea/MainCard/Margin/VBox/ResultBanner
@onready var result_label: Label = $CenterArea/MainCard/Margin/VBox/ResultBanner/ResultLabel

@onready var btn_play: Button = $CenterArea/MainCard/Margin/VBox/PanelMain/BtnPlay
@onready var btn_quit: Button = $CenterArea/MainCard/Margin/VBox/PanelMain/BtnQuit

@onready var btn_create: Button = $CenterArea/MainCard/Margin/VBox/PanelPlay/BtnCreate
@onready var btn_join: Button = $CenterArea/MainCard/Margin/VBox/PanelPlay/BtnJoin
@onready var btn_back_play: Button = $CenterArea/MainCard/Margin/VBox/PanelPlay/BtnBackPlay

@onready var line_room_code: LineEdit = $CenterArea/MainCard/Margin/VBox/PanelJoin/InputBox/RoomCodeInput
@onready var btn_connect: Button = $CenterArea/MainCard/Margin/VBox/PanelJoin/BtnConnect
@onready var btn_back_join: Button = $CenterArea/MainCard/Margin/VBox/PanelJoin/BtnBackJoin

@onready var btn_start: Button = $CenterArea/MainCard/Margin/VBox/PanelLobby/BtnStart
@onready var btn_leave_lobby: Button = $CenterArea/MainCard/Margin/VBox/PanelLobby/BtnLeaveLobby
@onready var header_signal: Label = $TopNotice/SignalLabel

var _time_passed: float = 0.0
var _original_btn_texts: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_button_effects()

	if not GameState.last_result.is_empty():
		result_banner.visible = true
		if GameState.last_result == "hiders":
			result_label.text = "[ LAS RATAS HAN SOBREVIVIDO ]"
			result_label.modulate = Color(0.4, 0.9, 0.55)
		else:
			result_label.text = "[ EL ATRAPADOR HA LIQUIDADO A TODOS ]"
			result_label.modulate = Color(1.0, 0.3, 0.25)
		GameState.last_result = ""
	else:
		result_banner.visible = false

	# Si venimos de una ronda que acaba de terminar, la conexión con los
	# demás jugadores sigue viva (nunca se cortó) -- hay que mostrar la sala
	# de espera, no el menú principal, o el host terminaría intentando abrir
	# un servidor nuevo estando ya conectado a uno.
	if multiplayer.multiplayer_peer != null:
		_show_only(panel_lobby)
		_update_lobby_ui()
	else:
		_show_only(panel_main)

	btn_play.pressed.connect(func(): _show_only(panel_play))
	btn_quit.pressed.connect(func(): get_tree().quit())

	btn_create.pressed.connect(_on_create_pressed)
	btn_join.pressed.connect(func(): _show_only(panel_join))
	btn_back_play.pressed.connect(func(): _show_only(panel_main))

	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back_join.pressed.connect(func(): _show_only(panel_play))

	btn_start.pressed.connect(_on_start_pressed)
	btn_leave_lobby.pressed.connect(_on_leave_lobby_pressed)

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.lobby_synced.connect(_on_lobby_synced)


func _process(delta: float) -> void:
	_time_passed += delta
	if int(_time_passed * 2.0) % 2 == 0:
		header_signal.text = "[ RED ACTIVA ]"
		header_signal.modulate = Color(0.85, 0.55, 0.2)
	else:
		header_signal.text = "[ RED ACTIVA ]"
		header_signal.modulate = Color(0.5, 0.35, 0.18)


func _show_only(panel: Control) -> void:
	status_label.text = "SELECCIONA UNA OPCION"
	for p in [panel_main, panel_play, panel_join, panel_lobby]:
		if p != null:
			p.visible = (p == panel)


func _on_create_pressed() -> void:
	var ok := NetworkManager.create_room()
	if ok:
		_show_only(panel_lobby)
		_update_lobby_ui()
		status_label.text = "[ SALA CREADA // ESPERANDO RIVALES ]"
	else:
		status_label.text = "[ ERROR AL CREAR SALA: PUERTO EN USO ]"


func _on_connect_pressed() -> void:
	var address := line_room_code.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "[ CONECTANDO A %s... ]" % address
	NetworkManager.join_room(address)


func _on_connected_to_server() -> void:
	_show_only(panel_lobby)
	_update_lobby_ui()
	status_label.text = "[ CONECTADO A LA SALA // ESPERANDO AL HOST ]"


func _on_connection_failed() -> void:
	_show_only(panel_join)
	status_label.text = "[ ERROR: NO SE PUDO CONECTAR AL HOST ]"


func _on_server_created() -> void:
	_show_only(panel_lobby)
	_update_lobby_ui()


func _on_server_disconnected() -> void:
	_show_only(panel_main)
	status_label.text = "[ EL HOST HA CERRADO LA SALA ]"


func _on_leave_lobby_pressed() -> void:
	NetworkManager.leave_room()
	_show_only(panel_main)
	status_label.text = "SALISTE DE LA SALA"


func _on_player_connected(_id: int) -> void:
	status_label.text = "[ JUGADOR EN SALA ]"
	_update_lobby_ui()


func _on_player_disconnected(_id: int) -> void:
	status_label.text = "[ JUGADOR DESCONECTADO ]"
	_update_lobby_ui()


func _on_lobby_synced(_count: int, _host_ip: String) -> void:
	_update_lobby_ui()


func _on_start_pressed() -> void:
	status_label.text = "[ INICIANDO PARTIDA... ]"
	NetworkManager.start_game()


func _update_lobby_ui() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	var is_host := multiplayer.is_server()
	var count := NetworkManager.lobby_player_count
	var ip := NetworkManager.lobby_host_ip

	var status_str := ""
	if is_host:
		status_str = "SALA LISTA // LISTO PARA EMPEZAR" if count >= 2 else "ESPERANDO RIVALES (MINIMO 2)"
	else:
		status_str = "CONECTADO // ESPERANDO QUE EL HOST INICIE..."

	lobby_label.text = "IP HOST: %s\nJUGADORES: [ %d / %d ]\nESTADO: %s" % [
		ip,
		count,
		NetworkManager.MAX_PLAYERS,
		status_str
	]

	btn_start.visible = is_host and (count >= 2)


func _setup_button_effects() -> void:
	var buttons := [btn_play, btn_quit, btn_create, btn_join, btn_back_play, btn_connect, btn_back_join, btn_start, btn_leave_lobby]
	for btn in buttons:
		if btn == null:
			continue
		_original_btn_texts[btn] = btn.text
		btn.mouse_entered.connect(_on_btn_mouse_entered.bind(btn))
		btn.mouse_exited.connect(_on_btn_mouse_exited.bind(btn))


func _on_btn_mouse_entered(btn: Button) -> void:
	var orig: String = _original_btn_texts.get(btn, btn.text)
	btn.text = "> %s <" % orig


func _on_btn_mouse_exited(btn: Button) -> void:
	var orig: String = _original_btn_texts.get(btn, btn.text)
	btn.text = orig
