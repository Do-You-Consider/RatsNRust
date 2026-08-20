class_name CharacterAppearance
extends Resource
## Aspecto de un personaje. HOY solo se usa para pintar el rig según el rol
## (equivalente a lo que hacía Player._apply_role_appearance()), pero la
## estructura ya es la definitiva para el sistema de customización futuro:
## el menú va a guardar uno de estos por jugador, se serializa en el
## spawn() de Game.gd y llega igual a todos los peers.
##
## - skin_color: color por defecto de todas las partes de piel (cabeza,
##   manos, hocico, orejas, cola).
## - part_colors: override por parte. Clave = id de parte (ver
##   CharacterRig.PARTS), valor = Color. Acá van a vivir las prendas.
## - attachments: escenas colgadas de un socket. Clave = nombre de socket
##   ("Socket_Head", "Socket_Face", "Socket_Back", "Socket_HandR"),
##   valor = ruta res:// de un PackedScene.

@export var skin_color: Color = Color(0.35, 0.33, 0.28)
@export var part_colors: Dictionary = {}
@export var attachments: Dictionary = {}

## Partes que emiten luz propia. Hoy solo los ojos del Atrapador; mañana
## puede ser una máscara con visor, un logo, lo que sea.
@export var emissive_parts: Array[String] = []


static func default_for_role(role: int) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	if role == GameState.Role.SEEKER:
		a.skin_color = Color(0.16, 0.06, 0.06)
		a.part_colors = {
			"TORSO": Color(0.12, 0.03, 0.03),
			"HIPS": Color(0.09, 0.025, 0.025),
			"ARM_L_UPPER": Color(0.12, 0.03, 0.03),
			"ARM_R_UPPER": Color(0.12, 0.03, 0.03),
			"LEG_L_THIGH": Color(0.09, 0.025, 0.025),
			"LEG_R_THIGH": Color(0.09, 0.025, 0.025),
			"LEG_L_SHIN": Color(0.09, 0.025, 0.025),
			"LEG_R_SHIN": Color(0.09, 0.025, 0.025),
			"FOOT_L": Color(0.05, 0.02, 0.02),
			"FOOT_R": Color(0.05, 0.02, 0.02),
			"NECK": Color(0.10, 0.03, 0.03),
			"FACE": Color(0.04, 0.02, 0.02),
			"EYE_L": Color(1.0, 0.16, 0.06),
			"EYE_R": Color(1.0, 0.16, 0.06),
		}
		# Dos brasas en una cabeza chica sobre un cuerpo enorme: es lo que
		# hace que se lea "atrapador" y no "tipo grande".
		a.emissive_parts = ["EYE_L", "EYE_R"]
	else:
		a.skin_color = Color(0.42, 0.40, 0.36)
		a.part_colors = {
			"TORSO": Color(0.30, 0.29, 0.25),
			"HIPS": Color(0.24, 0.23, 0.20),
			"LEG_L_THIGH": Color(0.24, 0.23, 0.20),
			"LEG_R_THIGH": Color(0.24, 0.23, 0.20),
			"LEG_L_SHIN": Color(0.24, 0.23, 0.20),
			"LEG_R_SHIN": Color(0.24, 0.23, 0.20),
			"FOOT_L": Color(0.14, 0.13, 0.12),
			"FOOT_R": Color(0.14, 0.13, 0.12),
			"NECK": Color(0.32, 0.30, 0.27),
			"FACE": Color(0.30, 0.28, 0.26),
			"EYE_L": Color(0.05, 0.04, 0.04),
			"EYE_R": Color(0.05, 0.04, 0.04),
		}
	return a


func color_for(part_id: String) -> Color:
	return part_colors.get(part_id, skin_color)


func is_emissive(part_id: String) -> bool:
	return emissive_parts.has(part_id)
