class_name RigBuilder
extends RefCounted
## Construye el rig segmentado de un personaje: una jerarquía de Node3D
## (articulaciones) con un MeshInstance3D de caja colgando de cada una.
##
## NO hay Skeleton3D ni skinning a propósito:
##   - la estética rígida de muñeco articulado es la que corresponde al
##     shader ps2_gameplay y al mapa de primitivas,
##   - cada parte es un MeshInstance3D independiente, así que el sistema de
##     customización futuro puede cambiar una prenda sola sin re-skinear,
##   - se puede autorar entero en código, igual que MapGenerator.
##
## Convención de cada hueso: el nodo articulación está en el EXTREMO SUPERIOR
## del segmento; la malla cuelga hacia -Y; el hijo siguiente se ancla a -largo.
## Así, rotar la articulación hace girar el segmento desde su punta, como un
## hueso real.

## Ids de parte. Son las claves que usa CharacterAppearance.part_colors y las
## que va a usar el menú de customización.
const PARTS := [
	"HEAD", "FACE", "EYE_L", "EYE_R", "NECK", "TORSO", "HIPS",
	"ARM_L_UPPER", "ARM_L_FORE", "HAND_L",
	"ARM_R_UPPER", "ARM_R_FORE", "HAND_R",
	"LEG_L_THIGH", "LEG_L_SHIN", "FOOT_L",
	"LEG_R_THIGH", "LEG_R_SHIN", "FOOT_R",
]

const SOCKETS := ["Socket_Head", "Socket_Face", "Socket_Back", "Socket_HandL", "Socket_HandR"]

## Partes que quedan visibles en el viewmodel de primera persona.
const ARM_PARTS := ["ARM_L_UPPER", "ARM_L_FORE", "HAND_L", "ARM_R_UPPER", "ARM_R_FORE", "HAND_R"]

## Rutas de articulación usadas por las animaciones. Relativas al CharacterRig.
const J_ROOT := "Root"
const J_HIPS := "Root/Hips"
const J_CHEST := "Root/Hips/Chest"
## OJO: entre Chest y Neck hay un pivote "NeckLook" que NINGUNA animación
## toca. Es el que rota CharacterRig.set_look() para que la cabeza siga a la
## cámara. Al estar en la jerarquía, la mirada y la animación se componen
## solas: si en cambio escribiéramos la rotación del cuello desde código, el
## AnimationPlayer la pisaría cada cuadro.
const J_NECKLOOK := "Root/Hips/Chest/NeckLook"
const J_NECK := "Root/Hips/Chest/NeckLook/Neck"
const J_HEAD := "Root/Hips/Chest/NeckLook/Neck/Head"
const J_UAL := "Root/Hips/Chest/ShoulderL/UpperArmL"
const J_FAL := "Root/Hips/Chest/ShoulderL/UpperArmL/ForearmL"
const J_UAR := "Root/Hips/Chest/ShoulderR/UpperArmR"
const J_FAR := "Root/Hips/Chest/ShoulderR/UpperArmR/ForearmR"
const J_THL := "Root/Hips/ThighL"
const J_SHINL := "Root/Hips/ThighL/ShinL"
const J_THR := "Root/Hips/ThighR"
const J_SHINR := "Root/Hips/ThighR/ShinR"


## Arma el rig completo bajo `rig`. Devuelve un Dictionary con:
##   parts   -> { part_id: MeshInstance3D }
##   sockets -> { socket_name: Node3D }
##   pose    -> { joint_path: Vector3 } rotación de reposo en GRADOS
static func build(rig: Node3D, p: Dictionary) -> Dictionary:
	var parts := {}
	var sockets := {}

	var hips_size: Vector3 = p.hips_size
	var chest_size: Vector3 = p.chest_size
	var head_size: Vector3 = p.head_size
	var hand_size: Vector3 = p.hand_size
	var foot_size: Vector3 = p.foot_size

	var root := _joint(rig, "Root", Vector3.ZERO)
	var hips := _joint(root, "Hips", Vector3(0, CharacterProfiles.hips_y(p), 0))
	parts["HIPS"] = _box(hips, "HipsMesh", hips_size, Vector3.ZERO)

	# --- Torso ---------------------------------------------------------
	var chest := _joint(hips, "Chest", Vector3(0, hips_size.y * 0.5, 0))
	parts["TORSO"] = _box(chest, "TorsoMesh", chest_size, Vector3(0, chest_size.y * 0.5, 0))

	sockets["Socket_Back"] = _joint(chest, "Socket_Back",
		Vector3(0, chest_size.y * 0.55, chest_size.z * 0.5 + 0.02))

	# --- Cabeza --------------------------------------------------------
	var neck_look := _joint(chest, "NeckLook", Vector3(0, chest_size.y, 0))
	var neck := _joint(neck_look, "Neck", Vector3.ZERO)
	# El cuello tiene malla propia: sin ella quedaba un hueco visible entre
	# el torso y la cabeza. Además es una parte más para customizar (cuellos,
	# bufandas, collares).
	var neck_h: float = float(p.neck_len) + 0.05
	parts["NECK"] = _box(neck, "NeckMesh",
		Vector3(head_size.x * 0.6, neck_h, head_size.z * 0.6),
		Vector3(0, neck_h * 0.5 - 0.03, 0))
	var head := _joint(neck, "Head", Vector3(0, p.neck_len, 0))
	parts["HEAD"] = _box(head, "HeadMesh", head_size, Vector3(0, head_size.y * 0.5, 0))

	# La cara es una placa fina al frente del cubo de la cabeza. Es la parte
	# que una máscara va a tapar o reemplazar.
	var face_size := Vector3(head_size.x * 0.82, head_size.y * 0.5, 0.03)
	parts["FACE"] = _box(head, "FaceMesh", face_size,
		Vector3(0, head_size.y * 0.62, -head_size.z * 0.5 - 0.015))

	# Dos cubitos de ojo sobre la placa de la cara. Son lo único que da
	# orientación de frente/espalda a un modelo hecho de cajas.
	var eye := Vector3(head_size.x * 0.2, head_size.y * 0.13, 0.02)
	var eye_y: float = head_size.y * 0.62
	var eye_z: float = -head_size.z * 0.5 - 0.04
	parts["EYE_L"] = _box(head, "EyeLMesh", eye, Vector3(-head_size.x * 0.22, eye_y, eye_z))
	parts["EYE_R"] = _box(head, "EyeRMesh", eye, Vector3(head_size.x * 0.22, eye_y, eye_z))



	sockets["Socket_Head"] = _joint(head, "Socket_Head", Vector3(0, head_size.y, 0))
	sockets["Socket_Face"] = _joint(head, "Socket_Face",
		Vector3(0, head_size.y * 0.6, -head_size.z * 0.5))


	# --- Brazos --------------------------------------------------------
	var sx: float = CharacterProfiles.shoulder_x(p)
	var sy: float = CharacterProfiles.shoulder_local_y(p)
	var at: float = p.arm_thick
	for side in ["L", "R"]:
		var sign_x := -1.0 if side == "L" else 1.0
		var shoulder := _joint(chest, "Shoulder" + side, Vector3(sign_x * sx, sy, 0))
		var upper := _joint(shoulder, "UpperArm" + side, Vector3.ZERO)
		parts["ARM_%s_UPPER" % side] = _box(upper, "UpperArmMesh",
			Vector3(at, p.upper_arm, at), Vector3(0, -p.upper_arm * 0.5, 0))

		var fore := _joint(upper, "Forearm" + side, Vector3(0, -p.upper_arm, 0))
		parts["ARM_%s_FORE" % side] = _box(fore, "ForearmMesh",
			Vector3(at * 0.9, p.forearm, at * 0.9), Vector3(0, -p.forearm * 0.5, 0))

		var hand := _joint(fore, "Hand" + side, Vector3(0, -p.forearm, 0))
		parts["HAND_" + side] = _box(hand, "HandMesh", hand_size,
			Vector3(0, -hand_size.y * 0.5, 0))
		sockets["Socket_Hand" + side] = _joint(hand, "Socket_Hand" + side,
			Vector3(0, -hand_size.y, 0))

	# --- Piernas -------------------------------------------------------
	var lt: float = p.leg_thick
	var hip_x: float = hips_size.x * 0.5 - lt * 0.5
	for side2 in ["L", "R"]:
		var sign_x2 := -1.0 if side2 == "L" else 1.0
		var thigh := _joint(hips, "Thigh" + side2, Vector3(sign_x2 * hip_x, -hips_size.y * 0.5, 0))
		parts["LEG_%s_THIGH" % side2] = _box(thigh, "ThighMesh",
			Vector3(lt, p.thigh, lt), Vector3(0, -p.thigh * 0.5, 0))

		var shin := _joint(thigh, "Shin" + side2, Vector3(0, -p.thigh, 0))
		parts["LEG_%s_SHIN" % side2] = _box(shin, "ShinMesh",
			Vector3(lt * 0.88, p.shin, lt * 0.88), Vector3(0, -p.shin * 0.5, 0))

		var foot := _joint(shin, "Foot" + side2, Vector3(0, -p.shin, 0))
		parts["FOOT_" + side2] = _box(foot, "FootMesh", foot_size,
			Vector3(0, -foot_size.y * 0.5, -foot_size.z * 0.5 + lt * 0.5))

	var pose := rest_pose(p)
	apply_pose(rig, pose)

	return {"parts": parts, "sockets": sockets, "pose": pose}


## Pose de reposo en GRADOS. Las animaciones se construyen SUMANDO sus
## offsets a estos valores, así el encorvado del Atrapador y la apertura de
## brazos se mantienen en todas las animaciones sin repetirlos a mano.
static func rest_pose(p: Dictionary) -> Dictionary:
	var flare: float = p.arm_flare
	var hunch: float = p.hunch
	return {
		J_ROOT: Vector3.ZERO,
		J_HIPS: Vector3.ZERO,
		J_CHEST: Vector3(hunch, 0, 0),
		J_NECK: Vector3(-hunch * 0.6, 0, 0),
		J_HEAD: Vector3.ZERO,
		J_UAL: Vector3(-hunch * 0.4, 0, -flare),
		J_UAR: Vector3(-hunch * 0.4, 0, flare),
		J_FAL: Vector3(6, 0, 0),
		J_FAR: Vector3(6, 0, 0),
		J_THL: Vector3.ZERO,
		J_THR: Vector3.ZERO,
		J_SHINL: Vector3.ZERO,
		J_SHINR: Vector3.ZERO,
	}


static func apply_pose(rig: Node3D, pose: Dictionary) -> void:
	for path in pose.keys():
		var node := rig.get_node_or_null(path) as Node3D
		if node != null:
			node.rotation = deg_vec(pose[path])


static func deg_vec(v: Vector3) -> Vector3:
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))


static func _joint(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = joint_name
	parent.add_child(n)
	n.position = pos
	return n


static func _box(parent: Node3D, mesh_name: String, size: Vector3, offset: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	parent.add_child(mi)
	mi.position = offset
	return mi
