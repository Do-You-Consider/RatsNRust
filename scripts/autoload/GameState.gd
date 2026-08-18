extends Node
## Autoload: estado de la partida en curso.
## Se registra en project.godot -> [autoload] como "GameState".

enum Role { NONE, HIDER, SEEKER }

## id de jugador (multiplayer unique id) -> Role
var player_roles: Dictionary = {}

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


func reset() -> void:
	player_roles.clear()
	round_time_left = round_duration
	round_active = false


func assign_seeker(id: int) -> void:
	for pid in player_roles.keys():
		player_roles[pid] = Role.HIDER
	player_roles[id] = Role.SEEKER


func get_role(id: int) -> int:
	return player_roles.get(id, Role.NONE)
