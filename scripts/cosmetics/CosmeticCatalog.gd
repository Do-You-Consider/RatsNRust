class_name CosmeticCatalog
extends RefCounted
## Catálogo de piezas de customización.
##
## HOY ESTÁ VACÍO A PROPÓSITO: todavía no hay ropa ni accesorios modelados. Lo
## que está terminado es la ESTRUCTURA, así que sumar una pieza más adelante es
## agregar un Dictionary a ITEMS y nada más -- el menú, la serialización por
## red y el rig ya saben qué hacer con ella.
##
## Cada item:
##   id          String  identificador estable (va serializado en el perfil)
##   name        String  lo que se muestra en la lista
##   slot        int     una de las constantes Slot
##   socket      String  socket del rig donde se cuelga la escena, o ""
##   scene       String  ruta res:// de un PackedScene, o ""
##   colors      Dict    part_id -> Color, para piezas que solo repintan
##   roles       Array   roles que pueden usarla; vacío = ambos
##
## Las dos formas de pieza (escena colgada de un socket vs. repintado de
## partes) conviven porque el rig es segmentado: un gorro es una malla nueva
## en Socket_Head, pero una campera es literalmente pintar TORSO y los brazos.

enum Slot { HEAD, ACCESSORY, TOP, BOTTOM, SHOES }

const SLOT_ORDER := [Slot.HEAD, Slot.ACCESSORY, Slot.TOP, Slot.BOTTOM, Slot.SHOES]

const SLOT_NAMES := {
	Slot.HEAD: "CABEZA",
	Slot.ACCESSORY: "ACCESORIO",
	Slot.TOP: "VESTIMENTA ARRIBA",
	Slot.BOTTOM: "VESTIMENTA ABAJO",
	Slot.SHOES: "ZAPATILLAS",
}

## Socket por defecto de cada slot, para las piezas que son escena colgada.
const SLOT_SOCKETS := {
	Slot.HEAD: "Socket_Head",
	Slot.ACCESSORY: "Socket_Face",
	Slot.TOP: "Socket_Back",
	Slot.BOTTOM: "",
	Slot.SHOES: "",
}

## Partes del rig que repinta cada slot. Es lo que hace que "campera" y
## "pantalón" funcionen sin una sola malla nueva.
const SLOT_PARTS := {
	Slot.HEAD: ["HEAD", "FACE"],
	Slot.ACCESSORY: [],
	Slot.TOP: ["TORSO", "ARM_L_UPPER", "ARM_R_UPPER", "ARM_L_FORE", "ARM_R_FORE", "NECK"],
	Slot.BOTTOM: ["HIPS", "LEG_L_THIGH", "LEG_R_THIGH", "LEG_L_SHIN", "LEG_R_SHIN"],
	Slot.SHOES: ["FOOT_L", "FOOT_R"],
}

## id reservado: "sin pieza". Siempre está disponible en todos los slots y es
## lo que deja la apariencia por defecto del rol.
const NONE_ID := "none"

## ------------------------------------------------------------------------
## ACÁ VAN LAS PIEZAS. Ejemplo de las dos formas, comentado hasta que existan:
##
##   {"id": "gorra_obrera", "name": "GORRA DE OBRA", "slot": Slot.HEAD,
##    "socket": "Socket_Head", "scene": "res://scenes/cosmetics/GorraObra.tscn",
##    "colors": {}, "roles": []},
##
##   {"id": "campera_cuero", "name": "CAMPERA DE CUERO", "slot": Slot.TOP,
##    "socket": "", "scene": "",
##    "colors": {"TORSO": Color(0.10, 0.06, 0.05)}, "roles": [GameState.Role.HIDER]},
## ------------------------------------------------------------------------
const ITEMS: Array[Dictionary] = []


static func slot_name(slot: int) -> String:
	return SLOT_NAMES.get(slot, "?")


## Piezas disponibles en un slot para un rol. Siempre devuelve al menos la
## entrada "sin pieza", así la lista nunca queda literalmente vacía y el menú
## no necesita un caso especial.
static func items_for(slot: int, role: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{
		"id": NONE_ID, "name": "-- SIN PIEZA --", "slot": slot,
		"socket": "", "scene": "", "colors": {}, "roles": [],
	}]
	for it in ITEMS:
		if it.get("slot", -1) != slot:
			continue
		var roles: Array = it.get("roles", [])
		if not roles.is_empty() and not roles.has(role):
			continue
		out.append(it)
	return out


static func find(item_id: String) -> Dictionary:
	for it in ITEMS:
		if it.get("id", "") == item_id:
			return it
	return {}


## ¿Ya hay piezas de verdad? El menú lo usa para mostrar el aviso de
## "próximamente" en vez de una lista con una sola entrada muerta.
static func is_empty() -> bool:
	return ITEMS.is_empty()


## Aplica la selección de slots sobre una apariencia base. `selection` es
## { slot(int): item_id(String) }.
static func apply_selection(base: CharacterAppearance, selection: Dictionary) -> CharacterAppearance:
	var out := base.copy()
	for slot in selection.keys():
		var item := find(str(selection[slot]))
		if item.is_empty():
			continue
		for part_id in (item.get("colors", {}) as Dictionary).keys():
			out.part_colors[part_id] = item["colors"][part_id]
		var socket: String = item.get("socket", "")
		var scene: String = item.get("scene", "")
		if socket != "" and scene != "":
			out.attachments[socket] = scene
	return out
