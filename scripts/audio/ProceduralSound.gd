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
