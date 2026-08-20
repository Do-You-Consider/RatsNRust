extends Node3D
## Orquesta la partida: genera el mapa (con la seed que mandó el host),
## spawnea el jugador de cada peer vía MultiplayerSpawner, maneja el COMBATE
## (validado en el servidor) y actualiza el HUD local simplificado.
##
## Sistema de combate (reemplaza al viejo agarre por proximidad):
##   - El Atrapador golpea con clic izquierdo. El golpe NO es instantáneo:
##     tiene HIT_WINDUP segundos de anticipación, y recién ahí se resuelve.
##     Esa ventana es lo que le da a la rata la chance de salir del cono.
##   - Cada rata aguanta GameState.RAT_MAX_HP golpes. Al segundo queda
##     DERRIBADA: sigue en el mapa pero solo puede arrastrarse.
##   - El golpe exige apuntar: la rata tiene que estar dentro de un cono
##     frontal Y sin pared en el medio. El agarre viejo era pura distancia,
##     así que se podía atrapar a través de un tabique.
##
## Flujo de red de un golpe (el cliente pide, el servidor decide):
##   clic  -> play_swing() local + _request_swing  -> server valida cooldown
##                                                 -> _apply_swing a todos
##   +windup -> _request_hit(objetivo)             -> server valida rango,
##                                                    cono, línea de visión
##                                                 -> _apply_hit / _apply_miss

const PlayerScene := preload("res://scenes/player/Player.tscn")

const HIT_RANGE := 1.9        # alcance real del golpe
const HIT_ARC_DOT := 0.55     # cono frontal (~57°): dot(mirada, dirección al objetivo)
const HIT_COOLDOWN := 0.9     # entre golpe y golpe
const HIT_WINDUP := 0.25      # anticipación antes de que el golpe se resuelva
const SWING_WINDOW_MIN := 120 # ms: el pedido de golpe no puede llegar antes de esto
const SWING_WINDOW_MAX := 800 # ms: ni después de esto (swing vencido)
const AIM_ASSIST_RANGE := 2.3 # el retículo avisa un poco antes de estar en rango

@onready var map_generator: MapGenerator = $MapGenerator
@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner

@onready var timer_label: Label = $UI/TopHUD/TimerLabel
@onready var status_label: Label = $UI/TopHUD/StatusLabel
@onready var intro_banner: CenterContainer = $UI/IntroBanner
@onready var intro_role_label: Label = $UI/IntroBanner/VBox/RoleTitle
@onready var intro_obj_label: Label = $UI/IntroBanner/VBox/RoleObjective
@onready var role_badge_label: Label = $UI/RoleBadge/RoleLabel
@onready var crosshair_dot: Label = $UI/Crosshair/Dot
@onready var hit_flash: ColorRect = $UI/HitFlash
@onready var rat_health: HBoxContainer = $UI/RatHealth/Pips

var _my_role: int = GameState.Role.NONE
var _target_id: int = -1        # a quién le pegaría el golpe si soltara ahora (solo cliente)
var _swing_cooldown: float = 0.0

## Solo servidor: momento (ms) del último swing de cada Atrapador. Sirve
## para el cooldown y para exigir que todo pedido de golpe venga precedido
## de un swing real -- si no, un cliente modificado podría mandar golpes en
## ráfaga sin animación.
var _swing_at: Dictionary = {}
var _last_swing_ms: Dictionary = {}


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	map_generator.generate(GameState.map_seed)

	if multiplayer.is_server():
		_spawn_all_players()

	_my_role = GameState.get_role(multiplayer.get_unique_id())
	hit_flash.modulate.a = 0.0
	_setup_hud()


func _setup_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	var role := GameState.get_role(my_id)

	if role == GameState.Role.SEEKER:
		intro_role_label.text = "ERES EL ATRAPADOR"
		intro_role_label.modulate = Color(1.0, 0.28, 0.18)
		intro_obj_label.text = "DERRIBA A TODAS LAS RATAS ANTES DE QUE SE AGOTE EL TIEMPO"
		role_badge_label.text = "[ ATRAPADOR ]"
		role_badge_label.modulate = Color(1.0, 0.35, 0.2)
	else:
		intro_role_label.text = "ERES UNA RATA"
		intro_role_label.modulate = Color(0.4, 0.9, 0.55)
		intro_obj_label.text = "ESCONDETE Y SOBREVIVE HASTA EL FINAL DE LA RONDA"
		role_badge_label.text = "[ RATA ]"
		role_badge_label.modulate = Color(0.4, 0.9, 0.55)

	# Las rayitas de vida son solo para la rata: el Atrapador no las tiene.
	rat_health.get_parent().visible = (role == GameState.Role.HIDER)
	_update_health_pips()

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
		_try_swing()


func _process(delta: float) -> void:
	if GameState.round_active:
		GameState.round_time_left = max(0.0, GameState.round_time_left - delta)

	if multiplayer.is_server() and GameState.round_active:
		if GameState.round_time_left <= 0.0:
			NetworkManager.end_round("hiders")

	_swing_cooldown = max(0.0, _swing_cooldown - delta)

	var total_secs := int(ceil(GameState.round_time_left))
	var mins := total_secs / 60
	var secs := total_secs % 60
	timer_label.text = "%02d:%02d" % [mins, secs]

	if total_secs <= 30:
		timer_label.modulate = Color(1.0, 0.3, 0.2)
	else:
		timer_label.modulate = Color(0.9, 0.72, 0.35)

	var total_rats := 0
	var downed_count := 0
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) == GameState.Role.HIDER:
			total_rats += 1
			if GameState.is_downed(pid):
				downed_count += 1
	var active_rats: int = maxi(0, total_rats - downed_count)
	if total_rats > 0:
		status_label.text = "RATAS VIVAS: %d / %d" % [active_rats, total_rats]
	else:
		status_label.text = "RATAS VIVAS: --"

	if _my_role == GameState.Role.SEEKER:
		_update_aim()


# ============================================================== objetivo

## Retículo del Atrapador local. Usa exactamente la misma función de
## validación que el servidor, así lo que el retículo promete es lo que el
## servidor acepta: nada de "estaba marcado en rojo y no le pegué".
func _update_aim() -> void:
	var me := _player_node(multiplayer.get_unique_id())
	if me == null:
		_target_id = -1
		return

	var target := _find_target(me, AIM_ASSIST_RANGE)
	_target_id = int(target.name) if target != null else -1

	var in_range := _target_id != -1 and _is_valid_hit(me, target, HIT_RANGE)
	if in_range and _swing_cooldown <= 0.0:
		crosshair_dot.text = "+"
		crosshair_dot.modulate = Color(1.0, 0.3, 0.22, 1.0)
	elif _target_id != -1:
		crosshair_dot.text = "+"
		crosshair_dot.modulate = Color(0.9, 0.75, 0.4, 0.7)
	else:
		crosshair_dot.text = "·"
		crosshair_dot.modulate = Color(0.85, 0.82, 0.78, 0.45)


## Rata golpeable más cercana. `max_range` se separa del alcance real para
## que el retículo pueda avisar un poco antes de que el golpe entre.
func _find_target(seeker: Node3D, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_range
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) != GameState.Role.HIDER:
			continue
		if GameState.is_downed(pid):
			continue
		var d: float = child.global_position.distance_to(seeker.global_position)
		if d < best_dist and _is_valid_hit(seeker, child, max_range):
			best_dist = d
			best = child
	return best


## Un golpe vale si el objetivo está en rango, dentro del cono frontal y con
## línea de visión libre. Es la única fuente de verdad: la usa el retículo
## del cliente y la usa el servidor para aceptar o rechazar.
func _is_valid_hit(seeker: Node3D, target: Node3D, max_range: float) -> bool:
	var delta := target.global_position - seeker.global_position
	if delta.length() > max_range:
		return false

	var flat := Vector3(delta.x, 0.0, delta.z)
	if flat.length() < 0.05:
		return true # encima tuyo: no hay dirección que medir
	var forward := -seeker.global_transform.basis.z
	forward.y = 0.0
	if forward.normalized().dot(flat.normalized()) < HIT_ARC_DOT:
		return false

	return _has_line_of_sight(seeker, target)


func _has_line_of_sight(seeker: Node3D, target: Node3D) -> bool:
	var space := seeker.get_world_3d().direct_space_state
	if space == null:
		return true
	var from: Vector3 = seeker.global_position + Vector3(0, 1.2, 0)
	var to: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Los jugadores no se tapan entre sí: solo bloquea la geometría del mapa.
	var excludes: Array[RID] = []
	for child in players_root.get_children():
		if child is CollisionObject3D:
			excludes.append((child as CollisionObject3D).get_rid())
	query.exclude = excludes
	return space.intersect_ray(query).is_empty()


func _player_node(pid: int) -> Node3D:
	return players_root.get_node_or_null(str(pid)) as Node3D


# =============================================================== combate

## Clic del Atrapador local. La animación arranca en el acto (sin esperar la
## red) y el pedido de golpe sale recién al terminar la anticipación, con el
## objetivo que haya en ese momento -- no con el que había al hacer clic.
func _try_swing() -> void:
	if _swing_cooldown > 0.0:
		return
	var me := _player_node(multiplayer.get_unique_id())
	if me == null:
		return

	_swing_cooldown = HIT_COOLDOWN
	me.play_swing()
	_request_swing.rpc_id(1)

	await get_tree().create_timer(HIT_WINDUP).timeout
	if not is_inside_tree():
		return
	me = _player_node(multiplayer.get_unique_id())
	if me == null:
		return
	var target := _find_target(me, HIT_RANGE)
	_request_hit.rpc_id(1, int(target.name) if target != null else -1)


## Devuelve quién mandó el RPC. Cuando el host se lo manda a sí mismo,
## get_remote_sender_id() da 0.
func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## OJO con el "call_local": estos dos los manda el Atrapador con rpc_id(1).
## Cuando el Atrapador ES el host, ese rpc_id(1) va del peer 1 al peer 1, y
## Godot solo ejecuta la llamada localmente si el RPC está declarado con
## call_local. Sin él, el host-Atrapador pegaba al aire: no se registraba el
## swing, no bajaba la vida y el broadcast a las ratas nunca salía.
@rpc("any_peer", "call_local", "reliable")
func _request_swing() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if GameState.get_role(id) != GameState.Role.SEEKER:
		return

	var now := Time.get_ticks_msec()
	var last := int(_last_swing_ms.get(id, -999999))
	# 60 ms de tolerancia: el cliente ya midió su propio cooldown, acá solo
	# cortamos el spam de un cliente modificado.
	if now - last < int(HIT_COOLDOWN * 1000.0) - 60:
		return

	_last_swing_ms[id] = now
	_swing_at[id] = now
	_apply_swing.rpc(id)


@rpc("authority", "call_local", "reliable")
func _apply_swing(seeker_id: int) -> void:
	# El Atrapador local ya arrancó la animación al hacer clic.
	if seeker_id == multiplayer.get_unique_id():
		return
	var seeker := _player_node(seeker_id)
	if seeker != null:
		seeker.play_swing()


## El cliente pide el golpe; SOLO el servidor decide si es válido (evita que
## un cliente modificado se auto-declare ganador). Verifica que quien pide
## sea el Atrapador, que venga de un swing real y reciente, y que el objetivo
## esté en rango, en el cono y sin pared en el medio.
@rpc("any_peer", "call_local", "reliable")
func _request_hit(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if GameState.get_role(id) != GameState.Role.SEEKER:
		return

	# Todo golpe tiene que venir precedido de un swing que ya haya terminado
	# su anticipación y que todavía no se haya usado.
	if not _swing_at.has(id):
		return
	var age := Time.get_ticks_msec() - int(_swing_at[id])
	_swing_at.erase(id)
	if age < SWING_WINDOW_MIN or age > SWING_WINDOW_MAX:
		return

	var seeker := _player_node(id)
	if seeker == null:
		return

	var target := _player_node(target_id) if target_id != -1 else null
	var valid := target != null \
		and GameState.get_role(target_id) == GameState.Role.HIDER \
		and not GameState.is_downed(target_id) \
		and _is_valid_hit(seeker, target, HIT_RANGE)

	if not valid:
		_apply_miss.rpc(id)
		return

	var hp: int = GameState.get_rat_hp(target_id) - 1
	var downed := hp <= 0
	_apply_hit.rpc(id, target_id, hp, downed)
	if downed:
		_check_all_downed()


## Corre en TODOS los peers: sincroniza el estado (esto es lo que el sistema
## viejo de atrape NO hacía -- guardaba el resultado solo en el host, y por
## eso el contador de ratas nunca bajaba en los clientes) y dispara la
## presentación: animación, partículas, sacudón y flash.
@rpc("authority", "call_local", "reliable")
func _apply_hit(seeker_id: int, target_id: int, hp: int, downed: bool) -> void:
	GameState.rat_hp[target_id] = hp
	if downed:
		GameState.rat_state[target_id] = GameState.RatState.DOWNED

	var seeker := _player_node(seeker_id)
	var target := _player_node(target_id)
	if seeker != null:
		seeker.resolve_swing(true)
	if target != null and seeker != null:
		target.receive_hit(seeker.global_position, downed)

	if target_id == multiplayer.get_unique_id():
		_flash_hit(downed)
		_update_health_pips()


@rpc("authority", "call_local", "reliable")
func _apply_miss(seeker_id: int) -> void:
	var seeker := _player_node(seeker_id)
	if seeker != null:
		seeker.resolve_swing(false)


## Solo corre en el host: si ya no queda ninguna rata en pie, gana el
## Atrapador.
func _check_all_downed() -> void:
	if not multiplayer.is_server():
		return

	var rat_ids: Array = []
	for child in players_root.get_children():
		var pid := int(child.name)
		if GameState.get_role(pid) == GameState.Role.HIDER:
			rat_ids.append(pid)

	if rat_ids.is_empty():
		return
	for pid in rat_ids:
		if not GameState.is_downed(pid):
			return

	NetworkManager.end_round("seeker")


# =================================================================== HUD

## Flash rojo al recibir un golpe. El derribo pinta más fuerte y tarda más
## en irse: querés que se note que fue el último.
func _flash_hit(downed: bool) -> void:
	hit_flash.color = Color(0.55, 0.03, 0.03) if downed else Color(0.75, 0.08, 0.06)
	hit_flash.modulate.a = 0.85 if downed else 0.55
	var tween := create_tween()
	tween.tween_property(hit_flash, "modulate:a", 0.0, 0.7 if downed else 0.28)


## Dos rayitas: se apaga una por golpe recibido. La segunda apagada = en el
## piso.
func _update_health_pips() -> void:
	if _my_role != GameState.Role.HIDER:
		return
	var hp := GameState.get_rat_hp(multiplayer.get_unique_id())
	var pips := rat_health.get_children()
	for i in pips.size():
		var pip := pips[i] as Label
		if i < hp:
			pip.text = "▮"
			pip.modulate = Color(0.4, 0.9, 0.55, 1.0)
		else:
			pip.text = "▯"
			pip.modulate = Color(0.5, 0.22, 0.2, 0.8)
