extends Control

@onready var panel_main: Control = $CenterArea/MainFrame/Margin/VBox/PanelMain
@onready var panel_play: Control = $CenterArea/MainFrame/Margin/VBox/PanelPlay
@onready var panel_join: Control = $CenterArea/MainFrame/Margin/VBox/PanelJoin
@onready var lobby_box: Control = $CenterArea/MainFrame/Margin/VBox/LobbyBox
@onready var lobby_label: Label = $CenterArea/MainFrame/Margin/VBox/LobbyBox/LobbyLabel
@onready var status_label: Label = $StatusLabel
@onready var result_banner: PanelContainer = $CenterArea/MainFrame/Margin/VBox/ResultBanner
@onready var result_label: Label = $CenterArea/MainFrame/Margin/VBox/ResultBanner/ResultLabel

@onready var btn_play: Button = $CenterArea/MainFrame/Margin/VBox/PanelMain/BtnPlay
@onready var btn_quit: Button = $CenterArea/MainFrame/Margin/VBox/PanelMain/BtnQuit

@onready var btn_create: Button = $CenterArea/MainFrame/Margin/VBox/PanelPlay/BtnCreate
@onready var btn_join: Button = $CenterArea/MainFrame/Margin/VBox/PanelPlay/BtnJoin
@onready var btn_back_play: Button = $CenterArea/MainFrame/Margin/VBox/PanelPlay/BtnBackPlay

@onready var line_room_code: LineEdit = $CenterArea/MainFrame/Margin/VBox/PanelJoin/InputBox/RoomCodeInput
@onready var btn_connect: Button = $CenterArea/MainFrame/Margin/VBox/PanelJoin/BtnConnect
@onready var btn_back_join: Button = $CenterArea/MainFrame/Margin/VBox/PanelJoin/BtnBackJoin

@onready var btn_start: Button = $CenterArea/MainFrame/Margin/VBox/BtnStart
@onready var header_signal: Label = $TopHeader/SignalLabel

var _time_passed: float = 0.0
var _original_btn_texts: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_button_effects()
	_show_only(panel_main)
	lobby_box.visible = false
	btn_start.visible = false

	if not GameState.last_result.is_empty():
		result_banner.visible = true
		if GameState.last_result == "hiders":
			result_label.text = ">>> LAS RATAS AGUANTARON Y SE LLEVARON EL POZO <<<"
			result_label.modulate = Color(0.4, 0.9, 0.5)
		else:
			result_label.text = ">>> EL COBRADOR LIQUIDÓ A TODAS LAS RATAS <<<"
			result_label.modulate = Color(1.0, 0.25, 0.2)
		GameState.last_result = ""
	else:
		result_banner.visible = false

	btn_play.pressed.connect(func(): _show_only(panel_play))
	btn_quit.pressed.connect(func(): get_tree().quit())

	btn_create.pressed.connect(_on_create_pressed)
	btn_join.pressed.connect(func(): _show_only(panel_join))
	btn_back_play.pressed.connect(func(): _show_only(panel_main))

	btn_connect.pressed.connect(_on_connect_pressed)
	btn_back_join.pressed.connect(func(): _show_only(panel_play))

	btn_start.pressed.connect(_on_start_pressed)

	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)


func _process(delta: float) -> void:
	_time_passed += delta
	if int(_time_passed * 2.0) % 2 == 0:
		header_signal.text = "[ * EN LÍNEA ]"
		header_signal.modulate = Color(0.85, 0.45, 0.15)
	else:
		header_signal.text = "[ o EN LÍNEA ]"
		header_signal.modulate = Color(0.5, 0.3, 0.15)


func _show_only(panel: Control) -> void:
	status_label.text = "// LISTO // SELECCIONÁ UNA OPCIÓN"
	for p in [panel_main, panel_play, panel_join]:
		if p != null:
			p.visible = (p == panel)
	if panel != null:
		lobby_box.visible = false
		btn_start.visible = false


func _on_create_pressed() -> void:
	var ok := NetworkManager.create_room()
	if ok:
		_show_only(null)
		lobby_box.visible = true
		_update_lobby_ui()
	else:
		status_label.text = "[ ERROR: NO SE PUDO ABRIR EL PUERTO 7777 ]"


func _on_connect_pressed() -> void:
	var address := line_room_code.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "[ CONECTANDO A %s... ]" % address
	NetworkManager.join_room(address)


func _on_connection_failed() -> void:
	status_label.text = "[ ERROR: NO SE PUDO CONECTAR AL HOST ]"


func _on_server_created() -> void:
	status_label.text = "[ SALA CREADA // ESPERANDO JUGADORES ]"
	_update_lobby_ui()


func _on_player_connected(_id: int) -> void:
	status_label.text = "[ NUEVO JUGADOR CONECTADO ]"
	_play_sfx(440.0, 0.04, -22.0)
	_update_lobby_ui()


func _on_player_disconnected(_id: int) -> void:
	status_label.text = "[ JUGADOR DESCONECTADO ]"
	_update_lobby_ui()


func _on_start_pressed() -> void:
	_play_sfx(120.0, 0.08, -18.0)
	status_label.text = "[ INICIANDO PARTIDA... ]"
	NetworkManager.start_game()


func _update_lobby_ui() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	var is_host := multiplayer.is_server()
	var count := multiplayer.get_peers().size() + 1
	var ip := NetworkManager.get_local_ip() if is_host else "CONECTADO"

	lobby_label.text = "IP DEL HOST: %s\nJUGADORES EN SALA: [ %d / %d ]\nESTADO: %s" % [
		ip,
		count,
		NetworkManager.MAX_PLAYERS,
		"SALA LISTA // LISTO PARA EMPEZAR" if count >= 2 else "ESPERANDO JUGADORES (MÍNIMO 2)"
	]

	btn_start.visible = is_host and (count >= 2)


func _setup_button_effects() -> void:
	var buttons := [btn_play, btn_quit, btn_create, btn_join, btn_back_play, btn_connect, btn_back_join, btn_start]
	for btn in buttons:
		if btn == null:
			continue
		_original_btn_texts[btn] = btn.text
		btn.mouse_entered.connect(_on_btn_mouse_entered.bind(btn))
		btn.mouse_exited.connect(_on_btn_mouse_exited.bind(btn))
		btn.pressed.connect(_on_btn_pressed.bind(btn))


var _last_sfx_time: float = 0.0


func _on_btn_mouse_entered(btn: Button) -> void:
	_play_sfx(320.0, 0.02, -26.0)
	var orig: String = _original_btn_texts.get(btn, btn.text)
	btn.text = "> %s <" % orig


func _on_btn_mouse_exited(btn: Button) -> void:
	var orig: String = _original_btn_texts.get(btn, btn.text)
	btn.text = orig


func _on_btn_pressed(_btn: Button) -> void:
	_play_sfx(140.0, 0.04, -20.0)


## Generador de sonido suave y atenuado (16-bit PCM, frecuencias cálidas y volumen bajo)
func _play_sfx(freq: float, duration: float, volume_db_gain: float = -24.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_sfx_time < 0.05:
		return # Evita acumulación de sonidos si se mueve rápido el cursor
	_last_sfx_time = now

	var sample_rate := 22050
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var phase := 0.0
	var phase_step := (freq * TAU) / float(sample_rate)

	for i in num_samples:
		var t: float = float(i) / float(num_samples)
		var attack: float = minf(1.0, float(i) / 15.0)
		var decay: float = pow(1.0 - t, 4.5)
		var sample: float = sin(phase) * attack * decay * 0.3
		var int16_val: int = int(clampf(sample, -1.0, 1.0) * 32767.0)

		var idx: int = i * 2
		data[idx] = int16_val & 0xFF
		data[idx + 1] = (int16_val >> 8) & 0xFF
		phase += phase_step

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data

	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = volume_db_gain
	player.autoplay = true
	player.finished.connect(player.queue_free)
	add_child(player)
