class_name CharacterProfiles
extends RefCounted
## Proporciones de cada personaje. Todo se deriva de acá: el rig segmentado,
## la cápsula de colisión, la altura de la cámara y las poses base de las
## animaciones. Cambiar un número acá cambia el personaje entero.
##
## Convención vertical (todo en metros, y=0 = pies en el piso):
##   hips_y   = thigh + shin + foot_size.y/2
##   chest_y  = hips_y + hips_size.y/2      (base del pecho, nodo Chest)
##   neck_y   = chest_y + chest_size.y      (nodo Neck)
##   head_y   = neck_y + neck_len           (nodo Head, base del cubo)
##   altura   = head_y + head_size.y
##
## Los dos son HUMANOIDES: "rata" y "atrapador" son roles, no especies. Lo
## que los diferencia es la proporción, no rasgos de animal.
##
## La RATA tiene proporciones humanas normales (1.70 m). El ATRAPADOR es
## deliberadamente desproporcionado: hombros muy anchos, cabeza chica,
## brazos largos y encorvado hacia adelante. La intimidación no viene de
## los metros sino de esa silueta.

const RAT := {
	"height": 1.70,
	"eye_y": 1.58,
	"col_radius": 0.35,
	"col_height": 1.70,

	"thigh": 0.45,
	"shin": 0.40,
	"leg_thick": 0.13,
	"foot_size": Vector3(0.14, 0.08, 0.24),

	"hips_size": Vector3(0.34, 0.22, 0.20),
	"chest_size": Vector3(0.38, 0.37, 0.22),

	"neck_len": 0.11,
	"head_size": Vector3(0.22, 0.22, 0.24),

	"upper_arm": 0.30,
	"forearm": 0.28,
	"arm_thick": 0.10,
	"hand_size": Vector3(0.11, 0.13, 0.09),

	"hunch": 2.0,        # inclinación del pecho hacia adelante (grados)
	"arm_flare": 4.0,    # separación de los brazos del cuerpo (grados en Z)
}

const SEEKER := {
	"height": 2.30,
	"eye_y": 2.14,
	"col_radius": 0.50,
	"col_height": 2.30,

	"thigh": 0.62,
	"shin": 0.53,
	"leg_thick": 0.20,
	"foot_size": Vector3(0.22, 0.10, 0.34),

	"hips_size": Vector3(0.56, 0.30, 0.30),
	"chest_size": Vector3(0.78, 0.57, 0.34),

	"neck_len": 0.11,
	"head_size": Vector3(0.26, 0.27, 0.28),

	"upper_arm": 0.52,
	"forearm": 0.50,
	"arm_thick": 0.17,
	"hand_size": Vector3(0.20, 0.22, 0.16),

	"hunch": 14.0,
	"arm_flare": 9.0,
}


static func for_role(role: int) -> Dictionary:
	return SEEKER if role == GameState.Role.SEEKER else RAT


static func hips_y(p: Dictionary) -> float:
	return p.thigh + p.shin + (p.foot_size as Vector3).y * 0.5


static func chest_y(p: Dictionary) -> float:
	return hips_y(p) + (p.hips_size as Vector3).y * 0.5


## Altura del hombro medida DENTRO del nodo Chest (que está en su base).
static func shoulder_local_y(p: Dictionary) -> float:
	return (p.chest_size as Vector3).y - (p.arm_thick as float) * 0.6


## Separación horizontal del hombro respecto del centro.
static func shoulder_x(p: Dictionary) -> float:
	return (p.chest_size as Vector3).x * 0.5 + (p.arm_thick as float) * 0.5


## Altura absoluta del hombro (para colgar el viewmodel de brazos).
static func shoulder_world_y(p: Dictionary) -> float:
	return chest_y(p) + shoulder_local_y(p)
