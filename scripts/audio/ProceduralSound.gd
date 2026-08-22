class_name ProceduralSound
extends RefCounted
## Genera clips de audio cortos en código (ruido filtrado) para no depender
## de archivos externos. Es un placeholder funcional, no diseño de sonido
## real -- pero permite tener ambiente tenso y pasos sin assets.

const MIX_RATE := 22050 # bajo a propósito: pesa menos y encaja con el look retro

static var _footstep_variants: Array[AudioStreamWAV] = []
static var _rng := RandomNumberGenerator.new()


static func get_footstep_stream() -> AudioStreamWAV:
	if _footstep_variants.is_empty():
		for i in 4:
			_footstep_variants.append(_make_footstep())
	return _footstep_variants[_rng.randi() % _footstep_variants.size()]


## Golpe grave (el peso del paso, decae rápido) + textura de roce contra el
## piso (aún más corta y filtrada) -- percusivo, no un "siseo" de ruido plano.
static func _make_footstep() -> AudioStreamWAV:
	_rng.randomize()
	var duration := 0.11
	var sample_count := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var thump_freq := _rng.randf_range(65.0, 110.0)
	var phase := 0.0
	var phase_step := (thump_freq * TAU) / float(MIX_RATE)
	var noise_last := 0.0

	for i in sample_count:
		var t := float(i) / float(MIX_RATE)

		var thump_env := exp(-t * 38.0)
		var thump := sin(phase) * thump_env
		phase += phase_step

		var scuff_env := exp(-t * 70.0)
		var white := _rng.randf_range(-1.0, 1.0)
		noise_last = (noise_last + 0.35 * white) / 1.35
		var scuff := noise_last * scuff_env

		var sample_f: float = clamp(thump * 0.55 + scuff * 0.5, -1.0, 1.0)
		var sample_i := int(sample_f * 32767.0)
		data.encode_s16(i * 2, sample_i)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Ruido marrón (integración simple de ruido blanco): un drone grave y sordo,
## bien distinto del "siseo" de un ruido blanco normal.
static func brown_noise(duration_sec: float, volume: float = 0.4) -> AudioStreamWAV:
	_rng.randomize()
	var sample_count := int(MIX_RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var last := 0.0
	for i in sample_count:
		var white := _rng.randf_range(-1.0, 1.0)
		last = (last + 0.02 * white) / 1.02
		var sample := int(clamp(last * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = data
	return stream


## Ráfaga corta de ruido con fade-out -- sirve para un paso, un golpe
## metálico distante, etc.
static func noise_burst(duration_sec: float, volume: float = 0.5) -> AudioStreamWAV:
	_rng.randomize()
	var sample_count := int(MIX_RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(max(sample_count - 1, 1))
		var envelope := 1.0 - t
		var white := _rng.randf_range(-1.0, 1.0)
		var sample := int(clamp(white * volume * envelope, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


# =============================================================================
# AMBIENTES DE ZONA (loops largos, posicionales)
# =============================================================================
## Los usa MapGenerator para que cada sala suene distinta sin un solo .ogg.
## Todos son loops enteros: el punto de loop cae en el final del buffer y las
## señales están construidas para que el último sample empalme con el primero
## (períodos enteros de las senoidales), si no se escucha un "clic" por vuelta.

## Los ambientes son loops largos (hasta 13s a 22 kHz = ~290k muestras) y el
## bucle que los sintetiza es GDScript puro: generarlos en cada `generate()`
## del mapa costaba casi medio segundo de la carga. Se cachean por parámetros
## y se comparten entre todas las fuentes que pidan lo mismo.
static var _ambient_cache: Dictionary = {}


static func _cached(key: String, gen: Callable) -> AudioStreamWAV:
	if not _ambient_cache.has(key):
		_ambient_cache[key] = gen.call()
	return _ambient_cache[key]


static func machine_hum(freq: float, duration_sec: float, volume: float = 0.35) -> AudioStreamWAV:
	return _cached("hum%.1f_%.1f_%.2f" % [freq, duration_sec, volume],
			func() -> AudioStreamWAV: return _make_machine_hum(freq, duration_sec, volume))


static func electric_buzz(duration_sec: float, volume: float = 0.22) -> AudioStreamWAV:
	return _cached("buzz%.1f_%.2f" % [duration_sec, volume],
			func() -> AudioStreamWAV: return _make_electric_buzz(duration_sec, volume))


static func drip_loop(duration_sec: float = 9.0, drops: int = 5, volume: float = 0.5) -> AudioStreamWAV:
	return _cached("drip%.1f_%d_%.2f" % [duration_sec, drops, volume],
			func() -> AudioStreamWAV: return _make_drip_loop(duration_sec, drops, volume))


static func metal_creak(duration_sec: float = 11.0, events: int = 3, volume: float = 0.38) -> AudioStreamWAV:
	return _cached("creak%.1f_%d_%.2f" % [duration_sec, events, volume],
			func() -> AudioStreamWAV: return _make_metal_creak(duration_sec, events, volume))


static func wind_loop(duration_sec: float = 13.0, volume: float = 0.3) -> AudioStreamWAV:
	return _cached("wind%.1f_%.2f" % [duration_sec, volume],
			func() -> AudioStreamWAV: return _make_wind_loop(duration_sec, volume))


static func _looped(data: PackedByteArray, sample_count: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = data
	return stream


## Zumbido de máquina: fundamental + dos armónicos + un colchón de ruido.
## Es el ambiente de la sala de calderas y de cualquier cosa con motor.
static func _make_machine_hum(freq: float, duration_sec: float, volume: float = 0.35) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration_sec)
	# Redondeo la frecuencia para que entren ciclos ENTEROS en el buffer:
	# de lo contrario el loop clickea una vez por vuelta.
	var cycles := maxf(round(freq * duration_sec), 1.0)
	var f := cycles / duration_sec

	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var last := 0.0
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var ph := TAU * f * t
		var tone := sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.12
		# Modulación lenta (2 ciclos exactos en el buffer): la máquina "respira"
		var wobble := 1.0 + sin(TAU * 2.0 * t / duration_sec) * 0.18
		var white := _rng.randf_range(-1.0, 1.0)
		last = (last + 0.06 * white) / 1.06
		var s: float = clampf((tone * wobble * 0.75 + last * 1.6) * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	return _looped(data, sample_count)


## Zumbido eléctrico de 100 Hz (el de una heladera o un balasto viejo), con
## armónicos impares -- por eso suena "sucio" y no como un tono puro.
static func _make_electric_buzz(duration_sec: float, volume: float = 0.22) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration_sec)
	var cycles := maxf(round(100.0 * duration_sec), 1.0)
	var f := cycles / duration_sec
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var ph := TAU * f * t
		var s := sin(ph) * 0.5 + sin(ph * 3.0) * 0.28 + sin(ph * 5.0) * 0.16 + sin(ph * 7.0) * 0.08
		data.encode_s16(i * 2, int(clampf(s * volume, -1.0, 1.0) * 32767.0))
	return _looped(data, sample_count)


## Goteo: silencio largo y cada tanto una gota (senoidal que sube de tono y
## decae rapidísimo -- el "plic" es justamente ese barrido ascendente).
static func _make_drip_loop(duration_sec: float = 9.0, drops: int = 5, volume: float = 0.5) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for d in drops:
		# Repartidas con un jitter determinista por índice: si van perfectas
		# se escucha un metrónomo, no una canilla.
		var at := (float(d) + 0.35 + sin(float(d) * 12.9898) * 0.3) / float(drops)
		var start := int(at * float(sample_count))
		var base := 620.0 + sin(float(d) * 3.7) * 260.0
		var len_s := int(MIX_RATE * 0.13)
		var ph := 0.0
		for k in len_s:
			var idx := start + k
			if idx >= sample_count:
				break
			var u := float(k) / float(len_s)
			var env: float = exp(-u * 16.0)
			# El tono sube durante la gota: es lo que la hace sonar a agua
			ph += TAU * (base * (1.0 + u * 2.4)) / float(MIX_RATE)
			var s: float = sin(ph) * env * volume
			var prev := data.decode_s16(idx * 2)
			data.encode_s16(idx * 2, int(clampf(float(prev) / 32767.0 + s, -1.0, 1.0) * 32767.0))
	return _looped(data, sample_count)


## Crujido de metal: ruido filtrado pasa-banda con la banda barriendo hacia
## abajo. Suena a estructura asentándose, que es lo que uno quiere oír en una
## nave abandonada cuando está escondido y en silencio.
static func _make_metal_creak(duration_sec: float = 11.0, events: int = 3, volume: float = 0.38) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for e in events:
		var at := (float(e) + 0.45 + sin(float(e) * 7.13) * 0.32) / float(events)
		var start := int(at * float(sample_count))
		var len_s := int(MIX_RATE * (0.7 + absf(sin(float(e) * 2.1)) * 0.9))
		var lp := 0.0
		var hp_prev := 0.0
		for k in len_s:
			var idx := start + k
			if idx >= sample_count:
				break
			var u := float(k) / float(len_s)
			var env: float = sin(u * PI)
			var white := _rng.randf_range(-1.0, 1.0)
			# Pasa-bajos de coeficiente variable = banda que baja de tono
			var a: float = lerpf(0.22, 0.045, u)
			lp = lp + a * (white - lp)
			# Y un pasa-altos simple encima, para sacarle el "soplido" grave
			var band := lp - hp_prev
			hp_prev = hp_prev + 0.02 * (lp - hp_prev)
			var s: float = clampf(band * 5.0 * env * volume, -1.0, 1.0)
			var prev := data.decode_s16(idx * 2)
			data.encode_s16(idx * 2, int(clampf(float(prev) / 32767.0 + s, -1.0, 1.0) * 32767.0))
	return _looped(data, sample_count)


## Viento entrando por la claraboya rota: ruido marrón con la amplitud
## modulada muy lento en dos frecuencias distintas (ráfagas irregulares).
static func _make_wind_loop(duration_sec: float = 13.0, volume: float = 0.3) -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * duration_sec)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var last := 0.0
	for i in sample_count:
		var t := float(i) / float(sample_count)
		var white := _rng.randf_range(-1.0, 1.0)
		last = (last + 0.05 * white) / 1.05
		# Dos moduladoras con ciclos enteros: 3 y 7 vueltas por buffer
		var gust := 0.45 + 0.35 * (sin(TAU * 3.0 * t) * 0.5 + 0.5) + 0.25 * (sin(TAU * 7.0 * t) * 0.5 + 0.5)
		var s: float = clampf(last * 3.2 * gust * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	return _looped(data, sample_count)
