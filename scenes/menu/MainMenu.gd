extends Control

@onready var panel_main: Control = $PanelMain
@onready var panel_play: Control = $PanelPlay
@onready var panel_join: Control = $PanelJoin
@onready var status_label: Label = $StatusLabel

@onready var btn_play: Button = $PanelMain/VBox/BtnPlay
@onready var btn_quit: Button = $PanelMain/VBox/BtnQuit

@onready var btn_create: Button = $PanelPlay/VBox/BtnCreate
@onready var btn_join: Button = $PanelPlay/VBox/BtnJoin
@onready var btn_back_play: Button = $PanelPlay/VBox/BtnBack

@onready var line_room_code: LineEdit = $PanelJoin/VBox/RoomCodeInput
@onready var btn_connect: Button = $PanelJoin/VBox/BtnConnect
@onready var btn_back_join: Button = $PanelJoin/VBox/BtnBack

@onready var btn_start: Button = $BtnStart


func _ready() -> void:
	_show_only(panel_main)

	if not GameState.last_result.is_empty():
		status_label.text = "GANARON LOS HIDERS" if GameState.last_result == "hiders" else "GANÓ EL SEEKER"
		GameState.last_result = ""
	else:
		status_label.text = ""

	btn_play.pressed.connect(func(): _show_only(panel_play))
	btn_quit.pressed.connect(func(): get_tree().quit())

	btn_create.pressed.connect(_on_create_pressed)
	btn_join.pressed.connect(func(): _show_only(panel_join))
	btn_back_play.pressed.connect(func(): _show_only(panel_main))

	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back_join.pressed.connect(func(): _show_only(panel_play))

	btn_start.pressed.connect(func(): NetworkManager.start_game())

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)


func _show_only(panel: Control) -> void:
	status_label.text = ""
	for p in [panel_main, panel_play, panel_join]:
		p.visible = (p == panel)


func _on_create_pressed() -> void:
	var ok := NetworkManager.create_room()
	if not ok:
		status_label.text = "No se pudo crear la sala."


func _on_connect_pressed() -> void:
	var address := line_room_code.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "Conectando a %s..." % address
	NetworkManager.join_room(address)


func _on_connection_failed() -> void:
	status_label.text = "No se pudo conectar a la sala."


func _on_server_created() -> void:
	status_label.text = "Sala creada. Código: %s" % NetworkManager.get_local_ip()
	_update_start_button()


func _on_player_connected(_id: int) -> void:
	status_label.text = "Jugador conectado."
	_update_start_button()


func _on_player_disconnected(_id: int) -> void:
	status_label.text = "Jugador desconectado."
	_update_start_button()


## El botón de iniciar solo lo ve el host, y solo cuando hay al menos
## otro jugador conectado (multiplayer.get_peers() no incluye al host mismo).
func _update_start_button() -> void:
	var is_host := multiplayer.multiplayer_peer != null and multiplayer.is_server()
	var enough_players := multiplayer.get_peers().size() >= 1
	btn_start.visible = is_host and enough_players
