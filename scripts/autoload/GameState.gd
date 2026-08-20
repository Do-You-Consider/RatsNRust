extends Node
## Autoload: estado de la partida en curso.
## Se registra en project.godot -> [autoload] como "GameState".

enum Role { NONE, HIDER, SEEKER }

## Estado de combate de cada rata. Una rata arranca ALIVE con RAT_MAX_HP
## golpes de aguante; al llegar a 0 queda DOWNED (derribada en el piso, se
## puede seguir arrastrando pero mucho más lento).
enum RatState { ALIVE, DOWNED }

const RAT_MAX_HP := 2

## id de jugador (multiplayer unique id) -> Role
var player_roles: Dictionary = {}

## id de rata -> golpes restantes (int) y estado (RatState). Los escribe el
## servidor y los replica Game.gd vía RPC a TODOS los peers -- ojo con esto:
## el sistema viejo de atrape guardaba el estado solo en el host, así que el
## HUD de los clientes nunca se enteraba de nada.
var rat_hp: Dictionary = {}
var rat_state: Dictionary = {}

## Duración de la ronda en segundos (los Hiders ganan si sobreviven este tiempo)
var round_duration: float = 300.0
var round_time_left: float = 0.0
var round_active: bool = false

## Seed del mapa, generada por el host y replicada a todos los clientes
## para que todos vean exactamente el mismo laberinto.
var map_seed: int = 0

## Resultado de la última ronda ("hiders" / "seeker" / ""), lo lee el menú
## para mostrar quién ganó al volver a la sala de espera.
var last_result: String = ""

## Velocidades base (Hider más rápido, Seeker más lento pero con habilidades)
var hider_speed: float = 6.5
var seeker_speed: float = 4.5

## Velocidad de la rata derribada arrastrándose por el piso. Muy por debajo
## de la de caminar: sirve para salir de la línea de visión o llegar hasta
## una esquina, no para escapar de verdad.
var crawl_speed: float = 1.2


func reset() -> void:
	player_roles.clear()
	rat_hp.clear()
	rat_state.clear()
	round_time_left = round_duration
	round_active = false


## Arranca (o reinicia) el estado de combate de todas las ratas según los
## roles ya asignados. Corre en todos los peers, porque player_roles se
## replica antes de cambiar de escena.
func init_rat_states() -> void:
	rat_hp.clear()
	rat_state.clear()
	for pid in player_roles.keys():
		if player_roles[pid] == Role.HIDER:
			rat_hp[pid] = RAT_MAX_HP
			rat_state[pid] = RatState.ALIVE


func assign_seeker(id: int) -> void:
	for pid in player_roles.keys():
		player_roles[pid] = Role.HIDER
	player_roles[id] = Role.SEEKER


func get_role(id: int) -> int:
	return player_roles.get(id, Role.NONE)


func get_rat_hp(id: int) -> int:
	return rat_hp.get(id, RAT_MAX_HP)


func get_rat_state(id: int) -> int:
	return rat_state.get(id, RatState.ALIVE)


func is_downed(id: int) -> bool:
	return rat_state.get(id, RatState.ALIVE) == RatState.DOWNED
