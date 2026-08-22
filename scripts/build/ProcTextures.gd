class_name ProcTextures
extends RefCounted
## Texturas generadas en código: superficies (ladrillo, hormigón, madera,
## azulejo, chapa, óxido, rejilla) y calcos (manchas, grafitis, afiches,
## marcas de neumático, grietas, quemaduras).
##
## POR QUÉ existe esto: el mapa es 100% primitivas con material_override de
## color plano. Sin textura, un muro de 22m de ladrillo es un rectángulo
## naranja liso y el ojo lo lee como plástico. Con una textura tileable +
## normal map aplicada por TRIPLANAR EN ESPACIO MUNDO, todas las cajas que
## comparten material calzan el patrón entre sí sin tocar una sola UV.
##
## Todo se genera una vez y queda cacheado como estático: la primera partida
## paga ~0.3s de generación y las siguientes salen gratis. El juego renderiza
## a 480x270, así que 128px de lado sobra y de paso el loop en GDScript no
## se hace eterno (un 256 cuadruplica el costo para nada).
##
## Todas las funciones son deterministas: misma seed -> mismos bytes. Eso
## importa porque el mapa se construye igual en todos los peers.

const TILE := 128       # lado de las texturas de superficie
const DECAL := 96       # lado base de los calcos

static var _cache: Dictionary = {}


# =============================================================================
# API DE SUPERFICIES
# =============================================================================
## Devuelven { "albedo": ImageTexture, "normal": ImageTexture, "rough": ImageTexture }

static func brick() -> Dictionary:
	return _surface("brick", Callable(ProcTextures, "_gen_brick"))


static func concrete() -> Dictionary:
	return _surface("concrete", Callable(ProcTextures, "_gen_concrete"))


static func planks() -> Dictionary:
	return _surface("planks", Callable(ProcTextures, "_gen_planks"))


static func tiles() -> Dictionary:
	return _surface("tiles", Callable(ProcTextures, "_gen_tiles"))


static func plate() -> Dictionary:
	return _surface("plate", Callable(ProcTextures, "_gen_plate"))


static func rust() -> Dictionary:
	return _surface("rust", Callable(ProcTextures, "_gen_rust"))


static func grate() -> Dictionary:
	return _surface("grate", Callable(ProcTextures, "_gen_grate"))


static func grunge() -> Dictionary:
	return _surface("grunge", Callable(ProcTextures, "_gen_grunge"))


## Aplica una superficie a un material existente.
##
## `world_size` = cuántos metros ocupa UN tile. Triplanar en espacio mundo:
## dos cajas distintas con el mismo material continúan el patrón entre sí,
## sin tocar una sola UV (que en primitivas de Godot no controlamos).
##
## OJO con `tint`: la textura MULTIPLICA a albedo_color. Los patrones con
## color propio (ladrillo, óxido, azulejo) necesitan tint casi blanco o
## salen negros; los que son sólo mugre gris se aplican sobre el color
## original del material y ahí el tint se deja en -1 (no tocar).
static func apply(mat: StandardMaterial3D, surface: Dictionary, world_size: float,
		normal_depth: float = 1.0, rough_amount: float = 0.0,
		tint: Color = Color(-1, -1, -1)) -> void:
	if surface.is_empty():
		return
	if tint.r >= 0.0:
		mat.albedo_color = tint
	mat.albedo_texture = surface["albedo"]
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	mat.uv1_scale = Vector3.ONE / maxf(world_size, 0.01)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if normal_depth > 0.0:
		mat.normal_enabled = true
		mat.normal_texture = surface["normal"]
		mat.normal_scale = normal_depth
	if rough_amount > 0.0:
		mat.roughness_texture = surface["rough"]
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED


# =============================================================================
# API DE CALCOS (RGBA con alpha: lo que no se dibuja no se proyecta)
# =============================================================================

static func stain(variant: int) -> Texture2D:
	return _decal("stain%d" % variant, func() -> Image: return _gen_stain(variant))


static func graffiti(variant: int) -> Texture2D:
	return _decal("graf%d" % variant, func() -> Image: return _gen_graffiti(variant))


static func poster(variant: int) -> Texture2D:
	return _decal("poster%d" % variant, func() -> Image: return _gen_poster(variant))


static func tire() -> Texture2D:
	return _decal("tire", func() -> Image: return _gen_tire())


static func crack(variant: int) -> Texture2D:
	return _decal("crack%d" % variant, func() -> Image: return _gen_crack(variant))


static func scorch() -> Texture2D:
	return _decal("scorch", func() -> Image: return _gen_scorch())


static func puddle(variant: int) -> Texture2D:
	return _decal("puddle%d" % variant, func() -> Image: return _gen_puddle(variant))


static func arrow() -> Texture2D:
	return _decal("arrow", func() -> Image: return _gen_arrow())


## Bocanada blanda para partículas (humo, vapor, CO2, polvo). SIN esto los
## sistemas de partículas dibujan QuadMesh a pelo y el humo de la pista se ve
## como una nube de cuadrados blancos con borde recto -- que es exactamente
## lo que pasaba.
static func puff() -> Texture2D:
	return _decal("puff", func() -> Image: return _gen_puff())


static func _gen_puff() -> Image:
	var s := 64
	var img := _rgba(s, s)
	var n := _noise(1234, 0.06, 3)
	var half := float(s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(float(x) - half, float(y) - half).length() / half
			# Borde mordido por ruido: una bocanada perfectamente circular se
			# lee como una pelota, no como humo.
			var wob := n.get_noise_2d(float(x), float(y)) * 0.28
			var a: float = clampf(1.0 - (d + wob), 0.0, 1.0)
			# Caida MUY blanda: si el disco tiene silueta reconocible, 40
			# bocanadas se leen como 40 bolas de algodon en vez de bruma.
			a = pow(a, 3.2)
			if a > 0.002:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


# =============================================================================
# INFRAESTRUCTURA
# =============================================================================

static func _surface(key: String, gen: Callable) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	# El generador devuelve [albedo: Image, height: PackedFloat32Array]
	var result: Array = gen.call()
	var albedo: Image = result[0]
	var height: PackedFloat32Array = result[1]
	albedo.generate_mipmaps()

	var out := {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(_normal_from_height(height, TILE)),
		"rough": ImageTexture.create_from_image(_rough_from_height(height, TILE)),
	}
	_cache[key] = out
	return out


static func _decal(key: String, gen: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img: Image = gen.call()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Ruido tileable: mezcla bilineal de 4 copias desplazadas. Sin esto se ve la
## costura del tile cada 2m en un muro de 22m y no hay forma de no notarla.
static func _tileable(n: FastNoiseLite, x: int, y: int) -> float:
	var fx := float(x) / float(TILE)
	var fy := float(y) / float(TILE)
	var a := n.get_noise_2d(float(x), float(y))
	var b := n.get_noise_2d(float(x - TILE), float(y))
	var c := n.get_noise_2d(float(x), float(y - TILE))
	var d := n.get_noise_2d(float(x - TILE), float(y - TILE))
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _noise(seed_value: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


## Determinista y barato: hash entero para variar cada ladrillo / tabla /
## baldosa sin gastar una llamada de ruido por pieza.
static func _hash01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 100000) / 100000.0


static func _blank_rgb() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(TILE * TILE * 3)
	return data


static func _put(data: PackedByteArray, i: int, c: Color) -> void:
	data[i * 3] = int(clampf(c.r, 0.0, 1.0) * 255.0)
	data[i * 3 + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
	data[i * 3 + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)


## Sobel sobre el height field. Las texturas son tileables, así que los
## vecinos se toman con wrap (%): si no, aparece un borde marcado de 1px.
static func _normal_from_height(h: PackedFloat32Array, size: int, strength: float = 2.6) -> Image:
	var data := PackedByteArray()
	data.resize(size * size * 3)
	for y in size:
		for x in size:
			var xl: float = h[y * size + (x - 1 + size) % size]
			var xr: float = h[y * size + (x + 1) % size]
			var yu: float = h[((y - 1 + size) % size) * size + x]
			var yd: float = h[((y + 1) % size) * size + x]
			var nx := (xl - xr) * strength
			var ny := (yd - yu) * strength
			var v := Vector3(nx, ny, 1.0).normalized()
			var i := y * size + x
			data[i * 3] = int((v.x * 0.5 + 0.5) * 255.0)
			data[i * 3 + 1] = int((v.y * 0.5 + 0.5) * 255.0)
			data[i * 3 + 2] = int((v.z * 0.5 + 0.5) * 255.0)
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return img


## Lo hundido está más sucio (junta, poro, pozo de óxido) => más rugoso.
static func _rough_from_height(h: PackedFloat32Array, size: int) -> Image:
	var data := PackedByteArray()
	data.resize(size * size * 3)
	for i in size * size:
		var r := int(clampf(1.0 - h[i] * 0.55, 0.0, 1.0) * 255.0)
		data[i * 3] = r
		data[i * 3 + 1] = r
		data[i * 3 + 2] = r
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)


# =============================================================================
# GENERADORES DE SUPERFICIE
# Cada uno devuelve [Image RGB8 de albedo, PackedFloat32Array de altura 0..1]
# =============================================================================

## Aparejo a soga: 4 ladrillos por hilada, hiladas alternadas corridas medio
## ladrillo. Con TILE=128 y ladrillo de 32x16 el patrón cierra en el borde.
static func _gen_brick() -> Array:
	var bw := 32
	var bh := 16
	var mortar := 3
	var grain := _noise(11, 0.09, 3)
	var dirt := _noise(29, 0.02, 2)

	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		var row := y / bh
		var shift := (row % 2) * (bw / 2)
		for x in TILE:
			var i := y * TILE + x
			var lx := posmod(x + shift, bw)
			var ly := posmod(y, bh)
			var g := _tileable(grain, x, y)
			var dust: float = _tileable(dirt, x, y) * 0.5 + 0.5

			var is_mortar := lx < mortar or ly < mortar
			if is_mortar:
				var m: float = 0.13 + g * 0.05 + dust * 0.05
				_put(data, i, Color(m * 1.05, m, m * 0.92))
				height[i] = 0.18 + g * 0.12
			else:
				# Cada ladrillo con su tono: sin esto la pared es un patrón
				# repetido evidente aunque tenga junta.
				var bid := _hash01(posmod(x + shift, TILE) / bw + row * 17, row)
				var tone: float = 0.72 + bid * 0.6
				var base := Color(0.30, 0.135, 0.095) * tone
				base = base.lerp(Color(0.16, 0.13, 0.12), dust * 0.45)
				base.r += g * 0.045
				base.g += g * 0.02
				_put(data, i, base)
				# Bisel en el borde del ladrillo (2px) para que la normal
				# no sea un escalón vertical duro
				var edge := minf(minf(float(lx - mortar), float(ly - mortar)), 2.0) / 2.0
				height[i] = 0.72 + clampf(edge, 0.0, 1.0) * 0.22 + g * 0.06
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Hormigón encofrado: manchones + poros + la línea horizontal del fenólico
## cada 32px (lo que delata que es hormigón y no "gris").
static func _gen_concrete() -> Array:
	var blotch := _noise(3, 0.014, 4)
	var pore := _noise(7, 0.22, 2)
	var stainn := _noise(41, 0.006, 3)

	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		var board := 1.0 if posmod(y, 32) < 2 else 0.0
		for x in TILE:
			var i := y * TILE + x
			var b := _tileable(blotch, x, y) * 0.5 + 0.5
			var p := _tileable(pore, x, y)
			var s: float = _tileable(stainn, x, y) * 0.5 + 0.5

			var v: float = 0.62 + b * 0.34 - board * 0.22
			# Poros: los picos altos del ruido fino se vuelven agujeritos
			var pit := 1.0 if p > 0.62 else 0.0
			v -= pit * 0.3
			var c := Color(v, v * 0.985, v * 0.955)
			c = c.lerp(Color(0.30, 0.28, 0.24), s * 0.35)
			_put(data, i, c)
			height[i] = clampf(0.72 + b * 0.2 - pit * 0.45 - board * 0.3, 0.0, 1.0)
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Tablas de 24px con veta estirada a lo largo (ruido muy anisotrópico).
static func _gen_planks() -> Array:
	var pw := 24
	var grain := FastNoiseLite.new()
	grain.seed = 17
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.5
	grain.fractal_octaves = 3
	var wear := _noise(59, 0.02, 3)

	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for x in TILE:
		var plank := x / pw
		var tint: float = 0.7 + _hash01(plank, 5) * 0.65
		var offset: float = _hash01(plank, 9) * 90.0
		for y in TILE:
			var i := y * TILE + x
			# Veta: ruido comprimido 12x en Y => vetas largas en el sentido
			# de la tabla en vez de manchas redondas.
			var g := grain.get_noise_2d(float(x) * 3.0, float(y) * 0.25 + offset)
			var w: float = _tileable(wear, x, y) * 0.5 + 0.5
			var lx := posmod(x, pw)
			var gap := lx < 1 or lx >= pw - 1

			var base := Color(0.20, 0.125, 0.068) * tint
			base.r += g * 0.06
			base.g += g * 0.035
			base = base.lerp(Color(0.13, 0.115, 0.10), w * 0.4)
			if gap:
				base *= 0.28
			_put(data, i, base)
			height[i] = (0.1 if gap else 0.75 + g * 0.14 - w * 0.1)
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Azulejo 32x32 con pastina de 3px. Un par de piezas rotas/faltantes: un
## baño de club sin una sola baldosa saltada no es un baño de club.
static func _gen_tiles() -> Array:
	var tw := 32
	var grout := 3
	var moho := _noise(23, 0.05, 3)
	var dirt := _noise(31, 0.012, 2)

	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		for x in TILE:
			var i := y * TILE + x
			var cx := x / tw
			var cy := y / tw
			var lx := posmod(x, tw)
			var ly := posmod(y, tw)
			var m: float = _tileable(moho, x, y) * 0.5 + 0.5
			var d: float = _tileable(dirt, x, y) * 0.5 + 0.5
			var broken: bool = _hash01(cx, cy) > 0.88

			if lx < grout or ly < grout:
				var gv: float = 0.16 + d * 0.1
				# La pastina agarra toda la mugre: verdosa y siempre más sucia
				_put(data, i, Color(gv * 0.85, gv * 1.0, gv * 0.86))
				height[i] = 0.15 + d * 0.1
			elif broken:
				var bv: float = 0.11 + m * 0.09
				_put(data, i, Color(bv, bv * 0.95, bv * 0.88))
				height[i] = 0.1
			else:
				var tone: float = 0.8 + _hash01(cx * 3, cy * 7) * 0.4
				var c := Color(0.13, 0.24, 0.205) * tone
				c = c.lerp(Color(0.10, 0.14, 0.09), m * 0.5)
				c = c.lerp(Color(0.16, 0.155, 0.13), d * 0.25)
				_put(data, i, c)
				var edge := minf(minf(float(lx - grout), float(ly - grout)), 2.0) / 2.0
				height[i] = 0.78 + clampf(edge, 0.0, 1.0) * 0.2
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Chapa antideslizante (rombos en relieve) para pasarelas y tapas.
static func _gen_plate() -> Array:
	var scuff := _noise(13, 0.07, 3)
	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		for x in TILE:
			var i := y * TILE + x
			var s := _tileable(scuff, x, y)
			# Dos familias de rombos cruzadas, alternando por celda de 32
			var cell := (x / 32 + y / 32) % 2
			var u := float(posmod(x, 32)) / 32.0
			var v := float(posmod(y, 32)) / 32.0
			var diag: float = absf(u - v) if cell == 0 else absf(u + v - 1.0)
			var raised := 1.0 if diag < 0.16 and u > 0.12 and u < 0.88 else 0.0

			var base: float = 0.20 + s * 0.06 + raised * 0.1
			_put(data, i, Color(base, base * 1.02, base * 1.1))
			height[i] = 0.45 + raised * 0.45 + s * 0.08
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Óxido: manchones naranjas sobre metal oscuro, con pozos.
static func _gen_rust() -> Array:
	var patch := _noise(5, 0.018, 4)
	var pit := _noise(37, 0.16, 2)
	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		for x in TILE:
			var i := y * TILE + x
			var p: float = _tileable(patch, x, y) * 0.5 + 0.5
			var q := _tileable(pit, x, y)
			var eaten := 1.0 if q > 0.55 and p > 0.45 else 0.0

			var metal := Color(0.16, 0.16, 0.175)
			var oxide := Color(0.42, 0.19, 0.07).lerp(Color(0.55, 0.30, 0.10), q * 0.5 + 0.5)
			var c := metal.lerp(oxide, clampf(p * 1.35 - 0.2, 0.0, 1.0))
			c = c.lerp(Color(0.12, 0.06, 0.03), eaten * 0.6)
			_put(data, i, c)
			height[i] = clampf(0.7 + q * 0.15 - eaten * 0.5, 0.0, 1.0)
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Rejilla tramada: barras cada 16px. Opaca (no usamos alpha en geometría de
## losa), pero el patrón oscuro alcanza para que se lea como rejilla.
static func _gen_grate() -> Array:
	var grime := _noise(19, 0.05, 2)
	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		for x in TILE:
			var i := y * TILE + x
			var g := _tileable(grime, x, y)
			var bar_x := posmod(x, 16) < 4
			var bar_y := posmod(y, 32) < 3
			var solid: bool = bar_x or bar_y

			if solid:
				var v: float = 0.19 + g * 0.05 + (0.03 if bar_y else 0.0)
				_put(data, i, Color(v, v * 1.03, v * 1.08))
				height[i] = 0.85 + g * 0.1
			else:
				var v2: float = 0.028 + g * 0.012
				_put(data, i, Color(v2, v2, v2 * 1.1))
				height[i] = 0.05
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


## Mugre genérica: multiplicador gris en [0.6, 1.0] para materiales que no
## merecen un patrón propio (cuero, tela, goma, plástico).
static func _gen_grunge() -> Array:
	var n := _noise(97, 0.02, 4)
	var fine := _noise(101, 0.13, 2)
	var data := _blank_rgb()
	var height := PackedFloat32Array()
	height.resize(TILE * TILE)

	for y in TILE:
		for x in TILE:
			var i := y * TILE + x
			var a: float = _tileable(n, x, y) * 0.5 + 0.5
			var b := _tileable(fine, x, y)
			var v: float = 0.62 + a * 0.34 + b * 0.05
			_put(data, i, Color(v, v * 0.995, v * 0.98))
			height[i] = 0.6 + a * 0.3 + b * 0.1
	return [Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGB8, data), height]


# =============================================================================
# GENERADORES DE CALCO
# =============================================================================

static func _rgba(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Composición "source over" sobre el pixel existente. La usan todas las
## primitivas de dibujo: sin esto, pintar el relleno encima del contorno no
## lo tapa (queda el que tenga más alpha) y los grafitis salen sin outline.
static func _blend_px(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if a <= 0.002:
		return
	var prev := img.get_pixel(x, y)
	var na: float = a + prev.a * (1.0 - a)
	var w0: float = a / na
	img.set_pixel(x, y, Color(
		lerpf(prev.r, col.r, w0),
		lerpf(prev.g, col.g, w0),
		lerpf(prev.b, col.b, w0),
		na))


## Disco DURO (borde a 1px): trazos de aerosol, grietas, marcas. Un disco
## blando de radio 2 queda en un fantasma de alpha 0.1 y no se ve.
static func _dot(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var x0 := maxi(int(cx - r) - 1, 0)
	var x1 := mini(int(cx + r) + 1, img.get_width() - 1)
	var y0 := maxi(int(cy - r) - 1, 0)
	var y1 := mini(int(cy + r) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) - cx, float(y) - cy).length()
			_blend_px(img, x, y, col, clampf(r + 0.5 - d, 0.0, 1.0) * col.a)


## Disco BLANDO: manchas, halos, difuminados.
static func _stamp(img: Image, cx: float, cy: float, r: float, col: Color, falloff: float = 2.0) -> void:
	var x0 := maxi(int(cx - r) - 1, 0)
	var x1 := mini(int(cx + r) + 1, img.get_width() - 1)
	var y0 := maxi(int(cy - r) - 1, 0)
	var y1 := mini(int(cy + r) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) - cx, float(y) - cy).length() / maxf(r, 0.01)
			if d > 1.0:
				continue
			_blend_px(img, x, y, col, pow(1.0 - d, falloff) * col.a)


static func _line(img: Image, a: Vector2, b: Vector2, r: float, col: Color) -> void:
	# El paso va atado al radio, no a la distancia: con discos de r=12 pisar
	# un punto por pixel cuesta 40x más y no se nota la diferencia.
	var steps := maxi(int(a.distance_to(b) / maxf(r * 0.34, 0.55)), 1)
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		_dot(img, p.x, p.y, r, col)


## Polilínea: la forma de las letras del grafiti.
static func _polyline(img: Image, pts: Array, r: float, col: Color) -> void:
	for i in pts.size() - 1:
		_line(img, pts[i], pts[i + 1], r, col)


## Mancha de humedad/aceite: caída radial irregular mordida por ruido.
static func _gen_stain(variant: int) -> Image:
	var s := DECAL
	var img := _rgba(s, s)
	var n := _noise(400 + variant * 13, 0.035, 3)
	var tints := [
		Color(0.06, 0.05, 0.04), # aceite
		Color(0.10, 0.11, 0.08), # humedad verdosa
		Color(0.13, 0.06, 0.05), # óxido corrido
		Color(0.05, 0.07, 0.09), # agua sucia
	]
	var col: Color = tints[variant % tints.size()]
	var half := float(s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(float(x) - half, float(y) - half).length() / half
			var wobble := n.get_noise_2d(float(x), float(y)) * 0.45
			var a: float = clampf(1.0 - (d + wobble) * 1.15, 0.0, 1.0)
			a = pow(a, 1.6) * 0.85
			if a > 0.002:
				var c := col
				c.a = a
				img.set_pixel(x, y, c)
	return img


## Trazos de letra en coordenadas normalizadas (x 0..1 a lo ancho de la
## letra, y 0 arriba / 1 abajo). Son las formas que hacen que un tag se lea
## como un tag y no como una madeja de líneas al azar.
const _TAG_GLYPHS := [
	[[0.0, 1.0], [0.0, 0.0], [1.0, 1.0], [1.0, 0.0]],                          # N
	[[0.0, 0.0], [0.5, 1.0], [1.0, 0.0]],                                      # V
	[[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]],                          # Z
	[[1.0, 0.12], [0.15, 0.0], [0.0, 0.45], [1.0, 0.58], [0.85, 1.0], [0.0, 0.88]], # S
	[[0.0, 1.0], [0.45, 0.0], [0.9, 1.0]],                                     # A
	[[0.18, 0.55], [0.8, 0.62]],                                               # travesaño de la A
	[[0.0, 0.0], [0.0, 1.0], [0.9, 1.0]],                                      # L
	[[0.1, 1.0], [0.1, 0.0], [0.9, 0.22], [0.1, 0.5], [0.9, 1.0]],             # R
	[[0.0, 0.0], [1.0, 1.0], [0.5, 0.5], [1.0, 0.0], [0.0, 1.0]],              # X
	[[0.0, 0.0], [1.0, 0.0], [0.5, 0.0], [0.5, 1.0]],                          # T
	[[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]],              # O
]


## Grafiti: 4-6 letras con contorno + chorreadas. Se usa como albedo Y como
## emisión del calco, así el tag "prende" bajo la luz del club.
static func _gen_graffiti(variant: int) -> Image:
	var w := 224
	var h := 96
	var img := _rgba(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant * 31

	var palettes := [
		[Color(1.0, 0.15, 0.55), Color(0.06, 0.02, 0.05), Color(0.95, 0.75, 0.1)],
		[Color(0.2, 0.9, 1.0), Color(0.02, 0.04, 0.08), Color(0.7, 0.25, 1.0)],
		[Color(0.3, 1.0, 0.45), Color(0.02, 0.06, 0.03), Color(0.95, 0.95, 0.9)],
		[Color(1.0, 0.42, 0.08), Color(0.07, 0.02, 0.0), Color(1.0, 0.92, 0.25)],
	]
	var pal: Array = palettes[variant % palettes.size()]
	var fill: Color = pal[0]
	var outline: Color = pal[1]
	var spark: Color = pal[2]

	var count := rng.randi_range(4, 6)
	var slot := float(w - 24) / float(count)
	var glyphs: Array[Array] = []
	var origins: PackedVector2Array = []

	for i in count:
		var g: Array = _TAG_GLYPHS[rng.randi_range(0, _TAG_GLYPHS.size() - 1)]
		var lw := slot * rng.randf_range(0.78, 1.0)
		var lh := rng.randf_range(52.0, 70.0)
		var ox := 12.0 + float(i) * slot + rng.randf_range(-3.0, 3.0)
		var oy := rng.randf_range(12.0, 24.0)
		var skew := rng.randf_range(-0.28, 0.28) # itálica: nadie tagea recto
		var pts: Array = []
		for p in g:
			var nx: float = p[0]
			var ny: float = p[1]
			pts.append(Vector2(ox + nx * lw + (1.0 - ny) * skew * lw, oy + ny * lh))
		glyphs.append(pts)
		origins.append(Vector2(ox + lw * 0.5, oy + lh))

	# 1) contorno grueso  2) relleno encima  -- el orden es el efecto
	var thick := rng.randf_range(7.0, 9.0)
	for pts in glyphs:
		_polyline(img, pts, thick + 3.0, outline)
	for pts in glyphs:
		_polyline(img, pts, thick, fill)

	# Chorreadas desde la base de cada letra
	for o in origins:
		if rng.randf() > 0.62:
			continue
		var dl := rng.randf_range(8.0, 22.0)
		var dx := o.x + rng.randf_range(-thick * 0.6, thick * 0.6)
		for k in int(dl):
			_dot(img, dx, o.y + float(k), thick * 0.32 * (1.0 - float(k) / dl * 0.65), fill)
		_dot(img, dx, o.y + dl, thick * 0.4, fill)

	# Brillos: dos tildes del tercer color cruzando el tag
	for i in 3:
		var a := Vector2(rng.randf_range(8.0, float(w) - 30.0), rng.randf_range(16.0, 70.0))
		_line(img, a, a + Vector2(rng.randf_range(14.0, 34.0), rng.randf_range(-12.0, 12.0)), 2.2, spark)
	return img


## Afiche de fecha pegado a la pared: fondo saturado, bloque de "arte",
## renglones de texto y bordes rotos.
static func _gen_poster(variant: int) -> Image:
	var w := 72
	var h := 104
	var img := _rgba(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1300 + variant * 47

	var bg := Color.from_hsv(rng.randf(), rng.randf_range(0.55, 0.9), rng.randf_range(0.35, 0.7))
	var ink := Color(0.03, 0.03, 0.04) if bg.get_luminance() > 0.3 else Color(0.95, 0.93, 0.88)

	for y in h:
		for x in w:
			img.set_pixel(x, y, bg)

	# Bloque de arte arriba
	var art := Color.from_hsv(fposmod(bg.h + 0.45, 1.0), 0.8, 0.85)
	for y in range(8, 48):
		for x in range(6, w - 6):
			var d := Vector2(float(x) - float(w) * 0.5, float(y) - 28.0)
			if d.length() < 20.0 + sin(float(y) * 0.4) * 4.0:
				img.set_pixel(x, y, art)

	# Renglones de "texto"
	var ry := 56
	while ry < h - 10:
		var lw := rng.randi_range(int(w * 0.35), w - 14)
		var lh := rng.randi_range(3, 7)
		var lx := (w - lw) / 2
		for y in range(ry, mini(ry + lh, h)):
			for x in range(lx, lx + lw):
				img.set_pixel(x, y, ink)
		ry += lh + rng.randi_range(4, 8)

	# Bordes rotos y esquina despegada
	for i in 90:
		var side := rng.randi_range(0, 3)
		var bite := rng.randi_range(2, 7)
		var px := rng.randi_range(0, w - 1)
		var py := rng.randi_range(0, h - 1)
		match side:
			0: py = rng.randi_range(0, 2)
			1: py = h - 1 - rng.randi_range(0, 2)
			2: px = rng.randi_range(0, 2)
			3: px = w - 1 - rng.randi_range(0, 2)
		for dy in range(-bite, bite):
			for dx in range(-bite, bite):
				var qx := px + dx
				var qy := py + dy
				if qx >= 0 and qx < w and qy >= 0 and qy < h and Vector2(dx, dy).length() < float(bite):
					img.set_pixel(qx, qy, Color(0, 0, 0, 0))
	return img


## Marca de neumático: banda oscura con dibujo de taco cruzado.
static func _gen_tire() -> Image:
	var w := 48
	var h := 160
	var img := _rgba(w, h)
	for y in h:
		# Se desvanece en las dos puntas: la goma se va gastando en el barrido
		var fade: float = pow(sin(float(y) / float(h) * PI), 0.45)
		for x in w:
			var edge: float = 1.0 - absf(float(x) / float(w) * 2.0 - 1.0)
			var tread := 0.6 if posmod(y + (x / 8) * 3, 11) < 6 else 1.0
			var a: float = clampf(edge * 3.2, 0.0, 1.0) * fade * tread
			if a > 0.01:
				img.set_pixel(x, y, Color(0.035, 0.032, 0.03, a))
	return img


## Grieta ramificada: una raíz y dos brazos que se abren.
static func _gen_crack(variant: int) -> Image:
	var s := 128
	var img := _rgba(s, s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant * 61
	var ink := Color(0.02, 0.018, 0.016, 1.0)

	var branches: Array[Array] = []
	var start := Vector2(rng.randf_range(6.0, 24.0), rng.randf_range(20.0, 108.0))
	var dir := Vector2(1, 0).rotated(rng.randf_range(-0.6, 0.6))
	branches.append([start, dir, 70.0, 2.4])

	var guard := 0
	while not branches.is_empty() and guard < 40:
		guard += 1
		var b: Array = branches.pop_front()
		var p: Vector2 = b[0]
		var d: Vector2 = b[1]
		var life: float = b[2]
		var thick: float = b[3]
		var steps := int(life)
		for i in steps:
			d = d.rotated(rng.randf_range(-0.25, 0.25)).normalized()
			p += d * 1.5
			if p.x < 1.0 or p.x > float(s) - 2.0 or p.y < 1.0 or p.y > float(s) - 2.0:
				break
			# Se afina hacia la punta: una fisura nace ancha y muere en pelo
			_dot(img, p.x, p.y, maxf(thick * (1.0 - float(i) / float(steps) * 0.7), 0.7), ink)
			if rng.randf() < 0.05 and thick > 1.1:
				branches.append([p, d.rotated(rng.randf_range(0.5, 1.2)), life * 0.5, thick * 0.62])
	return img


## Quemadura de tacho / fogata: círculo negro de borde comido.
static func _gen_scorch() -> Image:
	var s := DECAL
	var img := _rgba(s, s)
	var n := _noise(777, 0.05, 3)
	var half := float(s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(float(x) - half, float(y) - half).length() / half
			var wob := n.get_noise_2d(float(x), float(y)) * 0.3
			var a: float = clampf(1.0 - (d + wob) * 1.25, 0.0, 1.0)
			a = pow(a, 0.8)
			if a > 0.01:
				# Núcleo negro con un halo apenas rojizo de ceniza
				var c := Color(0.02, 0.018, 0.016).lerp(Color(0.10, 0.05, 0.03), 1.0 - a)
				c.a = a * 0.9
				img.set_pixel(x, y, c)
	return img


## Charco: alpha suave y color casi negro; el brillo lo da el material del
## calco (rugosidad baja), no la textura.
static func _gen_puddle(variant: int) -> Image:
	var s := DECAL
	var img := _rgba(s, s)
	var n := _noise(555 + variant * 17, 0.022, 3)
	var half := float(s) * 0.5
	for y in s:
		for x in s:
			var v := Vector2(float(x) - half, float(y) - half)
			# Aplastado en Y: los charcos no son círculos perfectos
			v.y *= 1.35
			var d := v.length() / half
			var wob := n.get_noise_2d(float(x), float(y)) * 0.5
			var a: float = clampf(1.0 - (d + wob) * 1.1, 0.0, 1.0)
			if a > 0.01:
				img.set_pixel(x, y, Color(0.02, 0.028, 0.035, clampf(pow(a, 0.5) * 1.1, 0.0, 1.0)))
	return img


## Flecha de circulación pintada en el piso de la nave (amarillo gastado).
static func _gen_arrow() -> Image:
	var w := 64
	var h := 96
	var img := _rgba(w, h)
	var n := _noise(888, 0.09, 2)
	var col := Color(0.62, 0.52, 0.09)
	for y in h:
		for x in w:
			var fx := float(x) - float(w) * 0.5
			var fy := float(y)
			var inside := false
			if fy > 44.0:
				inside = absf(fx) < 9.0 and fy < 90.0
			else:
				# Punta triangular
				inside = absf(fx) < (fy / 44.0) * 26.0 and fy > 6.0
			if not inside:
				continue
			# Pintura descascarada
			var wear := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			if wear < 0.32:
				continue
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(wear * 1.3, 0.0, 1.0)))
	return img
