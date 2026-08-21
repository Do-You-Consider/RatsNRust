extends Node
## Autoload: identidad y apariencia LOCALES del jugador. Es lo único del
## proyecto que persiste en disco (user://profile.cfg).
##
## Guarda DOS apariencias, una por rol, porque el rol se sortea al empezar la
## partida: si guardáramos una sola, la mitad de las veces el jugador entraría
## con un personaje que no eligió.
##
## El nombre se autogenera la primera vez y queda fijo. No hay pantalla para
## cambiarlo (todavía); si querés uno nuevo, borrá user://profile.cfg o llamá
## a regenerate_name().

const SAVE_PATH := "user://profile.cfg"

const NAME_HEADS := [
	"RAT", "RUST", "SEWER", "NEON", "GREASE", "SCRAP", "ASH", "VOLT",
	"COPPER", "SMOKE", "IRON", "GLASS", "DUST", "WIRE", "TAR", "CINDER",
]
const NAME_TAILS := [
	"FINDER", "KING", "QUEEN", "RUNNER", "CRAWLER", "HUNTER", "GHOST",
	"BITER", "DIGGER", "WATCHER", "BREAKER", "SNITCH", "CHEWER", "PROWLER",
]

var player_name: String = ""

## rol -> CharacterAppearance ya resuelta (base del rol + selección aplicada)
var appearances: Dictionary = {}

## rol -> { slot(int): item_id(String) } -- lo que el jugador eligió en el
## menú de apariencia. Se guarda esto y no los colores finales: el día que una
## pieza cambie de color, todos los jugadores la ven actualizada.
var selections: Dictionary = {}


func _ready() -> void:
	load_profile()


func regenerate_name() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	player_name = "%s_%s" % [
		NAME_HEADS[rng.randi() % NAME_HEADS.size()],
		NAME_TAILS[rng.randi() % NAME_TAILS.size()],
	]
	return player_name


func get_appearance(role: int) -> CharacterAppearance:
	if not appearances.has(role):
		appearances[role] = CharacterAppearance.default_for_role(role)
	return appearances[role]


func get_selection(role: int) -> Dictionary:
	if not selections.has(role):
		selections[role] = {}
	return selections[role]


## Elegir una pieza recalcula la apariencia entera desde la base del rol: así
## des-elegir una pieza no deja restos de la anterior pintados encima.
func set_slot(role: int, slot: int, item_id: String) -> void:
	var sel: Dictionary = get_selection(role)
	if item_id == CosmeticCatalog.NONE_ID:
		sel.erase(slot)
	else:
		sel[slot] = item_id
	appearances[role] = CosmeticCatalog.apply_selection(
		CharacterAppearance.default_for_role(role), sel)


func appearance_dicts() -> Dictionary:
	return {
		GameState.Role.HIDER: get_appearance(GameState.Role.HIDER).to_dict(),
		GameState.Role.SEEKER: get_appearance(GameState.Role.SEEKER).to_dict(),
	}


# ------------------------------------------------------------ persistencia

func load_profile() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)

	player_name = str(cfg.get_value("identity", "name", "")) if err == OK else ""
	if player_name.strip_edges().is_empty():
		regenerate_name()

	selections.clear()
	appearances.clear()
	for role in [GameState.Role.HIDER, GameState.Role.SEEKER]:
		var raw: Dictionary = {}
		if err == OK:
			raw = cfg.get_value("appearance", str(role), {})
		# Las claves vuelven del ConfigFile como String; los slots son int.
		var sel: Dictionary = {}
		for k in raw.keys():
			sel[int(k)] = str(raw[k])
		selections[role] = sel
		appearances[role] = CosmeticCatalog.apply_selection(
			CharacterAppearance.default_for_role(role), sel)

	if err != OK:
		save_profile()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "name", player_name)
	for role in selections.keys():
		var flat: Dictionary = {}
		for slot in (selections[role] as Dictionary).keys():
			flat[str(slot)] = selections[role][slot]
		cfg.set_value("appearance", str(role), flat)
	cfg.save(SAVE_PATH)
