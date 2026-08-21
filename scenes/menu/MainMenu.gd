extends Node3D
## Menú del juego. Dejó de ser un Control con paneles: ahora es una escena 3D
## con escenografía real, un actor animado y una cámara dirigida, y la UI
## flota encima.
##
## RECORRIDO
##   TÍTULO      balcón, el Atrapador mirando la pista desde arriba
##     |  (camina hasta la puerta de la izquierda y la abre)
##   SALAS       sala de cámaras, muro de monitores
##     |  modales de crear / unirse
##   SALA        exterior del boliche visto por la cámara de seguridad;
##               cada jugador que entra aparece afuera, cerca de la puerta
##     |
##   APARIENCIA  vestuario con plataforma giratoria
##     |
##   ARRANQUE    todos caminan hacia la entrada y se corta a la partida
##
## Las transiciones son SIEMPRE completas: no se pueden saltear. Es una
## decisión de dirección, no un olvido -- por eso _busy bloquea la UI durante
## toda la secuencia en vez de dejar botones a medio camino.
##
## Todo (sets, cámara, actores y UI) se construye por código, igual que el
## mapa y los personajes. La .tscn tiene un solo nodo.

enum State { TITLE, ROOMS, LOBBY, APPEARANCE, LAUNCH }

## Duración total de la secuencia de entrada al boliche. Tiene que coincidir
## con NetworkManager.LAUNCH_TIME o el host cambiaría de escena antes de que
## los clientes terminen de ver la animación.
const LAUNCH_TIME := 3.2

const WALK_SPEED := 2.2
const FADE_TIME := 0.35

const CRT_SHADER := preload("res://scripts/shaders/crt_terminal.gdshader")
const CAM_SHADER := preload("res://scripts/shaders/security_cam.gdshader")

var state: int = State.TITLE
var _busy: bool = false

var _set_holder: Node3D
var _current_set: Node3D
var _cam: MenuCameraDirector

var _hero: MenuActor                  # el Atrapador de las pantallas 1, 2 y 4
var _lobby_actors: Dictionary = {}    # peer id -> MenuActor

var _appearance_role: int = GameState.Role.HIDER
var _selected_slot: int = CosmeticCatalog.Slot.HEAD
var _dragging: bool = false

var _pending_rooms: Array = []
var _selected_room: Dictionary = {}

# --- UI -----------------------------------------------------------------
var _ui: CanvasLayer
var _menu_fx: ColorRect
var _cam_fx: ColorRect
var _osd: Control
var _osd_time: Label
var _osd_rec: Label
var _fade: ColorRect
var _status: Label
var _screens: Dictionary = {}         # State/modal -> Control
var _lobby_list: VBoxContainer
var _lobby_title: Label
var _room_rows: VBoxContainer
var _btn_ready: Button
var _btn_start: Button
var _btn_join_confirm: Button
var _create_fields: Dictionary = {}
var _appearance_items: VBoxContainer
var _appearance_hint: Label
var _slot_buttons: Dictionary = {}
var _result_banner: PanelContainer
var _result_label: Label
var _osd_t: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_set_holder = Node3D.new()
	_set_holder.name = "SetHolder"
	add_child(_set_holder)

	_cam = MenuCameraDirector.new()
	_cam.name = "CameraRig"
	add_child(_cam)

	_build_ui()

	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.roster_updated.connect(_on_roster_updated)
	NetworkManager.rooms_found.connect(_on_rooms_found)
	NetworkManager.launch_sequence_started.connect(_on_launch_sequence_started)

	# Volver de una ronda NO corta la conexión: si seguimos en una sala hay que
	# aterrizar en la sala de espera, no en el título (el host abriría un
	# servidor nuevo estando ya conectado a uno).
	if NetworkManager.is_connected_to_room():
		await _enter_lobby()
	else:
		await _enter_title()
	_show_result_banner()


func _process(delta: float) -> void:
	_osd_t += delta
	if _osd.visible:
		_osd_time.text = Time.get_time_string_from_system()
		_osd_rec.modulate.a = 1.0 if fmod(_osd_t, 1.6) < 0.9 else 0.15


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return

	# Arrastre para girar el personaje en el vestuario.
	if state != State.APPEARANCE or _hero == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_hero.rotation.y -= event.relative.x * 0.012


# =============================================================================
# SETS
# =============================================================================

func _swap_set(new_set: Node3D) -> void:
	if _current_set != null:
		# Liberar de inmediato, no en diferido: el set anterior tiene su propio
		# WorldEnvironment, y dos WorldEnvironment vivos a la vez hacen que el
		# ambiente que gana sea impredecible.
		_set_holder.remove_child(_current_set)
		_current_set.queue_free()
	_current_set = new_set
	_set_holder.add_child(new_set)
	_hero = null
	_lobby_actors.clear()


func _shots() -> Dictionary:
	return _current_set.get_meta("shots", {})


func _spawn_hero(role: int, at: Transform3D, pose: String) -> MenuActor:
	var actor := MenuActor.create(role, PlayerProfile.get_appearance(role))
	_current_set.add_child(actor)
	actor.transform = at
	actor.set_pose(pose)
	return actor


# =============================================================================
# PANTALLA 1: TÍTULO
# =============================================================================

func _enter_title(fade: bool = true) -> void:
	state = State.TITLE
	_swap_set(MenuSets.build_balcony())
	_cam.set_shake(1.0)
	_cam.drift(_shots()["main"], 0.55, 9.0)
	_hero = _spawn_hero(GameState.Role.SEEKER, _current_set.get_meta("actor"), "lean_rail")

	_set_fx(false)
	_show_screen(State.TITLE)
	_status.text = "SELECCIONÁ UNA OPCIÓN"
	if fade:
		await _fade_in()


## Transición título -> sala de cámaras. Camina hasta la puerta de la
## izquierda, la abre y entra. No se puede saltear.
func _play_enter_door() -> void:
	_set_busy(true)
	_hide_screens()

	var shots := _shots()
	var path: Array = _current_set.get_meta("path")
	var hinge := _current_set.get_node_or_null("DoorHinge") as Node3D

	_cam.move_to(shots["door"], 1.1)
	_hero.set_pose("wait_a")

	# Primero el recorrido hasta ANTES del vano: el último punto lo cruza
	# recién con la puerta abierta, o se lo vería frenar contra una hoja
	# cerrada durante un cuadro.
	await _hero.walk_along(path.slice(0, path.size() - 1), WALK_SPEED)
	if not is_inside_tree():
		return

	_hero.play_once("open_door")
	if hinge != null:
		var t := create_tween()
		t.tween_property(hinge, "rotation:y", -1.35, 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cam.move_to(shots["through"], 1.5)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return

	await _hero.walk_along([path[path.size() - 2], path[path.size() - 1]], WALK_SPEED)
	if not is_inside_tree():
		return

	await _fade_out()
	await _enter_rooms(true)
	_set_busy(false)


# =============================================================================
# PANTALLA 2: SALA DE CÁMARAS
# =============================================================================

func _enter_rooms(animate_in: bool) -> void:
	state = State.ROOMS
	_swap_set(MenuSets.build_control_room())
	_cam.set_shake(1.0)

	var shots := _shots()
	_hero = _spawn_hero(GameState.Role.SEEKER, _current_set.get_meta("actor"), "watch_monitors")

	_set_fx(false)
	if animate_in:
		_cam.snap(shots["entry"])
		await _fade_in()
		_cam.move_to(shots["main"], 1.6)
		await get_tree().create_timer(1.6).timeout
	else:
		_cam.snap(shots["main"])
		await _fade_in()

	_cam.drift(shots["main"], 0.30, 11.0)
	_show_screen(State.ROOMS)
	_status.text = "SISTEMA DE CÁMARAS EN LÍNEA"
	_start_pointing_loop()


## Cada tanto el Atrapador señala un monitor. Sin esto se queda quieto todo el
## rato que el jugador tarde en decidir, y a los 20 segundos parece colgado.
func _start_pointing_loop() -> void:
	while is_inside_tree() and state == State.ROOMS:
		await get_tree().create_timer(randf_range(7.0, 13.0)).timeout
		if not is_inside_tree():
			return
		if state == State.ROOMS and _hero != null and is_instance_valid(_hero):
			_hero.play_once("point_screen")


# =============================================================================
# PANTALLA 3: SALA DE ESPERA (exterior por cámara de seguridad)
# =============================================================================

func _enter_lobby(fade: bool = true) -> void:
	state = State.LOBBY
	_swap_set(MenuSets.build_exterior())
	_cam.set_shake(0.55)
	_cam.snap(_shots()["cam"])
	_cam.drift(_shots()["cam"], 0.35, 14.0)

	_set_fx(true)
	_sync_lobby_actors()
	_show_screen(State.LOBBY)
	_refresh_lobby()
	if fade:
		await _fade_in()


## Un muñeco por jugador del roster, en el puesto que le toca por orden de id.
## El orden tiene que ser el MISMO en todos los peers: por eso sale de
## NetworkManager.sorted_ids() y no de recorrer el Dictionary.
func _sync_lobby_actors() -> void:
	if state != State.LOBBY or _current_set == null:
		return
	var slots: Array = _current_set.get_meta("slots", [])
	var ids := NetworkManager.sorted_ids()

	for id in _lobby_actors.keys():
		if not ids.has(id):
			var gone: MenuActor = _lobby_actors[id]
			if is_instance_valid(gone):
				gone.queue_free()
			_lobby_actors.erase(id)

	for i in ids.size():
		var id: int = ids[i]
		if i >= slots.size():
			break
		if _lobby_actors.has(id):
			continue
		# Afuera del boliche todavía nadie sabe qué rol le va a tocar, así que
		# todos se muestran con su apariencia de RATA. El Atrapador es el que
		# está del otro lado de la cámara mirándolos.
		var app_dict: Dictionary = (NetworkManager.roster.get(id, {}) as Dictionary).get("app", {})
		var cfg: CharacterAppearance = CharacterAppearance.from_dict(
			app_dict.get(GameState.Role.HIDER, {}))
		if app_dict.is_empty():
			cfg = CharacterAppearance.default_for_role(GameState.Role.HIDER)

		var actor := MenuActor.create(GameState.Role.HIDER, cfg)
		_current_set.add_child(actor)
		actor.transform = slots[i]
		actor.set_pose("wait_a" if i % 2 == 0 else "wait_b")
		_lobby_actors[id] = actor


func _refresh_lobby() -> void:
	if state != State.LOBBY:
		return

	var cfg := NetworkManager.room_config
	_lobby_title.text = "SALA: %s   [%s]" % [
		str(cfg.get("name", "SALA")),
		RoomDiscovery.short_uuid(str(cfg.get("uuid", "")))]

	_clear(_lobby_list)

	var ids := NetworkManager.sorted_ids()
	for i in ids.size():
		var id: int = ids[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_lobby_list.add_child(row)

		var num := Label.new()
		num.text = "JUGADOR %d" % (i + 1)
		num.custom_minimum_size.x = 54
		num.add_theme_font_size_override("font_size", 7)
		num.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
		row.add_child(num)

		var nm := Label.new()
		nm.text = NetworkManager.player_name_of(id)
		nm.custom_minimum_size.x = 76
		nm.add_theme_font_size_override("font_size", 8)
		nm.add_theme_color_override("font_color",
			MenuTheme.TEXT_HOT if id == multiplayer.get_unique_id() else MenuTheme.TEXT)
		row.add_child(nm)

		var rd := Label.new()
		var ready := NetworkManager.is_ready(id)
		rd.text = "LISTO" if ready else "..."
		rd.add_theme_font_size_override("font_size", 7)
		rd.add_theme_color_override("font_color", MenuTheme.GOOD if ready else MenuTheme.TEXT_DIM)
		row.add_child(rd)

	var me := multiplayer.get_unique_id()
	var i_am_ready := NetworkManager.is_ready(me)
	_btn_ready.text = "CANCELAR LISTO" if i_am_ready else "LISTO"
	_btn_start.visible = multiplayer.is_server()
	_btn_start.disabled = not NetworkManager.all_ready()

	if NetworkManager.roster.size() < 2:
		_status.text = "ESPERANDO JUGADORES (MÍNIMO 2)"
	elif not NetworkManager.all_ready():
		_status.text = "ESPERANDO QUE TODOS ESTÉN LISTOS"
	elif multiplayer.is_server():
		_status.text = "TODOS LISTOS // PODÉS INICIAR"
	else:
		_status.text = "TODOS LISTOS // ESPERANDO AL HOST"


# =============================================================================
# PANTALLA 4: APARIENCIA
# =============================================================================

func _enter_appearance() -> void:
	_set_busy(true)
	await _fade_out()
	state = State.APPEARANCE
	_swap_set(MenuSets.build_studio())
	# En el vestuario la cámara es un trípode: cero temblor, o el personaje
	# nunca se queda quieto para mirarlo.
	_cam.set_shake(0.0)
	_apply_appearance_role()
	_set_fx(false)
	_show_screen(State.APPEARANCE)
	_status.text = "CATÁLOGO EN CONSTRUCCIÓN"
	await _fade_in()
	_set_busy(false)


func _apply_appearance_role() -> void:
	if state != State.APPEARANCE or _current_set == null:
		return
	if _hero != null and is_instance_valid(_hero):
		_hero.queue_free()
	_hero = _spawn_hero(_appearance_role, _current_set.get_meta("actor"), "present")
	_cam.snap(_shots()["seeker" if _appearance_role == GameState.Role.SEEKER else "rat"])
	_refresh_appearance_items()


func _refresh_appearance_items() -> void:
	_clear(_appearance_items)

	for slot in CosmeticCatalog.SLOT_ORDER:
		var b: Button = _slot_buttons[slot]
		b.modulate = Color(1, 1, 1) if slot == _selected_slot else Color(0.72, 0.70, 0.66)

	var items := CosmeticCatalog.items_for(_selected_slot, _appearance_role)
	var chosen := str(PlayerProfile.get_selection(_appearance_role).get(_selected_slot, CosmeticCatalog.NONE_ID))
	for it in items:
		var b := Button.new()
		b.theme_type_variation = "GhostButton"
		b.text = ("> %s" % it["name"]) if str(it["id"]) == chosen else str(it["name"])
		b.custom_minimum_size = Vector2(120, 15)
		b.pressed.connect(_on_item_chosen.bind(str(it["id"])))
		_appearance_items.add_child(b)

	_appearance_hint.visible = CosmeticCatalog.is_empty()


func _on_item_chosen(item_id: String) -> void:
	PlayerProfile.set_slot(_appearance_role, _selected_slot, item_id)
	if _hero != null and is_instance_valid(_hero):
		_hero.set_appearance(PlayerProfile.get_appearance(_appearance_role))
	_refresh_appearance_items()


func _on_apply_appearance() -> void:
	PlayerProfile.save_profile()
	_status.text = "APARIENCIA GUARDADA"
	# Si estamos en una sala, el resto tiene que ver el cambio: nos volvemos a
	# presentar con la ficha nueva.
	if NetworkManager.is_connected_to_room():
		NetworkManager.update_local_profile()


# =============================================================================
# ARRANQUE DE PARTIDA
# =============================================================================

func _on_launch_sequence_started() -> void:
	if state != State.LOBBY:
		return
	_play_launch()


func _play_launch() -> void:
	state = State.LAUNCH
	_set_busy(true)
	_hide_screens()
	_osd.visible = false

	var door: Vector3 = _current_set.get_meta("door", Vector3(0, 0, -22.6))
	_cam.set_shake(0.8)
	_cam.move_to(_shots()["launch"], 1.4)

	# Entran en fila, no todos a la vez: un desfase por puesto es lo que hace
	# que se lea como una cola avanzando.
	var ids := NetworkManager.sorted_ids()
	for i in ids.size():
		var actor: MenuActor = _lobby_actors.get(ids[i])
		if actor == null or not is_instance_valid(actor):
			continue
		var lane := door + Vector3(clampf(actor.position.x * 0.25, -0.8, 0.8), 0, 1.4)
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree():
			return
		actor.walk_to(lane, 2.4)

	await get_tree().create_timer(maxf(0.2, LAUNCH_TIME - 0.12 * ids.size() - 0.7)).timeout
	if not is_inside_tree():
		return
	await _fade_out(0.7)
	# El cambio de escena lo dispara el host cuando se cumple LAUNCH_TIME.


# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)

	var theme := MenuTheme.create()

	# --- postproceso ---
	# El orden importa: los dos leen el buffer de pantalla, así que van ANTES
	# que los paneles (si no, filtrarían también el texto de la UI) y nunca
	# encendidos los dos a la vez.
	_menu_fx = _fx_rect(CRT_SHADER, {
		"scanline_count": 150.0, "scanline_intensity": 0.15, "grain_amount": 0.045,
		"vignette_strength": 0.72, "chromatic_aberration": 0.0016, "flicker_intensity": 0.010})
	_cam_fx = _fx_rect(CAM_SHADER, {})
	_cam_fx.visible = false

	# --- OSD de la cámara de seguridad ---
	_osd = Control.new()
	_osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_osd.visible = false
	_ui.add_child(_osd)

	var cam_id := _label(_osd, "CAM 04 -- ENTRADA", 7, Color(0.75, 0.95, 0.8))
	cam_id.position = Vector2(12, 10)
	_osd_rec = _label(_osd, "* REC", 7, Color(1.0, 0.25, 0.2))
	_osd_rec.position = Vector2(410, 10)
	_osd_time = _label(_osd, "00:00:00", 7, Color(0.75, 0.95, 0.8))
	_osd_time.position = Vector2(388, 248)
	# Esquinas de encuadre: cuatro rayitas que insinúan el visor de la cámara.
	for c in [Vector2(10, 22), Vector2(452, 22), Vector2(10, 240), Vector2(452, 240)]:
		var mark := _label(_osd, "+", 8, Color(0.7, 0.9, 0.75, 0.6))
		mark.position = c

	# --- pantallas ---
	var screens := Control.new()
	screens.name = "Screens"
	screens.set_anchors_preset(Control.PRESET_FULL_RECT)
	screens.theme = theme
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(screens)

	_build_result_banner(screens)
	_build_title_screen(screens)
	_build_rooms_screen(screens)
	_build_create_modal(screens)
	_build_join_modal(screens)
	_build_lobby_screen(screens)
	_build_appearance_screen(screens)

	_status = _label(screens, "", 7, Color(0.68, 0.48, 0.26))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -14
	_status.offset_bottom = -4
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- fundido a negro, siempre lo último ---
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)


func _fx_rect(shader: Shader, params: Dictionary) -> ColorRect:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for k in params.keys():
		mat.set_shader_parameter(k, params[k])
	var r := ColorRect.new()
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(r)
	return r


func _set_fx(security_cam: bool) -> void:
	_menu_fx.visible = not security_cam
	_cam_fx.visible = security_cam
	_osd.visible = security_cam


# --- helpers de construcción --------------------------------------------

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, variation: String, width: float,
		on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(width, 0)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _column(parent: Node, pos: Vector2, sep: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _panel(parent: Node, rect: Rect2, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.custom_minimum_size = rect.size
	p.size = rect.size
	parent.add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)

	if title != "":
		var t := _label(v, title, 9, MenuTheme.TEXT_HOT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(HSeparator.new())
	return v


func _screen(parent: Node, key) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	parent.add_child(c)
	_screens[key] = c
	return c


# --- pantallas concretas -------------------------------------------------

func _build_result_banner(parent: Node) -> void:
	_result_banner = PanelContainer.new()
	_result_banner.position = Vector2(120, 236)
	_result_banner.custom_minimum_size = Vector2(240, 0)
	_result_banner.visible = false
	parent.add_child(_result_banner)
	_result_label = _label(_result_banner, "", 7, MenuTheme.TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_title_screen(parent: Node) -> void:
	var s := _screen(parent, State.TITLE)

	var title := _label(s, "RATS N RUST", 28, Color(0.93, 0.89, 0.81))
	title.position = Vector2(16, 14)
	var sub := _label(s, "ESCONDERSE ES LO ÚNICO QUE SABÉS HACER", 6, MenuTheme.TEXT_DIM)
	sub.position = Vector2(19, 46)

	var col := _column(s, Vector2(18, 66), 5)
	_button(col, "JUGAR", "BigButton", 104, _on_play_pressed)
	_button(col, "SALIR", "Button", 104, func(): get_tree().quit())

	var who := _label(s, "", 6, MenuTheme.TEXT_DIM)
	who.position = Vector2(19, 112)
	who.text = "IDENT: %s" % PlayerProfile.player_name


func _build_rooms_screen(parent: Node) -> void:
	var s := _screen(parent, State.ROOMS)
	var col := _column(s, Vector2(16, 26), 5)
	_button(col, "CREAR SALA", "BigButton", 112, func(): _show_modal("create"))
	_button(col, "UNIRSE A SALA", "BigButton", 112, _on_join_pressed)
	_button(col, "VOLVER", "GhostButton", 112, _on_back_pressed)

	var tag := _label(s, "CÁMARAS", 8, Color(0.55, 0.85, 0.65))
	tag.position = Vector2(196, 12)


func _build_create_modal(parent: Node) -> void:
	var s := _screen(parent, "create")
	var v := _panel(s, Rect2(268, 44, 198, 0), "CREAR SALA")

	_create_fields["name"] = LineEdit.new()
	_create_fields["name"].text = "SALA DE %s" % PlayerProfile.player_name
	_create_fields["name"].max_length = 22
	_create_fields["name"].custom_minimum_size = Vector2(180, 16)
	_label(v, "NOMBRE DE SALA", 7, MenuTheme.TEXT_DIM)
	v.add_child(_create_fields["name"])

	_create_fields["players"] = _stepper(v, "JUGADORES", 4, 2, NetworkManager.MAX_PLAYERS, 1,
		func(x): return "%d" % x)
	_create_fields["duration"] = _stepper(v, "DURACIÓN DE RONDA", 5, 2, 15, 1,
		func(x): return "%d MIN" % x)

	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	_button(row, "CREAR", "GoButton", 88, _on_create_confirmed)
	_button(row, "CANCELAR", "GhostButton", 84, func(): _show_screen(State.ROOMS))


## Campo numérico [-] valor [+]. Devuelve un Dictionary con el estado; a esta
## resolución un SpinBox es ilegible y un slider no da precisión de a uno.
func _stepper(parent: Node, label_text: String, start: int, lo: int, hi: int,
		step: int, fmt: Callable) -> Dictionary:
	_label(parent, label_text, 7, MenuTheme.TEXT_DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var data := {"value": start, "lo": lo, "hi": hi}
	var value_label := _label(row, "", 9, MenuTheme.TEXT_HOT)
	value_label.custom_minimum_size = Vector2(70, 14)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var apply := func(delta: int):
		data["value"] = clampi(int(data["value"]) + delta, lo, hi)
		value_label.text = fmt.call(int(data["value"]))
	apply.call(0)

	var minus := _button(row, "-", "Button", 20, func(): apply.call(-step))
	row.move_child(minus, 0)
	row.move_child(value_label, 1)
	_button(row, "+", "Button", 20, func(): apply.call(step))
	return data


func _build_join_modal(parent: Node) -> void:
	var s := _screen(parent, "join")
	var v := _panel(s, Rect2(196, 40, 270, 0), "UNIRSE A SALA")

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	v.add_child(head)
	for spec in [["NOMBRE DE SALA", 120], ["ID", 44], ["JUG.", 34], ["PING", 34]]:
		var l := _label(head, str(spec[0]), 6, MenuTheme.TEXT_DIM)
		l.custom_minimum_size.x = float(spec[1])

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(252, 118)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_room_rows = VBoxContainer.new()
	_room_rows.add_theme_constant_override("separation", 1)
	_room_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_room_rows)

	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	_btn_join_confirm = _button(row, "UNIRSE", "GoButton", 78, _on_join_confirmed)
	_btn_join_confirm.disabled = true
	_button(row, "BUSCAR DE NUEVO", "Button", 92, _on_join_pressed)
	_button(row, "CANCELAR", "GhostButton", 74, func(): _show_screen(State.ROOMS))


func _build_lobby_screen(parent: Node) -> void:
	var s := _screen(parent, State.LOBBY)

	var head := _label(s, "LOBBY", 16, Color(0.93, 0.89, 0.81))
	head.position = Vector2(14, 24)
	_lobby_title = _label(s, "", 6, MenuTheme.TEXT_DIM)
	_lobby_title.position = Vector2(15, 44)

	_lobby_list = _column(s, Vector2(15, 58), 3)

	var col := _column(s, Vector2(14, 196), 4)
	_btn_ready = _button(col, "LISTO", "GoButton", 116, _on_ready_pressed)
	_btn_start = _button(col, "INICIAR JUEGO", "BigButton", 116, _on_start_pressed)
	_button(col, "VOLVER", "GhostButton", 116, _on_back_pressed)

	var app := _column(s, Vector2(366, 236), 4)
	_button(app, "APARIENCIA", "Button", 100, _on_appearance_pressed)


func _build_appearance_screen(parent: Node) -> void:
	var s := _screen(parent, State.APPEARANCE)

	var col := _column(s, Vector2(14, 34), 3)
	for slot in CosmeticCatalog.SLOT_ORDER:
		var b := _button(col, CosmeticCatalog.slot_name(slot), "Button", 132,
			_on_slot_pressed.bind(slot))
		_slot_buttons[slot] = b
	_button(col, "APLICAR", "GoButton", 132, _on_apply_appearance)

	_button(_column(s, Vector2(14, 236), 4), "VOLVER", "GhostButton", 100, _on_back_pressed)

	# Lista de piezas del slot elegido
	var v := _panel(s, Rect2(156, 34, 132, 0), "")
	_appearance_items = VBoxContainer.new()
	_appearance_items.add_theme_constant_override("separation", 2)
	v.add_child(_appearance_items)
	_appearance_hint = _label(v, "SIN PIEZAS TODAVÍA\nPRÓXIMAMENTE", 6, MenuTheme.TEXT_DIM)

	# Interruptor rata / atrapador
	var toggle_row := HBoxContainer.new()
	toggle_row.position = Vector2(320, 240)
	toggle_row.add_theme_constant_override("separation", 6)
	s.add_child(toggle_row)
	_label(toggle_row, "RATA O ATRAPADOR", 7, MenuTheme.TEXT)
	var cb := CheckButton.new()
	cb.button_pressed = (_appearance_role == GameState.Role.SEEKER)
	cb.toggled.connect(_on_role_toggled)
	toggle_row.add_child(cb)

	var hint := _label(s, "ARRASTRÁ PARA GIRAR", 6, MenuTheme.TEXT_DIM)
	hint.position = Vector2(196, 224)


# --- navegación de UI ----------------------------------------------------

## queue_free() es diferido: las filas viejas seguirían un cuadro más y las
## nuevas se apilarían debajo. Sacarlas del árbol en el acto evita el salto.
func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _hide_screens() -> void:
	for c in _screens.values():
		(c as Control).visible = false


func _show_screen(key) -> void:
	_hide_screens()
	if _screens.has(key):
		_screens[key].visible = true


func _show_modal(key: String) -> void:
	_show_screen(State.ROOMS)
	if _screens.has(key):
		_screens[key].visible = true


func _set_busy(value: bool) -> void:
	_busy = value
	for c in _screens.values():
		_set_buttons_disabled(c, value)
	# Re-habilitar en masa pisaría los botones que están apagados por una
	# condición (iniciar sin todos listos, unirse sin sala elegida).
	if not value:
		if state == State.LOBBY:
			_refresh_lobby()
		_btn_join_confirm.disabled = _selected_room.is_empty()


func _set_buttons_disabled(node: Node, value: bool) -> void:
	for child in node.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = value
		_set_buttons_disabled(child, value)


func _fade_out(duration: float = FADE_TIME) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, duration)
	await t.finished


func _fade_in(duration: float = FADE_TIME) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, duration)
	await t.finished


func _show_result_banner() -> void:
	if GameState.last_result.is_empty():
		return
	_result_banner.visible = true
	_result_banner.modulate.a = 1.0
	# Se desvanece solo: es el resultado de la ronda anterior, no un panel.
	var t := create_tween()
	t.tween_interval(5.5)
	t.tween_property(_result_banner, "modulate:a", 0.0, 1.0)
	t.tween_callback(func(): _result_banner.visible = false)
	if GameState.last_result == "hiders":
		_result_label.text = "[ LAS RATAS HAN SOBREVIVIDO ]"
		_result_label.modulate = MenuTheme.GOOD
	else:
		_result_label.text = "[ EL ATRAPADOR LAS LIQUIDÓ A TODAS ]"
		_result_label.modulate = MenuTheme.BAD
	GameState.last_result = ""


# =============================================================================
# ACCIONES
# =============================================================================

func _on_play_pressed() -> void:
	if _busy:
		return
	_play_enter_door()


func _on_back_pressed() -> void:
	if _busy:
		return
	match state:
		State.ROOMS:
			_set_busy(true)
			await _fade_out()
			await _enter_title()
			_set_busy(false)
		State.LOBBY:
			NetworkManager.leave_room()
			_set_busy(true)
			await _fade_out()
			await _enter_rooms(false)
			_set_busy(false)
		State.APPEARANCE:
			_set_busy(true)
			PlayerProfile.save_profile()
			await _fade_out()
			if NetworkManager.is_connected_to_room():
				await _enter_lobby()
			else:
				await _enter_title()
			_set_busy(false)


func _on_create_confirmed() -> void:
	var cfg := {
		"name": _create_fields["name"].text,
		"max_players": int(_create_fields["players"]["value"]),
		"round_duration": float(_create_fields["duration"]["value"]) * 60.0,
	}
	if not NetworkManager.create_room(cfg):
		_status.text = "ERROR: EL PUERTO %d YA ESTÁ EN USO" % NetworkManager.PORT


func _on_join_pressed() -> void:
	_show_modal("join")
	_selected_room = {}
	_btn_join_confirm.disabled = true
	_clear(_room_rows)
	var searching := _label(_room_rows, "BUSCANDO SALAS EN LA RED...", 7, MenuTheme.TEXT_DIM)
	searching.name = "Searching"
	_status.text = "BARRIENDO LA RED LOCAL..."
	NetworkManager.find_rooms()


func _on_rooms_found(rooms: Array) -> void:
	_pending_rooms = rooms
	_clear(_room_rows)

	if rooms.is_empty():
		_label(_room_rows, "NO SE ENCONTRÓ NINGUNA SALA", 7, MenuTheme.TEXT_DIM)
		_status.text = "SIN SALAS EN LA RED // PROBÁ CREAR UNA"
		return

	for room in rooms:
		var b := Button.new()
		b.theme_type_variation = "GhostButton"
		b.custom_minimum_size = Vector2(250, 15)
		b.pressed.connect(_on_room_selected.bind(room))
		_room_rows.add_child(b)

		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)

		var full: bool = int(room["players"]) >= int(room["max"])
		for spec in [
			[str(room["name"]), 120, MenuTheme.TEXT],
			[str(room["short"]), 44, MenuTheme.TEXT_DIM],
			["%d/%d" % [room["players"], room["max"]], 34,
				MenuTheme.BAD if full else MenuTheme.TEXT],
			["%d ms" % room["ping"], 34, MenuTheme.TEXT_DIM],
		]:
			var l := _label(row, str(spec[0]), 7, spec[2])
			l.custom_minimum_size.x = float(spec[1])

	_status.text = "%d SALA(S) ENCONTRADA(S)" % rooms.size()


func _on_room_selected(room: Dictionary) -> void:
	_selected_room = room
	_btn_join_confirm.disabled = int(room["players"]) >= int(room["max"])
	_status.text = "SALA: %s [%s]" % [room["name"], room["short"]]


func _on_join_confirmed() -> void:
	if _selected_room.is_empty():
		return
	_status.text = "CONECTANDO A %s..." % _selected_room["name"]
	NetworkManager.join_room(_selected_room)


func _on_ready_pressed() -> void:
	NetworkManager.set_ready(not NetworkManager.is_ready(multiplayer.get_unique_id()))


func _on_start_pressed() -> void:
	if not NetworkManager.all_ready():
		return
	_status.text = "INICIANDO PARTIDA..."
	NetworkManager.start_game()


func _on_appearance_pressed() -> void:
	if _busy:
		return
	_enter_appearance()


func _on_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	_refresh_appearance_items()


func _on_role_toggled(pressed: bool) -> void:
	_appearance_role = GameState.Role.SEEKER if pressed else GameState.Role.HIDER
	_apply_appearance_role()


# =============================================================================
# RED
# =============================================================================

func _on_server_created() -> void:
	_set_busy(true)
	await _fade_out()
	await _enter_lobby()
	_set_busy(false)


func _on_connected_to_server() -> void:
	_set_busy(true)
	await _fade_out()
	await _enter_lobby()
	_set_busy(false)


func _on_connection_failed() -> void:
	_status.text = "ERROR: NO SE PUDO CONECTAR A LA SALA"
	if state == State.ROOMS:
		_show_modal("join")


func _on_server_disconnected() -> void:
	if state != State.LOBBY:
		return
	_set_busy(true)
	await _fade_out()
	await _enter_rooms(false)
	_status.text = "EL HOST CERRÓ LA SALA"
	_set_busy(false)


func _on_roster_updated() -> void:
	if state != State.LOBBY:
		return
	_sync_lobby_actors()
	_refresh_lobby()
