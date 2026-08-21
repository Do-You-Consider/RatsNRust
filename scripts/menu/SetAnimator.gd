class_name SetAnimator
extends Node
## Anima la escenografía del menú: gente saltando en la pista, monitores
## titilando, cabezales barriendo la pista, neones respirando.
##
## Un solo _process para todo el set en vez de un Tween por objeto. Con ~50
## siluetas en la pista y 12 monitores, la diferencia entre 60 tweens y un
## bucle plano es la que decide si el menú corre a 60fps en una máquina
## modesta -- y además todo muere junto con el set, sin tweens huérfanos.
##
## Cada canal guarda su FASE: si todas las siluetas saltaran en el mismo
## cuadro parecería una animación rota, no una pista llena.

class Bob:
	var node: Node3D
	var base: Vector3
	var amp: float
	var freq: float
	var phase: float

class Sway:
	var node: Node3D
	var base: float
	var amp: float
	var freq: float
	var phase: float

class Pulse:
	var mat: StandardMaterial3D
	var lo: float
	var hi: float
	var freq: float
	var phase: float

class Sweep:
	var node: Node3D
	var axis: Vector3
	var center: float
	var amp: float
	var freq: float
	var phase: float

class Blink:
	var light: Light3D
	var lo: float
	var hi: float
	var freq: float
	var phase: float

var _bobs: Array[Bob] = []
var _sways: Array[Sway] = []
var _pulses: Array[Pulse] = []
var _sweeps: Array[Sweep] = []
var _blinks: Array[Blink] = []
var _t: float = 0.0


func bob(node: Node3D, amp: float, freq: float, phase: float) -> void:
	var b := Bob.new()
	b.node = node
	b.base = node.position
	b.amp = amp
	b.freq = freq
	b.phase = phase
	_bobs.append(b)


func sway(node: Node3D, amp_deg: float, freq: float, phase: float) -> void:
	var s := Sway.new()
	s.node = node
	s.base = node.rotation.y
	s.amp = deg_to_rad(amp_deg)
	s.freq = freq
	s.phase = phase
	_sways.append(s)


func pulse(mat: StandardMaterial3D, lo: float, hi: float, freq: float, phase: float) -> void:
	var p := Pulse.new()
	p.mat = mat
	p.lo = lo
	p.hi = hi
	p.freq = freq
	p.phase = phase
	_pulses.append(p)


## Barrido de un pivote sobre un eje: cabezales de luz de la pista.
func sweep(node: Node3D, axis: Vector3, center_deg: float, amp_deg: float, freq: float, phase: float) -> void:
	var s := Sweep.new()
	s.node = node
	s.axis = axis
	s.center = deg_to_rad(center_deg)
	s.amp = deg_to_rad(amp_deg)
	s.freq = freq
	s.phase = phase
	_sweeps.append(s)


func blink(light: Light3D, lo: float, hi: float, freq: float, phase: float) -> void:
	var b := Blink.new()
	b.light = light
	b.lo = lo
	b.hi = hi
	b.freq = freq
	b.phase = phase
	_blinks.append(b)


func _process(delta: float) -> void:
	_t += delta

	for b in _bobs:
		if not is_instance_valid(b.node):
			continue
		# abs(sin) en vez de sin: el rebote de un salto no baja del piso.
		var s: float = absf(sin(_t * b.freq + b.phase))
		b.node.position = b.base + Vector3(0, s * b.amp, 0)

	for s2 in _sways:
		if not is_instance_valid(s2.node):
			continue
		s2.node.rotation.y = s2.base + sin(_t * s2.freq + s2.phase) * s2.amp

	for p in _pulses:
		if p.mat == null:
			continue
		var k: float = 0.5 + 0.5 * sin(_t * p.freq + p.phase)
		p.mat.emission_energy_multiplier = lerpf(p.lo, p.hi, k)

	for sw in _sweeps:
		if not is_instance_valid(sw.node):
			continue
		var ang: float = sw.center + sin(_t * sw.freq + sw.phase) * sw.amp
		sw.node.rotation = sw.axis * ang

	for bl in _blinks:
		if not is_instance_valid(bl.light):
			continue
		var k2: float = 0.5 + 0.5 * sin(_t * bl.freq + bl.phase)
		bl.light.light_energy = lerpf(bl.lo, bl.hi, k2)
