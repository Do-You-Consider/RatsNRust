extends Node3D
class_name MapGenerator
## =============================================================================
## WAREHOUSE RAVE -- NAVE INDUSTRIAL ABANDONADA DE 4 PLANTAS
## =============================================================================
## Reescritura completa del mapa. La idea: una warehouse de ladrillo tomada por
## una rave clandestina. TODO lo jugable pasa en planta baja; los 3 niveles de
## arriba son pura ambientación (pasarelas, barandas, siluetas mirando hacia
## abajo, cerchas del techo) visibles desde el atrio central.
##
## PLANTA BAJA (66m x 66m, grid fijo de 9 zonas de 22m):
##
##   [ TALLER      ] ── [ DEPÓSITO CARGA ] ── [ CHILL ROOM NE ]
##         │                    │                     │
##   [ BAR & LOUNGE ] ── [ PISTA + DJ SET ] ── [ SALA CALDERAS ]
##         │                (ATRIO 18m)               │
##   [ BAÑOS        ] ── [ ENTRADA/CARGA  ] ── [ CHILL ROOM SE ]
##
## VERTICALIDAD -- LA SEPARACIÓN PLANTA BAJA / PRIMER PISO:
## Antes el techo jugable (4.5m) ERA la losa del primer nivel decorativo, así
## que desde la pista el primer piso se leía como "el borde del techo" y no
## como otra planta. Ahora hay tres cosas separándolos:
##
##   y = 6.50  techo jugable (losa con colisión, cubre TODO el anillo)
##   y = 6.85  arranca la FAJA: viga de hormigón + cartel de la fábrica +
##             tira de LEDs rojos, todo a la vista desde la pista
##   y = 8.25  piso del nivel 1 decorativo, RETRANQUEADO 2.2m respecto del
##             borde del atrio -- queda un voladizo con sombra profunda
##             debajo, que es lo que hace legible "hay otro piso allá arriba"
##
## Sobre el retranqueo queda una cornisa de 2.2m a la altura del techo
## jugable: ahí va el anillo de truss con los cabezales y los PAR, o sea que
## el límite entre "el club" y "la fábrica muerta" está marcado por luz.
##
## - La pista de baile central es un atrio abierto hasta las cerchas (~21m).
## - Escalera derrumbada en la entrada (bloqueada con escombros + reja +
##   colisión invisible): nadie sube ni con glitches.
##
## Iluminación: punto medio techno-oscuro / neón -- base opresiva con strobe
## blanco y rojo profundo en la pista, acentos magenta (DJ), cian (bar) y
## violeta (chill rooms). Arriba, penumbra con acentos rojos sucios y niebla
## volumétrica más densa (FogVolume): dos mundos visualmente distintos.
##
## TODO el show está atado a UN reloj de BPM (ver BEAT/BAR/PHRASE): piso LED,
## strobe, cabezales, lásers, pantalla y cañones de CO2 caen en el mismo
## tiempo. Antes cada efecto tenía su período primo y la pista parecía
## "iluminada de fábrica" en vez de tener un show.
##
## Contrato con Game.gd (idéntico al mapa anterior):
##   generate(seed) / hider_spawn_points / seeker_spawn_point / club_music
## Determinista con la seed: todos los peers construyen el mismo mapa.
## =============================================================================

@export var room_size: float = 22.0 # lado de cada zona del grid 3x3

## Arrastrá acá el .ogg/.mp3 que quieras que suene desde la cabina del DJ
## (audio 3D posicional: fuerte en la pista, se apaga en las zonas vecinas).
## Si lo cargás, además alimenta el analizador de espectro: los graves reales
## del tema manejan el wash del escenario y el brillo de la pantalla LED.
@export var club_music: AudioStream

# --- Alturas de la nave -------------------------------------------------------
const PLAY_H := 6.5        # techo de las zonas jugables perimetrales
const SLAB_T := 0.35       # espesor de losa de cada nivel
const BAND_H := 1.4        # faja/parapeto entre el techo jugable y el nivel 1
const LEVEL1_Y := PLAY_H + SLAB_T + BAND_H     # 8.25 -- piso del nivel 1 deco
const LEVEL_H := 4.5       # alto de cada nivel decorativo
const DECO_LEVELS := 3     # niveles no jugables sobre la planta baja
const BALCONY_SETBACK := 2.2 # cuánto se retira el balcón del borde del atrio
const ROOF_Y := LEVEL1_Y + LEVEL_H * DECO_LEVELS # 21.75 -- arranque del techo
const WALL_H := ROOF_Y + 0.5                   # muros exteriores hasta el techo

## Los faroles se colgaban del techo jugable con un cable calculado para 4.5m.
## Al subir el techo a 6.5 todos quedaban 2m más arriba de lo diseñado, así
## que el cable se estira exactamente lo que subió el techo.
const CEILING_RISE := PLAY_H - 4.5

## Aunque las lámparas quedan a la misma altura que antes, la sala creció un
## 44% en volumen y ahora hay niebla volumétrica comiéndose la luz a
## distancia: con las energías originales las salas perimetrales quedaban
## negras. Estos dos factores se aplican a los faroles y tubos del perímetro
## (NO al rig del club, que se calibra aparte).
const ZONE_LIGHT_BOOST := 1.75
const ZONE_RANGE_BOOST := 1.35

# --- Reloj del club (A1) -----------------------------------------------------
# Todo lo que late en el mapa usa estos tres valores. Cambiar BPM cambia el
# show entero de una, sin tocar un solo tween.
const BPM := 138.0
const BEAT := 60.0 / BPM      # 0.4348 s -- el pulso
const BAR := BEAT * 4.0       # 1.739 s  -- el compás
const PHRASE := BAR * 8.0     # 13.91 s  -- la frase: acá cae el drop

# --- Caras interiores de los muros, en coordenadas LOCALES de zona -----------
# Todo prop "montado en pared" tiene que apoyarse en estas caras. El muro
# exterior es de ladrillo de 0.6 centrado en el borde del edificio (±33), así
# que su cara interior cae en ±10.7 locales; los tabiques interiores son de
# 0.3 y su cara cae en ±10.85. Clavar 10.1/10.3 "a ojo" dejaba carteles,
# espejos y tableros flotando hasta 0.7m en el aire.
const FACE_EXT := 10.7     # cara interior del muro exterior de ladrillo
const FACE_BASE := 10.575  # cara del zócalo de hormigón (solo hasta y = 1.2)
const FACE_PART := 10.85   # cara interior de un tabique de 0.3

var rng := RandomNumberGenerator.new()

var hider_spawn_points: Array[Vector3] = []
var seeker_spawn_point: Vector3 = Vector3.ZERO

# Tweens de efectos (strobe, parpadeos): hay que matarlos al regenerar para
# que no queden apuntando a luces liberadas de la partida anterior.
var _fx_tweens: Array[Tween] = []

# --- Paleta de materiales -----------------------------------------------------
var mat_concrete_floor: StandardMaterial3D
var mat_concrete_wall: StandardMaterial3D
var mat_brick: StandardMaterial3D
var mat_tile_floor: StandardMaterial3D
var mat_tile_wall: StandardMaterial3D
var mat_wood_floor: StandardMaterial3D
var mat_rust_metal: StandardMaterial3D
var mat_dark_steel: StandardMaterial3D
var mat_grate: StandardMaterial3D
var mat_aged_wood: StandardMaterial3D
var mat_leather_brown: StandardMaterial3D
var mat_pipe_industrial: StandardMaterial3D
var mat_hazard_mark: StandardMaterial3D
var mat_rubble: StandardMaterial3D
var mat_fabric_red: StandardMaterial3D
var mat_mattress: StandardMaterial3D
var mat_shrinkwrap: StandardMaterial3D
var mat_silhouette: StandardMaterial3D
var mat_mirror: StandardMaterial3D
var mat_rubber_black: StandardMaterial3D
var mat_paint_worn: StandardMaterial3D

var mat_neon_magenta: StandardMaterial3D
var mat_neon_cyan: StandardMaterial3D
var mat_neon_violet: StandardMaterial3D
var mat_neon_red_dim: StandardMaterial3D
var mat_led_warm: StandardMaterial3D
var mat_moon_glass: StandardMaterial3D
var mat_fire_orange: StandardMaterial3D
var mat_crt_phosphor: StandardMaterial3D
var mat_exit_green: StandardMaterial3D
var mat_bulb_pale: StandardMaterial3D
var mat_laser_green: StandardMaterial3D

# --- Materiales nuevos de esta pasada ---------------------------------------
var mat_grey_dust: StandardMaterial3D   # clutter de los niveles de arriba (D5)
var mat_stage_black: StandardMaterial3D # tarima y frentes de escenario
var mat_screen_off: StandardMaterial3D  # marco/fondo muerto de la pantalla LED
var mat_pvc_strip: StandardMaterial3D   # cortina de tiras del depósito
var mat_cobweb: StandardMaterial3D      # telarañas de los rincones
var mat_water: StandardMaterial3D       # charcos (rugosidad baja: refleja)
var mat_sign_paint: StandardMaterial3D  # cartel viejo de la fábrica
var mat_fur_dark: StandardMaterial3D    # ratas
var mat_bird_dark: StandardMaterial3D   # palomas de las cerchas
var mat_co2_white: StandardMaterial3D   # boquillas y cuerpo de los cañones

# --- Estado del show ----------------------------------------------------------
# El analizador de espectro solo existe si hay club_music cargado. Las luces y
# materiales "reactivos" NO se tweenean: los maneja _process a partir de los
# graves, así que tienen que estar separados de los que van por reloj de BPM.
var _analyzer: AudioEffectSpectrumAnalyzerInstance = null
var _bass: float = 0.0
var _reactive_lights: Array[Light3D] = []
var _reactive_light_base: PackedFloat32Array = PackedFloat32Array()
var _reactive_mats: Array[StandardMaterial3D] = []
var _reactive_mat_base: PackedFloat32Array = PackedFloat32Array()

## Superficies procedurales cacheadas (se generan una vez por proceso).
var _surf: Dictionary = {}


func _init() -> void:
	_init_palette()


func _matte(albedo: Color, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	return BuildKit.matte(albedo, rough, metallic)


func _emissive(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	return BuildKit.emissive(albedo, emission, energy)


func _init_palette() -> void:
	mat_concrete_floor = _matte(Color(0.08, 0.075, 0.07), 0.95)
	mat_concrete_wall = _matte(Color(0.15, 0.135, 0.12), 0.9)
	mat_brick = _matte(Color(0.19, 0.085, 0.06), 0.92)
	mat_tile_floor = _matte(Color(0.09, 0.15, 0.13), 0.45)
	mat_tile_wall = _matte(Color(0.12, 0.22, 0.19), 0.4)
	mat_wood_floor = _matte(Color(0.14, 0.09, 0.05), 0.85)
	mat_rust_metal = _matte(Color(0.32, 0.16, 0.08), 0.55, 0.8)
	mat_dark_steel = _matte(Color(0.20, 0.21, 0.23), 0.35, 0.9)
	mat_grate = _matte(Color(0.13, 0.14, 0.15), 0.5, 0.85)
	mat_aged_wood = _matte(Color(0.22, 0.12, 0.06), 0.85)
	mat_leather_brown = _matte(Color(0.14, 0.07, 0.04), 0.7)
	mat_pipe_industrial = _matte(Color(0.60, 0.40, 0.08), 0.4, 0.7)
	mat_hazard_mark = _matte(Color(0.55, 0.45, 0.08), 0.65, 0.4)
	mat_rubble = _matte(Color(0.30, 0.28, 0.26), 0.98)
	mat_fabric_red = _matte(Color(0.22, 0.05, 0.07), 0.95)
	mat_mattress = _matte(Color(0.42, 0.38, 0.30), 0.95)
	mat_shrinkwrap = _matte(Color(0.55, 0.58, 0.60), 0.3)

	# Siluetas de las pasarelas: negro casi puro y SIN sombreado, para que se
	# lean como recortes contra el resplandor rojo aunque la luz cambie.
	mat_silhouette = StandardMaterial3D.new()
	mat_silhouette.albedo_color = Color(0.015, 0.012, 0.02)
	mat_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_mirror = _matte(Color(0.85, 0.85, 0.9), 0.05, 1.0)
	mat_rubber_black = _matte(Color(0.05, 0.05, 0.055), 0.95)
	mat_paint_worn = _matte(Color(0.28, 0.30, 0.31), 0.8)

	mat_neon_magenta = _emissive(Color(1.0, 0.15, 0.55), Color(1.0, 0.1, 0.55), 2.6)
	mat_neon_cyan = _emissive(Color(0.15, 0.85, 0.95), Color(0.1, 0.8, 0.95), 2.4)
	mat_neon_violet = _emissive(Color(0.6, 0.2, 1.0), Color(0.55, 0.15, 1.0), 2.2)
	mat_neon_red_dim = _emissive(Color(0.7, 0.08, 0.06), Color(0.9, 0.1, 0.08), 1.1)
	mat_led_warm = _emissive(Color(1.0, 0.7, 0.3), Color(1.0, 0.65, 0.25), 1.8)
	mat_moon_glass = _emissive(Color(0.5, 0.58, 0.7), Color(0.55, 0.65, 0.85), 0.8)
	mat_fire_orange = _emissive(Color(1.0, 0.3, 0.05), Color(1.0, 0.35, 0.08), 3.5)
	mat_crt_phosphor = _emissive(Color(0.1, 0.45, 0.2), Color(0.15, 0.75, 0.3), 1.4)
	mat_exit_green = _emissive(Color(0.15, 0.8, 0.3), Color(0.1, 0.9, 0.3), 1.8)
	mat_bulb_pale = _emissive(Color(0.9, 0.88, 0.92), Color(0.92, 0.9, 0.95), 2.2)
	mat_laser_green = _emissive(Color(0.2, 1.0, 0.3), Color(0.15, 1.0, 0.25), 3.0)

	# --- Materiales nuevos ---------------------------------------------------
	# El clutter de los niveles de arriba va en gris polvo, no en los colores
	# de la planta baja: es la mitad del truco de "arriba es otro mundo" (D5).
	mat_grey_dust = _matte(Color(0.19, 0.185, 0.175), 0.95)
	mat_stage_black = _matte(Color(0.035, 0.035, 0.04), 0.85)
	mat_screen_off = _matte(Color(0.018, 0.018, 0.022), 0.55)
	mat_sign_paint = _matte(Color(0.34, 0.31, 0.26), 0.9)
	mat_fur_dark = _matte(Color(0.09, 0.075, 0.065), 0.95)
	mat_bird_dark = _matte(Color(0.13, 0.125, 0.13), 0.9)
	mat_co2_white = _matte(Color(0.62, 0.63, 0.66), 0.35, 0.4)

	# Charco: casi negro pero espejado. El brillo lo hace la rugosidad, no el
	# color -- un charco "gris claro" se lee como una mancha de pintura.
	mat_water = _matte(Color(0.02, 0.03, 0.04), 0.04, 0.35)

	# Cortina de tiras de PVC y telarañas: translúcidas, sin sombreado duro.
	mat_pvc_strip = BuildKit.glow_alpha(Color(0.62, 0.66, 0.62), 0.05, 0.30)
	mat_cobweb = BuildKit.glow_alpha(Color(0.55, 0.55, 0.58), 0.02, 0.13)

	_apply_surfaces()


## Texturas procedurales (ProcTextures) sobre la paleta. Triplanar en espacio
## MUNDO: dos cajas distintas con el mismo material continúan el patrón entre
## sí, que es lo único que hace que un muro armado con 6 primitivas no se vea
## como 6 primitivas.
##
## Los patrones con color propio (ladrillo, azulejo, óxido) pisan el
## albedo_color con un tint casi neutro; los que son sólo mugre gris se
## multiplican sobre el color original y ahí no se toca el tint.
func _apply_surfaces() -> void:
	if _surf.is_empty():
		_surf = {
			"brick": ProcTextures.brick(),
			"concrete": ProcTextures.concrete(),
			"planks": ProcTextures.planks(),
			"tiles": ProcTextures.tiles(),
			"plate": ProcTextures.plate(),
			"rust": ProcTextures.rust(),
			"grate": ProcTextures.grate(),
			"grunge": ProcTextures.grunge(),
		}

	# Ladrillo: 1 tile = 2.4m => ladrillos de ~60cm. Grande a propósito, la
	# nave es de 66m y con ladrillo "real" de 25cm el patrón hace moiré.
	ProcTextures.apply(mat_brick, _surf["brick"], 2.4, 1.5, 0.6, Color(0.62, 0.6, 0.6))
	ProcTextures.apply(mat_concrete_wall, _surf["concrete"], 3.2, 0.9, 0.5, Color(0.22, 0.205, 0.19))
	# El piso NO usa la textura de muro: sus lineas de encofrado, proyectadas
	# por triplanar sobre el plano horizontal, pintaban el piso entero a rayas
	# paralelas cada 80cm. Va mugre moteada, que es lo que tiene un piso.
	ProcTextures.apply(mat_concrete_floor, _surf["grunge"], 3.4, 0.55, 0.5, Color(0.155, 0.146, 0.138))
	ProcTextures.apply(mat_tile_floor, _surf["tiles"], 2.0, 1.1, 0.7, Color(0.66, 0.68, 0.66))
	ProcTextures.apply(mat_tile_wall, _surf["tiles"], 1.6, 1.1, 0.7, Color(0.78, 0.82, 0.80))
	# La textura de tablas es oscura de por sí (madera quemada por el uso), así
	# que el tint va bien arriba de 1.0: si no, el piso del bar queda negro.
	ProcTextures.apply(mat_wood_floor, _surf["planks"], 2.6, 1.0, 0.55, Color(1.25, 1.18, 1.08))
	ProcTextures.apply(mat_aged_wood, _surf["planks"], 1.4, 0.9, 0.5, Color(1.35, 1.28, 1.18))
	ProcTextures.apply(mat_rust_metal, _surf["rust"], 1.8, 1.2, 0.7, Color(0.75, 0.72, 0.70))
	ProcTextures.apply(mat_pipe_industrial, _surf["rust"], 1.2, 0.8, 0.5, Color(1.05, 0.95, 0.55))
	ProcTextures.apply(mat_grate, _surf["grate"], 1.2, 1.4, 0.4, Color(0.85, 0.87, 0.90))
	ProcTextures.apply(mat_dark_steel, _surf["plate"], 1.6, 0.7, 0.45, Color(0.85, 0.87, 0.92))
	ProcTextures.apply(mat_hazard_mark, _surf["plate"], 1.0, 0.6, 0.4, Color(1.10, 0.95, 0.28))
	ProcTextures.apply(mat_stage_black, _surf["plate"], 1.4, 0.5, 0.4, Color(0.22, 0.22, 0.26))

	# Estos no llevan patrón propio: sólo mugre encima de su color de siempre.
	for m in [mat_rubble, mat_paint_worn, mat_leather_brown, mat_fabric_red,
			mat_mattress, mat_rubber_black, mat_grey_dust, mat_sign_paint]:
		ProcTextures.apply(m, _surf["grunge"], 2.2, 0.4, 0.5)


# =============================================================================
# LAYOUT FIJO -- la arquitectura vertical necesita el atrio en el centro, así
# que el edificio es siempre el mismo; la seed randomiza el "desgaste": qué
# pasos del anillo perimetral están tapiados, escombros, cables colgando,
# posiciones de las siluetas y el orden de los spawns.
# =============================================================================

## Escondite sugerido dentro de cada zona (offset local al centro de la zona).
const ZONE_HIDE_OFFSETS := {
	# El escondite de la pista se mudó: donde estaba (9.2, -9.2) ahora está la
	# tarima del DJ. Nuevo lugar: el rincón suroeste del atrio, detrás del
	# muro de flight cases (el "backstage" improvisado). Ahí no da ninguna de
	# las 4 bocas del atrio, así que hay que meterse para ver adentro.
	"dance": Vector3(-9.3, 0.8, 8.6),    # backstage de road cases, esquina SO
	"bar": Vector3(1.7, 0.8, -5.3),      # el pasillo detrás de la barra
	"banos": Vector3(-1.4, 0.8, 8.2),    # último cubículo (el de la puerta caída)
	"chill_ne": Vector3(0.0, 0.8, -4.35),# detrás del respaldo del sofá grande
	"chill_se": Vector3(5.0, 0.8, 7.6),  # rincón de los colchones
	"boiler": Vector3(-8.6, 0.8, 8.6),   # detrás de la pila de barriles
	"cargo": Vector3(2.0, 0.8, -2.0),    # el pasillo entre estanterías
	"workshop": Vector3(9.0, 0.8, 9.0),  # detrás de los tambores de aceite
}

var _zone_centers: Dictionary = {}


func generate(seed_value: int = -1) -> void:
	for t in _fx_tweens:
		if t != null and t.is_valid():
			t.kill()
	_fx_tweens.clear()
	for c in get_children():
		c.queue_free()
	hider_spawn_points.clear()
	seeker_spawn_point = Vector3.ZERO
	_zone_centers.clear()
	# Las listas reactivas apuntan a nodos/materiales de la partida anterior:
	# si no se limpian, _process escribe sobre luces ya liberadas.
	_analyzer = null
	_bass = 0.0
	_reactive_lights.clear()
	_reactive_light_base.clear()
	_reactive_mats.clear()
	_reactive_mat_base.clear()

	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value

	var r := room_size
	_zone_centers = {
		"dance": Vector3.ZERO,
		"bar": Vector3(-r, 0, 0),
		"boiler": Vector3(r, 0, 0),
		"cargo": Vector3(0, 0, -r),
		"entrance": Vector3(0, 0, r),
		"workshop": Vector3(-r, 0, -r),
		"chill_ne": Vector3(r, 0, -r),
		"banos": Vector3(-r, 0, r),
		"chill_se": Vector3(r, 0, r),
	}

	_build_shell()
	_build_ground_partitions()
	_build_perimeter_ceiling()
	_build_fascia_band()
	_build_upper_levels()
	_build_roof_structure()
	_build_silhouettes()

	_build_dance_atrium(_zone_centers["dance"])
	_build_bar(_zone_centers["bar"])
	_build_boiler(_zone_centers["boiler"])
	_build_cargo(_zone_centers["cargo"])
	_build_entrance(_zone_centers["entrance"])
	_build_workshop(_zone_centers["workshop"])
	_build_chill_room(_zone_centers["chill_ne"], 0)
	_build_banos(_zone_centers["banos"])
	_build_chill_room(_zone_centers["chill_se"], 1)

	# Capas transversales: van DESPUÉS de las zonas porque se apoyan en la
	# geometría ya construida (calcos sobre muros, bichos contra los zócalos,
	# basura suelta encima del piso definitivo de cada sector).
	_build_zone_fill()
	_build_atmosphere()
	_build_decal_pass()
	_build_critters()
	_build_zone_ambience()
	_build_loose_debris()

	_setup_spawns()


# =============================================================================
# CASCARÓN: piso, muros exteriores de ladrillo (altura completa), techo
# =============================================================================

func _build_shell() -> void:
	var total := room_size * 3.0
	var half := total * 0.5

	# Piso monolítico de hormigón
	_create_box(Vector3(0, -0.25, 0), Vector3(total + 4.0, 0.5, total + 4.0), mat_concrete_floor)

	# Muros exteriores de ladrillo hasta el techo (sellado, sin salidas)
	var thick := 0.6
	_create_box(Vector3(0, WALL_H * 0.5, -half), Vector3(total + thick * 2.0, WALL_H, thick), mat_brick)
	_create_box(Vector3(0, WALL_H * 0.5, half), Vector3(total + thick * 2.0, WALL_H, thick), mat_brick)
	_create_box(Vector3(-half, WALL_H * 0.5, 0), Vector3(thick, WALL_H, total + thick * 2.0), mat_brick)
	_create_box(Vector3(half, WALL_H * 0.5, 0), Vector3(thick, WALL_H, total + thick * 2.0), mat_brick)

	# Zócalo de hormigón en la base de los muros (planta baja)
	for side in [-1, 1]:
		_create_box(Vector3(0, 0.6, side * (half - 0.35)), Vector3(total, 1.2, 0.15), mat_concrete_wall, false)
		_create_box(Vector3(side * (half - 0.35), 0.6, 0), Vector3(0.15, 1.2, total), mat_concrete_wall, false)

	# Techo (nadie llega, sin colisión)
	_create_box(Vector3(0, WALL_H + 0.25, 0), Vector3(total + 4.0, 0.5, total + 4.0), _matte(Color(0.06, 0.055, 0.06), 0.95), false)

	_build_wall_articulation(half)
	_build_windows(half)
	_build_service_runs(half)


## C2 -- ARTICULACIÓN DE LOS MUROS.
## Un muro de 66m x 22m de ladrillo liso se lee como un telón pintado por más
## textura que tenga. Lo que lo rompe es la sombra propia: pilastras verticales
## y cornisas horizontales que proyectan sombra sobre el propio muro.
##
## Las pilastras arrancan ARRIBA del techo jugable a propósito: abajo hay
## decenas de props apoyados exactamente en FACE_EXT y cualquier resalto de
## 0.3m se los comería. Arriba, en cambio, hay 15m de ladrillo pelado que es
## justo lo que se ve desde la pista al mirar hacia el vacío del atrio.
func _build_wall_articulation(half: float) -> void:
	var total := room_size * 3.0
	var base_y := PLAY_H + SLAB_T
	var top_y := WALL_H
	var face := half - 0.32

	# Pilastras cada 5.5m, salteando las esquinas
	var step := 5.5
	var n := int(total / step)
	for i in range(1, n):
		var t := -total * 0.5 + float(i) * step
		for s in [-1.0, 1.0]:
			_create_box(Vector3(t, (base_y + top_y) * 0.5, s * face), Vector3(0.9, top_y - base_y, 0.26), mat_brick, false)
			_create_box(Vector3(s * face, (base_y + top_y) * 0.5, t), Vector3(0.26, top_y - base_y, 0.9), mat_brick, false)

	# Cornisas: una por nivel decorativo + la de coronamiento. Marcan las
	# plantas desde adentro del atrio aun con las losas retranqueadas.
	var courses: Array[float] = [LEVEL1_Y - 0.55]
	for i in DECO_LEVELS:
		courses.append(LEVEL1_Y + LEVEL_H * float(i + 1) - 0.55)
	courses.append(WALL_H - 0.9)
	for cy in courses:
		if cy < base_y or cy > WALL_H - 0.2:
			continue
		for s in [-1.0, 1.0]:
			_create_box(Vector3(0, cy, s * (half - 0.24)), Vector3(total, 0.3, 0.34), mat_concrete_wall, false)
			_create_box(Vector3(s * (half - 0.24), cy, 0), Vector3(0.34, 0.3, total), mat_concrete_wall, false)

	# Columnas de esquina de hormigón, de piso a techo: cierran el volumen.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_create_box(Vector3(sx * (half - 0.45), WALL_H * 0.5, sz * (half - 0.45)), Vector3(1.1, WALL_H, 1.1), mat_concrete_wall, false)


## Tres bandas de ventanales rotos en vez de una: a la altura de la planta
## baja (luz de luna entrando a las salas perimetrales), a la del nivel 1 y
## arriba de todo. Es lo que le da escala vertical al edificio desde adentro.
func _build_windows(half: float) -> void:
	var face := half - 0.05
	var bands := [PLAY_H - 1.5, LEVEL1_Y + 2.2, ROOF_Y - 2.4]
	for band in bands.size():
		var win_y: float = bands[band]
		# Cada banda corrida respecto de la anterior: alineadas verticalmente
		# se leen como una grilla de oficina, no como una nave abandonada.
		var shift: float = float(band) * 3.5
		for wall_side in [-1, 1]:
			for offset in [-room_size * 0.7 + shift, 0.0 + shift, room_size * 0.7 + shift]:
				_create_broken_window(Vector3(offset, win_y, wall_side * face), true)
				_create_broken_window(Vector3(wall_side * face, win_y, offset), false)

	# Un par de haces de luna entrando por los ventanales de la planta baja:
	# atraviesan las salas perimetrales en diagonal y dan un punto de fuga.
	for shaft in [Vector3(-room_size, PLAY_H - 1.5, -half + 0.4), Vector3(room_size * 0.3, PLAY_H - 1.5, half - 0.4)]:
		var inward := 1.0 if shaft.z < 0.0 else -1.0
		var beam := SpotLight3D.new()
		beam.light_color = Color(0.55, 0.66, 0.95)
		beam.light_energy = 1.6
		beam.spot_range = 16.0
		beam.spot_angle = 26.0
		beam.spot_attenuation = 1.4
		add_child(beam)
		beam.look_at_from_position(shaft, shaft + Vector3(0.15, -0.75, inward), Vector3.UP)


## Bandejas portacables, caños y cajas de luz corriendo por los muros de la
## planta baja a 5.4m: arriba de todos los props, abajo del techo. Es la capa
## que hace que la nave se vea "instalada" y no modelada.
func _build_service_runs(half: float) -> void:
	var total := room_size * 3.0
	var run_y := PLAY_H - 1.1
	var face := half - 0.42

	for s in [-1.0, 1.0]:
		# Bandeja horizontal + su ala inferior (perfil en L, no una tira plana)
		_create_box(Vector3(0, run_y, s * face), Vector3(total - 1.0, 0.16, 0.34), mat_grate, false)
		_create_box(Vector3(0, run_y - 0.11, s * face - s * 0.14), Vector3(total - 1.0, 0.06, 0.06), mat_dark_steel, false)
		_create_box(Vector3(s * face, run_y, 0), Vector3(0.34, 0.16, total - 1.0), mat_grate, false)
		_create_box(Vector3(s * face - s * 0.14, run_y - 0.11, 0), Vector3(0.06, 0.06, total - 1.0), mat_dark_steel, false)

		# Ménsulas cada 4m y un caño grueso corriendo por debajo
		var m := 4.0
		var count := int(total / m)
		for i in range(1, count):
			var t := -total * 0.5 + float(i) * m
			_create_box(Vector3(t, run_y - 0.05, s * (face + 0.12)), Vector3(0.08, 0.3, 0.28), mat_rust_metal, false)
			_create_box(Vector3(s * (face + 0.12), run_y - 0.05, t), Vector3(0.28, 0.3, 0.08), mat_rust_metal, false)
		_create_box(Vector3(0, run_y - 0.55, s * (face + 0.06)), Vector3(total - 1.0, 0.17, 0.17), mat_pipe_industrial, false)
		_create_box(Vector3(s * (face + 0.06), run_y - 0.55, 0), Vector3(0.17, 0.17, total - 1.0), mat_pipe_industrial, false)

	# Cajas de luz con su bajada de caño, en puntos fijos de cada muro
	var boxes := [
		Vector3(-room_size, 0, -half + 0.5), Vector3(room_size * 0.5, 0, -half + 0.5),
		Vector3(-room_size * 0.4, 0, half - 0.5), Vector3(room_size, 0, half - 0.5),
		Vector3(-half + 0.5, 0, room_size * 0.6), Vector3(half - 0.5, 0, -room_size * 0.6),
	]
	for b in boxes:
		var on_z: bool = absf(b.z) > absf(b.x)
		var depth := Vector3(0, 0, 0.22) if on_z else Vector3(0.22, 0, 0)
		var inward: float = -signf(b.z) if on_z else -signf(b.x)
		var d: Vector3 = depth * inward
		var size := Vector3(0.7, 0.95, 0.24) if on_z else Vector3(0.24, 0.95, 0.7)
		_create_box(b + Vector3(0, 2.3, 0) + d, size, mat_hazard_mark, false)
		_create_box(b + Vector3(0, 2.55, 0) + d * 1.9, Vector3(0.09, 0.09, 0.09), mat_neon_red_dim, false)
		_create_beam(b + Vector3(0, 2.78, 0) + d, b + Vector3(0, PLAY_H - 1.2, 0) + d, 0.045, mat_dark_steel)

	# Matafuegos con su cartel: el detalle que todo galpón tiene y ningún
	# mapa procedural pone.
	var ext := [
		Vector3(-room_size * 1.3, 0, -half + 0.42), Vector3(room_size * 1.2, 0, half - 0.42),
		Vector3(-half + 0.42, 0, -room_size * 1.2), Vector3(half - 0.42, 0, room_size * 1.25),
	]
	for e in ext:
		var on_z: bool = absf(e.z) > absf(e.x)
		var inward: float = -signf(e.z) if on_z else -signf(e.x)
		var d := (Vector3(0, 0, 0.2) if on_z else Vector3(0.2, 0, 0)) * inward
		_create_cylinder(e + Vector3(0, 1.15, 0) + d, 0.11, 0.6, _matte(Color(0.42, 0.05, 0.04), 0.6), false)
		_create_cylinder(e + Vector3(0, 1.5, 0) + d, 0.04, 0.12, mat_dark_steel, false)
		var sign_size := Vector3(0.36, 0.36, 0.03) if on_z else Vector3(0.03, 0.36, 0.36)
		_create_box(e + Vector3(0, 2.1, 0) + d * 0.55, sign_size, _emissive(Color(0.5, 0.05, 0.05), Color(0.8, 0.08, 0.06), 0.7), false)


func _create_broken_window(pos: Vector3, on_z_wall: bool) -> void:
	var pane := Vector3(2.4, 1.7, 0.08) if on_z_wall else Vector3(0.08, 1.7, 2.4)
	_create_box(pos, pane, mat_moon_glass, false)
	if on_z_wall:
		_create_box(pos, Vector3(2.6, 0.09, 0.1), mat_dark_steel, false)
		_create_box(pos, Vector3(0.09, 1.85, 0.1), mat_dark_steel, false)
		if rng.randf() < 0.5: # travesaño caído -- vidrio "roto"
			_create_box(pos, Vector3(0.08, 2.1, 0.1), mat_dark_steel, false, Vector3(0, 0, 0.55))
	else:
		_create_box(pos, Vector3(0.1, 0.09, 2.6), mat_dark_steel, false)
		_create_box(pos, Vector3(0.1, 1.85, 0.09), mat_dark_steel, false)
		if rng.randf() < 0.5:
			_create_box(pos, Vector3(0.1, 2.1, 0.08), mat_dark_steel, false, Vector3(0.55, 0, 0))


# =============================================================================
# TABIQUES DE PLANTA BAJA
# =============================================================================

func _build_ground_partitions() -> void:
	var hr := room_size * 0.5 # 11 -- media zona = borde del atrio
	var r := room_size

	# --- Aberturas del atrio hacia las 4 zonas cardinales ---
	# Norte (depósito): corrida hacia el oeste para no chocar con la cabina DJ
	_build_wall_with_opening(Vector3(0, 0, -hr), r, PLAY_H, 5.0, 3.4, -6.5, 0.3, false, mat_concrete_wall)
	# Sur (entrada): la boca principal del club, bien ancha
	_build_wall_with_opening(Vector3(0, 0, hr), r, PLAY_H, 7.0, 3.6, 0.0, 0.3, false, mat_concrete_wall)
	# Oeste (bar) y Este (calderas)
	_build_wall_with_opening(Vector3(-hr, 0, 0), r, PLAY_H, 5.0, 3.2, 0.0, 0.3, true, mat_concrete_wall)
	_build_wall_with_opening(Vector3(hr, 0, 0), r, PLAY_H, 5.0, 3.2, 0.0, 0.3, true, mat_concrete_wall)

	# Tira de neón perimetral del atrio, montada arriba de las aberturas
	# (el "trim" arquitectónico del club: magenta y cian alternados)
	var trim_y := PLAY_H - 0.12
	_create_box(Vector3(0, trim_y, -hr + 0.22), Vector3(r - 1.0, 0.07, 0.05), mat_neon_magenta, false)
	_create_box(Vector3(0, trim_y, hr - 0.22), Vector3(r - 1.0, 0.07, 0.05), mat_neon_cyan, false)
	_create_box(Vector3(-hr + 0.22, trim_y, 0), Vector3(0.05, 0.07, r - 1.0), mat_neon_cyan, false)
	_create_box(Vector3(hr - 0.22, trim_y, 0), Vector3(0.05, 0.07, r - 1.0), mat_neon_magenta, false)

	# --- Anillo perimetral: pasos entre zonas vecinas. La seed tapia 2 de los
	# 8 pasos, así el recorrido cambia partida a partida sin tocar el edificio.
	var ring_passages := [
		{"c": Vector3(-hr, 0, -r), "v": true},  # taller | depósito
		{"c": Vector3(hr, 0, -r), "v": true},   # depósito | chill NE
		{"c": Vector3(r, 0, -hr), "v": false},  # chill NE | calderas
		{"c": Vector3(r, 0, hr), "v": false},   # calderas | chill SE
		{"c": Vector3(hr, 0, r), "v": true},    # chill SE | entrada
		{"c": Vector3(-hr, 0, r), "v": true},   # entrada | baños
		{"c": Vector3(-r, 0, hr), "v": false},  # baños | bar
		{"c": Vector3(-r, 0, -hr), "v": false}, # bar | taller
	]
	var order := range(ring_passages.size())
	_seeded_shuffle(order)
	var sealed := {order[0]: true, order[1]: true}
	for i in ring_passages.size():
		var p: Dictionary = ring_passages[i]
		if sealed.has(i):
			_build_wall_with_opening(p["c"], r, PLAY_H, 0.0, 0.0, 0.0, 0.3, p["v"], mat_concrete_wall, false)
		else:
			_build_wall_with_opening(p["c"], r, PLAY_H, 3.0, 2.8, 0.0, 0.3, p["v"], mat_concrete_wall)


## Muro de un tramo de zona: macizo (is_open=false) o con vano descentrable
## (off = corrimiento del centro del vano a lo largo del muro) y jambas de
## acero oxidado.
func _build_wall_with_opening(center: Vector3, length: float, height: float, ow: float, oh: float, off: float, thick: float, vertical: bool, mat: StandardMaterial3D, is_open: bool = true) -> void:
	if not is_open or ow <= 0.0:
		var solid_size := Vector3(thick, height, length) if vertical else Vector3(length, height, thick)
		_create_box(center + Vector3(0, height * 0.5, 0), solid_size, mat)
		return

	var a_len := (length * 0.5) + (off - ow * 0.5) # tramo del lado negativo
	var b_len := (length * 0.5) - (off + ow * 0.5) # tramo del lado positivo
	var a_center := -length * 0.5 + a_len * 0.5
	var b_center := length * 0.5 - b_len * 0.5
	var lintel_h := height - oh

	if vertical:
		if a_len > 0.05:
			_create_box(center + Vector3(0, height * 0.5, a_center), Vector3(thick, height, a_len), mat)
		if b_len > 0.05:
			_create_box(center + Vector3(0, height * 0.5, b_center), Vector3(thick, height, b_len), mat)
		_create_box(center + Vector3(0, oh + lintel_h * 0.5, off), Vector3(thick, lintel_h, ow), mat)
		_create_box(center + Vector3(0, oh * 0.5, off - ow * 0.5), Vector3(thick * 1.25, oh, 0.1), mat_rust_metal)
		_create_box(center + Vector3(0, oh * 0.5, off + ow * 0.5), Vector3(thick * 1.25, oh, 0.1), mat_rust_metal)
		_create_box(center + Vector3(0, oh, off), Vector3(thick * 1.25, 0.1, ow), mat_rust_metal)
	else:
		if a_len > 0.05:
			_create_box(center + Vector3(a_center, height * 0.5, 0), Vector3(a_len, height, thick), mat)
		if b_len > 0.05:
			_create_box(center + Vector3(b_center, height * 0.5, 0), Vector3(b_len, height, thick), mat)
		_create_box(center + Vector3(off, oh + lintel_h * 0.5, 0), Vector3(ow, lintel_h, thick), mat)
		_create_box(center + Vector3(off - ow * 0.5, oh * 0.5, 0), Vector3(0.1, oh, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(off + ow * 0.5, oh * 0.5, 0), Vector3(0.1, oh, thick * 1.25), mat_rust_metal)
		_create_box(center + Vector3(off, oh, 0), Vector3(ow, 0.1, thick * 1.25), mat_rust_metal)


## El techo de las zonas perimetrales. YA NO es la losa del nivel 1: cubre el
## anillo completo (setback 0) y es el "cielo" real del área jugable. Sobre
## él queda una cornisa de BALCONY_SETBACK metros a la vista desde el atrio,
## que es donde se monta el anillo de truss.
func _build_perimeter_ceiling() -> void:
	_build_ring_slab(PLAY_H, true, 0.0)


## Losa en anillo (deja el hueco del atrio en el centro) a la altura level_y.
## `setback` retira el borde interior respecto del borde del atrio: es lo que
## convierte el balcón en un voladizo con sombra debajo en vez de un canto
## pegado al vacío.
func _build_ring_slab(level_y: float, with_collision: bool, setback: float) -> void:
	var outer := room_size * 1.5              # 33 -- borde del edificio
	var inner := room_size * 0.5 + setback    # borde interior de la losa
	var strip := outer - inner
	var center := (outer + inner) * 0.5
	var y := level_y + SLAB_T * 0.5
	var slab_mat := mat_concrete_floor if with_collision else mat_grate

	# Tiras norte y sur (ancho completo) + tiras este y oeste (entre ambas)
	_create_box(Vector3(0, y, -center), Vector3(outer * 2.0, SLAB_T, strip), slab_mat, with_collision)
	_create_box(Vector3(0, y, center), Vector3(outer * 2.0, SLAB_T, strip), slab_mat, with_collision)
	_create_box(Vector3(-center, y, 0), Vector3(strip, SLAB_T, inner * 2.0), slab_mat, with_collision)
	_create_box(Vector3(center, y, 0), Vector3(strip, SLAB_T, inner * 2.0), slab_mat, with_collision)

	if with_collision:
		return # el techo jugable no lleva canto luminoso: lo tapa la faja

	# Canto de losa hacia el atrio con tira emisiva roja tenue: es lo que hace
	# legibles los niveles desde la pista, aun en penumbra.
	var span := inner * 2.0 + 0.4
	_create_box(Vector3(0, y, -inner - 0.05), Vector3(span, 0.08, 0.05), mat_neon_red_dim, false)
	_create_box(Vector3(0, y, inner + 0.05), Vector3(span, 0.08, 0.05), mat_neon_red_dim, false)
	_create_box(Vector3(-inner - 0.05, y, 0), Vector3(0.05, 0.08, span), mat_neon_red_dim, false)
	_create_box(Vector3(inner + 0.05, y, 0), Vector3(0.05, 0.08, span), mat_neon_red_dim, false)


# =============================================================================
# D3 -- LA FAJA: lo que separa la planta baja del primer piso
# =============================================================================
## Un parapeto de hormigón de 1.4m apoyado sobre el canto del techo jugable,
## con la cara mirando a la pista. Sobre esa cara van el cartel viejo de la
## fábrica con su marquesina de bombitas, una tira de LED roja que late en el
## compás y las telas colgando hacia el vacío.
##
## Es lo que hace que desde la pista mirés para arriba y veas TRES cosas
## distintas -- techo, faja, balcón retranqueado -- en vez de un solo canto.
func _build_fascia_band() -> void:
	var hr := room_size * 0.5
	var base := PLAY_H + SLAB_T
	var top := LEVEL1_Y
	var mid := (base + top) * 0.5
	var depth := 0.55
	var span := room_size + 0.6

	for s in [-1.0, 1.0]:
		# Parapeto: cara interior a ras del borde del atrio
		_create_box(Vector3(0, mid, s * (hr + depth * 0.5)), Vector3(span, BAND_H, depth), mat_concrete_wall, false)
		_create_box(Vector3(s * (hr + depth * 0.5), mid, 0), Vector3(depth, BAND_H, span), mat_concrete_wall, false)
		# Goterón: una moldura que sobresale abajo. Sin esto la faja es una
		# franja plana y la sombra no la despega del techo.
		_create_box(Vector3(0, base + 0.14, s * (hr - 0.03)), Vector3(span, 0.28, 0.2), mat_dark_steel, false)
		_create_box(Vector3(s * (hr - 0.03), base + 0.14, 0), Vector3(0.2, 0.28, span), mat_dark_steel, false)
		# Tira de LED roja al pie de la faja (late en el compás, ver abajo)
		_create_box(Vector3(0, base + 0.34, s * (hr - 0.07)), Vector3(span - 0.6, 0.1, 0.06), mat_neon_red_dim, false)
		_create_box(Vector3(s * (hr - 0.07), base + 0.34, 0), Vector3(0.06, 0.1, span - 0.6), mat_neon_red_dim, false)

	# Ménsulas de acero cada 3m sujetando la faja al techo
	for i in range(-3, 4):
		var t := float(i) * 3.0
		for s in [-1.0, 1.0]:
			_create_box(Vector3(t, base + 0.5, s * (hr + depth + 0.1)), Vector3(0.14, 0.9, 0.3), mat_rust_metal, false)
			_create_box(Vector3(s * (hr + depth + 0.1), base + 0.5, t), Vector3(0.3, 0.9, 0.14), mat_rust_metal, false)

	_build_factory_sign(Vector3(0, mid + 0.05, -hr - 0.06), true)
	_build_fascia_drapes(hr, base)

	# Baño de luz sobre la faja. SIN esto todo este trabajo es invisible: el
	# atrio no tiene ninguna luz a esa altura y desde la pista se veía una
	# franja negra entre el techo del club y el balcón. Es, literalmente, lo
	# que hace legible la separación entre plantas.
	for i in 3:
		var t: float = -6.5 + float(i) * 6.5
		for s: float in [-1.0, 1.0]:
			# Alcance corto a propósito: con 13m el baño de la faja llegaba hasta
			# las cerchas y pintaba de rojo uniforme los 21m del atrio entero.
			_add_omni(Vector3(t, mid + 0.3, s * (hr - 1.3)), Color(0.95, 0.42, 0.28), 0.9, 8.5)
			_add_omni(Vector3(s * (hr - 1.3), mid + 0.3, t), Color(0.95, 0.42, 0.28), 0.9, 8.5)
			# Y la lámpara que "produce" ese baño, apoyada en el goterón
			_create_cylinder(Vector3(t, base + 0.42, s * (hr - 0.42)), 0.09, 0.2, mat_dark_steel, false)
			_create_cylinder(Vector3(s * (hr - 0.42), base + 0.42, t), 0.09, 0.2, mat_dark_steel, false)

	# El LED de la faja late en el compás: un solo material compartido por las
	# 8 tiras, así son 8 mallas y UN tween.
	var tw := create_tween().set_loops()
	tw.tween_property(mat_neon_red_dim, "emission_energy_multiplier", 2.2, BEAT * 0.25)
	tw.tween_property(mat_neon_red_dim, "emission_energy_multiplier", 0.75, BEAT * 0.75)
	tw.tween_property(mat_neon_red_dim, "emission_energy_multiplier", 1.5, BEAT * 0.25)
	tw.tween_property(mat_neon_red_dim, "emission_energy_multiplier", 0.75, BEAT * 0.75)
	_fx_tweens.append(tw)


## Cartel de chapa de la fábrica original, con marquesina de bombitas que
## corren en el compás. Media docena están fundidas -- el club se apropió del
## cartel, no lo arregló.
func _build_factory_sign(pos: Vector3, on_z_wall: bool) -> void:
	var w := 9.5
	var h := 1.05
	var panel := Vector3(w, h, 0.12) if on_z_wall else Vector3(0.12, h, w)
	_create_box(pos, panel, mat_sign_paint, false)
	# Marco y perfiles: el cartel tiene que tener canto, no ser una calcomanía
	var edge_v := Vector3(w + 0.3, 0.1, 0.2) if on_z_wall else Vector3(0.2, 0.1, w + 0.3)
	_create_box(pos + Vector3(0, h * 0.5, 0), edge_v, mat_rust_metal, false)
	_create_box(pos - Vector3(0, h * 0.5, 0), edge_v, mat_rust_metal, false)

	# Marquesina: 22 bombitas alrededor, en 4 materiales que corren en cadena
	var chase: Array[StandardMaterial3D] = []
	for i in 4:
		chase.append(_emissive(Color(1.0, 0.85, 0.55), Color(1.0, 0.8, 0.45), 1.4))
	var bulbs := 22
	for b in bulbs:
		var t: float = lerpf(-w * 0.5 + 0.35, w * 0.5 - 0.35, float(b) / float(bulbs - 1))
		for sy in [-1.0, 1.0]:
			# 1 de cada 7 está quemada
			var dead: bool = (b * 3 + int(sy)) % 7 == 0
			var m: StandardMaterial3D = mat_screen_off if dead else chase[b % 4]
			var bp := pos + (Vector3(t, sy * (h * 0.5 + 0.13), -0.16) if on_z_wall else Vector3(-0.16, sy * (h * 0.5 + 0.13), t))
			_create_sphere(bp, 0.075, m)

	for i in chase.size():
		var tw := create_tween().set_loops()
		for step in 4:
			var target := 3.6 if step == i else 0.35
			tw.tween_property(chase[i], "emission_energy_multiplier", target, BEAT)
		_fx_tweens.append(tw)

	# Resplandor cálido del cartel sobre la faja
	_add_omni(pos + Vector3(0, 0.1, 1.1 if on_z_wall else 0.0), Color(1.0, 0.72, 0.35), 1.1, 9.0)


## Telas de gira colgando de la faja hacia el vacío del atrio. Se mecen muy
## despacio: es movimiento periférico gratis que llena los 26m de aire vacío
## que quedan entre la pista y el balcón.
func _build_fascia_drapes(hr: float, base: float) -> void:
	var specs := [
		[Vector3(-6.5, 0, -hr + 0.2), 2.6, 4.2, mat_fabric_red, 0.0],
		[Vector3(7.2, 0, -hr + 0.2), 2.2, 3.4, mat_neon_violet, 0.0],
		[Vector3(hr - 0.2, 0, -4.0), 2.4, 3.8, mat_fabric_red, PI * 0.5],
		[Vector3(-hr + 0.2, 0, 5.5), 2.8, 4.6, mat_leather_brown, PI * 0.5],
		[Vector3(2.0, 0, hr - 0.2), 3.0, 3.6, mat_fabric_red, 0.0],
	]
	for sp in specs:
		var p: Vector3 = sp[0]
		var w: float = sp[1]
		var h: float = sp[2]
		var mat: StandardMaterial3D = sp[3]
		var yaw: float = sp[4]
		var pivot := Node3D.new()
		pivot.position = Vector3(p.x, base + 0.05, p.z)
		pivot.rotation.y = yaw
		add_child(pivot)
		# La tela cuelga del pivote: rotar el pivote la hamaca desde el borde
		# superior, que es como cuelga una tela de verdad.
		_add_mesh_box(pivot, Vector3(0, -h * 0.5, 0), Vector3(w, h, 0.05), mat)
		_add_mesh_box(pivot, Vector3(0, -0.06, 0), Vector3(w + 0.2, 0.12, 0.12), mat_rust_metal)
		var tw := create_tween().set_loops()
		var amp := rng.randf_range(0.025, 0.05)
		var period := BAR * rng.randf_range(3.0, 5.0)
		tw.tween_property(pivot, "rotation:x", amp, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(pivot, "rotation:x", -amp, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fx_tweens.append(tw)


# =============================================================================
# NIVELES DECORATIVOS (NO JUGABLES) + PASARELAS + COLUMNAS
# =============================================================================

func _build_upper_levels() -> void:
	var hr := room_size * 0.5
	var inner := hr + BALCONY_SETBACK # borde de los balcones retranqueados

	# Columnas del atrio: de piso a techo, en las 4 esquinas del vacío. Con el
	# balcón retirado 2.2m quedan EXENTAS dentro del atrio, no embutidas en el
	# canto de la losa, y suben 22m limpios. Abajo son cajón de acero (a la
	# altura de la gente se toca y se ve macizo), arriba reticuladas.
	for cx in [-hr, hr]:
		for cz in [-hr, hr]:
			_create_box(Vector3(cx, PLAY_H * 0.5, cz), Vector3(0.62, PLAY_H, 0.62), mat_dark_steel)
			_create_truss(Vector3(cx, PLAY_H, cz), Vector3(cx, WALL_H, cz), 0.34, 0.05, 10)
			# Capitel donde apoya la faja
			_create_box(Vector3(cx, PLAY_H + 0.12, cz), Vector3(0.95, 0.24, 0.95), mat_dark_steel, false)

	# Sofito del voladizo: viguetas bajo cada balcón, mirando al atrio. Es lo
	# que se ve al levantar la vista desde la pista y lo que hace leer el
	# retranqueo como voladizo en vez de como un agujero más grande.
	_build_balcony_soffits(hr, inner)

	for i in range(1, DECO_LEVELS + 1):
		var level_y := LEVEL1_Y + float(i - 1) * LEVEL_H
		var rail_base := level_y + SLAB_T

		_build_ring_slab(level_y, false, BALCONY_SETBACK)

		# Barandas hacia el atrio en los 4 bordes (sobre el canto retranqueado)
		_create_railing(Vector3(0, rail_base, -inner - 0.2), inner * 2.0, true)
		_create_railing(Vector3(0, rail_base, inner + 0.2), inner * 2.0, true)
		_create_railing(Vector3(-inner - 0.2, rail_base, 0), inner * 2.0, false)
		_create_railing(Vector3(inner + 0.2, rail_base, 0), inner * 2.0, false)

		# Puertas negras de oficinas muertas sobre los muros exteriores
		# (huecos oscuros sin sombreado: profundidad falsa, costo cero)
		var face := room_size * 1.5 - 0.5
		for offset in [-room_size, 0.0, room_size]:
			var jitter := rng.randf_range(-3.0, 3.0)
			_create_box(Vector3(offset + jitter, rail_base + 1.2, -face), Vector3(1.3, 2.4, 0.15), mat_silhouette, false)
			_create_box(Vector3(offset - jitter, rail_base + 1.2, face), Vector3(1.3, 2.4, 0.15), mat_silhouette, false)

		# Una oficina de cada tres tiene todavía un tubo agonizando adentro:
		# un rectángulo apenas encendido a 20m se lee como "hay algo ahí".
		for lit in 2:
			var lx := rng.randf_range(-room_size * 1.2, room_size * 1.2)
			var side := -face if rng.randf() < 0.5 else face
			_create_box(Vector3(lx, rail_base + 1.3, side), Vector3(1.15, 2.1, 0.06), _emissive(Color(0.16, 0.2, 0.2), Color(0.35, 0.5, 0.5), 0.5), false)
			_add_omni(Vector3(lx, rail_base + 1.4, side * 0.93), Color(0.4, 0.6, 0.62), 0.5, 5.5)

		# Clutter abandonado cerca del borde: pilas de cajas, barriles, pallets
		# y bobinas de cable. Sin colisión (nadie sube), así que sale gratis y
		# es lo que le saca la sensación de "losa vacía" a los niveles.
		# TODO en gris polvo (D5): arriba no hay colores del club.
		for k in 9:
			var edge := rng.randi_range(0, 3)
			var along := rng.randf_range(-inner + 2.0, inner - 2.0)
			var depth := rng.randf_range(1.0, 5.5)
			var p := Vector3.ZERO
			match edge:
				0: p = Vector3(along, rail_base, -inner - depth)
				1: p = Vector3(along, rail_base, inner + depth)
				2: p = Vector3(-inner - depth, rail_base, along)
				3: p = Vector3(inner + depth, rail_base, along)
			var roll := rng.randf()
			if roll < 0.34:
				for c in rng.randi_range(1, 3):
					var s := 1.15 - float(c) * 0.18
					_create_box(p + Vector3(rng.randf_range(-0.1, 0.1), 0.28 + float(c) * 0.52, rng.randf_range(-0.1, 0.1)), Vector3(s, 0.52, s), mat_grey_dust, false, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
			elif roll < 0.55:
				_create_cylinder(p + Vector3(0, 0.45, 0), 0.36, 0.9, mat_grey_dust, false)
			elif roll < 0.72:
				# Pallets tirados de canto contra la baranda
				_create_box(p + Vector3(0, 0.6, 0), Vector3(1.2, 1.15, 0.12), mat_grey_dust, false, Vector3(0, rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.2)))
			elif roll < 0.86:
				# Bobina de cable de obra
				_create_cylinder(p + Vector3(0, 0.55, 0), 0.55, 0.5, mat_grey_dust, false, Vector3(0, 0, PI * 0.5))
			else:
				# Escritorio de oficina muerta, dado vuelta
				_create_box(p + Vector3(0, 0.45, 0), Vector3(1.5, 0.08, 0.8), mat_grey_dust, false, Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, PI), 0.35))
				_create_box(p + Vector3(0.3, 0.12, 0.2), Vector3(0.6, 0.24, 0.5), mat_grey_dust, false)

		# LEDs rojos de "equipo muerto" en las columnas, uno por nivel
		for cx in [-hr, hr]:
			for cz in [-hr, hr]:
				_create_box(Vector3(cx * 0.94, rail_base + 1.6, cz * 0.94), Vector3(0.1, 0.1, 0.1), mat_neon_red_dim, false)

		# Penumbra roja del nivel. Antes eran dos omnis en r = 11, o sea DENTRO
		# del vacío del atrio: con el balcón retranqueado a 13.2 no llegaban a
		# tocar la losa y los pisos de arriba se veían como una franja negra.
		# Ahora la luz está sobre el balcón, y hay una rasante contra la
		# baranda para que el canto y las siluetas se recorten desde la pista.
		var deep := inner + 4.5
		for s: float in [-1.0, 1.0]:
			_add_omni(Vector3(0.0, rail_base + 2.2, s * deep), Color(0.9, 0.14, 0.11), 0.55, 16.0)
			_add_omni(Vector3(s * deep, rail_base + 2.2, 0.0), Color(0.9, 0.14, 0.11), 0.55, 16.0)
			# Rasante contra la baranda: es lo que la hace legible a 25m
			_add_omni(Vector3(rng.randf_range(-8.0, 8.0), rail_base + 0.5, s * (inner + 1.2)), Color(1.0, 0.3, 0.15), 0.7, 9.0)
			_add_omni(Vector3(s * (inner + 1.2), rail_base + 0.5, rng.randf_range(-8.0, 8.0)), Color(1.0, 0.3, 0.15), 0.7, 9.0)

	# --- Pasarelas cruzando el vacío del atrio ---
	# Nivel 1: cruza de norte a sur pegada al este; nivel 2 de oeste a este;
	# nivel 3 de norte a sur. Tres cruces a alturas distintas convierten el
	# vacío en una caja de estructura en vez de un tubo hueco.
	var span := inner * 2.0
	_build_catwalk(Vector3(6.5, LEVEL1_Y, 0), false, span)
	_build_catwalk(Vector3(0, LEVEL1_Y + LEVEL_H, 3.0), true, span)
	_build_catwalk(Vector3(-3.0, LEVEL1_Y + LEVEL_H * 2.0, 0), false, span)

	# Cables sueltos colgando del techo hacia el vacío. Se esquivan las franjas
	# de las pasarelas: si no, los cables las atraviesan y se ven "clavados".
	for k in 9:
		var cx := rng.randf_range(-11.5, 11.5)
		var cz := rng.randf_range(-11.5, 11.5)
		if absf(cx + 3.0) < 1.7:
			cx += 1.7 if cx > -3.0 else -1.7
		if absf(cx - 6.5) < 1.7:
			cx += 1.7 if cx > 6.5 else -1.7
		var drop := rng.randf_range(3.0, 9.0)
		_create_beam(Vector3(cx, ROOF_Y, cz), Vector3(cx + rng.randf_range(-0.5, 0.5), ROOF_Y - drop, cz), 0.025, mat_dark_steel)
		if rng.randf() < 0.4:
			# Portalámparas muerto en la punta del cable
			_create_cylinder(Vector3(cx, ROOF_Y - drop - 0.08, cz), 0.06, 0.16, mat_dark_steel, false)

	_build_upper_haze(inner)


## Viguetas bajo el voladizo de cada balcón. Solo la franja que mira al atrio
## (el resto no lo ve nadie): 2.4m de profundidad de viguetas cruzadas.
func _build_balcony_soffits(hr: float, inner: float) -> void:
	for i in range(1, DECO_LEVELS + 1):
		var y := LEVEL1_Y + float(i - 1) * LEVEL_H - 0.16
		var depth := BALCONY_SETBACK + 1.6
		var mid := inner + depth * 0.5
		for s in [-1.0, 1.0]:
			# Viga madre paralela al borde
			_create_box(Vector3(0, y, s * (inner + 0.35)), Vector3(inner * 2.0, 0.3, 0.24), mat_dark_steel, false)
			_create_box(Vector3(s * (inner + 0.35), y, 0), Vector3(0.24, 0.3, inner * 2.0), mat_dark_steel, false)
			# Viguetas perpendiculares cada 1.6m
			var n := int(inner * 2.0 / 1.6)
			for k in range(0, n + 1):
				var t: float = -inner + float(k) * 1.6
				_create_box(Vector3(t, y, s * mid), Vector3(0.14, 0.26, depth), mat_dark_steel, false)
				_create_box(Vector3(s * mid, y, t), Vector3(depth, 0.26, 0.14), mat_dark_steel, false)

			# Sólo el voladizo del NIVEL 1 se ilumina, y en rojo sucio: es el
			# que se ve desde la pista y el que tiene que leerse como techo de
			# otra planta. Los de arriba quedan a oscuras a propósito (D5).
			if i == 1:
				for k in 3:
					var t2: float = -7.0 + float(k) * 7.0
					_add_omni(Vector3(t2, y - 0.5, s * (inner + 0.9)), Color(0.85, 0.16, 0.12), 0.6, 11.0)
					_add_omni(Vector3(s * (inner + 0.9), y - 0.5, t2), Color(0.85, 0.16, 0.12), 0.6, 11.0)


## D5 -- ARRIBA ES OTRO MUNDO.
## Una caja de niebla volumétrica sobre los niveles decorativos, más densa y
## más gris que la del club. Desde la pista, los pisos de arriba se ven
## "lejos" y lavados; desde arriba, la pista se ve como un pozo de color.
func _build_upper_haze(inner: float) -> void:
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var height := ROOF_Y - LEVEL1_Y + 2.0
	fog.size = Vector3(room_size * 3.0, height, room_size * 3.0)
	var fm := FogMaterial.new()
	fm.density = 0.055
	fm.albedo = Color(0.34, 0.30, 0.31)
	fm.emission = Color(0.10, 0.018, 0.015)
	fm.height_falloff = 0.12
	fm.edge_fade = 0.35
	fog.material = fm
	add_child(fog)
	fog.position = Vector3(0, LEVEL1_Y + height * 0.5 - 1.0, 0)

	# Y una segunda, angosta y roja, justo sobre la faja: subraya el corte
	# entre las dos plantas cuando mirás hacia arriba desde la pista.
	var lip := FogVolume.new()
	lip.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	lip.size = Vector3(inner * 2.0 + 4.0, 2.6, inner * 2.0 + 4.0)
	var lm := FogMaterial.new()
	lm.density = 0.09
	lm.albedo = Color(0.5, 0.22, 0.22)
	lm.emission = Color(0.22, 0.03, 0.02)
	lm.edge_fade = 0.5
	lip.material = lm
	add_child(lip)
	lip.position = Vector3(0, LEVEL1_Y - 0.4, 0)


## Pasarela de rejilla con barandas a ambos lados y tensores al techo.
func _build_catwalk(center: Vector3, along_x: bool, length: float) -> void:
	var deck_y := center.y + SLAB_T - 0.075
	var deck_size := Vector3(length, 0.15, 1.8) if along_x else Vector3(1.8, 0.15, length)
	_create_box(Vector3(center.x, deck_y, center.z), deck_size, mat_grate, false)
	# Larguero lateral: el canto de la pasarela vista de perfil desde abajo
	for s in [-1.0, 1.0]:
		var beam_size := Vector3(length, 0.24, 0.1) if along_x else Vector3(0.1, 0.24, length)
		var off := Vector3(0, -0.16, s * 0.9) if along_x else Vector3(s * 0.9, -0.16, 0)
		_create_box(Vector3(center.x, deck_y, center.z) + off, beam_size, mat_dark_steel, false)

	var rail_base := center.y + SLAB_T
	if along_x:
		_create_railing(Vector3(center.x, rail_base, center.z - 0.85), length, true)
		_create_railing(Vector3(center.x, rail_base, center.z + 0.85), length, true)
		for hx in [-length * 0.3, length * 0.3]:
			_create_beam(Vector3(center.x + hx, deck_y, center.z), Vector3(center.x + hx, ROOF_Y, center.z), 0.05, mat_dark_steel)
	else:
		_create_railing(Vector3(center.x - 0.85, rail_base, center.z), length, false)
		_create_railing(Vector3(center.x + 0.85, rail_base, center.z), length, false)
		for hz in [-length * 0.3, length * 0.3]:
			_create_beam(Vector3(center.x, deck_y, center.z + hz), Vector3(center.x, ROOF_Y, center.z + hz), 0.05, mat_dark_steel)


## Baranda industrial: 2 largueros + parantes cada ~3.6m. Sin colisión (nadie
## llega ahí arriba).
func _create_railing(center: Vector3, length: float, along_x: bool) -> void:
	# Zócalo de chapa al pie (rodapié): las barandas industriales lo llevan y
	# es lo que hace que la baranda no parezca dos palitos flotando.
	var kick_size := Vector3(length, 0.14, 0.04) if along_x else Vector3(0.04, 0.14, length)
	_create_box(center + Vector3(0, 0.09, 0), kick_size, mat_dark_steel, false)
	for rail_h in [0.55, 1.05]:
		var rail_size := Vector3(length, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, length)
		_create_box(center + Vector3(0, rail_h, 0), rail_size, mat_rust_metal, false)
	# Parantes cada ~1.9m: con 7 fijos, una baranda de 26m los dejaba a 4.4m
	# y se leía como una soga tendida.
	var posts := maxi(int(length / 1.9), 4)
	for p in posts + 1:
		var t: float = lerpf(-length * 0.5 + 0.2, length * 0.5 - 0.2, float(p) / float(posts))
		var post_pos := center + (Vector3(t, 0.525, 0) if along_x else Vector3(0, 0.525, t))
		_create_box(post_pos, Vector3(0.06, 1.05, 0.06), mat_rust_metal, false)


## Cercha / torre reticulada entre dos puntos: 4 cordones paralelos + celosía
## en zigzag en dos caras. De acá sale TODO el vocabulario estructural de la
## nave -- cerchas de techo, torres de columna y el truss del escenario --
## así que con una sola función el edificio y el rig del club se ven hechos
## por la misma gente, que es exactamente lo que pasa en un club okupa.
func _create_truss(a: Vector3, b: Vector3, radius: float, chord_r: float, segments: int) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.1:
		return
	var dir := d / length
	# Referencia perpendicular: con dir vertical, Vector3.UP no sirve.
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()

	for c in [u * radius + v * radius, u * radius - v * radius, -u * radius + v * radius, -u * radius - v * radius]:
		_create_beam(a + c, b + c, chord_r, mat_dark_steel)

	for s in segments:
		var p0 := a.lerp(b, float(s) / float(segments))
		var p1 := a.lerp(b, float(s + 1) / float(segments))
		for sv: float in [-1.0, 1.0]:
			var off := v * (radius * sv)
			var hi := u * radius
			var lo := -u * radius
			_create_beam(p0 + off + hi, p0 + off + lo, chord_r * 0.75, mat_dark_steel)
			# Diagonal alternada: la que le da el aspecto de celosía
			if s % 2 == 0:
				_create_beam(p0 + off + lo, p1 + off + hi, chord_r * 0.75, mat_dark_steel)
			else:
				_create_beam(p0 + off + hi, p1 + off + lo, chord_r * 0.75, mat_dark_steel)


# =============================================================================
# TECHO: CERCHAS + CLARABOYA ROTA
# =============================================================================

func _build_roof_structure() -> void:
	var total := room_size * 3.0 - 2.0
	var half := total * 0.5
	var chord_top := ROOF_Y - 0.35
	var chord_bot := ROOF_Y - 1.75

	# Cerchas principales de este a oeste, cada 8m: 5 en vez de 3 (con el
	# atrio de 26m de luz, tres cerchas dejaban 16m de techo desnudo).
	for tz in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_create_truss(Vector3(-half, (chord_top + chord_bot) * 0.5, tz), Vector3(half, (chord_top + chord_bot) * 0.5, tz), (chord_top - chord_bot) * 0.5, 0.11, 14)

	# Correas transversales apoyadas sobre las cerchas + contravientos en
	# cruz de San Andrés en los dos vanos centrales. Es la trama que hace
	# que el techo se lea como una nave y no como un plano oscuro.
	for px in range(-4, 5):
		var x := float(px) * 7.0
		_create_box(Vector3(x, chord_top + 0.22, 0), Vector3(0.14, 0.2, total), mat_dark_steel, false)
	for tz in [-12.0, -4.0, 4.0, 12.0]:
		_create_beam(Vector3(-14.0, chord_bot + 0.1, tz - 4.0), Vector3(14.0, chord_bot + 0.1, tz + 4.0), 0.05, mat_rust_metal)
		_create_beam(Vector3(-14.0, chord_bot + 0.1, tz + 4.0), Vector3(14.0, chord_bot + 0.1, tz - 4.0), 0.05, mat_rust_metal)

	# Claraboyas rotas: cuatro paños entre cerchas, "luz de luna" cayendo al
	# atrio. Con el atrio 4m más alto, los haces son mucho más largos.
	var panes := [Vector3(0, 0, -4.0), Vector3(0, 0, 4.0), Vector3(-9.0, 0, -12.0), Vector3(9.0, 0, 12.0)]
	for p in panes:
		_create_box(Vector3(p.x, ROOF_Y - 0.1, p.z), Vector3(9.0, 0.1, 3.2), mat_moon_glass, false)
		_create_box(Vector3(p.x, ROOF_Y - 0.15, p.z), Vector3(9.4, 0.12, 0.18), mat_dark_steel, false)
		# Perfiles del paño, dos de ellos vencidos
		for k in 4:
			var gx: float = p.x - 3.6 + float(k) * 2.4
			var tilt := 0.0 if k != 2 else 0.45
			_create_box(Vector3(gx, ROOF_Y - 0.18, p.z), Vector3(0.1, 0.1, 3.3), mat_dark_steel, false, Vector3(tilt, 0, 0))

	for sp in [Vector3(-3.5, 0, -4.0), Vector3(3.5, 0, 4.0), Vector3(-9.0, 0, -12.0), Vector3(9.0, 0, 12.0)]:
		var beam := SpotLight3D.new()
		beam.light_color = Color(0.6, 0.7, 0.95)
		beam.light_energy = 2.2
		beam.spot_range = ROOF_Y + 1.0
		beam.spot_angle = 12.0
		beam.spot_attenuation = 1.6
		beam.shadow_enabled = true
		add_child(beam)
		var beam_pos := Vector3(sp.x, ROOF_Y - 0.4, sp.z)
		beam.look_at_from_position(beam_pos, beam_pos + Vector3(0, -1, 0), Vector3(0, 0, -1))

	# Ventiladores extractores muertos en el techo, girando apenas con el
	# tiraje: movimiento lento allá arriba, que es donde el ojo descansa.
	for fp in [Vector3(-15.0, 0, 6.0), Vector3(14.0, 0, -7.0)]:
		var housing := Vector3(fp.x, ROOF_Y - 0.45, fp.z)
		_create_cylinder(housing, 1.0, 0.5, mat_rust_metal, false)
		_create_cylinder(housing + Vector3(0, -0.3, 0), 1.1, 0.1, mat_dark_steel, false)
		var fan := Node3D.new()
		fan.position = housing + Vector3(0, -0.32, 0)
		add_child(fan)
		for b in 4:
			_add_mesh_box(fan, Vector3(cos(TAU * float(b) / 4.0) * 0.5, 0, sin(TAU * float(b) / 4.0) * 0.5), Vector3(0.9, 0.03, 0.28), mat_dark_steel, Vector3(0, -TAU * float(b) / 4.0, 0.28))
		var tw := create_tween().set_loops()
		tw.tween_property(fan, "rotation:y", TAU, rng.randf_range(7.0, 11.0)).from(0.0)
		_fx_tweens.append(tw)


# =============================================================================
# SILUETAS -- figuras quietas en las barandas, mirando la rave desde arriba
# =============================================================================

func _build_silhouettes() -> void:
	var hr := room_size * 0.5
	# (nivel, borde 0=N 1=S 2=O 3=E) fijos; la posición sobre el borde la da la seed
	var spots := [
		[1, 0], [1, 3], [1, 1],
		[2, 2], [2, 1],
		[3, 0], [3, 2],
	]
	var inner := hr + BALCONY_SETBACK
	var rim_count := 0
	for s in spots:
		var level: int = s[0]
		var edge: int = s[1]
		var base_y := LEVEL1_Y + float(level - 1) * LEVEL_H + SLAB_T
		var along := rng.randf_range(-inner + 1.5, inner - 1.5)
		var pos := Vector3.ZERO
		var face := 0.0
		match edge:
			0:
				pos = Vector3(along, base_y, -inner - 0.65)
				face = PI
			1:
				pos = Vector3(along, base_y, inner + 0.65)
				face = 0.0
			2:
				pos = Vector3(-inner - 0.65, base_y, along)
				face = -PI * 0.5
			3:
				pos = Vector3(inner + 0.65, base_y, along)
				face = PI * 0.5
		_create_silhouette(pos, face)
		# Resplandor rojo de contraluz detrás de las figuras: sin esto son
		# invisibles contra la penumbra -- el contraluz es lo que las delata
		if rim_count < 4:
			var back := (Vector3(0, 0, -1.4) if edge == 0 else Vector3(0, 0, 1.4) if edge == 1 else Vector3(-1.4, 0, 0) if edge == 2 else Vector3(1.4, 0, 0))
			_add_omni(pos + back + Vector3(0, 1.6, 0), Color(0.95, 0.1, 0.08), 0.85, 5.0)
			rim_count += 1

	# Una figura más, parada en el medio de la pasarela del nivel 2
	_create_silhouette(Vector3(rng.randf_range(-5.0, 5.0), LEVEL1_Y + LEVEL_H + SLAB_T, 3.0 - 0.55), 0.0)


## Figura humana simplificada: torso apenas inclinado hacia adelante (apoyada
## en la baranda) + cabeza. Negro sin sombreado, sin colisión.
##
## B2 -- ahora cuelga de un pivote y se mueve: un balanceo mínimo en el
## compás (asiente con la música) más un giro lento de cabeza. Son las mismas
## tres cajas de siempre; lo único que cambió es que dejaron de ser cartón.
func _create_silhouette(base_pos: Vector3, face_y: float) -> void:
	var body := Node3D.new()
	body.position = base_pos
	add_child(body)
	_add_mesh_box(body, Vector3(0, 0.98, 0), Vector3(0.52, 1.28, 0.30), mat_silhouette, Vector3(0.12, face_y, 0))
	_add_mesh_box(body, Vector3(0, 0.35, 0), Vector3(0.4, 0.75, 0.26), mat_silhouette, Vector3(0, face_y, 0))
	# La cabeza cuelga de su propio pivote para poder girarla sin mover el
	# torso (y sin recalcular el offset del cuello a mano).
	var neck := Node3D.new()
	neck.position = Vector3(0, 1.63, 0)
	neck.rotation.y = face_y
	body.add_child(neck)
	_add_mesh_sphere(neck, Vector3(0, 0.13, 0.12), 0.13, mat_silhouette)

	# Cabeceo en el compás, con la fase corrida por figura: si asienten todas
	# juntas parecen un mecanismo, no gente mirando desde arriba.
	var phase := rng.randf_range(0.0, 1.0)
	var bob := create_tween().set_loops()
	bob.tween_interval(BEAT * phase)
	bob.tween_property(body, "position:y", base_pos.y + 0.05, BEAT * 0.45).set_trans(Tween.TRANS_SINE)
	bob.tween_property(body, "position:y", base_pos.y, BEAT * 0.55).set_trans(Tween.TRANS_SINE)
	bob.tween_property(body, "position:y", base_pos.y + 0.035, BEAT * 0.45).set_trans(Tween.TRANS_SINE)
	bob.tween_property(body, "position:y", base_pos.y, BEAT * 0.55).set_trans(Tween.TRANS_SINE)
	_fx_tweens.append(bob)

	# Giro de cabeza cada tantos compases: mira la pista, mira al costado.
	var look := create_tween().set_loops()
	var sweep := rng.randf_range(0.4, 0.85)
	look.tween_interval(BAR * rng.randf_range(1.0, 3.0))
	look.tween_property(neck, "rotation:y", face_y + sweep, BAR * 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	look.tween_interval(BAR * 2.0)
	look.tween_property(neck, "rotation:y", face_y - sweep * 0.6, BAR * 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	look.tween_interval(BAR)
	look.tween_property(neck, "rotation:y", face_y, BAR * 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(look)


# =============================================================================
# ZONA CENTRAL: PISTA DE BAILE + DJ SET (el atrio)
# =============================================================================

func _build_dance_atrium(pos: Vector3) -> void:
	var hr := room_size * 0.5

	# --- Piso LED estilo disco: 4 materiales COMPARTIDOS que pulsan en
	# secuencia (chase de 4 tiempos). Son 4 tweens en total para las 49
	# baldosas, y ahora el chase corre EN EL BEAT del club, no a 0.22s a ojo:
	# el piso y el strobe caen juntos, que es la mitad del efecto. ---
	# Baldosa de 1.4m, no de 2.2: con baldosas de dos metros el piso se lee
	# como una alfombra de damero de jardín de infantes en vez de un panel LED.
	var tile := 1.4
	var tiles := 11
	var span := tile * float(tiles)
	var start := -span * 0.5 + tile * 0.5
	var floor_z := 1.5 # corrido al sur: al norte ahora está la tarima del DJ
	var tile_colors := [
		Color(0.62, 0.06, 0.34), Color(0.10, 0.55, 0.64),
		Color(0.38, 0.10, 0.68), Color(0.62, 0.16, 0.09),
	]
	var tile_mats: Array[StandardMaterial3D] = []
	for ci in tile_colors.size():
		var c: Color = tile_colors[ci]
		# Albedo CASI NEGRO: el piso es un panel apagado que emite, no una
		# baldosa de color. Con albedo alto las 121 baldosas se veían todas
		# pintadas a la vez y el chase no se leía -- quedaba un damero de
		# jardín de infantes en vez de un piso LED.
		tile_mats.append(_emissive(c * 0.10, c, 0.3))
	for ix in tiles:
		for iz in tiles:
			var mi := (ix + iz) % tile_mats.size()
			_create_box(pos + Vector3(start + float(ix) * tile, 0.03, start + float(iz) * tile + floor_z), Vector3(tile - 0.09, 0.06, tile - 0.09), tile_mats[mi], false)
	# Marco de aluminio del piso: sin canto, las baldosas flotan sobre el
	# hormigón como una calcomanía.
	for s in [-1.0, 1.0]:
		_create_box(pos + Vector3(0, 0.045, floor_z + s * span * 0.5), Vector3(span + 0.24, 0.09, 0.12), mat_dark_steel, false)
		_create_box(pos + Vector3(s * span * 0.5, 0.045, floor_z), Vector3(0.12, 0.09, span + 0.24), mat_dark_steel, false)

	var floor_quads := [Vector3(-4.0, 0, -2.5), Vector3(4.0, 0, -2.5), Vector3(4.0, 0, 5.5), Vector3(-4.0, 0, 5.5)]
	for m in tile_mats.size():
		var ttw := create_tween().set_loops()
		# Omni tenue por cuadrante: sin esto el pulso del piso no baña a nadie
		# (la emisión sola no ilumina). Late en el mismo tiempo que su color.
		var quad_light := _add_omni(pos + floor_quads[m] + Vector3(0, 0.9, 0), tile_colors[m], 0.0, 9.5)
		var ltw := create_tween().set_loops()
		for step in tile_mats.size():
			# El apagado tiene que ser CASI CERO: con 0.22 las 121 baldosas se
			# veían encendidas todas a la vez y el chase no existía. Con 0.04,
			# en cada tiempo se prende una diagonal y el resto es panel negro.
			var target := 2.4 if step == m else 0.04
			var lit := 1.45 if step == m else 0.06
			ttw.tween_property(tile_mats[m], "emission_energy_multiplier", target, BEAT)
			ltw.tween_property(quad_light, "light_energy", lit, BEAT)
		_fx_tweens.append(ttw)
		_fx_tweens.append(ltw)

	_build_stage(pos)
	_build_rig(pos, hr)
	_build_backstage(pos)
	_build_atrium_filler(pos)

# =============================================================================
# A5 -- EL ESCENARIO: tarima, cabina, pantalla LED y torres de PA
# =============================================================================
## Antes la cabina estaba a nivel de piso contra el muro norte y no había
## ninguna jerarquía entre "el escenario" y "la pista": eran el mismo suelo.
## Ahora hay una tarima de 1.35m con escalones, faldón negro, zócalo de neón
## y valla de contención al frente. Todo lo de la cabina se apoya en STAGE_Y.
const STAGE_Y := 1.35
const STAGE_CX := 4.0
const STAGE_CZ := -8.35
const STAGE_W := 12.0
const STAGE_D := 4.7


func _build_stage(pos: Vector3) -> void:
	var west := STAGE_CX - STAGE_W * 0.5   # -2.0
	var front := STAGE_CZ + STAGE_D * 0.5  # -6.0

	# Tarima. La boca norte del atrio cae en x -9..-4, así que el escenario
	# arranca en x = -2 y no tapa el paso desde el depósito.
	_create_box(pos + Vector3(STAGE_CX, STAGE_Y * 0.5, STAGE_CZ), Vector3(STAGE_W, STAGE_Y, STAGE_D), mat_stage_black)
	_create_box(pos + Vector3(STAGE_CX, STAGE_Y + 0.03, STAGE_CZ), Vector3(STAGE_W + 0.2, 0.06, STAGE_D + 0.2), mat_dark_steel, false)
	# Faldón y zócalo de neón: es lo que hace que la tarima se lea desde el
	# fondo de la pista aunque el escenario esté a contraluz.
	_create_box(pos + Vector3(STAGE_CX, STAGE_Y * 0.5, front + 0.03), Vector3(STAGE_W, STAGE_Y - 0.2, 0.06), mat_stage_black, false)
	_create_box(pos + Vector3(STAGE_CX, 0.16, front + 0.06), Vector3(STAGE_W - 0.4, 0.14, 0.06), mat_neon_magenta, false)
	for s in [-1.0, 1.0]:
		_create_box(pos + Vector3(STAGE_CX + s * STAGE_W * 0.5, 0.16, STAGE_CZ), Vector3(0.06, 0.14, STAGE_D - 0.4), mat_neon_magenta, false)

	# Escalones al oeste
	_create_box(pos + Vector3(west - 0.45, 0.45, STAGE_CZ), Vector3(0.9, 0.9, 2.4), mat_stage_black)
	_create_box(pos + Vector3(west - 1.2, 0.225, STAGE_CZ), Vector3(0.6, 0.45, 2.4), mat_stage_black)
	for s in [-1.0, 1.0]:
		_create_cylinder(pos + Vector3(west - 0.8, STAGE_Y * 0.5 + 0.3, STAGE_CZ + s * 1.25), 0.04, 1.2, mat_rust_metal, false)
	_create_beam(pos + Vector3(west - 1.5, 1.35, STAGE_CZ - 1.25), pos + Vector3(west - 0.1, 1.75, STAGE_CZ - 1.25), 0.04, mat_rust_metal)

	# Valla de contención delante del escenario, con hueco en el medio
	for side: float in [-1.0, 1.0]:
		var bz := front + 1.6
		for i in 4:
			var bxp := STAGE_CX + side * (1.8 + float(i) * 1.35)
			_create_cylinder(pos + Vector3(bxp, 0.55, bz), 0.05, 1.1, mat_dark_steel)
			if i > 0:
				_create_beam(pos + Vector3(bxp, 1.02, bz), pos + Vector3(bxp - side * 1.35, 1.02, bz), 0.035, mat_rust_metal)
				_create_beam(pos + Vector3(bxp, 0.45, bz), pos + Vector3(bxp - side * 1.35, 0.45, bz), 0.03, mat_rust_metal)

	_build_dj_booth(pos)
	_build_led_wall(pos)
	_build_pa_stacks(pos)
	_build_stage_truss(pos)
	_build_co2_jets(pos, front)


## Cabina del DJ, ahora encima de la tarima.
func _build_dj_booth(pos: Vector3) -> void:
	var bx := STAGE_CX
	var bz := STAGE_CZ - 0.9
	var y := STAGE_Y

	_create_box(pos + Vector3(bx, y + 0.5, bz), Vector3(6.0, 1.0, 2.4), mat_dark_steel)
	_create_box(pos + Vector3(bx, y + 1.06, bz), Vector3(5.4, 0.12, 1.9), mat_rust_metal)
	# Bandejas + displays
	for dx in [-1.6, -0.55, 0.55, 1.6]:
		_create_box(pos + Vector3(bx + dx, y + 1.17, bz), Vector3(0.5, 0.1, 0.42), mat_dark_steel, false)
		_create_box(pos + Vector3(bx + dx, y + 1.23, bz + 0.14), Vector3(0.3, 0.03, 0.09), mat_neon_cyan, false)
		# Plato: el disco girando es de las pocas piezas del club que se mueven
		# a velocidad constante y no en el beat -- y por eso se nota.
		var deck := Node3D.new()
		deck.position = pos + Vector3(bx + dx, y + 1.23, bz - 0.06)
		add_child(deck)
		_add_mesh_cylinder(deck, Vector3.ZERO, 0.14, 0.02, mat_rubber_black)
		_add_mesh_box(deck, Vector3(0.09, 0.012, 0.0), Vector3(0.1, 0.012, 0.02), mat_bulb_pale)
		var dtw := create_tween().set_loops()
		dtw.tween_property(deck, "rotation:y", TAU, 1.8).from(0.0)
		_fx_tweens.append(dtw)
	# Mixer central, más alto
	_create_box(pos + Vector3(bx, y + 1.2, bz - 0.35), Vector3(0.95, 0.16, 0.55), mat_dark_steel, false)
	for f in 6:
		_create_box(pos + Vector3(bx - 0.36 + float(f) * 0.145, y + 1.3, bz - 0.35), Vector3(0.03, 0.05, 0.22), mat_neon_cyan, false)

	# Panel frontal magenta de la cabina (la cara que ve toda la pista)
	_create_box(pos + Vector3(bx, y + 0.55, bz + 1.26), Vector3(5.8, 0.85, 0.08), mat_neon_magenta, false)

	# Wash del escenario: NO se tweenea, lo maneja el analizador de espectro.
	var wash := _add_omni(pos + Vector3(bx, y + 2.6, bz + 0.6), Color(1.0, 0.15, 0.6), 1.5, 12.0)
	_register_reactive_light(wash, 1.5)

	# Música del DJ: audio 3D posicional, se re-loopea sola. Sale por un bus
	# propio con analizador de espectro para que los graves del tema manejen
	# el wash y la pantalla (A7).
	if club_music != null:
		var music_player := AudioStreamPlayer3D.new()
		music_player.stream = club_music
		music_player.unit_size = 22.0
		music_player.max_db = 3.0
		music_player.bus = _ensure_club_bus()
		add_child(music_player)
		music_player.position = pos + Vector3(bx, y + 1.5, bz)
		music_player.play()
		music_player.finished.connect(func(): music_player.play())


## A3 -- PANTALLA LED detrás de la cabina, sobre el tabique norte del atrio.
## 18 columnas que suben y bajan como un VU. Cada columna es UN pivote con
## una malla emisiva y un tween: escalando el pivote (con el origen abajo) la
## barra crece desde el piso de la pantalla, que es lo que la hace leer como
## medidor y no como un cartel que titila.
func _build_led_wall(pos: Vector3) -> void:
	var z := -FACE_PART + 0.1   # cara del tabique norte, del lado del atrio
	var base_y := 2.5
	var wall_h := 3.9
	var cols := 18
	var col_w := 0.54
	var total_w := float(cols) * col_w
	var cx := STAGE_CX

	# Fondo muerto + marco
	_create_box(pos + Vector3(cx, base_y + wall_h * 0.5, z - 0.05), Vector3(total_w + 0.5, wall_h + 0.5, 0.12), mat_screen_off, false)
	for s in [-1.0, 1.0]:
		_create_box(pos + Vector3(cx + s * (total_w * 0.5 + 0.28), base_y + wall_h * 0.5, z), Vector3(0.16, wall_h + 0.6, 0.2), mat_dark_steel, false)
		_create_box(pos + Vector3(cx, base_y + wall_h * 0.5 + s * (wall_h * 0.5 + 0.28), z), Vector3(total_w + 0.7, 0.16, 0.2), mat_dark_steel, false)

	var palette := [
		Color(1.0, 0.12, 0.5), Color(0.7, 0.2, 1.0), Color(0.15, 0.85, 1.0),
		Color(0.2, 1.0, 0.55), Color(1.0, 0.65, 0.1),
	]
	for c in cols:
		var col: Color = palette[c % palette.size()]
		var mat := _emissive(col * 0.7, col, 1.6)
		var pivot := Node3D.new()
		pivot.position = pos + Vector3(cx - total_w * 0.5 + col_w * (float(c) + 0.5), base_y, z + 0.05)
		add_child(pivot)
		_add_mesh_box(pivot, Vector3(0, wall_h * 0.5, 0), Vector3(col_w - 0.07, wall_h, 0.07), mat)

		# Patrón por columna: una onda que recorre la pantalla en un compás.
		# La fase la da la posición, así el barrido va de izquierda a derecha.
		var phase := float(c) / float(cols)
		var tw := create_tween().set_loops()
		for step in 8:
			var wave: float = sin((float(step) / 8.0 + phase) * TAU) * 0.5 + 0.5
			var height: float = lerpf(0.18, 1.0, wave * wave)
			tw.tween_property(pivot, "scale:y", height, BEAT * 0.5).set_trans(Tween.TRANS_SINE)
		_fx_tweens.append(tw)
		# El brillo del panel sí es reactivo al bajo real de la música.
		_register_reactive_mat(mat, 1.6)

	# Dos washes detrás para que la pantalla tiña la pared y el humo
	for s in [-1.0, 1.0]:
		var glow := _add_omni(pos + Vector3(cx + s * 3.0, base_y + wall_h * 0.6, z + 1.2), Color(0.75, 0.25, 0.95), 1.0, 11.0)
		_register_reactive_light(glow, 1.0)


## Torres de PA a los costados del escenario: line array colgado + subs en el
## piso. Un club que suena en serio tiene los graves ABAJO y los medios
## ARRIBA, y esa silueta es la que se reconoce de inmediato.
func _build_pa_stacks(pos: Vector3) -> void:
	for s: float in [-1.0, 1.0]:
		var x := STAGE_CX + s * (STAGE_W * 0.5 - 0.9)
		var z := STAGE_CZ + 0.6

		# Subs apilados en el piso (no en la tarima: pegan contra el hormigón)
		for k in 2:
			_create_box(pos + Vector3(x, 0.55 + float(k) * 1.1, z + 2.6), Vector3(1.3, 1.1, 1.3), mat_dark_steel)
			_create_cylinder(pos + Vector3(x, 0.55 + float(k) * 1.1, z + 1.96), 0.42, 0.06, mat_rubber_black, false, Vector3(PI * 0.5, 0, 0))

		# Line array: 5 cajas colgadas del truss, cada una un poco más
		# inclinada que la de arriba (el "curvado" del array).
		var hang := Node3D.new()
		hang.position = pos + Vector3(x, STAGE_Y + 4.6, z)
		add_child(hang)
		for k in 5:
			var tilt := float(k) * 0.09
			_add_mesh_box(hang, Vector3(0, -0.32 - float(k) * 0.62, float(k) * 0.12), Vector3(1.15, 0.56, 0.95), mat_dark_steel, Vector3(tilt, 0, 0))
			var grill := mat_neon_cyan if s < 0.0 else mat_neon_magenta
			_add_mesh_box(hang, Vector3(0, -0.32 - float(k) * 0.62, float(k) * 0.12 + 0.5), Vector3(0.9, 0.4, 0.03), grill, Vector3(tilt, 0, 0))
		_add_mesh_box(hang, Vector3(0, 0.06, 0), Vector3(0.7, 0.12, 0.7), mat_rust_metal)
		_create_beam(pos + Vector3(x, STAGE_Y + 5.6, z), pos + Vector3(x, STAGE_Y + 4.66, z), 0.03, mat_dark_steel)


## A3 -- TRUSS DEL ESCENARIO: dos torres y un puente, todo de celosía, con
## los PAR colgando y el foco de contra sobre la cabina.
func _build_stage_truss(pos: Vector3) -> void:
	var top := STAGE_Y + 5.6
	var west := STAGE_CX - STAGE_W * 0.5 + 0.5
	var east := STAGE_CX + STAGE_W * 0.5 - 0.5
	var z := STAGE_CZ + 0.6

	for x in [west, east]:
		_create_truss(pos + Vector3(x, STAGE_Y, z), pos + Vector3(x, top, z), 0.28, 0.045, 8)
		# Base lastrada de la torre
		_create_box(pos + Vector3(x, STAGE_Y + 0.14, z), Vector3(1.1, 0.28, 1.1), mat_dark_steel, false)
	_create_truss(pos + Vector3(west, top, z), pos + Vector3(east, top, z), 0.28, 0.045, 9)

	# PAR-64 colgados del puente, alternando magenta / ámbar, encendiendo en
	# cadena de 4 tiempos. Es el "wash" clásico de escenario.
	var par_colors := [Color(1.0, 0.18, 0.5), Color(1.0, 0.62, 0.15), Color(0.35, 0.35, 1.0), Color(0.2, 0.95, 0.85)]
	var lamps := 8
	for i in lamps:
		var t: float = lerpf(west + 0.8, east - 0.8, float(i) / float(lamps - 1))
		var col: Color = par_colors[i % par_colors.size()]
		var lamp := _create_par_can(pos + Vector3(t, top - 0.45, z), pos + Vector3(t * 0.4, 0.6, z + 9.0), col, 2.4)
		var tw := create_tween().set_loops()
		for step in 4:
			var on := 3.0 if step == (i % 4) else 0.15
			tw.tween_property(lamp, "light_energy", on, BEAT)
		_fx_tweens.append(tw)

	# Foco de contra sobre la cabina (el que recorta al DJ contra la pantalla)
	var back := BuildKit.spot(self, pos + Vector3(STAGE_CX, top - 0.4, z - 2.2), pos + Vector3(STAGE_CX, STAGE_Y + 0.6, STAGE_CZ - 0.9), Color(0.9, 0.35, 0.95), 3.2, 14.0, 20.0)
	_register_reactive_light(back, 3.2)


## A6 -- CAÑONES DE CO2 en las puntas del escenario. Disparan en el drop
## (cada frase de 8 compases) y otra vez a mitad de frase. El chorro es
## GPUParticles + un flash: sin el flash el humo no "sale disparado".
func _build_co2_jets(pos: Vector3, front: float) -> void:
	for s: float in [-1.0, 1.0]:
		var x := STAGE_CX + s * (STAGE_W * 0.5 - 0.4)
		var origin := pos + Vector3(x, STAGE_Y + 0.35, front - 0.3)
		# Cuerpo del cañón, apuntando hacia arriba y hacia la pista
		var yoke := Node3D.new()
		yoke.position = origin
		yoke.rotation = Vector3(-1.0, s * 0.25, 0)
		add_child(yoke)
		_add_mesh_cylinder(yoke, Vector3(0, 0.3, 0), 0.09, 0.6, mat_co2_white)
		_add_mesh_cylinder(yoke, Vector3(0, 0.62, 0), 0.13, 0.1, mat_dark_steel)
		_add_mesh_box(yoke, Vector3(0, 0.02, 0), Vector3(0.3, 0.12, 0.3), mat_dark_steel)
		# Tubo de gas bajando a la garrafa
		_create_beam(origin + Vector3(0, 0.1, 0), origin + Vector3(s * 0.6, 0.05, -0.9), 0.025, mat_dark_steel)
		_create_cylinder(pos + Vector3(x + s * 0.7, STAGE_Y + 0.45, front - 1.3), 0.16, 0.9, mat_co2_white)

		var jet := _make_jet_particles(Color(0.95, 0.97, 1.0))
		yoke.add_child(jet)
		jet.position = Vector3(0, 0.7, 0)

		var flash := _add_omni(origin + Vector3(0, 1.2, 0.6), Color(0.9, 0.95, 1.0), 0.0, 10.0)
		var tw := create_tween().set_loops()
		tw.tween_interval(PHRASE * 0.5 - BAR * 0.5)
		tw.tween_callback(jet.restart)
		tw.tween_property(flash, "light_energy", 2.6, 0.06)
		tw.tween_property(flash, "light_energy", 0.0, 0.5)
		tw.tween_interval(PHRASE * 0.5 - BAR * 0.5)
		tw.tween_callback(jet.restart)
		tw.tween_property(flash, "light_energy", 3.4, 0.06)
		tw.tween_property(flash, "light_energy", 0.0, 0.7)
		_fx_tweens.append(tw)


# =============================================================================
# D4 -- EL RIG: anillo de truss en el límite planta baja / primer piso,
# truss volante sobre la pista, bola de espejos, lásers, strobe y humo
# =============================================================================

func _build_rig(pos: Vector3, hr: float) -> void:
	_build_truss_ring(pos, hr)
	_build_flying_truss(pos)
	_build_lasers(pos)
	_build_strobe(pos)
	_build_floor_haze(pos)

	# Relleno rojo profundo, apenas para que la pista no sea negro absoluto
	_add_omni(pos + Vector3(0, 4.5, 0.5), Color(0.85, 0.08, 0.1), 0.5, 18.0)


## Anillo de truss atornillado a las 4 columnas del atrio, justo debajo del
## techo jugable. Marca físicamente el límite entre "el club" (abajo) y "la
## fábrica muerta" (arriba): mirando desde la pista, todo lo que está por
## encima de este anillo ya es otro mundo.
func _build_truss_ring(pos: Vector3, hr: float) -> void:
	var y := PLAY_H - 1.1
	var r := hr - 0.35
	var corners := [
		Vector3(-r, y, -r), Vector3(r, y, -r), Vector3(r, y, r), Vector3(-r, y, r),
	]
	for i in 4:
		var a: Vector3 = pos + corners[i]
		var b: Vector3 = pos + corners[(i + 1) % 4]
		_create_truss(a, b, 0.26, 0.045, 12)

	# Los 4 cabezales móviles, uno por esquina, colgados del anillo. Cada uno
	# apunta al cuadrante OPUESTO: el haz cruza la pista entera y en el
	# barrido lame los props del perímetro, que si no quedan invisibles.
	var show_colors := [Color(1.0, 0.15, 0.55), Color(0.15, 0.85, 0.95), Color(0.6, 0.15, 1.0), Color(0.95, 0.3, 0.1)]
	var quad := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	# Períodos en COMPASES, no en segundos primos: el barrido cierra con la
	# música en vez de flotar por su cuenta.
	var periods := [BAR * 2.0, BAR * 3.0, BAR * 2.0, BAR * 4.0]
	var sweeps := [0.78, 0.62, 0.86, 0.7]
	for i in 4:
		var mount: Vector3 = pos + quad[i] * (r - 0.4) + Vector3(0, y - 0.35, 0)
		var aim := pos + Vector3(-quad[i].x * 5.0, 0.9, -quad[i].z * 5.0 + 1.0)
		_create_moving_head(mount, aim, show_colors[i], 3.0, sweeps[i], periods[i])

	# PAR fijos entre cabezal y cabezal, apuntando al centro de la pista
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		for k in 3:
			var t: float = lerpf(0.22, 0.78, float(k) / 2.0)
			var p := pos + a.lerp(b, t) + Vector3(0, -0.3, 0)
			var col := Color(0.9, 0.2, 0.35) if (i + k) % 2 == 0 else Color(0.25, 0.5, 1.0)
			var lamp := _create_par_can(p, pos + Vector3(0, 0.8, 1.5), col, 1.6)
			var tw := create_tween().set_loops()
			# Respiración de 2 compases, desfasada por lámpara: es la capa de
			# luz "de fondo" sobre la que se recortan strobe y cabezales.
			tw.tween_interval(BEAT * float((i * 3 + k) % 8) * 0.5)
			tw.tween_property(lamp, "light_energy", 2.2, BAR).set_trans(Tween.TRANS_SINE)
			tw.tween_property(lamp, "light_energy", 0.35, BAR).set_trans(Tween.TRANS_SINE)
			_fx_tweens.append(tw)


## Truss volante cuadrado sobre la pista, colgado del techo por cuatro
## aparejos de cadena. Lleva la bola de espejos en el centro y downlights.
func _build_flying_truss(pos: Vector3) -> void:
	var y := 6.2
	var r := 5.0
	var corners := [Vector3(-r, y, -r + 1.5), Vector3(r, y, -r + 1.5), Vector3(r, y, r + 1.5), Vector3(-r, y, r + 1.5)]
	for i in 4:
		_create_truss(pos + corners[i], pos + corners[(i + 1) % 4], 0.22, 0.04, 8)

	# Aparejos: cadena larga hasta las cerchas + motor. Los 15m de cadena son
	# lo que da la escala real del atrio cuando mirás para arriba.
	for c in corners:
		_create_beam(pos + c + Vector3(0, 0.35, 0), pos + Vector3(c.x, ROOF_Y - 1.9, c.z), 0.022, mat_dark_steel)
		_create_box(pos + c + Vector3(0, 0.42, 0), Vector3(0.32, 0.4, 0.3), mat_rust_metal, false)

	# Downlights hacia la pista
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		for k in 2:
			var p := pos + a.lerp(b, lerpf(0.3, 0.7, float(k)))
			var lamp := _create_par_can(p + Vector3(0, -0.28, 0), p + Vector3(0, -6.0, 0), Color(0.95, 0.9, 1.0), 1.2)
			var tw := create_tween().set_loops()
			tw.tween_interval(BEAT * float(i * 2 + k))
			tw.tween_property(lamp, "light_energy", 2.0, BEAT * 0.3)
			tw.tween_property(lamp, "light_energy", 0.2, BEAT * 0.7)
			tw.tween_interval(BAR * 2.0 - BEAT)
			_fx_tweens.append(tw)

	_build_mirror_ball(pos + Vector3(0, y - 1.1, 1.5))


func _build_mirror_ball(at: Vector3) -> void:
	_create_beam(at + Vector3(0, 1.1, 0), at + Vector3(0, 0.65, 0), 0.02, mat_dark_steel)
	var ball := Node3D.new()
	ball.position = at
	add_child(ball)
	_add_mesh_sphere(ball, Vector3.ZERO, 0.65, mat_mirror)
	# Facetas: dos anillos, no uno, así el brillo recorre la bola al girar.
	# Emisión BAJA (el espejo no emite, devuelve): con la del bulbo pelado la
	# bola se veía como una corona de rectángulos blancos flotando.
	var facet := _emissive(Color(0.55, 0.58, 0.66), Color(0.7, 0.74, 0.85), 0.5)
	for ring in 2:
		var ry: float = -0.22 + float(ring) * 0.44
		var rr: float = sqrt(maxf(0.42 - ry * ry, 0.02))
		for f in 14:
			var fa := TAU * float(f) / 14.0 + float(ring) * 0.22
			_add_mesh_box(ball, Vector3(cos(fa) * rr, ry, sin(fa) * rr), Vector3(0.17, 0.17, 0.04), facet, Vector3(0, -fa, 0))
	for bs in [-1.0, 1.0]:
		var bspot := SpotLight3D.new()
		bspot.light_color = Color(0.85, 0.9, 1.0)
		bspot.light_energy = 2.8
		bspot.spot_range = 14.0
		bspot.spot_angle = 8.0
		ball.add_child(bspot)
		bspot.position = Vector3(bs * 0.5, -0.15, 0)
		bspot.rotation = Vector3(-1.1, bs * PI * 0.5, 0)
	# Una vuelta cada 6 compases: lento, constante, contra el pulso del resto.
	var btw := create_tween().set_loops()
	btw.tween_property(ball, "rotation:y", TAU, BAR * 6.0).from(0.0)
	_fx_tweens.append(btw)


## Lásers: cuatro abanicos, dos desde las torres del escenario y dos desde
## las columnas del fondo, barriendo el atrio en compases enteros.
func _build_lasers(pos: Vector3) -> void:
	var lz := STAGE_CZ + 0.6
	_create_laser_fan(pos + Vector3(STAGE_CX - STAGE_W * 0.5 + 0.5, STAGE_Y + 5.2, lz), -0.30, mat_laser_green, 5, 0.5, BAR * 2.0)
	_create_laser_fan(pos + Vector3(STAGE_CX + STAGE_W * 0.5 - 0.5, STAGE_Y + 5.2, lz), 0.32, mat_neon_magenta, 5, 0.55, BAR * 3.0)
	_create_laser_fan(pos + Vector3(-9.6, 4.4, 10.0), PI - 0.35, mat_neon_cyan, 4, 0.62, BAR * 2.0)
	_create_laser_fan(pos + Vector3(9.6, 4.4, 10.0), PI + 0.35, mat_neon_violet, 4, 0.62, BAR * 3.0)


## Strobe blanco: el corazón del techno oscuro. Ahora dispara EN el beat --
## dos ráfagas de semicorchea en los tiempos 1 y 3, y una tanda larga en el
## último compás de cada frase (el drop).
func _build_strobe(pos: Vector3) -> void:
	var strobe := OmniLight3D.new()
	strobe.light_color = Color(1.0, 0.97, 0.92)
	strobe.light_energy = 0.0
	strobe.omni_range = 20.0
	add_child(strobe)
	strobe.position = pos + Vector3(0, 5.4, 1.5)

	var tw := create_tween().set_loops()
	# 7 compases "normales": flash en los tiempos 1 y 3
	for b in 7:
		tw.tween_property(strobe, "light_energy", 3.4, 0.035)
		tw.tween_property(strobe, "light_energy", 0.0, 0.05)
		tw.tween_interval(BEAT * 2.0 - 0.085)
		tw.tween_property(strobe, "light_energy", 2.6, 0.035)
		tw.tween_property(strobe, "light_energy", 0.0, 0.05)
		tw.tween_interval(BEAT * 2.0 - 0.085)
	# Compás 8: tanda de semicorcheas -- el drop
	for f in 16:
		tw.tween_property(strobe, "light_energy", 4.2, 0.03)
		tw.tween_property(strobe, "light_energy", 0.0, BEAT * 0.25 - 0.03)
	_fx_tweens.append(tw)


## B5 -- HUMO BAJO arrastrándose por el piso LED. Es lo que convierte cada
## haz de luz en un cono visible a la altura de la cintura (arriba lo hace la
## niebla volumétrica del Environment).
func _build_floor_haze(pos: Vector3) -> void:
	var smoke := GPUParticles3D.new()
	smoke.amount = 26
	smoke.lifetime = 18.0
	smoke.preprocess = 8.0
	smoke.visibility_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 8, 28))
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 0.1, 9.0)
	pm.direction = Vector3(1, 0.0, 0.3)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.12
	pm.initial_velocity_max = 0.38
	# Gravedad levemente NEGATIVA: es humo pesado de máquina, tiene que
	# arrastrarse por el piso. Con +0.02 se despegaba y en 14s de vida
	# terminaba flotando a 4m como bolas de algodón.
	pm.gravity = Vector3(0, -0.012, 0)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.scale_min = 6.0
	pm.scale_max = 12.0
	# El alpha va ACÁ, no en el material: con vertex_color_use_as_albedo el
	# color de la partícula pisa el albedo del material, alpha incluido.
	pm.color = Color(0.72, 0.74, 0.82, 0.085)
	pm.color_ramp = _fade_ramp(0.25, 0.7)
	smoke.process_material = pm

	# Sábanas HORIZONTALES, no billboards. Un billboard de 12m centrado a 60cm
	# del piso tapa media pantalla y se lee como una bola de algodón flotando;
	# tumbado sobre el plano XZ es una capa de humo arrastrándose por el piso,
	# que es lo que hace un cañón de humo pesado.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	smoke.draw_pass_1 = quad
	# Humo = MIX con alpha bajísimo, no ADD: sumando luz, las bocanadas
	# apiladas contra el piso LED daban un muro blanco que tapaba la pista.
	var sm := _particle_material(Color(0.5, 0.52, 0.62), 0.0, false, 0.055)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke.material_override = sm

	add_child(smoke)
	smoke.position = pos + Vector3(0, 0.35, 1.0)


# =============================================================================
# EL "BACKSTAGE": muro de road cases en la esquina suroeste del atrio.
# Es el escondite marcado de la zona (ZONE_HIDE_OFFSETS["dance"]): hay que
# meterse adentro para ver si hay alguien, no alcanza con mirar desde la pista.
# =============================================================================

func _build_backstage(pos: Vector3) -> void:
	# Muro de cases mirando al este, de z 5.6 a 10.4 en x = -7.6
	var x := -7.6
	var z := 5.6
	while z < 10.5:
		var h := rng.randf_range(0.85, 1.15)
		_create_flight_case(pos + Vector3(x + rng.randf_range(-0.1, 0.1), 0, z), Vector3(1.15, h, 0.85), rng.randf_range(-0.1, 0.1))
		# Segundo piso de cases: la mitad de las torres llegan a ~1.9m, que es
		# lo que hace que no se vea por encima desde la pista.
		if rng.randf() < 0.7:
			_create_flight_case(pos + Vector3(x + rng.randf_range(-0.12, 0.12), h + 0.02, z), Vector3(1.05, rng.randf_range(0.6, 0.9), 0.8), rng.randf_range(-0.2, 0.2))
		z += 1.25

	# Tapa norte del nicho: una torre de cases y un carro de cables
	_create_flight_case(pos + Vector3(-9.6, 0, 5.7), Vector3(1.2, 1.0, 0.9), 0.4)
	_create_flight_case(pos + Vector3(-9.5, 1.02, 5.7), Vector3(1.1, 0.7, 0.85), 0.15)
	_create_cable_spool(pos + Vector3(-10.0, 0, 7.6), 0.7)

	# Un tubo agonizante colgado ahí adentro: el nicho tiene que estar oscuro,
	# pero no negro absoluto (si no, esconderse es invisible en vez de tenso).
	var lamp := _create_fluorescent_fixture(pos + Vector3(-9.2, PLAY_H - 0.05, 8.4), Color(0.5, 0.85, 0.9), 0.55, 5.5)
	var tw := create_tween().set_loops()
	tw.tween_interval(3.1)
	tw.tween_property(lamp, "light_energy", 0.1, 0.06)
	tw.tween_property(lamp, "light_energy", 0.55, 0.09)
	_fx_tweens.append(tw)

	# Cortina de tiras a la entrada del nicho (por el norte)
	_create_strip_curtain(pos + Vector3(-9.1, 0, 5.5), 3.0, 2.1, false)


# =============================================================================
# RELLENO DEL ATRIO
# =============================================================================
## Todo lo de acá respeta las 4 bocas del atrio (norte x -9..-4, sur x ±3.5,
## este/oeste z ±2.5), la tarima (x -2..10, z -10.7..-6) y el nicho del
## backstage (x < -7.5, z > 5.5).

func _build_atrium_filler(pos: Vector3) -> void:
	for tp in [Vector3(-8.6, 0, -4.2), Vector3(-8.2, 0, 3.4), Vector3(8.6, 0, 4.6), Vector3(9.2, 0, -3.2), Vector3(-5.4, 0, 9.6), Vector3(5.6, 0, 10.0)]:
		_create_high_table(pos + tp, rng.randi_range(1, 3))

	# Tarimas go-gó: dan verticalidad y tapan la vista en diagonal sin cerrar
	# ninguna línea de visión larga del Atrapador.
	_create_gogo_platform(pos + Vector3(-10.0, 0, -9.3), 1.7, mat_neon_magenta)
	_create_gogo_platform(pos + Vector3(9.7, 0, 9.7), 1.7, mat_neon_cyan)
	_create_gogo_platform(pos + Vector3(-10.1, 0, 0.0), 1.6, mat_neon_violet)

	# Torres de PA de sala contra el muro oeste (fuera del vano, que va en
	# z ±2.5) -- el club sonaba fuerte en serio
	for pz in [-6.5, 4.6]:
		_create_box(pos + Vector3(-10.25, 0.85, pz), Vector3(1.1, 1.7, 1.2), mat_dark_steel)
		_create_box(pos + Vector3(-10.25, 2.15, pz), Vector3(0.95, 0.9, 1.0), mat_dark_steel)
		_create_box(pos + Vector3(-9.66, 1.9, pz), Vector3(0.04, 0.7, 0.7), mat_neon_cyan, false)

	# Barra auxiliar del atrio contra el muro este: donde se hace la cola
	# mientras suena el set. Rompe los 10m de hormigón pelado de ese lado.
	var bx := 9.9
	_create_box(pos + Vector3(bx, 0.55, 6.6), Vector3(0.85, 1.1, 5.4), mat_aged_wood)
	_create_box(pos + Vector3(bx, 1.13, 6.6), Vector3(1.0, 0.08, 5.7), mat_rust_metal)
	_create_box(pos + Vector3(bx + 0.35, 1.6, 6.6), Vector3(0.1, 0.9, 4.6), mat_neon_violet, false)
	for gz in 5:
		_create_cylinder(pos + Vector3(bx - 0.2, 1.25, 4.4 + float(gz) * 1.1), 0.045, 0.16, mat_moon_glass, false)
	_add_omni(pos + Vector3(bx - 0.8, 2.0, 6.6), Color(0.6, 0.3, 1.0), 0.8, 6.5)

	# Vallas de contención tumbadas + basura de after
	_create_fallen_barrier(pos + Vector3(-4.0, 0, 9.3), 0.42)
	_create_fallen_barrier(pos + Vector3(6.8, 0, 8.6), -1.15)
	_create_debris_scatter(pos + Vector3(-8.0, 0, 0.5), 2.4, 9)
	_create_debris_scatter(pos + Vector3(7.8, 0, 7.6), 2.4, 9)
	_create_debris_scatter(pos + Vector3(0.0, 0, 8.6), 3.2, 12)
	_create_debris_scatter(pos + Vector3(2.0, 0, -5.0), 3.0, 10)


# =============================================================================
# BAR & LOUNGE (oeste)
# =============================================================================

func _build_bar(pos: Vector3) -> void:
	# Piso de madera gastada del sector
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_wood_floor, false)

	# Barra larga mirando al atrio, con pasillo de servicio detrás
	_create_box(pos + Vector3(3.0, 0.575, -2.0), Vector3(0.9, 1.15, 8.0), mat_aged_wood)
	_create_box(pos + Vector3(3.0, 1.19, -2.0), Vector3(1.05, 0.08, 8.4), mat_rust_metal)
	# Taburetes
	for sz in [-5.2, -3.6, -2.0, -0.4, 1.2]:
		_create_cylinder(pos + Vector3(4.3, 0.47, sz), 0.24, 0.94, mat_leather_brown)

	# Estantería de botellas contra el fondo del pasillo
	_create_box(pos + Vector3(0.8, 1.3, -2.0), Vector3(0.4, 2.6, 7.2), mat_aged_wood)
	var bottle_colors := [Color(0.2, 0.9, 0.5), Color(0.9, 0.5, 0.15), Color(0.3, 0.5, 0.95), Color(0.85, 0.2, 0.3)]
	for shelf_y in [1.25, 1.85, 2.45]:
		_create_box(pos + Vector3(1.05, shelf_y, -2.0), Vector3(0.32, 0.05, 6.8), mat_dark_steel, false)
		for b in 7:
			var bz: float = -5.0 + b * 1.0 + rng.randf_range(-0.15, 0.15)
			var bc: Color = bottle_colors[rng.randi_range(0, bottle_colors.size() - 1)]
			_create_box(pos + Vector3(1.05, shelf_y + 0.25, bz), Vector3(0.13, 0.4, 0.13), _emissive(bc, bc, 0.6), false)

	# Heladera de bebidas con frente cian
	_create_box(pos + Vector3(0.8, 0.8, 2.6), Vector3(0.8, 1.6, 1.0), mat_dark_steel)
	_create_box(pos + Vector3(1.22, 0.85, 2.6), Vector3(0.05, 1.2, 0.8), mat_neon_cyan, false)

	# Cartel de neón del bar, colgado sobre la barra
	_create_box(pos + Vector3(3.0, 3.3, -2.0), Vector3(0.1, 0.24, 5.0), mat_neon_cyan, false)
	_create_beam(pos + Vector3(3.0, PLAY_H, -4.2), pos + Vector3(3.0, 3.42, -4.2), 0.02, mat_dark_steel)
	_create_beam(pos + Vector3(3.0, PLAY_H, 0.2), pos + Vector3(3.0, 3.42, 0.2), 0.02, mat_dark_steel)

	# Lounge de sofás en la esquina suroeste
	_create_box(pos + Vector3(-6.5, 0.3, 5.5), Vector3(3.0, 0.6, 1.0), mat_leather_brown)
	_create_box(pos + Vector3(-6.5, 0.65, 6.15), Vector3(3.0, 1.3, 0.4), mat_leather_brown)
	_create_box(pos + Vector3(-8.3, 0.3, 4.0), Vector3(1.0, 0.6, 2.6), mat_leather_brown)
	_create_box(pos + Vector3(-8.9, 0.65, 4.0), Vector3(0.4, 1.3, 2.6), mat_leather_brown)
	_create_box(pos + Vector3(-6.0, 0.28, 3.6), Vector3(1.3, 0.56, 0.9), mat_aged_wood)

	# --- Relleno de la mitad norte y del centro (era piso de madera pelado) ---
	# Mesa de pool despedazada: el landmark que le faltaba al sector norte.
	var pool := pos + Vector3(-6.0, 0, -8.0)
	_create_box(pool + Vector3(0, 0.72, 0), Vector3(1.55, 0.18, 2.85), mat_tile_floor)
	for rail in [Vector3(0.82, 0.85, 0.0), Vector3(-0.82, 0.85, 0.0)]:
		_create_box(pool + rail, Vector3(0.16, 0.14, 2.85), mat_aged_wood)
	for rail_z in [-1.5, 1.5]:
		_create_box(pool + Vector3(0, 0.85, rail_z), Vector3(1.8, 0.14, 0.16), mat_aged_wood)
	for lx in [-0.6, 0.6]:
		for lz in [-1.15, 1.15]:
			_create_box(pool + Vector3(lx, 0.32, lz), Vector3(0.18, 0.64, 0.18), mat_aged_wood)
	for b in 4:
		_create_sphere(pool + Vector3(rng.randf_range(-0.55, 0.55), 0.87, rng.randf_range(-1.15, 1.15)), 0.055, mat_bulb_pale)
	_create_beam(pool + Vector3(-0.5, 0.86, -1.2), pool + Vector3(0.35, 0.9, 1.0), 0.03, mat_aged_wood)
	_create_hanging_lamp(pool + Vector3(0, PLAY_H, 0), 2.2, Color(0.95, 0.85, 0.6), 0.9, 5.5)

	# Mesas con sillas repartidas por el sector
	_create_table_set(pos + Vector3(-3.2, 0, -8.6), 0.35)
	_create_table_set(pos + Vector3(-8.2, 0, -3.4), -0.5)
	_create_table_set(pos + Vector3(-4.6, 0, 0.8), 0.9)

	# Depósito improvisado contra el muro oeste: cajones de botellas y barriles
	_create_bottle_crates(pos + Vector3(-10.1, 0, -6.0), 3)
	_create_bottle_crates(pos + Vector3(-10.05, 0, -4.7), 2)
	for kz in [-8.6, -7.7]:
		_create_cylinder(pos + Vector3(-10.15, 0.44, kz), 0.34, 0.88, mat_dark_steel)
	_create_cylinder(pos + Vector3(-9.35, 0.44, -8.2), 0.34, 0.88, mat_dark_steel)

	# Rockola muerta contra el tabique norte (fuera del vano, que va en x ±1.5)
	_create_box(pos + Vector3(4.2, 0.85, -10.5), Vector3(1.3, 1.7, 0.7), mat_aged_wood)
	_create_box(pos + Vector3(4.2, 1.35, -10.13), Vector3(1.0, 0.6, 0.06), _emissive(Color(0.5, 0.15, 0.35), Color(0.7, 0.2, 0.5), 0.5), false)
	_add_omni(pos + Vector3(4.2, 1.5, -9.7), Color(0.85, 0.25, 0.6), 0.45, 4.0)

	_create_debris_scatter(pos + Vector3(-5.5, 0, -5.0), 2.6, 8)
	_create_debris_scatter(pos + Vector3(-2.0, 0, 5.5), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(3.0, PLAY_H, -2.0), 1.4, Color(0.2, 0.85, 0.95), 1.2, 7.0)
	_create_hanging_lamp(pos + Vector3(-6.5, PLAY_H, 5.0), 1.6, Color(1.0, 0.55, 0.2), 0.9, 6.0)
	_create_fluorescent_fixture(pos + Vector3(-4.0, PLAY_H - 0.05, -8.0), Color(0.45, 0.9, 0.95), 0.9, 7.5)


# =============================================================================
# BAÑOS (suroeste)
# =============================================================================

func _build_banos(pos: Vector3) -> void:
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_tile_floor, false)
	# Revestimiento de azulejos en el muro sur (apoyado en la cara real del
	# muro exterior, no 0.24 adelante como estaba)
	_create_box(pos + Vector3(0, 1.3, FACE_EXT - 0.06), Vector3(room_size - 1.5, 2.6, 0.12), mat_tile_wall, false)

	# 4 cubículos contra el muro sur. El último tiene la puerta caída en el
	# piso: es el escondite marcado de la zona.
	var first_x := -7.0
	var cw := 1.6
	for i in 5:
		var px := first_x + i * cw
		_create_box(pos + Vector3(px, 1.15, 8.5), Vector3(0.08, 2.3, 3.0), mat_rust_metal)
	for i in 4:
		var cx := first_x + i * cw + cw * 0.5
		_create_box(pos + Vector3(cx, 0.37, 9.4), Vector3(0.5, 0.74, 0.65), mat_tile_wall)
		if i < 3:
			_create_box(pos + Vector3(cx, 1.1, 7.1), Vector3(1.4, 2.1, 0.06), mat_aged_wood)
	# La puerta del cubículo 4, arrancada, tirada en el piso
	_create_box(pos + Vector3(first_x + 3.5 * cw + 0.9, 0.05, 6.2), Vector3(1.4, 0.07, 2.1), mat_aged_wood, true, Vector3(0, 0.35, 0))

	# Lavamanos + espejo contra el tabique este. OJO: el vano baños<->entrada
	# cae en z ±1.5 de esta misma pared, así que el mueble arranca en z = 2.25
	# (antes iba de -3 a 3 y dejaba la puerta detrás de un espejo, con 0.77m
	# de paso). Y todo apoya en FACE_PART, no en 10.15.
	var sink_z := 5.0
	_create_box(pos + Vector3(FACE_PART - 0.375, 0.45, sink_z), Vector3(0.75, 0.9, 5.5), mat_concrete_wall)
	_create_box(pos + Vector3(FACE_PART - 0.025, 1.6, sink_z), Vector3(0.05, 1.0, 5.1), mat_mirror, false)
	for sz in [-1.7, 0.0, 1.7]:
		_create_box(pos + Vector3(FACE_PART - 0.42, 0.95, sink_z + sz), Vector3(0.5, 0.12, 0.5), mat_tile_wall, false)
		_create_cylinder(pos + Vector3(FACE_PART - 0.12, 1.06, sink_z + sz), 0.03, 0.22, mat_pipe_industrial, false)

	# Caño con pérdida arrimado a la esquina noroeste + charco
	_create_cylinder(pos + Vector3(-FACE_EXT + 0.14, 2.25, -FACE_PART + 0.14), 0.12, PLAY_H, mat_pipe_industrial)
	_create_box(pos + Vector3(-9.0, 0.015, -8.8), Vector3(2.2, 0.03, 1.8), _matte(Color(0.05, 0.09, 0.1), 0.1), false)

	# --- Relleno de la mitad norte (era todo azulejo pelado) -----------------
	# Mingitorios sobre el muro oeste (exterior), con tabiques separadores
	for uz in [-6.2, -5.1, -4.0]:
		_create_urinal(pos + Vector3(-FACE_EXT, 0, uz), 1.0)
	for dz in [-6.75, -5.65, -4.55, -3.45]:
		_create_box(pos + Vector3(-FACE_EXT + 0.3, 1.25, dz), Vector3(0.6, 1.3, 0.05), mat_tile_wall)
	_create_beam(pos + Vector3(-FACE_EXT + 0.12, 1.95, -6.9), pos + Vector3(-FACE_EXT + 0.12, 1.95, -3.3), 0.045, mat_pipe_industrial)

	# Carro de limpieza abandonado en el medio + cubículo derrumbado al oeste
	_create_cleaning_cart(pos + Vector3(-5.2, 0, 3.4), 0.6)
	_create_rubble_pile(pos + Vector3(-9.2, 0, 8.2), 5, 0.9)
	_create_box(pos + Vector3(-10.35, 1.05, 6.4), Vector3(0.12, 2.1, 1.4), mat_rust_metal, true, Vector3(0, 0, -0.22))
	_create_box(pos + Vector3(-8.4, 0.06, 4.9), Vector3(1.4, 0.08, 2.1), mat_aged_wood, true, Vector3(0, 0.8, 0))

	# Tacho volcado, secamanos roto y baldosas sueltas
	_create_cylinder(pos + Vector3(-2.0, 0.3, 1.2), 0.32, 0.9, mat_dark_steel, true, Vector3(PI * 0.5, 0.4, 0))
	_create_box(pos + Vector3(-FACE_EXT + 0.11, 1.35, 0.6), Vector3(0.22, 0.35, 0.3), mat_paint_worn, false)
	_create_debris_scatter(pos + Vector3(-4.0, 0, -1.0), 3.2, 9)
	_create_debris_scatter(pos + Vector3(3.5, 0, -6.0), 3.0, 7)

	# Rejilla de piso en el centro (el agua va a algún lado)
	_create_box(pos + Vector3(0.5, 0.045, 0.5), Vector3(0.6, 0.03, 0.6), mat_grate, false)

	# Segundo fluorescente fijo sobre los cubículos + luz pálida en lavamanos
	# (energías altas a propósito: el azulejo oscuro se come mucha luz)
	_create_fluorescent_fixture(pos + Vector3(-3.5, PLAY_H - 0.05, 5.6), Color(0.4, 0.85, 0.9), 2.2, 10.0)
	_add_omni(pos + Vector3(9.3, 2.6, sink_z), Color(0.7, 0.8, 0.85), 1.1, 6.0)
	_create_fluorescent_fixture(pos + Vector3(-7.0, PLAY_H - 0.05, -5.0), Color(0.35, 0.85, 0.9), 1.4, 8.0)

	# Fluorescente frío parpadeando: el clásico baño de club quemado
	var flicker := _create_fluorescent_fixture(pos + Vector3(0, PLAY_H - 0.05, 0.0), Color(0.3, 0.9, 0.95), 2.0, 10.0)
	var tw := create_tween().set_loops()
	tw.tween_interval(1.35)
	tw.tween_property(flicker, "light_energy", 0.3, 0.05)
	tw.tween_property(flicker, "light_energy", 2.0, 0.07)
	tw.tween_interval(0.22)
	tw.tween_property(flicker, "light_energy", 0.6, 0.04)
	tw.tween_property(flicker, "light_energy", 2.0, 0.05)
	_fx_tweens.append(tw)


# =============================================================================
# CHILL ROOMS / RESTING ROOMS (variant 0 = NE cálida, 1 = SE violeta)
# =============================================================================

func _build_chill_room(pos: Vector3, variant: int) -> void:
	# El NE es una esquina del edificio (muro norte de ladrillo) y el SE da al
	# pasillo (tabique): la cara donde apoyan guirnalda y póster cambia.
	var north_face := -FACE_EXT if variant == 0 else -FACE_PART
	_create_box(pos + Vector3(0, 0.02, 0), Vector3(room_size - 1.5, 0.04, room_size - 1.5), mat_wood_floor, false)
	_create_box(pos + Vector3(0, 0.045, -0.8), Vector3(7.0, 0.03, 6.0), mat_fabric_red, false)

	# Sofás en U alrededor de la mesa baja
	_create_box(pos + Vector3(0, 0.28, -2.8), Vector3(4.0, 0.56, 1.1), mat_leather_brown)
	_create_box(pos + Vector3(0, 0.55, -3.45), Vector3(4.0, 1.1, 0.35), mat_leather_brown)
	_create_box(pos + Vector3(-2.9, 0.28, -0.6), Vector3(1.1, 0.56, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(-3.5, 0.55, -0.6), Vector3(0.35, 1.1, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(2.9, 0.28, -0.6), Vector3(1.1, 0.56, 3.2), mat_leather_brown)
	_create_box(pos + Vector3(3.5, 0.55, -0.6), Vector3(0.35, 1.1, 3.2), mat_leather_brown)

	# Mesa baja (un cajón dado vuelta) con velitas encima
	_create_box(pos + Vector3(0, 0.25, -0.8), Vector3(1.3, 0.5, 0.95), mat_aged_wood)
	for c in 3:
		_create_box(pos + Vector3(-0.35 + c * 0.35, 0.55, -0.8), Vector3(0.06, 0.1, 0.06), mat_led_warm, false)

	# Rincón de colchones tirados en el piso
	_create_box(pos + Vector3(6.3, 0.14, 6.6), Vector3(2.1, 0.28, 1.5), mat_mattress)
	_create_box(pos + Vector3(7.2, 0.4, 7.6), Vector3(2.1, 0.26, 1.5), mat_mattress, true, Vector3(0, 0.5, 0))
	_create_box(pos + Vector3(5.9, 0.35, 6.2), Vector3(0.6, 0.16, 0.42), mat_fabric_red, false)

	# Guirnalda de luces colgada del muro norte: las bombitas apoyan en la cara
	# del muro y el cable las une (antes flotaban a 0.3-0.55m, sueltas).
	var garland_y := 3.05
	var bulb_z := north_face + 0.05
	_create_beam(pos + Vector3(-8.4, garland_y + 0.28, bulb_z), pos + Vector3(0.0, garland_y - 0.05, bulb_z), 0.02, mat_dark_steel)
	_create_beam(pos + Vector3(0.0, garland_y - 0.05, bulb_z), pos + Vector3(8.4, garland_y + 0.28, bulb_z), 0.02, mat_dark_steel)
	for b in 8:
		var lx: float = lerpf(-8.0, 8.0, float(b) / 7.0)
		var bulb_mat := mat_led_warm if (b % 2 == 0) == (variant == 0) else mat_neon_violet
		_create_box(pos + Vector3(lx, garland_y + sin(float(b) * 1.7) * 0.15, bulb_z), Vector3(0.09, 0.12, 0.09), bulb_mat, false)

	# Lámpara de pie + lámpara colgante sobre los sofás: los resting rooms son
	# el refugio "cálido" del club, tienen que invitar a quedarse (y verse)
	_create_cylinder(pos + Vector3(-6.0, 0.8, 5.0), 0.05, 1.6, mat_dark_steel)
	_create_sphere(pos + Vector3(-6.0, 1.75, 5.0), 0.22, mat_bulb_pale)
	var lamp_color := Color(1.0, 0.55, 0.2) if variant == 0 else Color(0.6, 0.25, 1.0)
	_add_omni(pos + Vector3(-6.0, 1.9, 5.0), lamp_color, 1.5, 9.5, true)
	var couch_color := Color(1.0, 0.45, 0.15) if variant == 0 else Color(0.75, 0.35, 1.0)
	_create_hanging_lamp(pos + Vector3(0, PLAY_H, -1.5), 1.8, couch_color, 1.2, 8.5)
	# Resplandor tenue de la guirnalda
	_add_omni(pos + Vector3(0, 2.6, -9.5), couch_color, 0.5, 6.0)

	# Pósters viejos apenas luminosos, pegados a la cara real del muro
	_create_box(pos + Vector3(-FACE_PART + 0.025, 1.9, -3.0), Vector3(0.05, 1.4, 1.0), _emissive(Color(0.5, 0.2, 0.5), Color(0.6, 0.2, 0.6), 0.35), false)
	_create_box(pos + Vector3(4.0, 2.1, north_face + 0.025), Vector3(1.0, 1.4, 0.05), _emissive(Color(0.2, 0.4, 0.6), Color(0.2, 0.5, 0.7), 0.35), false)
	_create_box(pos + Vector3(-FACE_PART + 0.025, 2.2, 4.5), Vector3(0.05, 1.1, 0.8), _emissive(Color(0.45, 0.35, 0.15), Color(0.6, 0.45, 0.15), 0.3), false)

	# --- Relleno: el sofá en U ocupaba el centro y el resto era piso vacío ---
	# Pufs y almohadones desparramados (el lado oeste, fuera del paso del vano
	# que cae en z ±1.5 sobre el tabique)
	var puff_mat := mat_fabric_red if variant == 0 else mat_leather_brown
	_create_bean_bag(pos + Vector3(-6.5, 0, 3.2), puff_mat)
	_create_bean_bag(pos + Vector3(-7.9, 0, 4.7), mat_mattress)
	_create_bean_bag(pos + Vector3(-5.2, 0, 4.6), puff_mat)
	for c in 4:
		_create_box(pos + Vector3(-8.4 + rng.randf_range(-0.8, 0.8), 0.11, -5.5 + rng.randf_range(-1.2, 1.2)), Vector3(0.75, 0.22, 0.6), mat_mattress, false, Vector3(0, rng.randf_range(0, PI), 0))

	# Estante bajo con equipo de música contra el tabique oeste
	_create_box(pos + Vector3(-FACE_PART + 0.28, 0.35, -7.6), Vector3(0.55, 0.7, 2.2), mat_aged_wood)
	_create_box(pos + Vector3(-FACE_PART + 0.28, 0.92, -7.6), Vector3(0.5, 0.44, 1.1), mat_dark_steel)
	_create_box(pos + Vector3(-FACE_PART + 0.55, 0.92, -7.6), Vector3(0.04, 0.3, 0.9), mat_crt_phosphor, false)
	_add_omni(pos + Vector3(-9.6, 1.3, -7.6), Color(0.2, 0.8, 0.35), 0.35, 3.5)

	# Mesa-carrete y ceniceros de pie en el lado este
	_create_cable_spool(pos + Vector3(7.4, 0, -6.4), 0.62)
	for ax in [4.6, -3.0]:
		_create_cylinder(pos + Vector3(ax, 0.5, 5.4), 0.16, 1.0, mat_dark_steel)
		_create_cylinder(pos + Vector3(ax, 1.03, 5.4), 0.2, 0.08, mat_rust_metal, false)

	# Cajón-mesa con botellas y velas al este de los sofás
	_create_box(pos + Vector3(5.2, 0.3, 1.4), Vector3(1.1, 0.6, 1.1), mat_aged_wood)
	for bq in 3:
		_create_cylinder(pos + Vector3(4.85 + bq * 0.35, 0.74, 1.4 + rng.randf_range(-0.25, 0.25)), 0.05, 0.28, mat_moon_glass, false)
	_create_box(pos + Vector3(5.6, 0.68, 1.1), Vector3(0.07, 0.16, 0.07), mat_led_warm, false)

	# Telas colgando del techo: parten la línea de visión sin bloquear el paso
	for dz in [-6.5, 2.0]:
		_create_box(pos + Vector3(-1.5, 3.4, dz), Vector3(2.6, 2.2, 0.04), puff_mat, false, Vector3(0, 0.25, 0))
		_create_beam(pos + Vector3(-2.8, PLAY_H - 0.05, dz - 0.3), pos + Vector3(-0.2, PLAY_H - 0.05, dz + 0.3), 0.02, mat_dark_steel)

	_create_debris_scatter(pos + Vector3(0.0, 0, 4.5), 3.0, 8)
	_create_debris_scatter(pos + Vector3(-6.0, 0, -2.0), 2.6, 6)


# =============================================================================
# SALA DE CALDERAS (este)
# =============================================================================

func _build_boiler(pos: Vector3) -> void:
	# Caldera cilíndrica gigante con boca de fuego
	_create_cylinder(pos + Vector3(3, 1.6, -3), 1.5, 3.2, mat_rust_metal)
	_create_cylinder(pos + Vector3(3, 3.8, -3), 0.35, 1.2, mat_dark_steel)
	_create_box(pos + Vector3(3, 0.6, -1.42), Vector3(0.8, 0.5, 0.14), mat_fire_orange, false)
	for g in 3:
		_create_box(pos + Vector3(2.2 + g * 0.8, 2.1, -1.55), Vector3(0.18, 0.18, 0.06), mat_led_warm, false)

	# --- Cañería troncal + bajadas sobre el muro ESTE (el comentario viejo
	# decía "norte" pero siempre estuvieron al este). Ahora el troncal muere
	# contra la pared, dobla en un colector y de ahí bajan las tres columnas,
	# con ménsulas a la pared: antes flotaban a 0.65m, sueltas en el aire. ---
	var east_face := FACE_EXT - 0.15
	var trunk_z := -5.5
	_create_beam(pos + Vector3(-FACE_PART + 0.18, 3.9, trunk_z), pos + Vector3(east_face, 3.9, trunk_z), 0.18, mat_pipe_industrial)
	_create_beam(pos + Vector3(east_face, 3.9, trunk_z), pos + Vector3(east_face, 3.9, 2.6), 0.15, mat_pipe_industrial)
	for hx in [-8.0, -3.5, 1.0, 6.0]:
		_create_beam(pos + Vector3(hx, PLAY_H, trunk_z), pos + Vector3(hx, 4.08, trunk_z), 0.03, mat_dark_steel)
	for pz in [-2.0, 0.0, 2.0]:
		_create_cylinder(pos + Vector3(east_face, 1.95, pz), 0.15, 3.9, mat_pipe_industrial)
		for by in [1.1, 3.0]:
			_create_box(pos + Vector3(FACE_EXT - 0.06, by, pz), Vector3(0.12, 0.14, 0.34), mat_dark_steel, false)
		_create_cylinder(pos + Vector3(east_face - 0.3, 1.55, pz), 0.05, 0.34, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
		_create_cylinder(pos + Vector3(east_face - 0.48, 1.55, pz), 0.16, 0.05, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))

	# Tablero eléctrico apoyado en el tabique norte y CORRIDO al este: antes
	# arrancaba en x = 1.4 y se comía la jamba del vano (que va en x ±1.5).
	_create_box(pos + Vector3(3.6, 1.4, -FACE_PART + 0.175), Vector3(1.2, 1.8, 0.35), mat_hazard_mark)
	_create_box(pos + Vector3(3.95, 1.7, -FACE_PART + 0.38), Vector3(0.12, 0.12, 0.06), mat_neon_red_dim, false)
	_create_beam(pos + Vector3(3.6, 2.3, -FACE_PART + 0.1), pos + Vector3(3.6, PLAY_H, -FACE_PART + 0.1), 0.04, mat_dark_steel)

	# Barriles de combustible apilados (el escondite queda detrás)
	var barrels := [Vector3(-6.2, 0, 6.2), Vector3(-7.2, 0, 6.8), Vector3(-6.0, 0, 7.4), Vector3(-7.0, 0, 5.6)]
	for b in barrels:
		_create_cylinder(pos + b + Vector3(0, 0.45, 0), 0.38, 0.9, mat_rust_metal)
	_create_cylinder(pos + Vector3(-6.6, 1.35, 6.5), 0.38, 0.9, mat_rust_metal)

	# --- Relleno del oeste y del sur (eran 10x20m de hormigón vacío) --------
	# Tanques horizontales sobre cunas contra el noroeste
	_create_horizontal_tank(pos + Vector3(-6.8, 1.15, -6.6), 4.6, 0.85, true)
	_create_horizontal_tank(pos + Vector3(-6.8, 1.05, -8.9), 4.0, 0.75, true)
	_create_beam(pos + Vector3(-8.9, 2.0, -6.6), pos + Vector3(-8.9, 2.0, -8.9), 0.07, mat_pipe_industrial)

	# Pila de carbón / escoria en la esquina noroeste
	for k in 7:
		var cs := rng.randf_range(0.5, 1.1)
		_create_box(pos + Vector3(-9.4 + rng.randf_range(-1.0, 1.0), cs * 0.35, -9.6 + rng.randf_range(-0.9, 0.9)), Vector3(cs, cs * 0.7, cs), mat_rubble, k < 3, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, PI), rng.randf_range(-0.4, 0.4)))
	_create_box(pos + Vector3(-7.6, 0.35, -9.0), Vector3(0.9, 0.7, 0.7), mat_dark_steel, true, Vector3(0, 0.4, 0))

	# Tramo de cañería baja cruzando el piso. Va cortado al medio a propósito:
	# el hueco de 1.6m deja pasar caminando hacia el escondite de los barriles
	# y el resto queda como obstáculo bajo (se salta).
	for seg in [Vector3(-7.6, 0, 0), Vector3(-1.6, 0, 0)]:
		_create_cylinder(pos + seg + Vector3(0, 0.38, 5.6), 0.24, 4.4, mat_pipe_industrial, true, Vector3(0, 0, PI * 0.5))
	for sx in [-9.4, -5.7, -3.5, 0.4]:
		_create_box(pos + Vector3(sx, 0.08, 5.6), Vector3(0.4, 0.16, 0.7), mat_dark_steel)

	# Caldera chica hermana, al sureste
	_create_cylinder(pos + Vector3(7.2, 1.1, 5.6), 1.0, 2.2, mat_rust_metal)
	_create_cylinder(pos + Vector3(7.2, 2.75, 5.6), 0.25, 1.1, mat_dark_steel)
	_create_beam(pos + Vector3(7.2, 3.3, 5.6), pos + Vector3(east_face, 3.85, 2.6), 0.1, mat_pipe_industrial)
	_create_box(pos + Vector3(7.2, 0.55, 4.55), Vector3(0.55, 0.4, 0.12), mat_fire_orange, false)
	_add_omni(pos + Vector3(7.2, 0.8, 4.2), Color(1.0, 0.35, 0.1), 0.9, 5.0)

	# Banco de válvulas y manómetros contra el muro este
	for vz in [7.4, 8.6]:
		_create_cylinder(pos + Vector3(FACE_EXT - 0.3, 1.5, vz), 0.34, 0.08, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
		_create_box(pos + Vector3(FACE_EXT - 0.12, 1.5, vz), Vector3(0.24, 0.24, 0.24), mat_pipe_industrial, false)
	_create_box(pos + Vector3(FACE_EXT - 0.09, 2.4, 8.0), Vector3(0.18, 0.7, 1.6), mat_hazard_mark, false)
	for gq in 3:
		_create_cylinder(pos + Vector3(FACE_EXT - 0.19, 2.4, 7.4 + gq * 0.6), 0.11, 0.05, mat_moon_glass, false, Vector3(0, 0, PI * 0.5))

	_create_debris_scatter(pos + Vector3(-3.0, 0, -1.0), 3.0, 7)
	_create_debris_scatter(pos + Vector3(2.0, 0, 8.0), 3.0, 6)

	# Resplandor del fuego + fluorescente industrial
	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.3, 0.08)
	fire_light.light_energy = 1.8
	fire_light.omni_range = 8.5
	fire_light.shadow_enabled = true
	add_child(fire_light)
	fire_light.position = pos + Vector3(3, 1.1, -0.6)

	_create_fluorescent_fixture(pos + Vector3(-2, PLAY_H - 0.05, 3), Color(0.4, 0.95, 0.9), 1.2, 8.0)
	# Sin esto, el noroeste (tanques y pila de carbón) queda en negro absoluto
	# Energía alta a propósito: el acero de los tanques es metallic 0.8 y sin
	# reflejos se come toda la luz -- con 1.2 no se veía nada.
	_create_fluorescent_fixture(pos + Vector3(-6.8, PLAY_H - 0.05, -7.5), Color(0.5, 0.9, 0.85), 2.2, 11.0)


# =============================================================================
# DEPÓSITO DE CARGA (norte)
# =============================================================================

func _build_cargo(pos: Vector3) -> void:
	# Dos estanterías largas paralelas: el pasillo entre ambas es el escondite
	_create_pallet_rack(pos + Vector3(-2, 0, -4.5), 12.0, 3.2)
	_create_pallet_rack(pos + Vector3(-2, 0, 0.5), 12.0, 3.2)
	_create_pallet_rack(pos + Vector3(4, 0, 6.0), 7.0, 3.2)

	# Autoelevador abandonado
	_create_box(pos + Vector3(-7.5, 0.5, 5.0), Vector3(1.2, 1.0, 2.0), mat_hazard_mark)
	_create_box(pos + Vector3(-7.5, 1.35, 4.4), Vector3(1.0, 0.7, 0.15), mat_dark_steel)
	_create_box(pos + Vector3(-7.5, 1.2, 6.1), Vector3(0.18, 2.4, 0.18), mat_dark_steel)
	for fx in [-0.35, 0.35]:
		_create_box(pos + Vector3(-7.5 + fx, 0.06, 6.7), Vector3(0.12, 0.06, 1.1), mat_dark_steel)

	# Pallet envuelto en film + cajas sueltas
	_create_box(pos + Vector3(8.5, 0.65, -8.5), Vector3(1.2, 1.3, 1.2), mat_shrinkwrap)
	_create_crate_stack(pos + Vector3(-8.5, 0, -8.0), 3, true)
	_create_crate_stack(pos + Vector3(8.0, 0, 1.5), 2, true)

	# --- Relleno del sector este (quedaban ~9x18m de piso libre) ------------
	# Estantería cruzada de norte a sur: cierra el vacío del este sin tapar el
	# vano hacia el chill NE (que va en z ±1.5 sobre el tabique)
	_create_pallet_rack(pos + Vector3(8.4, 0, -2.5), 8.0, 3.2, PI * 0.5)

	# Pallets, zorra y bidones sueltos
	_create_pallet_stack(pos + Vector3(6.8, 0, 4.6), 4, 0.2)
	_create_pallet_stack(pos + Vector3(9.3, 0, 6.0), 3, -0.35)
	_create_pallet_jack(pos + Vector3(5.2, 0, -8.4), 1.1)
	_create_cable_spool(pos + Vector3(-9.6, 0, 8.8), 0.85)
	_create_cable_spool(pos + Vector3(-8.2, 0, 9.6), 0.6)
	for bx in [-9.0, -8.1, -7.2, -6.3]:
		_create_cylinder(pos + Vector3(bx, 0.45, -FACE_EXT + 0.38), 0.38, 0.9, mat_rust_metal)
	_create_cylinder(pos + Vector3(-8.55, 1.35, -FACE_EXT + 0.38), 0.38, 0.9, mat_rust_metal)

	# Cajones envueltos en film y marcas de carga en el piso
	_create_box(pos + Vector3(6.2, 0.75, 9.0), Vector3(1.3, 1.5, 1.3), mat_shrinkwrap)
	_create_box(pos + Vector3(3.6, 0.6, 9.4), Vector3(1.1, 1.2, 1.1), mat_shrinkwrap)
	for mz in [-1.0, 1.0]:
		_create_box(pos + Vector3(-6.5, 0.025, mz * 2.6 + 7.0), Vector3(5.0, 0.03, 0.18), mat_hazard_mark, false)
	_create_debris_scatter(pos + Vector3(1.0, 0, 4.0), 3.4, 8)
	_create_debris_scatter(pos + Vector3(8.0, 0, -8.0), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, -2), 1.3, Color(0.55, 0.25, 1.0), 1.2, 8.5)
	_create_fluorescent_fixture(pos + Vector3(4, PLAY_H - 0.05, 6), Color(0.4, 0.9, 0.95), 1.0, 7.0)
	_create_fluorescent_fixture(pos + Vector3(8.4, PLAY_H - 0.05, -6.5), Color(0.4, 0.9, 0.95), 0.9, 7.0)


# =============================================================================
# TALLER (noroeste)
# =============================================================================

func _build_workshop(pos: Vector3) -> void:
	# Mesa de trabajo contra el muro norte + panel de herramientas. Todo apoya
	# en FACE_EXT: antes el panel estaba a -10.3 con la pared en -10.7 y se
	# veía colgado en el aire, con la mesa despegada medio metro.
	var bench_z := -FACE_EXT + 0.55
	_create_box(pos + Vector3(0, 0.95, bench_z), Vector3(6.5, 0.12, 1.1), mat_aged_wood)
	for lx in [-3.0, 3.0]:
		for lz in [-0.4, 0.4]:
			_create_box(pos + Vector3(lx, 0.45, bench_z + lz), Vector3(0.1, 0.9, 0.1), mat_dark_steel)
	_create_box(pos + Vector3(0, 0.45, bench_z), Vector3(6.0, 0.08, 0.9), mat_dark_steel, false)
	_create_box(pos + Vector3(0, 2.2, -FACE_EXT + 0.04), Vector3(6.0, 1.6, 0.08), mat_aged_wood, false)
	for t in 6:
		_create_box(pos + Vector3(-2.2 + t * 0.9, 2.2 + (0.25 if t % 2 == 0 else -0.2), -FACE_EXT + 0.105), Vector3(0.12, 0.4, 0.05), mat_dark_steel, false)
	# Morsa sobre la mesa
	_create_box(pos + Vector3(-2.4, 1.15, bench_z), Vector3(0.45, 0.3, 0.35), mat_rust_metal)

	# Compresor + carro de herramientas
	_create_cylinder(pos + Vector3(6.5, 0.8, -6.0), 0.5, 1.6, mat_pipe_industrial)
	_create_box(pos + Vector3(6.5, 1.7, -6.0), Vector3(0.5, 0.3, 0.4), mat_dark_steel)
	_create_box(pos + Vector3(2.0, 0.5, -4.0), Vector3(0.9, 1.0, 1.2), mat_rust_metal)
	_create_chair(pos + Vector3(-1.0, 0, -8.2), PI)

	# Tambores de aceite en la esquina sureste (escondite detrás)
	for d in [Vector3(7.3, 0, 7.3), Vector3(8.2, 0, 6.6), Vector3(6.7, 0, 8.3)]:
		_create_cylinder(pos + d + Vector3(0, 0.45, 0), 0.4, 0.9, mat_rust_metal)

	# Cadenas sueltas colgando del techo
	for c in 2:
		var cx := rng.randf_range(-3.0, 4.0)
		var cz := rng.randf_range(-2.0, 3.0)
		_create_beam(pos + Vector3(cx, PLAY_H, cz), pos + Vector3(cx, PLAY_H - rng.randf_range(1.6, 2.4), cz), 0.03, mat_dark_steel)

	# --- Aparejo con un motor colgando: las cadenas ahora sostienen ALGO ----
	var hoist := pos + Vector3(2.6, 0, 1.2)
	_create_beam(hoist + Vector3(-2.2, PLAY_H - 0.2, 0), hoist + Vector3(2.2, PLAY_H - 0.2, 0), 0.09, mat_dark_steel)
	_create_box(hoist + Vector3(0, PLAY_H - 0.45, 0), Vector3(0.45, 0.4, 0.5), mat_rust_metal, false)
	_create_beam(hoist + Vector3(0, PLAY_H - 0.6, 0), hoist + Vector3(0, 1.85, 0), 0.035, mat_dark_steel)
	_create_box(hoist + Vector3(0, 1.42, 0), Vector3(0.95, 0.85, 1.15), mat_dark_steel)
	_create_box(hoist + Vector3(0, 1.95, 0), Vector3(0.55, 0.25, 0.7), mat_rust_metal)
	_create_cylinder(hoist + Vector3(0.62, 1.3, 0), 0.18, 0.5, mat_rust_metal, false, Vector3(0, 0, PI * 0.5))
	# Bandeja de aceite abajo, para que el motor "esté trabajándose"
	_create_box(hoist + Vector3(0, 0.06, 0), Vector3(1.4, 0.12, 1.4), mat_dark_steel)
	_create_box(hoist + Vector3(0.1, 0.135, 0.1), Vector3(1.1, 0.02, 1.1), _matte(Color(0.03, 0.025, 0.02), 0.15), false)
	# Portátil de taller colgada del aparejo, apuntando al motor
	_create_hanging_lamp(hoist + Vector3(1.1, PLAY_H - 0.3, 0.5), 1.9, Color(1.0, 0.9, 0.7), 1.3, 6.0)

	# --- Relleno del oeste y del centro-sur --------------------------------
	# Chasis quemado: el landmark del taller y buena cobertura para esconderse
	_create_wreck_car(pos + Vector3(-5.0, 0, 3.4), 0.38)

	# Estantería metálica contra el muro oeste
	_create_shelf_unit(pos + Vector3(-FACE_EXT + 0.32, 0, -2.5), 5.0, PI * 0.5)

	# Pilas de neumáticos y bidones
	_create_tire_stack(pos + Vector3(-7.6, 0, -5.6), 4)
	_create_tire_stack(pos + Vector3(-8.6, 0, -4.4), 3)
	_create_tire_stack(pos + Vector3(-6.6, 0, 7.4), 5)
	for dz in [8.6, 9.4]:
		_create_cylinder(pos + Vector3(-2.4, 0.45, dz), 0.34, 0.9, mat_pipe_industrial)
	_create_box(pos + Vector3(0.5, 0.4, 8.8), Vector3(1.6, 0.8, 1.0), mat_rust_metal, true, Vector3(0, 0.3, 0))

	# Manchas de aceite y basura de taller
	for oi in 3:
		_create_box(pos + Vector3(rng.randf_range(-6.0, 4.0), 0.024, rng.randf_range(-4.0, 6.0)), Vector3(rng.randf_range(1.2, 2.4), 0.02, rng.randf_range(1.0, 2.0)), _matte(Color(0.03, 0.025, 0.02), 0.2), false, Vector3(0, rng.randf_range(0, PI), 0))
	_create_debris_scatter(pos + Vector3(-3.0, 0, -6.0), 3.0, 7)
	_create_debris_scatter(pos + Vector3(4.0, 0, 2.0), 3.0, 6)

	_create_fluorescent_fixture(pos + Vector3(0, PLAY_H - 0.05, -6), Color(0.4, 0.95, 0.9), 1.3, 8.0)
	_create_hanging_lamp(pos + Vector3(5, PLAY_H, 5), 1.5, Color(1.0, 0.6, 0.25), 0.8, 6.0)
	_create_hanging_lamp(pos + Vector3(-6.5, PLAY_H, 1.0), 1.2, Color(0.9, 0.85, 0.8), 0.9, 6.5)


# =============================================================================
# ENTRADA / DOCK DE CARGA (sur) -- spawn del Atrapador + escalera derrumbada
# =============================================================================

func _build_entrance(pos: Vector3) -> void:
	# Portón de carga cerrado (por acá "entraba" la gente: ahora sellado),
	# embutido contra la cara real del muro sur
	_create_box(pos + Vector3(0, 2.1, FACE_EXT - 0.11), Vector3(7.0, 4.2, 0.22), mat_dark_steel)
	for rib in 6:
		_create_box(pos + Vector3(0, 0.6 + rib * 0.6, FACE_EXT - 0.245), Vector3(7.0, 0.1, 0.05), mat_rust_metal, false)
	_create_box(pos + Vector3(0, 0.02, 9.4), Vector3(7.0, 0.04, 1.4), mat_hazard_mark, false)
	# Cartel de salida arriba del portón (antes se superponía con la chapa)
	_create_box(pos + Vector3(0, 4.45, FACE_EXT - 0.05), Vector3(1.2, 0.35, 0.1), mat_exit_green, false)
	_add_omni(pos + Vector3(0, 4.3, 9.9), Color(0.15, 0.9, 0.35), 0.5, 4.5)

	# Cabina de seguridad/tickets con monitor CRT muerto-vivo
	_create_box(pos + Vector3(-7, 1.25, 4), Vector3(2.2, 2.5, 2.2), mat_concrete_wall)
	_create_box(pos + Vector3(-7, 1.7, 5.12), Vector3(1.4, 0.9, 0.06), mat_crt_phosphor, false)
	_add_omni(pos + Vector3(-7, 1.9, 5.6), Color(0.25, 0.85, 0.4), 0.5, 3.5)

	# Vallas de fila hacia la boca del atrio
	for side in [-1.6, 1.6]:
		var prev := Vector3.ZERO
		for i in 4:
			var post := pos + Vector3(side, 0, 8.0 - i * 1.5)
			_create_cylinder(post + Vector3(0, 0.5, 0), 0.06, 1.0, mat_dark_steel)
			if i > 0:
				_create_beam(prev + Vector3(0, 0.92, 0), post + Vector3(0, 0.92, 0), 0.03, mat_rust_metal)
			prev = post

	# Grafitis de neón en el tabique oeste (dos tajos cruzados magenta/cian).
	# Pegados a la cara del tabique y corridos a z = -3.5: en -2.0 quedaban
	# montados sobre la jamba del vano hacia baños (que va en z ±1.5).
	_create_box(pos + Vector3(-FACE_PART + 0.03, 1.8, -3.5), Vector3(0.06, 1.8, 0.3), mat_neon_magenta, false, Vector3(0.5, 0, 0))
	_create_box(pos + Vector3(-FACE_PART + 0.03, 1.8, -3.5), Vector3(0.06, 1.8, 0.3), mat_neon_cyan, false, Vector3(-0.5, 0, 0))

	# --- ESCALERA DERRUMBADA contra el muro este: sube 8 escalones y muere en
	# escombros + reja. Cuenta la historia de los pisos de arriba y deja claro
	# que no se sube. Colisión invisible por si alguien lo intenta igual. ---
	var rise := 0.34
	for i in 8:
		var h := rise * (i + 1)
		_create_box(pos + Vector3(9.3, h * 0.5, 7.0 - i * 0.6), Vector3(2.2, h, 0.6), mat_concrete_wall)
	# Escombros al tope
	for k in 5:
		var s := rng.randf_range(0.35, 0.85)
		_create_box(pos + Vector3(9.3 + rng.randf_range(-0.7, 0.7), 2.9 + k * 0.18, 1.6 + rng.randf_range(-0.5, 0.5)), Vector3(s, s * 0.7, s), mat_rubble, true, Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0, PI), 0))
	# Reja caída tapando el hueco
	_create_box(pos + Vector3(9.3, 3.6, 2.2), Vector3(2.2, 1.9, 0.08), mat_grate, false, Vector3(-0.35, 0, 0))
	# Red de seguridad invisible
	_create_invisible_barrier(pos + Vector3(9.3, 3.9, 1.6), Vector3(2.6, 2.6, 2.0))
	# Luz roja sucia marcando la escalera muerta
	_add_omni(pos + Vector3(9.3, 3.8, 4.5), Color(0.95, 0.15, 0.1), 1.0, 7.0)

	# --- Relleno del hall (era el sector más pelado del mapa) ---------------
	# Banco de lockers contra el tabique oeste, fuera del vano hacia baños
	_create_locker_bank(pos + Vector3(-FACE_PART + 0.25, 0, -7.0), 6, PI * 0.5)
	_create_locker_bank(pos + Vector3(-FACE_PART + 0.25, 0, 5.6), 4, PI * 0.5)
	# Cartelera del club arriba de los lockers
	_create_box(pos + Vector3(-FACE_PART + 0.06, 2.55, -7.0), Vector3(0.08, 1.2, 2.4), mat_aged_wood, false)
	for fl in 5:
		_create_box(pos + Vector3(-FACE_PART + 0.11, 2.2 + rng.randf_range(0.0, 0.9), -8.0 + rng.randf_range(0.0, 2.0)), Vector3(0.02, 0.34, 0.26), _emissive(Color(0.4, 0.4, 0.45), Color(0.5, 0.5, 0.6), 0.25), false, Vector3(rng.randf_range(-0.15, 0.15), 0, 0))

	# Mesa de cacheo + silla al costado de la fila
	_create_box(pos + Vector3(-4.2, 0.78, 6.4), Vector3(2.0, 0.1, 0.8), mat_aged_wood)
	for lx in [-1.85, 1.85]:
		for lz in [-0.3, 0.3]:
			_create_box(pos + Vector3(-4.2 + lx * 0.5, 0.38, 6.4 + lz), Vector3(0.08, 0.76, 0.08), mat_dark_steel)
	_create_chair(pos + Vector3(-4.2, 0, 7.6), PI)
	_create_box(pos + Vector3(-3.6, 0.9, 6.4), Vector3(0.35, 0.14, 0.3), mat_dark_steel)

	# Guardarropa: mostrador y perchero detrás
	_create_box(pos + Vector3(4.6, 0.55, 8.7), Vector3(3.2, 1.1, 0.7), mat_aged_wood)
	_create_box(pos + Vector3(4.6, 1.13, 8.7), Vector3(3.4, 0.08, 0.85), mat_rust_metal)
	_create_beam(pos + Vector3(3.2, 1.8, 9.7), pos + Vector3(6.2, 1.8, 9.7), 0.04, mat_rust_metal)
	for hz in 6:
		_create_box(pos + Vector3(3.4 + hz * 0.55, 1.4, 9.7), Vector3(0.4, 0.75, 0.14), mat_fabric_red, false, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
	_add_omni(pos + Vector3(4.6, 2.1, 8.9), Color(0.9, 0.6, 0.3), 0.6, 5.0)

	# Molinete roto y valla tumbada al final de la fila
	_create_cylinder(pos + Vector3(3.6, 0.5, 3.6), 0.18, 1.0, mat_dark_steel)
	for ta in 3:
		var tang := -0.4 + ta * 1.2
		_create_beam(pos + Vector3(3.6, 0.9, 3.6), pos + Vector3(3.6 + cos(tang) * 0.75, 0.9, 3.6 + sin(tang) * 0.75), 0.04, mat_rust_metal)
	_create_fallen_barrier(pos + Vector3(-1.2, 0, 9.2), 1.35)

	# Tacho volcado y basura de la puerta
	_create_cylinder(pos + Vector3(6.8, 0.32, 5.2), 0.34, 0.95, mat_dark_steel, true, Vector3(PI * 0.5, 0.9, 0))
	_create_debris_scatter(pos + Vector3(6.0, 0, 5.6), 2.2, 8)
	_create_debris_scatter(pos + Vector3(-6.5, 0, -4.5), 3.0, 7)
	_create_debris_scatter(pos + Vector3(0.0, 0, 6.5), 2.6, 6)

	_create_hanging_lamp(pos + Vector3(0, PLAY_H, 5.5), 1.4, Color(0.75, 0.8, 0.95), 1.4, 9.0)
	_create_hanging_lamp(pos + Vector3(-5.5, PLAY_H, 0.5), 1.6, Color(0.9, 0.5, 0.2), 0.9, 6.5)
	_create_fluorescent_fixture(pos + Vector3(-6.0, PLAY_H - 0.05, -7.0), Color(0.5, 0.85, 0.95), 1.1, 8.0)


# =============================================================================
# SPAWNS
# =============================================================================

func _setup_spawns() -> void:
	# El Atrapador arranca en la entrada, del lado opuesto del edificio a la
	# mayoría de los escondites.
	seeker_spawn_point = _zone_centers["entrance"] + Vector3(0, 0.8, 2.0)

	hider_spawn_points.clear()
	for key in ZONE_HIDE_OFFSETS.keys():
		hider_spawn_points.append(_zone_centers[key] + ZONE_HIDE_OFFSETS[key])
	_seeded_shuffle(hider_spawn_points)


## Fisher-Yates con NUESTRA rng seedeada (no Array.shuffle(), que usa el RNG
## global y daría un resultado distinto en cada cliente).
func _seeded_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# =============================================================================
# HELPERS DE PROPS COMPUESTOS
# =============================================================================

func _create_crate_stack(base: Vector3, count: int, with_collision: bool) -> void:
	for i in count:
		var s := 1.15 - i * 0.18
		var mat := mat_aged_wood if i % 2 == 0 else mat_dark_steel
		_create_box(base + Vector3(rng.randf_range(-0.1, 0.1), 0.28 + i * 0.52, rng.randf_range(-0.1, 0.1)), Vector3(s, 0.52, s), mat, with_collision, Vector3(0, rng.randf_range(-0.3, 0.3), 0))


func _create_pallet_rack(pos: Vector3, length: float, height: float, rot_y: float = 0.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var w := 0.95
	for dx in [-length * 0.5, 0.0, length * 0.5]:
		for dz in [-w * 0.5, w * 0.5]:
			_add_primitive_box(root, Vector3(dx, height * 0.5, dz), Vector3(0.09, height, 0.09), mat_rust_metal)
	for h in [0.75, 1.65, 2.55]:
		_add_primitive_box(root, Vector3(0, h, 0), Vector3(length, 0.06, w), mat_rust_metal)
		_add_primitive_box(root, Vector3(length * 0.28, h + 0.28, 0), Vector3(0.7, 0.5, 0.65), mat_aged_wood)
		_add_primitive_box(root, Vector3(-length * 0.22, h + 0.25, 0), Vector3(0.55, 0.45, 0.55), mat_aged_wood)


func _create_chair(pos: Vector3, rot_y: float) -> void:
	var base := Node3D.new()
	base.position = pos
	base.rotation.y = rot_y
	add_child(base)
	_add_primitive_box(base, Vector3(0, 0.45, 0), Vector3(0.45, 0.06, 0.45), mat_aged_wood)
	_add_primitive_box(base, Vector3(0, 0.75, -0.2), Vector3(0.45, 0.55, 0.06), mat_aged_wood)
	for dx in [-0.18, 0.18]:
		for dz in [-0.18, 0.18]:
			_add_primitive_box(base, Vector3(dx, 0.22, dz), Vector3(0.05, 0.44, 0.05), mat_dark_steel)


## Farol colgado del techo jugable. El cable se estira CEILING_RISE metros:
## todos los llamadores pasan un largo pensado para un techo de 4.5m y con el
## techo a 6.5 las lámparas quedaban 2m arriba de donde tienen que estar.
func _create_hanging_lamp(pos: Vector3, cable_len: float, color: Color, energy: float, light_range: float) -> void:
	var length := cable_len + CEILING_RISE
	_create_cylinder(pos - Vector3(0, length * 0.5, 0), 0.02, length, mat_dark_steel, false)
	_create_cylinder(pos - Vector3(0, length, 0), 0.35, 0.2, mat_rust_metal, false)
	_create_cylinder(pos - Vector3(0, length + 0.05, 0), 0.12, 0.1, mat_bulb_pale, false)
	_add_omni(pos - Vector3(0, length + 0.25, 0), color, energy * ZONE_LIGHT_BOOST, light_range * ZONE_RANGE_BOOST, true)


## Tubo industrial. Con el techo a 6.5m ya no va pegado a la losa: baja
## CEILING_RISE colgado de dos varillas, así el tubo termina a la altura para
## la que se calibraron todas las energías del mapa (y de paso la suspensión
## es un detalle más de instalación).
func _create_fluorescent_fixture(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var at := pos - Vector3(0, CEILING_RISE, 0)
	for dz in [-0.65, 0.65]:
		_create_beam(pos + Vector3(0, 0.05, dz), at + Vector3(0, 0.05, dz), 0.015, mat_dark_steel)
	_create_box(at, Vector3(0.3, 0.1, 1.8), mat_dark_steel, false)
	_create_box(at - Vector3(0, 0.06, 0), Vector3(0.12, 0.05, 1.6), mat_neon_cyan, false)
	return _add_omni(at - Vector3(0, 0.3, 0), color, energy * ZONE_LIGHT_BOOST, light_range * ZONE_RANGE_BOOST, true)


# =============================================================================
# LUCES DE SHOW ANIMADAS
# =============================================================================

## Cabezal móvil colgado de una columna del atrio: yugo + luminaria + spot, con
## barrido en péndulo. Que la luz salga de un cuerpo visible es la mitad del
## efecto; la otra mitad es que se mueva.
func _create_moving_head(mount: Vector3, aim: Vector3, color: Color, energy: float, sweep: float, period: float) -> void:
	var d := aim - mount
	var flat := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var tilt := atan2(-d.y, maxf(flat, 0.01))

	# Ménsula fija a la columna
	_create_box(mount + Vector3(0, 0.3, 0), Vector3(0.34, 0.14, 0.34), mat_dark_steel, false)

	var pivot := Node3D.new()
	pivot.position = mount
	pivot.rotation.y = yaw
	add_child(pivot)
	_add_mesh_box(pivot, Vector3(0, 0.12, 0), Vector3(0.36, 0.12, 0.22), mat_dark_steel)
	for sx in [-0.17, 0.17]:
		_add_mesh_box(pivot, Vector3(sx, -0.1, 0), Vector3(0.05, 0.36, 0.16), mat_dark_steel)

	var head := Node3D.new()
	head.rotation.x = -tilt
	pivot.add_child(head)
	_add_mesh_cylinder(head, Vector3(0, -0.12, -0.18), 0.13, 0.46, mat_dark_steel, Vector3(PI * 0.5, 0, 0))
	_add_mesh_cylinder(head, Vector3(0, -0.12, -0.41), 0.115, 0.03, _emissive(color, color, 3.2), Vector3(PI * 0.5, 0, 0))

	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_range = 21.0
	spot.spot_angle = 15.0
	spot.spot_angle_attenuation = 0.9
	head.add_child(spot)
	spot.position = Vector3(0, -0.12, -0.43)

	var tw := create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", yaw + sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:y", yaw - sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw)

	# El cabeceo va a compás y medio contra el barrido (relación 3:2): el
	# patrón tarda 3 barridos en cerrarse sobre sí mismo, pero los dos siguen
	# cayendo en el tiempo. Antes era 1.41 -- irracional, nunca cerraba y
	# nada quedaba anclado a la música.
	var tw2 := create_tween().set_loops()
	tw2.tween_property(head, "rotation:x", -tilt + 0.20, period * 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(head, "rotation:x", -tilt - 0.12, period * 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw2)


## Abanico de láseres saliendo de un cabezal, barriendo el atrio. Los haces se
## construyen en el espacio LOCAL del pivot, así rotan todos juntos.
func _create_laser_fan(origin: Vector3, base_yaw: float, mat: StandardMaterial3D, count: int, sweep: float, period: float) -> void:
	var pivot := Node3D.new()
	pivot.position = origin
	pivot.rotation.y = base_yaw
	add_child(pivot)
	_add_mesh_box(pivot, Vector3(0, 0, 0.08), Vector3(0.32, 0.24, 0.36), mat_dark_steel)
	_add_mesh_box(pivot, Vector3(0, 0, 0.27), Vector3(0.18, 0.1, 0.03), mat)
	for i in count:
		var t: float = float(i) / maxf(float(count - 1), 1.0) - 0.5
		var end := Vector3(t * 12.0, 6.0 + absf(t) * 4.2, 22.0)
		_add_beam(pivot, Vector3(0, 0, 0.26), end, 0.025, mat)

	var tw := create_tween().set_loops()
	tw.tween_property(pivot, "rotation:y", base_yaw + sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation:y", base_yaw - sweep, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw)
	# Balanceo a 3/4 del barrido: sigue siendo un valor musical (antes 0.67).
	var tw2 := create_tween().set_loops()
	tw2.tween_property(pivot, "rotation:z", 0.26, period * 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw2.tween_property(pivot, "rotation:z", -0.26, period * 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tweens.append(tw2)

	# Corte del haz en el drop: el abanico se apaga un compás y vuelve. Que
	# los lásers desaparezcan de golpe es lo que hace que el drop se sienta.
	var blank := create_tween().set_loops()
	blank.tween_interval(PHRASE - BAR)
	blank.tween_property(pivot, "visible", false, 0.0)
	blank.tween_interval(BAR * 0.75)
	blank.tween_property(pivot, "visible", true, 0.0)
	blank.tween_interval(BAR * 0.25)
	_fx_tweens.append(blank)


# =============================================================================
# PROPS DE RELLENO
# =============================================================================

## Mesa alta de bar, la típica de pie, con vasos abandonados arriba.
func _create_high_table(pos: Vector3, glasses: int = 2) -> void:
	_create_cylinder(pos + Vector3(0, 0.04, 0), 0.42, 0.08, mat_dark_steel)
	_create_cylinder(pos + Vector3(0, 0.55, 0), 0.08, 1.02, mat_dark_steel)
	_create_cylinder(pos + Vector3(0, 1.09, 0), 0.55, 0.07, mat_aged_wood)
	# Velita LED: sin esto la mesa es un poste negro invisible en la penumbra
	_create_cylinder(pos + Vector3(0, 1.19, 0), 0.05, 0.13, mat_led_warm, false)
	_add_omni(pos + Vector3(0, 1.32, 0), Color(1.0, 0.6, 0.25), 0.55, 2.8)
	for g in glasses:
		var a := rng.randf_range(0.0, TAU)
		var dd := rng.randf_range(0.16, 0.34)
		_create_cylinder(pos + Vector3(cos(a) * dd, 1.2, sin(a) * dd), 0.045, 0.16, mat_moon_glass, false)


## Tarima go-gó: cajón con zócalo de neón y barra de apoyo atrás.
func _create_gogo_platform(pos: Vector3, size: float, neon: StandardMaterial3D) -> void:
	_create_box(pos + Vector3(0, 0.35, 0), Vector3(size, 0.7, size), mat_dark_steel)
	_create_box(pos + Vector3(0, 0.73, 0), Vector3(size + 0.14, 0.06, size + 0.14), mat_rust_metal, false)
	for s in [-1.0, 1.0]:
		# Zócalo de neón alto: es lo que hace legible la tarima desde la pista
		_create_box(pos + Vector3(s * size * 0.51, 0.36, 0), Vector3(0.05, 0.5, size * 0.92), neon, false)
		_create_box(pos + Vector3(0, 0.36, s * size * 0.51), Vector3(size * 0.92, 0.5, 0.05), neon, false)
		_create_cylinder(pos + Vector3(s * size * 0.42, 1.3, -size * 0.42), 0.04, 1.1, mat_rust_metal, false)
	_add_omni(pos + Vector3(0, 0.45, 0), neon.emission, 0.7, 4.5)
	_create_beam(pos + Vector3(-size * 0.42, 1.83, -size * 0.42), pos + Vector3(size * 0.42, 1.83, -size * 0.42), 0.04, mat_rust_metal)


## Flight case de gira.
func _create_flight_case(pos: Vector3, size: Vector3, rot_y: float) -> void:
	var rot := Vector3(0, rot_y, 0)
	_create_box(pos + Vector3(0, size.y * 0.5, 0), size, mat_dark_steel, true, rot)
	_create_box(pos + Vector3(0, size.y + 0.02, 0), Vector3(size.x * 0.94, 0.04, size.z * 0.94), mat_rust_metal, false, rot)
	_create_box(pos + Vector3(0, size.y * 0.55, 0), Vector3(size.x * 1.03, 0.05, size.z * 1.03), mat_rust_metal, false, rot)


## Valla de contención tumbada: desorden post-rave que no tapa el paso.
func _create_fallen_barrier(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.07, -0.45), Vector3(2.2, 0.06, 0.06), mat_rust_metal)
	_add_primitive_box(root, Vector3(0, 0.34, 0.45), Vector3(2.2, 0.06, 0.06), mat_rust_metal)
	for bx in [-0.95, -0.32, 0.32, 0.95]:
		_add_primitive_box(root, Vector3(bx, 0.2, 0.0), Vector3(0.05, 0.05, 0.95), mat_rust_metal)
	for lx in [-1.0, 1.0]:
		_add_primitive_box(root, Vector3(lx, 0.2, -0.72), Vector3(0.07, 0.42, 0.07), mat_dark_steel)


## Basura fina de after: vasos, latas, volantes. SIN colisión a propósito, para
## que llene el piso sin trabar a nadie.
func _create_debris_scatter(pos: Vector3, spread: float, count: int) -> void:
	for i in count:
		var p := pos + Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var kind := rng.randi_range(0, 2)
		if kind == 0:
			_create_cylinder(p + Vector3(0, 0.05, 0), 0.045, 0.11, mat_shrinkwrap, false, Vector3(PI * 0.5, rng.randf_range(0, PI), 0))
		elif kind == 1:
			_create_box(p + Vector3(0, 0.012, 0), Vector3(0.22, 0.01, 0.16), mat_mattress, false, Vector3(0, rng.randf_range(0, PI), 0))
		else:
			_create_cylinder(p + Vector3(0, 0.035, 0), 0.032, 0.12, mat_dark_steel, false, Vector3(PI * 0.5, rng.randf_range(0, PI), 0))


## Mesa baja con dos sillas enfrentadas.
func _create_table_set(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.73, 0), Vector3(1.1, 0.07, 1.1), mat_aged_wood)
	for dx in [-0.45, 0.45]:
		for dz in [-0.45, 0.45]:
			_add_primitive_box(root, Vector3(dx, 0.36, dz), Vector3(0.07, 0.72, 0.07), mat_dark_steel)
	_add_mesh_cylinder(root, Vector3(rng.randf_range(-0.3, 0.3), 0.85, rng.randf_range(-0.3, 0.3)), 0.05, 0.18, mat_moon_glass)
	_create_chair(pos + Vector3(cos(rot_y) * 1.05, 0, -sin(rot_y) * 1.05), rot_y - PI * 0.5)
	_create_chair(pos - Vector3(cos(rot_y) * 1.05, 0, -sin(rot_y) * 1.05), rot_y + PI * 0.5)


## Cajones de botellas apilados.
func _create_bottle_crates(pos: Vector3, count: int) -> void:
	for i in count:
		var y := 0.16 + i * 0.32
		var jx := rng.randf_range(-0.08, 0.08)
		var jz := rng.randf_range(-0.08, 0.08)
		var rot := Vector3(0, rng.randf_range(-0.25, 0.25), 0)
		_create_box(pos + Vector3(jx, y, jz), Vector3(0.62, 0.32, 0.44), mat_aged_wood, true, rot)
		for b in 3:
			_create_box(pos + Vector3(jx - 0.18 + b * 0.18, y + 0.22, jz), Vector3(0.09, 0.18, 0.09), mat_moon_glass, false, rot)


## Banco de lockers: las puertas miran al +Z local.
func _create_locker_bank(pos: Vector3, units: int, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var w := 0.45
	var total := units * w
	_add_primitive_box(root, Vector3(0, 0.95, 0), Vector3(total, 1.9, 0.5), mat_dark_steel)
	for i in units:
		var lx := -total * 0.5 + w * 0.5 + i * w
		_add_mesh_box(root, Vector3(lx, 1.4, 0.26), Vector3(w - 0.05, 0.86, 0.03), mat_paint_worn)
		_add_mesh_box(root, Vector3(lx, 0.48, 0.26), Vector3(w - 0.05, 0.86, 0.03), mat_paint_worn)
		_add_mesh_box(root, Vector3(lx + w * 0.28, 1.15, 0.29), Vector3(0.04, 0.14, 0.03), mat_rust_metal)


## Estantería metálica con cajas: el largo corre sobre el X local.
func _create_shelf_unit(pos: Vector3, length: float, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var d := 0.6
	var levels := [0.45, 1.05, 1.65]
	for sx in [-length * 0.5, length * 0.5]:
		for sz in [-d * 0.5, d * 0.5]:
			_add_primitive_box(root, Vector3(sx, 1.0, sz), Vector3(0.06, 2.0, 0.06), mat_rust_metal)
	for h in levels:
		_add_primitive_box(root, Vector3(0, h, 0), Vector3(length, 0.05, d), mat_rust_metal)
	for k in 6:
		var bh: float = levels[rng.randi_range(0, 2)]
		_add_mesh_box(root, Vector3(rng.randf_range(-length * 0.42, length * 0.42), bh + 0.2, rng.randf_range(-0.08, 0.08)), Vector3(0.4, 0.34, 0.38), mat_aged_wood, Vector3(0, rng.randf_range(-0.2, 0.2), 0))


## Pila de neumáticos.
func _create_tire_stack(pos: Vector3, count: int) -> void:
	for i in count:
		_create_cylinder(pos + Vector3(rng.randf_range(-0.07, 0.07), 0.11 + i * 0.22, rng.randf_range(-0.07, 0.07)), 0.42, 0.22, mat_rubber_black)


## Mingitorio de pared; inward_x = hacia dónde sobresale respecto del muro.
func _create_urinal(pos: Vector3, inward_x: float) -> void:
	_create_box(pos + Vector3(inward_x * 0.21, 0.95, 0), Vector3(0.42, 0.62, 0.36), mat_tile_wall)
	_create_box(pos + Vector3(inward_x * 0.24, 0.62, 0), Vector3(0.34, 0.06, 0.28), mat_tile_wall, false)
	_create_cylinder(pos + Vector3(inward_x * 0.08, 1.45, 0), 0.04, 0.36, mat_pipe_industrial, false)


## Carro de limpieza con balde y palo de piso.
func _create_cleaning_cart(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.5, 0), Vector3(0.55, 0.6, 0.85), mat_hazard_mark)
	_add_mesh_box(root, Vector3(0, 0.94, -0.32), Vector3(0.5, 0.06, 0.06), mat_dark_steel)
	for wx in [-0.22, 0.22]:
		for wz in [-0.3, 0.3]:
			_add_mesh_cylinder(root, Vector3(wx, 0.1, wz), 0.09, 0.05, mat_dark_steel, Vector3(0, 0, PI * 0.5))
	_add_mesh_cylinder(root, Vector3(0.14, 1.3, 0.26), 0.03, 1.5, mat_aged_wood, Vector3(0.28, 0, 0.14))
	_add_mesh_box(root, Vector3(0.3, 0.16, 0.62), Vector3(0.34, 0.32, 0.34), mat_mattress)


## Tanque horizontal sobre cunas.
func _create_horizontal_tank(pos: Vector3, length: float, radius: float, along_x: bool) -> void:
	var rot := Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
	_create_cylinder(pos, radius, length, mat_rust_metal, true, rot)
	for s in [-1.0, 1.0]:
		var off := Vector3(s * length * 0.32, 0, 0) if along_x else Vector3(0, 0, s * length * 0.32)
		_create_box(Vector3(pos.x + off.x, (pos.y - radius) * 0.5, pos.z + off.z), Vector3(radius * 1.3, maxf(pos.y - radius, 0.2), radius * 1.3), mat_dark_steel)
	_create_box(pos + Vector3(0, radius + 0.14, 0), Vector3(0.26, 0.28, 0.26), mat_pipe_industrial, false)


## Pallets vacíos apilados.
func _create_pallet_stack(pos: Vector3, count: int, rot_y: float) -> void:
	for i in count:
		var rot := Vector3(0, rot_y + i * 0.05, 0)
		var y := 0.09 + i * 0.16
		_create_box(pos + Vector3(0, y, 0), Vector3(1.2, 0.06, 1.0), mat_aged_wood, true, rot)
		_create_box(pos + Vector3(0, y - 0.05, 0), Vector3(1.15, 0.06, 0.15), mat_aged_wood, false, rot)


## Zorra hidráulica.
func _create_pallet_jack(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	for fx in [-0.28, 0.28]:
		_add_primitive_box(root, Vector3(fx, 0.08, 0.55), Vector3(0.16, 0.12, 1.5), mat_hazard_mark)
	_add_primitive_box(root, Vector3(0, 0.3, -0.32), Vector3(0.5, 0.5, 0.42), mat_dark_steel)
	_add_mesh_cylinder(root, Vector3(0, 0.98, -0.58), 0.04, 1.25, mat_rust_metal, Vector3(0.32, 0, 0))


## Carrete de cable de obra, tumbado de canto.
func _create_cable_spool(pos: Vector3, radius: float) -> void:
	var w := radius * 0.9
	var rot := Vector3(0, 0, PI * 0.5)
	_create_cylinder(pos + Vector3(0, radius, 0), radius * 0.62, w, mat_dark_steel, true, rot)
	for s in [-1.0, 1.0]:
		_create_cylinder(pos + Vector3(s * w * 0.5, radius, 0), radius, 0.07, mat_aged_wood, true, rot)
	_create_cylinder(pos + Vector3(0, radius, 0), radius * 0.9, w * 0.7, mat_dark_steel, false, rot)


## Chasis quemado: cobertura alta para esconderse en el taller.
func _create_wreck_car(pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	_add_primitive_box(root, Vector3(0, 0.62, 0), Vector3(1.85, 0.55, 4.1), mat_rust_metal)
	_add_primitive_box(root, Vector3(0, 1.12, -0.35), Vector3(1.7, 0.5, 1.9), mat_dark_steel)
	_add_mesh_box(root, Vector3(0, 1.22, 0.62), Vector3(1.5, 0.42, 0.06), mat_silhouette, Vector3(-0.45, 0, 0))
	_add_mesh_box(root, Vector3(0, 0.32, 2.03), Vector3(1.7, 0.3, 0.12), mat_dark_steel)
	for wx in [-0.86, 0.86]:
		for wz in [-1.35, 1.35]:
			_add_mesh_cylinder(root, Vector3(wx, 0.34, wz), 0.34, 0.22, mat_rubber_black, Vector3(0, 0, PI * 0.5))


## Puf de los chill rooms.
func _create_bean_bag(pos: Vector3, mat: StandardMaterial3D) -> void:
	_create_cylinder(pos + Vector3(0, 0.22, 0), 0.6, 0.44, mat)
	_create_sphere(pos + Vector3(0, 0.42, 0), 0.48, mat)


## Montón de escombros: los dos primeros con colisión, el resto decorativo.
func _create_rubble_pile(pos: Vector3, count: int, spread: float) -> void:
	for i in count:
		var s := rng.randf_range(0.22, 0.6)
		_create_box(pos + Vector3(rng.randf_range(-spread, spread), s * 0.4, rng.randf_range(-spread, spread)), Vector3(s, s * 0.75, s * 0.9), mat_rubble, i < 2, Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, PI), rng.randf_range(-0.3, 0.3)))


func _add_omni(pos: Vector3, color: Color, energy: float, light_range: float, shadows: bool = false) -> OmniLight3D:
	return BuildKit.omni(self, pos, color, energy, light_range, shadows)


# =============================================================================
# PRIMITIVAS
# =============================================================================

func _create_box(center: Vector3, size: Vector3, mat: StandardMaterial3D, has_collision: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	return BuildKit.box(self, center, size, mat, has_collision, rot)


func _create_cylinder(center: Vector3, radius: float, height: float, mat: StandardMaterial3D, has_collision: bool = true, rot: Vector3 = Vector3.ZERO) -> Node3D:
	return BuildKit.cylinder(self, center, radius, height, mat, has_collision, rot)


func _create_sphere(center: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	return BuildKit.sphere(self, center, radius, mat)


## Cilindro entre dos puntos arbitrarios: lásers, cables colgando, tensores de
## pasarela, cañerías cruzadas, sogas de las vallas. Sin colisión.
func _create_beam(from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	_add_beam(self, from, to, radius, mat)


## Igual que _create_beam pero colgando de un parent arbitrario y resolviendo
## la orientación con matemática pura en vez de look_at(): look_at() trabaja en
## espacio GLOBAL, así que dentro de un pivot rotado (cabezales, abanicos de
## láser) daba haces apuntando a cualquier lado.
func _add_beam(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	return BuildKit.beam(parent, from, to, radius, mat)


## Mesh sin colisión colgando de un parent arbitrario (los props compuestos que
## viven bajo un Node3D rotado los necesitan: _create_box siempre cuelga de self).
func _add_mesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return BuildKit.box(parent, pos, size, mat, false, rot) as MeshInstance3D


func _add_mesh_cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return BuildKit.cylinder(parent, pos, radius, height, mat, false, rot) as MeshInstance3D


func _add_mesh_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	return BuildKit.sphere(parent, pos, radius, mat)


## Colisión sin malla: red de seguridad (p.ej. arriba de la escalera rota).
func _create_invisible_barrier(center: Vector3, size: Vector3) -> void:
	BuildKit.barrier(self, center, size)


func _add_primitive_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


# =============================================================================
# A7 -- EL CLUB REACCIONA A LA MÚSICA DE VERDAD
# =============================================================================
## Si hay un club_music cargado, sale por un bus propio con un analizador de
## espectro y los graves reales manejan el wash del escenario, el foco de
## contra y el brillo de la pantalla LED.
##
## Esto convive con el reloj de BPM en vez de pelearse con él: los efectos
## reactivos NUNCA se tweenean (si no, dos escritores sobre light_energy y
## gana el último), y los del reloj no se registran acá. El reloj da el
## esqueleto rítmico aunque no haya música cargada; el analizador le pone el
## detalle del tema que esté sonando.

const CLUB_BUS := "ClubFX"


func _ensure_club_bus() -> String:
	var idx := AudioServer.get_bus_index(CLUB_BUS)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, CLUB_BUS)
		AudioServer.set_bus_send(idx, "Master")
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.12
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(idx, fx)
	_analyzer = AudioServer.get_bus_effect_instance(idx, 0)
	return CLUB_BUS


func _register_reactive_light(l: Light3D, base: float) -> void:
	_reactive_lights.append(l)
	_reactive_light_base.append(base)


func _register_reactive_mat(m: StandardMaterial3D, base: float) -> void:
	_reactive_mats.append(m)
	_reactive_mat_base.append(base)


func _process(delta: float) -> void:
	if _analyzer == null:
		return
	var mag := _analyzer.get_magnitude_for_frequency_range(35.0, 160.0,
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
	# En dB, no en lineal: la magnitud lineal de un bombo vive en un rango
	# minúsculo y mapeada directo da un valor pegado a cero casi siempre.
	var db := linear_to_db(maxf(mag, 0.0001))
	var target := clampf((db + 58.0) / 46.0, 0.0, 1.0)
	# Ataque rápido, caída lenta: el golpe se ve entero y la cola no titila.
	var rate := 26.0 if target > _bass else 5.0
	_bass = lerpf(_bass, target, clampf(rate * delta, 0.0, 1.0))

	for i in _reactive_lights.size():
		var l: Light3D = _reactive_lights[i]
		if is_instance_valid(l):
			l.light_energy = _reactive_light_base[i] * (0.45 + _bass * 1.5)
	for i in _reactive_mats.size():
		_reactive_mats[i].emission_energy_multiplier = _reactive_mat_base[i] * (0.5 + _bass * 2.2)


# =============================================================================
# LUMINARIAS Y PARTÍCULAS
# =============================================================================

## PAR-64: lata + gancho + abrazadera, con el spot saliendo de la boca. El
## cuerpo se orienta con look_at y el spot cuelga de él con rotación cero, así
## que apunta exactamente adonde apunta la lata (que es la mitad del efecto:
## una luz sin cuerpo visible no se lee como luminaria).
func _create_par_can(at: Vector3, aim: Vector3, color: Color, energy: float) -> SpotLight3D:
	var body := Node3D.new()
	add_child(body)
	body.position = at
	if at.distance_to(aim) > 0.05:
		var dir := at.direction_to(aim)
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		body.look_at_from_position(at, aim, up)

	_add_mesh_cylinder(body, Vector3(0, 0, -0.16), 0.13, 0.34, mat_dark_steel, Vector3(PI * 0.5, 0, 0))
	_add_mesh_cylinder(body, Vector3(0, 0, -0.34), 0.135, 0.03, _emissive(color, color, 3.0), Vector3(PI * 0.5, 0, 0))
	_add_mesh_box(body, Vector3(0, 0.17, 0), Vector3(0.05, 0.32, 0.05), mat_rust_metal)
	_add_mesh_box(body, Vector3(0, 0.32, 0), Vector3(0.2, 0.07, 0.2), mat_rust_metal)
	# Cable de alimentación colgando: el detalle que delata que es un aparato
	_add_mesh_cylinder(body, Vector3(0.1, 0.05, 0.14), 0.012, 0.34, mat_dark_steel, Vector3(0.5, 0, 0.3))

	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = energy
	spot.spot_range = 26.0
	spot.spot_angle = 21.0
	spot.spot_angle_attenuation = 1.1
	body.add_child(spot)
	spot.position = Vector3(0, 0, -0.36)
	return spot


## Chorro de CO2: one-shot explosivo que se dispara con restart().
func _make_jet_particles(tint: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 44
	p.lifetime = 1.2
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.6
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 18, 16))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.07
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -1.4, 0)
	pm.damping_min = 8.0
	pm.damping_max = 12.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	# La nube se abre a medida que frena: chorro fino al salir, hongo al final
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.2))
	growth.add_point(Vector2(0.3, 1.0))
	growth.add_point(Vector2(1.0, 2.6))
	var growth_tex := CurveTexture.new()
	growth_tex.curve = growth
	pm.scale_curve = growth_tex
	pm.color = Color(tint.r, tint.g, tint.b, 0.34)
	pm.color_ramp = _fade_ramp(0.06, 0.65)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	p.draw_pass_1 = quad
	p.material_override = _particle_material(tint, 0.9, true, 0.26)
	return p


## Rampa de alpha: entra rápido, se sostiene, se disuelve. La usan todos los
## sistemas de partículas del mapa.
func _fade_ramp(fade_in: float, fade_out: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(fade_in, Color(1, 1, 1, 1.0))
	g.add_point(fade_out, Color(1, 1, 1, 0.75))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Material de partículas. `additive` decide si el sistema SUMA luz (CO2,
## chispas, polvo en un haz) o si sólo tapa (humo, vapor).
##
## La textura de bocanada NO es opcional: sin ella el QuadMesh se dibuja
## entero y el humo de la pista se ve como una nube de cuadrados con borde
## recto en vez de humo.
func _particle_material(tint: Color, energy: float, additive: bool = true, alpha: float = 0.5) -> StandardMaterial3D:
	var m := BuildKit.glow_alpha(tint, energy, alpha)
	m.albedo_texture = ProcTextures.puff()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	if not additive:
		m.emission_enabled = false
	return m


## B3 -- Cortina de tiras de PVC: cada tira cuelga de su propio pivote y se
## mece con fase propia. Es movimiento periférico constante en un vano por el
## que la gente pasa todo el tiempo.
func _create_strip_curtain(at: Vector3, width: float, height: float, along_x: bool) -> void:
	var rail_size := Vector3(width, 0.08, 0.14) if along_x else Vector3(0.14, 0.08, width)
	_create_box(at + Vector3(0, height, 0), rail_size, mat_dark_steel, false)

	var n := maxi(int(width / 0.24), 3)
	var axis := "rotation:x" if along_x else "rotation:z"
	var strip_len := height - 0.12
	for i in n + 1:
		var t: float = lerpf(-width * 0.5 + 0.12, width * 0.5 - 0.12, float(i) / float(n))
		var off := Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)
		var pivot := Node3D.new()
		pivot.position = at + off + Vector3(0, height - 0.05, 0)
		add_child(pivot)
		var size := Vector3(0.22, strip_len, 0.014) if along_x else Vector3(0.014, strip_len, 0.22)
		_add_mesh_box(pivot, Vector3(0, -strip_len * 0.5, 0), size, mat_pvc_strip)

		var amp := rng.randf_range(0.012, 0.045)
		var per := rng.randf_range(2.4, 5.0)
		var tw := create_tween().set_loops()
		tw.tween_interval(rng.randf_range(0.0, 2.0))
		tw.tween_property(pivot, axis, amp, per).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(pivot, axis, -amp, per).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fx_tweens.append(tw)


# =============================================================================
# ATMÓSFERA: confeti, polvo en los haces, vapor, chispas
# =============================================================================

func _build_atmosphere() -> void:
	_build_confetti()
	_build_dust_motes()
	_build_boiler_steam()
	_build_sparks(Vector3(-room_size, 3.1, -room_size * 1.42))
	_build_sparks(Vector3(room_size * 1.35, 2.9, room_size * 0.2))


## A6 -- Confeti sobre la pista, disparado en el drop de cada frase.
func _build_confetti() -> void:
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 7.5
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.85
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-16, -2, -16), Vector3(32, 14, 32))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 0.2, 7.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -1.1, 0)   # papel: cae lento y se va de costado
	pm.damping_min = 0.4
	pm.damping_max = 1.1
	pm.angular_velocity_min = -420.0
	pm.angular_velocity_max = 420.0
	pm.scale_min = 0.06
	pm.scale_max = 0.13
	pm.color_ramp = _fade_ramp(0.02, 0.8)
	# Cada papelito de un color: el confeti monocromo no se lee como confeti
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.2, 0.55))
	ramp.set_color(1, Color(0.2, 0.9, 1.0))
	ramp.add_point(0.33, Color(1.0, 0.85, 0.2))
	ramp.add_point(0.66, Color(0.55, 0.3, 1.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_initial_ramp = ramp_tex
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.45)
	p.draw_pass_1 = quad
	var m := BuildKit.glow_alpha(Color(1, 1, 1), 0.35, 1.0)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m

	add_child(p)
	p.position = Vector3(0, 6.6, 1.5)

	var tw := create_tween().set_loops()
	tw.tween_interval(PHRASE - BAR)
	tw.tween_callback(p.restart)
	tw.tween_interval(BAR)
	_fx_tweens.append(tw)


## Polvo suspendido en los haces de luna. Poquísimas partículas, muy lentas:
## solo se ven cuando cruzan un haz, que es exactamente el efecto buscado.
func _build_dust_motes() -> void:
	for at in [Vector3(-3.5, 8.0, -4.0), Vector3(3.5, 8.0, 4.0), Vector3(-room_size, 3.0, -room_size * 1.4)]:
		var p := GPUParticles3D.new()
		p.amount = 90
		p.lifetime = 26.0
		p.preprocess = 14.0
		p.visibility_aabb = AABB(Vector3(-6, -10, -6), Vector3(12, 20, 12))

		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(2.6, 5.0, 2.6)
		pm.direction = Vector3(0.2, -1, 0.1)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.03
		pm.initial_velocity_max = 0.16
		pm.gravity = Vector3(0.01, -0.015, 0.0)
		pm.scale_min = 0.012
		pm.scale_max = 0.035
		pm.color = Color(0.75, 0.82, 1.0, 0.5)
		pm.color_ramp = _fade_ramp(0.12, 0.72)
		p.process_material = pm

		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		p.draw_pass_1 = quad
		p.material_override = _particle_material(Color(0.8, 0.85, 1.0), 1.2, true, 0.35)
		add_child(p)
		p.position = at


## Vapor saliendo de la chimenea de la caldera: la sala de calderas es la
## única del mapa que todavía "funciona" y tiene que notarse.
func _build_boiler_steam() -> void:
	var p := GPUParticles3D.new()
	p.amount = 34
	p.lifetime = 5.0
	p.preprocess = 3.0
	p.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 12, 10))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0.25, 1, 0.1)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.06, 0.25, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.scale_min = 0.9
	pm.scale_max = 2.2
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(1.0, 2.8))
	var gt := CurveTexture.new()
	gt.curve = growth
	pm.scale_curve = gt
	pm.color = Color(0.8, 0.78, 0.75, 0.2)
	pm.color_ramp = _fade_ramp(0.1, 0.5)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	p.draw_pass_1 = quad
	# Vapor: también MIX. Es blanco y opaco, no una fuente de luz.
	p.material_override = _particle_material(Color(0.62, 0.60, 0.58), 0.0, false, 0.18)
	add_child(p)
	# Boca de la chimenea de la caldera grande (zona calderas + offset local)
	p.position = _zone_centers["boiler"] + Vector3(3, 4.5, -3)


## Caja de empalme reventada: chisporrotea cada tanto y tira una luz azul.
func _build_sparks(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 0.8
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -4, -3), Vector3(6, 6, 6))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0, -0.4, 1)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.color = Color(1.0, 0.85, 0.55, 0.9)
	pm.color_ramp = _fade_ramp(0.02, 0.35)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	p.draw_pass_1 = quad
	p.material_override = _particle_material(Color(1.0, 0.8, 0.45), 3.0)
	add_child(p)
	p.position = at

	var flash := _add_omni(at + Vector3(0, -0.2, 0.3), Color(0.7, 0.85, 1.0), 0.0, 6.0)
	var tw := create_tween().set_loops()
	tw.tween_interval(rng.randf_range(6.0, 11.0))
	tw.tween_callback(p.restart)
	tw.tween_property(flash, "light_energy", 2.4, 0.03)
	tw.tween_property(flash, "light_energy", 0.0, 0.12)
	tw.tween_property(flash, "light_energy", 1.6, 0.04)
	tw.tween_property(flash, "light_energy", 0.0, 0.2)
	_fx_tweens.append(tw)


# =============================================================================
# C1 -- CALCOS (Decal): manchas, grafitis, afiches, grietas, charcos
# =============================================================================
## Los muros y el piso son primitivas de un solo material. La textura los saca
## de "plástico", pero lo que los saca de "genéricos" es la marca puntual: el
## tag que alguien pintó ACÁ, la mancha de aceite donde estaba el motor, la
## huella de la zorra que pasó mil veces por el mismo lado.
##
## Los Decal se proyectan sobre lo que ya está construido, así que esta pasada
## va al final de generate(). Cuestan poco (Forward+ los agrupa) y se apagan
## solos por distancia.

## Atajo: posición local de una zona -> posición mundo.
func _z(key: String, local: Vector3) -> Vector3:
	return _zone_centers[key] + local


# =============================================================================
# RELLENO DE LUZ DE LAS SALAS PERIMETRALES
# =============================================================================
## Con el techo a 6.5m y niebla volumétrica, los rincones de las 8 salas
## quedaban en negro absoluto: no se veía el detalle nuevo y, peor, esconderse
## dejaba de ser una decisión (todo era escondite). Dos omnis tenues por sala
## levantan el piso de negro SIN tocar el contraste de las luminarias, que
## siguen siendo las que marcan dónde mirar.
##
## Cada sala en su color: el ojo distingue en qué sector está aunque no vea
## un solo prop.
func _build_zone_fill() -> void:
	var fill := {
		"bar": Color(0.35, 0.75, 0.85),
		"banos": Color(0.35, 0.7, 0.75),
		"chill_ne": Color(1.0, 0.55, 0.25),
		"chill_se": Color(0.65, 0.35, 1.0),
		"boiler": Color(1.0, 0.42, 0.18),
		"cargo": Color(0.55, 0.4, 0.85),
		"workshop": Color(0.85, 0.72, 0.55),
		"entrance": Color(0.55, 0.62, 0.85),
	}
	for key in fill.keys():
		var col: Color = fill[key]
		for spot in [Vector3(-5.5, 3.4, -5.5), Vector3(5.5, 3.4, 5.5)]:
			_add_omni(_z(key, spot), col, 0.34, 15.0)
		# Y un rasante bajo contra el piso: es lo que hace que se vean los
		# calcos y la basura del suelo, que si no son detalle invisible.
		_add_omni(_z(key, Vector3(0, 1.1, 0)), col * 0.8, 0.22, 13.0)


func _floor_decal(at: Vector3, w: float, h: float, yaw: float, tex: Texture2D,
		tint: Color = Color.WHITE) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(w, 1.4, h)
	d.modulate = tint
	d.upper_fade = 0.35
	d.lower_fade = 0.35
	d.distance_fade_enabled = true
	d.distance_fade_begin = 34.0
	d.distance_fade_length = 14.0
	add_child(d)
	d.position = at
	d.rotation.y = yaw


## `normal` = hacia dónde mira la pared (hacia la sala). El calco proyecta en
## sentido contrario, hacia adentro del muro.
##
## OJO CON LA ORIENTACIÓN. Un Decal proyecta a lo largo de su -Y local y
## muestrea la textura con u = X local y v = Z local (v creciendo hacia
## ABAJO de la imagen). Armar la rotación "a ojo" con ángulos de Euler falla
## de dos formas distintas y las dos pasaron acá:
##   - en los muros ±X el X local terminaba siendo el eje VERTICAL, así que
##     el tag salía rotado 90° y estirado a lo ancho de la pared;
##   - en el muro -Z el X local apuntaba al revés y el tag salía ESPEJADO.
##
## Así que la base se arma explícita:
##   Y = normal            (para que -Y entre en el muro)
##   X = UP × normal       (el "a la derecha" del que mira la pared)
##   Z = X × normal        (que da el "hacia abajo": v de la imagen)
## y con eso `size` es siempre (ancho, profundidad, alto).
func _wall_decal(at: Vector3, normal: Vector3, w: float, h: float, tex: Texture2D,
		tint: Color = Color.WHITE, emissive: bool = false, energy: float = 1.0) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = tint
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 14.0
	if emissive:
		d.texture_emission = tex
		d.emission_energy = energy
	# Profundidad de proyeccion CORTA: un tabique del mapa tiene 0.3m y con
	# 0.9 de caja el calco atravesaba la pared y volvia a dibujarse -- espejado
	# -- sobre la cara de la sala de al lado.
	d.size = Vector3(w, 0.28, h)

	var n := normal.normalized()
	var right := Vector3.UP.cross(n)
	if right.length() < 0.01:
		right = Vector3.RIGHT # muro horizontal: no debería pasar, pero no rompe
	right = right.normalized()
	add_child(d)
	d.transform = Transform3D(Basis(right, n, right.cross(n)), at)


func _build_decal_pass() -> void:
	var ext := FACE_EXT   # cara del muro exterior, en locales de zona
	var part := FACE_PART # cara de un tabique

	# --- ATRIO: los tags de la pista, que es donde más gente pasó ----------
	# Cuidado con las 4 bocas del atrio (norte x -9..-4, sur x ±3.5, este y
	# oeste z ±2.5) y con la pantalla LED (norte, x -0.9..8.9): un calco
	# puesto sobre un vano se proyecta a través y aterriza en la sala de al
	# lado, que es exactamente lo que pasaba con el primero de esta lista.
	var atrium := [
		[Vector3(-2.4, 2.3, -part), Vector3(0, 0, 1)],
		[Vector3(-7.0, 1.9, part), Vector3(0, 0, -1)],
		[Vector3(6.5, 2.5, part), Vector3(0, 0, -1)],
		[Vector3(-part, 2.2, -9.2), Vector3(1, 0, 0)],
		[Vector3(-part, 1.8, 6.5), Vector3(1, 0, 0)],
		[Vector3(part, 2.4, -6.5), Vector3(-1, 0, 0)],
		[Vector3(part, 2.0, 5.0), Vector3(-1, 0, 0)],
	]
	for i in atrium.size():
		var a: Array = atrium[i]
		# Emisivos: bajo la luz del club los tags "prenden". Es gratis y hace
		# que la pista tenga color aun cuando el strobe está apagado.
		_wall_decal(_z("dance", a[0]), a[1], 2.9, 1.25, ProcTextures.graffiti(i % 4), Color(1, 1, 1), true, 0.8)

	for k in 7:
		_floor_decal(_z("dance", Vector3(rng.randf_range(-10.0, 10.0), 0.02, rng.randf_range(-9.5, 10.0))),
				rng.randf_range(1.6, 3.0), rng.randf_range(1.6, 3.0), rng.randf_range(0, PI),
				ProcTextures.stain(k % 4), Color(1, 1, 1, 0.8))
	for k in 4:
		_floor_decal(_z("dance", Vector3(rng.randf_range(-9.0, 9.0), 0.02, rng.randf_range(-9.0, 9.0))),
				3.0, 3.0, rng.randf_range(0, PI), ProcTextures.crack(k % 3))

	# --- ENTRADA: la zona más pisada del club. Tags, afiches y gomas ------
	for i in 5:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_wall_decal(_z("entrance", Vector3(side * (part - 0.02), 1.6 + float(i) * 0.35, -6.0 + float(i) * 2.6)),
				Vector3(-side, 0, 0), 2.8, 1.2, ProcTextures.graffiti(i % 4), Color(1, 1, 1), true, 0.7)
	for i in 6:
		_wall_decal(_z("entrance", Vector3(-part + 0.02, 1.5 + rng.randf_range(0.0, 1.4), -9.0 + float(i) * 0.75)),
				Vector3(1, 0, 0), 0.52, 0.76, ProcTextures.poster(i % 4))
	# Huellas de neumático desde el portón hacia el atrio
	for i in 4:
		_floor_decal(_z("entrance", Vector3(-2.4 + float(i) * 1.6, 0.02, 6.0)), 0.55, 5.5, 0.0, ProcTextures.tire())
	for i in 3:
		_floor_decal(_z("entrance", Vector3(-1.5 + float(i) * 1.5, 0.02, 1.2)), 0.9, 1.35, 0.0, ProcTextures.arrow())
	_floor_decal(_z("entrance", Vector3(9.3, 0.02, 3.0)), 3.4, 3.4, 0.4, ProcTextures.stain(2))

	# --- BAÑOS: tags en los cubículos, charcos y azulejo rajado -----------
	for i in 4:
		_wall_decal(_z("banos", Vector3(-6.2 + float(i) * 1.6, 1.7, 7.05)), Vector3(0, 0, -1),
				1.3, 0.8, ProcTextures.graffiti((i + 2) % 4), Color(1, 1, 1), true, 0.5)
	_wall_decal(_z("banos", Vector3(0.0, 2.1, ext - 0.13)), Vector3(0, 0, -1), 3.0, 1.3, ProcTextures.graffiti(1), Color(1, 1, 1), true, 0.6)
	for i in 4:
		_floor_decal(_z("banos", Vector3(rng.randf_range(-9.0, 4.0), 0.02, rng.randf_range(-8.0, 8.0))),
				rng.randf_range(1.8, 3.2), rng.randf_range(1.4, 2.6), rng.randf_range(0, PI), ProcTextures.puddle(i % 2))
	_floor_decal(_z("banos", Vector3(-9.0, 0.025, -8.8)), 3.0, 2.6, 0.2, ProcTextures.puddle(0))
	for i in 3:
		_floor_decal(_z("banos", Vector3(rng.randf_range(-8.0, 8.0), 0.02, rng.randf_range(-8.0, 8.0))),
				2.6, 2.6, rng.randf_range(0, PI), ProcTextures.crack(i % 3))

	# --- TALLER: aceite, gomas y quemaduras -------------------------------
	for i in 5:
		_floor_decal(_z("workshop", Vector3(rng.randf_range(-7.0, 6.0), 0.02, rng.randf_range(-4.0, 8.0))),
				rng.randf_range(2.0, 3.4), rng.randf_range(1.8, 3.0), rng.randf_range(0, PI),
				ProcTextures.stain(0), Color(1, 1, 1, 0.95))
	_floor_decal(_z("workshop", Vector3(2.6, 0.025, 1.2)), 2.4, 2.4, 0.0, ProcTextures.stain(0))
	for i in 3:
		_floor_decal(_z("workshop", Vector3(-5.0 + float(i) * 0.1, 0.02, 3.4 + float(i) * 3.0)), 0.5, 4.0, 0.38, ProcTextures.tire())
	_floor_decal(_z("workshop", Vector3(0.5, 0.025, 8.8)), 2.0, 2.0, 0.0, ProcTextures.scorch())
	_wall_decal(_z("workshop", Vector3(-ext + 0.02, 2.4, 4.0)), Vector3(1, 0, 0), 2.6, 1.1, ProcTextures.graffiti(3), Color(0.8, 0.8, 0.8), true, 0.4)

	# --- DEPÓSITO: flechas de circulación, gomas de la zorra, cajas -------
	# La punta de la flecha apunta al -Z local del calco; con yaw = PI señalan
	# hacia +Z, o sea hacia la boca que da al atrio. (Con PI*0.5 apuntaban
	# hacia el muro oeste, cruzadas respecto del pasillo que marcan.)
	for i in 5:
		_floor_decal(_z("cargo", Vector3(-6.5, 0.02, -6.0 + float(i) * 3.4)), 1.0, 1.5, PI, ProcTextures.arrow())
	for i in 4:
		_floor_decal(_z("cargo", Vector3(-8.2 + float(i) * 0.9, 0.02, 2.0)), 0.5, 7.0, 0.0, ProcTextures.tire())
	for i in 4:
		_floor_decal(_z("cargo", Vector3(rng.randf_range(-9.0, 9.0), 0.02, rng.randf_range(-9.0, 9.0))),
				rng.randf_range(1.6, 2.8), rng.randf_range(1.6, 2.8), rng.randf_range(0, PI), ProcTextures.stain(3))
	_wall_decal(_z("cargo", Vector3(3.0, 2.6, -ext + 0.02)), Vector3(0, 0, 1), 3.0, 1.3, ProcTextures.graffiti(0), Color(1, 1, 1), true, 0.5)

	# --- CALDERAS: óxido corrido, charcos, quemaduras ---------------------
	for i in 5:
		_floor_decal(_z("boiler", Vector3(rng.randf_range(-9.0, 8.0), 0.02, rng.randf_range(-9.0, 9.0))),
				rng.randf_range(2.0, 3.6), rng.randf_range(1.8, 3.2), rng.randf_range(0, PI), ProcTextures.stain(2))
	_floor_decal(_z("boiler", Vector3(3.0, 0.025, -1.0)), 2.6, 2.6, 0.0, ProcTextures.scorch())
	_floor_decal(_z("boiler", Vector3(7.2, 0.025, 4.4)), 2.0, 2.0, 0.0, ProcTextures.scorch())
	for i in 3:
		_floor_decal(_z("boiler", Vector3(rng.randf_range(-8.0, 2.0), 0.02, rng.randf_range(0.0, 9.0))),
				2.4, 1.9, rng.randf_range(0, PI), ProcTextures.puddle(i % 2))
	# Chorreadura de óxido bajando por el muro este, debajo de las válvulas
	for i in 3:
		_wall_decal(_z("boiler", Vector3(ext - 0.02, 2.6 - float(i) * 0.2, 7.0 + float(i) * 0.9)), Vector3(-1, 0, 0), 1.4, 2.6, ProcTextures.stain(2), Color(1.2, 0.9, 0.7))

	# --- BAR: manchas en la madera, afiches sobre la barra ----------------
	for i in 5:
		_floor_decal(_z("bar", Vector3(rng.randf_range(-9.0, 4.0), 0.02, rng.randf_range(-9.0, 9.0))),
				rng.randf_range(1.4, 2.6), rng.randf_range(1.4, 2.6), rng.randf_range(0, PI), ProcTextures.stain(1))
	for i in 5:
		_wall_decal(_z("bar", Vector3(-ext + 0.02, 1.7 + rng.randf_range(0.0, 1.2), -2.0 + float(i) * 1.1)),
				Vector3(1, 0, 0), 0.5, 0.74, ProcTextures.poster((i + 1) % 4))
	_wall_decal(_z("bar", Vector3(part - 0.02, 2.5, -6.0)), Vector3(-1, 0, 0), 2.8, 1.2, ProcTextures.graffiti(2), Color(1, 1, 1), true, 0.7)

	# --- CHILL ROOMS: la pared de los afiches ------------------------------
	for zone in ["chill_ne", "chill_se"]:
		for i in 7:
			_wall_decal(_z(zone, Vector3(-part + 0.02, 1.5 + rng.randf_range(0.0, 1.7), -6.0 + float(i) * 1.7)),
					Vector3(1, 0, 0), 0.5, 0.74, ProcTextures.poster(i % 4))
		_wall_decal(_z(zone, Vector3(4.0, 2.4, -ext + 0.02)), Vector3(0, 0, 1), 2.7, 1.15, ProcTextures.graffiti(1), Color(1, 1, 1), true, 0.55)
		for i in 3:
			_floor_decal(_z(zone, Vector3(rng.randf_range(-8.0, 8.0), 0.02, rng.randf_range(-8.0, 8.0))),
					rng.randf_range(1.5, 2.6), rng.randf_range(1.5, 2.6), rng.randf_range(0, PI), ProcTextures.stain(1))


# =============================================================================
# B3 -- BICHOS: ratas contra los zócalos, palomas en las cerchas
# =============================================================================
## Es un juego que se llama Rats N Rust: que haya ratas de verdad correteando
## contra las paredes es la clase de detalle que se nota sin que nadie lo
## busque. No tienen colisión ni entran en la lógica de nada -- son puro
## movimiento periférico.

func _build_critters() -> void:
	var routes := [
		# Depósito: pegada al muro norte y bajando por el este
		PackedVector3Array([_z("cargo", Vector3(-9.8, 0, -9.9)), _z("cargo", Vector3(9.8, 0, -9.9)),
				_z("cargo", Vector3(9.8, 0, -4.0)), _z("cargo", Vector3(-2.0, 0, -4.2))]),
		# Calderas: alrededor de los barriles
		PackedVector3Array([_z("boiler", Vector3(-9.9, 0, 9.8)), _z("boiler", Vector3(-4.5, 0, 9.8)),
				_z("boiler", Vector3(-4.5, 0, 4.0)), _z("boiler", Vector3(-9.9, 0, 4.0))]),
		# Taller: bajo la mesa de trabajo
		PackedVector3Array([_z("workshop", Vector3(-9.8, 0, -9.8)), _z("workshop", Vector3(6.0, 0, -9.8)),
				_z("workshop", Vector3(6.0, 0, -6.5)), _z("workshop", Vector3(-9.8, 0, -6.2))]),
		# Baños: por detrás de los cubículos
		PackedVector3Array([_z("banos", Vector3(-9.9, 0, 9.9)), _z("banos", Vector3(6.5, 0, 9.9)),
				_z("banos", Vector3(6.5, 0, 6.6)), _z("banos", Vector3(-9.9, 0, 6.6))]),
	]
	for r in routes:
		_create_rat(r)

	# Palomas en el cordón inferior de las cerchas: se quedan quietas y cada
	# tanto pegan un saltito. A 20m de altura con un aleteo alcanza.
	var perches := [
		Vector3(-11.0, ROOF_Y - 1.6, -8.0), Vector3(4.0, ROOF_Y - 1.6, 0.0),
		Vector3(13.0, ROOF_Y - 1.6, 8.0), Vector3(-6.0, ROOF_Y - 1.6, 16.0),
		Vector3(9.0, ROOF_Y - 1.6, -16.0),
	]
	for p in perches:
		_create_pigeon(p)


func _create_rat(waypoints: PackedVector3Array) -> void:
	if waypoints.size() < 2:
		return
	var rat := Node3D.new()
	add_child(rat)
	rat.position = waypoints[0]
	# El bicho mira a -Z (igual que los personajes del juego)
	_add_mesh_box(rat, Vector3(0, 0.075, 0.02), Vector3(0.11, 0.1, 0.24), mat_fur_dark)
	_add_mesh_sphere(rat, Vector3(0, 0.085, -0.14), 0.052, mat_fur_dark)
	for e in [-0.035, 0.035]:
		_add_mesh_sphere(rat, Vector3(e, 0.125, -0.14), 0.021, mat_fur_dark)
	_add_mesh_cylinder(rat, Vector3(0, 0.055, 0.24), 0.011, 0.24, mat_fur_dark, Vector3(PI * 0.5, 0, 0))
	# Dos puntitos rojos: a oscuras, lo único que se ve de una rata son los ojos
	for e in [-0.022, 0.022]:
		_add_mesh_sphere(rat, Vector3(e, 0.095, -0.185), 0.009, mat_neon_red_dim)

	var tw := create_tween().set_loops()
	for i in waypoints.size():
		var from: Vector3 = waypoints[i]
		var to: Vector3 = waypoints[(i + 1) % waypoints.size()]
		var dir := from.direction_to(to)
		var yaw := atan2(-dir.x, -dir.z)
		tw.tween_property(rat, "rotation:y", yaw, 0.16)
		# Se queda quieta olfateando antes de arrancar: el arranque brusco
		# después de la pausa es lo que hace que se lea como bicho vivo.
		tw.tween_interval(rng.randf_range(0.5, 2.6))
		tw.tween_property(rat, "position", to, from.distance_to(to) / rng.randf_range(2.2, 3.8))
	_fx_tweens.append(tw)


func _create_pigeon(at: Vector3) -> void:
	var bird := Node3D.new()
	add_child(bird)
	bird.position = at
	bird.rotation.y = rng.randf_range(0.0, TAU)
	_add_mesh_box(bird, Vector3(0, 0.09, 0), Vector3(0.1, 0.13, 0.2), mat_bird_dark)
	_add_mesh_sphere(bird, Vector3(0, 0.19, -0.07), 0.045, mat_bird_dark)
	_add_mesh_box(bird, Vector3(0, 0.075, 0.14), Vector3(0.07, 0.03, 0.11), mat_bird_dark, Vector3(-0.3, 0, 0))
	var wings: Array[Node3D] = []
	for s in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(s * 0.05, 0.12, 0)
		bird.add_child(w)
		_add_mesh_box(w, Vector3(s * 0.07, 0, 0), Vector3(0.14, 0.02, 0.16), mat_bird_dark)
		wings.append(w)

	var tw := create_tween().set_loops()
	tw.tween_interval(rng.randf_range(4.0, 12.0))
	# Saltito + aleteo: dos vueltas de alas y se acomoda de nuevo
	tw.tween_property(bird, "position:y", at.y + 0.22, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bird, "position:y", at.y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(bird, "rotation:y", bird.rotation.y + rng.randf_range(-1.4, 1.4), 0.25)
	_fx_tweens.append(tw)

	for i in wings.size():
		var w: Node3D = wings[i]
		var s := -1.0 if i == 0 else 1.0
		var wt := create_tween().set_loops()
		wt.tween_interval(rng.randf_range(4.0, 12.0))
		for f in 3:
			wt.tween_property(w, "rotation:z", s * -0.9, 0.07)
			wt.tween_property(w, "rotation:z", 0.0, 0.09)
		_fx_tweens.append(wt)


# =============================================================================
# B4 -- AMBIENTE SONORO POR ZONA
# =============================================================================
## Hasta ahora lo único que sonaba en el mapa era la música del DJ. Cada sala
## tiene su fuente propia (todas generadas en código, cero assets): la caldera
## zumba, el baño gotea, el metal cruje, entra viento por la claraboya. Con
## audio 3D, moverse por la nave suena distinto en cada sector -- y estando
## escondido en silencio, esa capa es lo que sostiene la tensión.

func _build_zone_ambience() -> void:
	var sources := [
		# [posición, stream, unit_size, volumen dB]
		[_z("boiler", Vector3(3, 1.6, -3)), ProceduralSound.machine_hum(62.0, 4.0, 0.4), 9.0, -10.0],
		[_z("boiler", Vector3(-6.8, 1.2, -7.5)), ProceduralSound.machine_hum(118.0, 3.0, 0.25), 7.0, -16.0],
		[_z("banos", Vector3(-9.0, 1.2, -8.8)), ProceduralSound.drip_loop(9.0, 5, 0.55), 6.0, -9.0],
		[_z("banos", Vector3(0.5, 0.6, 0.5)), ProceduralSound.drip_loop(13.0, 3, 0.4), 5.0, -14.0],
		[_z("bar", Vector3(0.8, 1.0, 2.6)), ProceduralSound.electric_buzz(2.0, 0.3), 4.5, -18.0],
		[_z("workshop", Vector3(2.6, 3.0, 1.2)), ProceduralSound.metal_creak(11.0, 3, 0.45), 12.0, -12.0],
		[_z("cargo", Vector3(0, 5.0, 0)), ProceduralSound.metal_creak(14.0, 2, 0.4), 14.0, -14.0],
		[Vector3(0, ROOF_Y - 3.0, -4.0), ProceduralSound.wind_loop(13.0, 0.42), 24.0, -11.0],
		[Vector3(9.0, ROOF_Y - 3.0, 12.0), ProceduralSound.wind_loop(11.0, 0.32), 20.0, -15.0],
		[_z("entrance", Vector3(0, 3.0, 9.0)), ProceduralSound.wind_loop(9.0, 0.3), 10.0, -16.0],
		[_z("chill_ne", Vector3(-9.6, 1.0, -7.6)), ProceduralSound.electric_buzz(2.0, 0.2), 4.0, -21.0],
		[_z("chill_se", Vector3(-9.6, 1.0, -7.6)), ProceduralSound.electric_buzz(2.0, 0.2), 4.0, -21.0],
	]
	for s in sources:
		var p := AudioStreamPlayer3D.new()
		p.stream = s[1]
		p.unit_size = s[2]
		p.volume_db = s[3]
		# Atenuación fuerte: el ambiente tiene que morirse al salir de la sala,
		# si no se mezcla todo y la nave suena a una sola cosa.
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.max_distance = 30.0
		add_child(p)
		p.position = s[0]
		p.play()


# =============================================================================
# B6 -- BASURA CON FÍSICA
# =============================================================================
## Vasos, latas y botellas sueltas que salen volando cuando alguien corre.
##
## Van en su PROPIA capa de colisión (LOOSE_LAYER) y el jugador NO la enmascara:
## un CharacterBody3D trata a un RigidBody3D como pared, así que si compartieran
## capa una lata de 13cm sería un muro invisible en plena persecución. El
## empujón lo da un Area3D en el pie del jugador (ver Player._kick_loose_props).

const LOOSE_LAYER := 4 # bit 4 -> valor 8


func _build_loose_debris() -> void:
	var phys := PhysicsMaterial.new()
	phys.friction = 0.45
	phys.bounce = 0.3

	var spots := [
		[_z("dance", Vector3(-7.0, 0, 3.0)), 4], [_z("dance", Vector3(6.5, 0, 6.5)), 4],
		[_z("dance", Vector3(1.0, 0, 9.0)), 3], [_z("dance", Vector3(8.5, 0, -3.0)), 3],
		[_z("bar", Vector3(4.6, 0, -3.0)), 4], [_z("bar", Vector3(-5.0, 0, 4.0)), 3],
		[_z("entrance", Vector3(6.2, 0, 5.0)), 4], [_z("entrance", Vector3(-3.0, 0, 8.0)), 3],
		[_z("banos", Vector3(-3.0, 0, 0.0)), 3],
		[_z("chill_ne", Vector3(1.5, 0, 3.5)), 3], [_z("chill_se", Vector3(1.5, 0, 3.5)), 3],
		[_z("workshop", Vector3(3.0, 0, 3.0)), 3], [_z("cargo", Vector3(1.0, 0, 4.0)), 3],
		[_z("boiler", Vector3(-2.0, 0, 1.0)), 3],
	]
	for s in spots:
		var at: Vector3 = s[0]
		for i in int(s[1]):
			_create_loose_item(at + Vector3(rng.randf_range(-1.3, 1.3), 0, rng.randf_range(-1.3, 1.3)), phys)


func _create_loose_item(at: Vector3, phys: PhysicsMaterial) -> void:
	var kind := rng.randi_range(0, 2)
	var radius := 0.042
	var height := 0.13
	var mat := mat_shrinkwrap
	match kind:
		0: # lata
			radius = 0.033
			height = 0.125
			mat = mat_dark_steel
		1: # vaso de plástico
			radius = 0.043
			height = 0.115
			mat = mat_shrinkwrap
		2: # botella
			radius = 0.038
			height = 0.24
			mat = mat_moon_glass

	var body := RigidBody3D.new()
	body.mass = 0.13
	body.physics_material_override = phys
	body.linear_damp = 0.5
	body.angular_damp = 1.1
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_collision_layer_value(LOOSE_LAYER, true)
	body.set_collision_mask_value(1, true)          # el mapa
	body.set_collision_mask_value(LOOSE_LAYER, true) # entre ellas
	add_child(body)
	body.position = at + Vector3(0, height * 0.5 + 0.02, 0)

	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * (0.62 if kind == 2 else 1.0)
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)
